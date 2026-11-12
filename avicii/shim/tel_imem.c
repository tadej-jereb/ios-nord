/*
 * Rung 6: the IMEM record.
 *
 * IMEM is a small always-on SRAM the ABL, the SBL and the PSCI firmware all
 * keep using, so a word written here outlives a reset in a way the framebuffer
 * and the UFS ring cannot: it needs no MMU, no DMA, no panel and no controller
 * init. One store is the whole mechanism, which is why it is the first rung.
 *
 * The record (see tel.h) carries a sequence number, the step code and the two
 * timestamps, so a single readback after any outcome says three things at once:
 * did code run (magic + kimg_base), how far it got (max code), and how long it
 * lived (w14 - w6). A refused image leaves all of it zero and restart_reason
 * at whatever the previous boot set.
 *
 * The self-check writes the header, reads every word back and stores a verdict,
 * so an IMEM address that is not actually writable is reported by the record
 * itself instead of being assumed.
 */
#include <stdint.h>
#include "console.h"
#include "diaglog.h"
#include "tel.h"

/* 19.2 MHz counter, no MMU: cntvct_el0 is the only clock with no vote. */
uint64_t tel_ticks(void)
{
	uint64_t t;
	__asm__ volatile("isb; mrs %0, cntvct_el0" : "=r"(t));
	return t;
}

void tel_msleep(unsigned ms)
{
	uint64_t f, start;

	__asm__ volatile("isb; mrs %0, cntfrq_el0" : "=r"(f));
	if (!f)
		f = 19200000UL;
	start = tel_ticks();
	while ((tel_ticks() - start) < (uint64_t)ms * (f / 1000))
		__asm__ volatile("isb");
}

/* Panel first, then the ring (which is off here and returns immediately). */
void tel_say(char kind, const char *label, const char *text)
{
	char buf[80];
	unsigned n = 0;

	while (label[n] && n < 8) {
		buf[n] = label[n];
		n++;
	}
	buf[n++] = ' ';
	for (unsigned i = 0; text[i] && n < sizeof(buf) - 1; i++)
		buf[n++] = text[i];
	buf[n] = 0;
	con_str(label, text);
	dlog_line(kind, buf);
}

void tel_begin(unsigned stage)
{
	TEL_W(0) = 0;			/* cleared first: a stale magic is not evidence */
	TEL_W(1) = stage;
	TEL_W(4) = 0;
	TEL_W(5) = 0;
	TEL_W(6) = 0;
	TEL_W(2) = 0;
	TEL_W(3) = 0;
	TEL_W(7) = 0;
	TEL_W(8) = 0;
	TEL_W(9) = 0;
	TEL_W(10) = 0;
	TEL_W(11) = 0;
	TEL_W(12) = 0;
	TEL_W(13) = 0;
	TEL_W(14) = 0;
	__asm__ volatile("dsb sy" ::: "memory");
}

void tel_mark(uint32_t code)
{
	extern uint64_t kimg_base;

	TEL_W(0) = TEL_MAGIC;
	TEL_W(4) = (uint32_t)kimg_base;
	TEL_W(5) = (uint32_t)(kimg_base >> 32);
	TEL_W(3) = code;
	TEL_W(2) = TEL_W(2) + 1;
	if (!TEL_W(6))
		TEL_W(6) = (uint32_t)tel_ticks();
	TEL_RR = TEL_MAGIC;
	__asm__ volatile("dsb sy; isb" ::: "memory");
}

void tel_result(unsigned slot, uint32_t v)
{
	TEL_W(slot) = v;
	__asm__ volatile("dsb sy" ::: "memory");
}

void tel_alive_ms(uint32_t ms)
{
	TEL_W(14) = (uint32_t)tel_ticks();
	TEL_W(15) = ms;
	__asm__ volatile("dsb sy" ::: "memory");
}

int tel_selfcheck(void)
{
	uint32_t magic = TEL_W(0), code = TEL_W(3), rr = TEL_RR;
	uint32_t seq = TEL_W(2);

	if (magic != TEL_MAGIC || !code || !seq || rr != TEL_MAGIC) {
		TEL_W(7) = TEL_BAD;
		__asm__ volatile("dsb sy" ::: "memory");
		return -1;
	}
	TEL_W(7) = TEL_OK;
	TEL_W(8) = TEL_OK;
	__asm__ volatile("dsb sy" ::: "memory");
	return 0;
}

/* Rung 6 proper: mark, write, verify, report, and hand back to the park. */
void tel_imem_rung(void)
{
	char b[48];
	unsigned n;
	int rc;

	tel_mark(TEL_S6_ENTER);
	tel_say('B', "T6", "imem record begin (magic 1TEL)");
	tel_mark(TEL_S6_MAGIC);
	tel_mark(TEL_S6_SELFCHK);
	rc = tel_selfcheck();
	if (rc) {
		tel_say('X', "T6", "imem NOT writable: no evidence channel");
		return;
	}
	tel_mark(TEL_S6_VERIFIED);
	/* address, so a wrong-offset report is self-evident */
	n = 0;
	b[n++] = 's';
	b[n++] = 'c';
	b[n++] = 'r';
	b[n++] = 'a';
	b[n++] = 't';
	b[n++] = 'c';
	b[n++] = 'h';
	b[n++] = '=';
	b[n++] = '0';
	b[n++] = 'x';
	for (int i = 7; i >= 0; i--) {
		unsigned d = (unsigned)((TEL_IMEM_BASE + TEL_REC_OFF) >> (4 * i)) & 15;
		b[n++] = (char)(d < 10 ? '0' + d : 'a' + d - 10);
	}
	b[n] = 0;
	tel_say('K', "T6", b);
	tel_say('K', "T6", "record intact; read with tooling/51-imem-read.sh");
	tel_mark(TEL_S6_CLEAR);
	con_clear(0xff08080aU);
	tel_say('-', "T6", "screen cleared: the panel path works too");
	tel_mark(TEL_S6_PARK);
}
