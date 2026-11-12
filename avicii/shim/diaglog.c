/*
 * Persistent diag log: see diaglog.h for the on-disk shape.
 *
 * MMU off, so the ring buffer and the header live in Device memory that the
 * UFS host DMAs straight out of. One line per WRITE(10) of one 4096-byte
 * block, followed by SYNCHRONIZE CACHE - a hang between two lines can lose at
 * most the line being written, never the ones before it.
 *
 * Return codes from dlog_init():
 *   1  UFS host not ours (see ufs_takeover())
 *   2  no GPT / no userdata entry
 *   3  userdata too small for the ring
 *   4  header write failed
 *   5  header read-back did not match
 *   6  ring wipe failed
 */
#include <stdint.h>
#include "diaglog.h"
#include "ufs.h"

#define BLOCK		4096u
#define RING_BLOCKS	1024u		/* 4 MiB, as tooling/42-log-pull.sh reads */
#define TEXT_MAX	96u		/* one line, truncated if longer */

static uint8_t hdr[BLOCK] __attribute__((aligned(4096)));
static uint8_t blk[BLOCK] __attribute__((aligned(4096)));
static uint8_t chk[BLOCK] __attribute__((aligned(4096)));
static uint8_t wipe[16 * BLOCK] __attribute__((aligned(4096)));	/* 64 KB, .bss = zero */

static uint32_t header_lba, ring_lba;
static uint32_t total;			/* bytes ever written into the ring */
static uint32_t cur_blk = 0xffffffffu;	/* ring block mirrored in blk[] */
static uint64_t start_ticks, ticks_per_ms;
static int on, fails;

static uint64_t ticks(void)
{
	uint64_t t;
	__asm__ volatile("isb; mrs %0, cntvct_el0" : "=r"(t));
	return t;
}

static void put32(uint8_t *p, uint32_t v)
{
	for (int i = 0; i < 4; i++)
		p[i] = v >> (8 * i);
}

static void put64(uint8_t *p, uint64_t v)
{
	for (int i = 0; i < 8; i++)
		p[i] = v >> (8 * i);
}

static uint64_t now_ms(void)
{
	if (!ticks_per_ms)
		return 0;
	return (ticks() - start_ticks) / ticks_per_ms;
}

static void zero(void *p, unsigned n)
{
	volatile uint8_t *b = p;
	for (unsigned i = 0; i < n; i++)
		b[i] = 0;
}

int dlog_on(void)
{
	return on;
}

void dlog_off(const char *why)
{
	(void)why;
	on = 0;
}

/* Header carries the counters; rewritten after every line. */
static int write_hdr(uint64_t seq)
{
	zero(hdr, sizeof(hdr));
	const char magic[8] = "SWEETLOG";
	for (int i = 0; i < 8; i++)
		hdr[i] = magic[i];
	put32(hdr + 8, 1);			/* version */
	put32(hdr + 12, RING_BLOCKS * BLOCK);	/* ring size in bytes */
	put64(hdr + 16, total);			/* total bytes written */
	put64(hdr + 24, seq);			/* flush sequence */
	const char note[] = "avicii diag ladder, DIAG_STAGE image, last 1024 blocks of userdata";
	for (unsigned i = 0; i < sizeof(note); i++)
		hdr[32 + i] = (uint8_t)note[i];
	return ufs_write(header_lba, 1, hdr) || ufs_sync();
}

int dlog_init(void)
{
	uint64_t first = 0, last = 0;
	uint32_t rc;

	__asm__ volatile("isb; mrs %0, cntfrq_el0" : "=r"(ticks_per_ms));
	ticks_per_ms /= 1000;
	start_ticks = ticks();
	if (!ticks_per_ms)
		ticks_per_ms = 1;

	rc = ufs_takeover();
	if (rc)
		return 1;
	rc = ufs_part_find("userdata", &first, &last);
	if (rc)
		return 2;
	if (last <= first || last - first + 1 < RING_BLOCKS + 2)
		return 3;
	header_lba = (uint32_t)(last - RING_BLOCKS);
	ring_lba = header_lba + 1;

	/* Zero the ring before any line: otherwise the first pull of a fresh
	 * area shows the old filesystem bytes behind the log lines. */
	for (uint32_t done = 0; done < RING_BLOCKS; done += 16) {
		if (ufs_write(ring_lba + done, 16, wipe))
			return 6;
	}
	if (ufs_sync())
		return 6;
	if (write_hdr(0))
		return 4;
	/* Prove the header is readable where we will look for it later. */
	if (ufs_read(header_lba, 1, chk) || __builtin_strcmp((const char *)chk, "SWEETLOG"))
		return 5;

	on = 1;
	total = 0;
	return 0;
}

/*
 * Append one line. `kind` is a single letter that lands in the text:
 *   B rung begin (written before the rung touches anything)
 *   K rung result, okay
 *   X rung result, bad
 *   - plain note
 */
void dlog_line(char kind, const char *text)
{
	if (!on)
		return;

	char line[TEXT_MAX];
	unsigned n = 0;
	line[n++] = '[';
	uint64_t ms = now_ms();
	char tmp[12];
	int d = 0;
	do {
		tmp[d++] = (char)('0' + ms % 10);
		ms /= 10;
	} while (ms && d < 11);
	while (n < 7 && d)
		line[n++] = tmp[--d];
	while (n < 7)
		line[n++] = ' ';
	line[n++] = ']';
	line[n++] = ' ';
	line[n++] = kind;
	line[n++] = ' ';
	for (unsigned i = 0; text[i] && n < sizeof(line) - 1; i++)
		line[n++] = text[i];
	line[n++] = '\n';

	for (unsigned done = 0; done < n;) {
		uint32_t off = total % (RING_BLOCKS * BLOCK);
		uint32_t b = off / BLOCK, bo = off % BLOCK;
		if (b != cur_blk) {
			zero(blk, sizeof(blk));
			cur_blk = b;
		}
		uint32_t chunk = n - done;
		if (chunk > BLOCK - bo)
			chunk = BLOCK - bo;
		for (uint32_t i = 0; i < chunk; i++)
			blk[bo + i] = (uint8_t)line[done + i];
		if (ufs_write(ring_lba + b, 1, blk)) {
			if (++fails > 3) {
				on = 0;
				return;
			}
		} else {
			fails = 0;
		}
		ufs_sync();
		done += chunk;
		total += chunk;
	}
	if (write_hdr(total) && ++fails > 3)
		on = 0;
}
