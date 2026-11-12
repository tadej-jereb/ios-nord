/*
 * The diag ladder: the first images that are safe to run on hardware.
 *
 * One rung per DIAG_STAGE, compiled cumulatively (stage 3 carries rungs 1-3).
 * Every rung announces itself on the panel and in the UFS ring *before* it
 * touches the block it probes, so a hang or a reset always names its own last
 * step - on screen while it is up, and in the ring afterwards.
 *
 * Rules the rungs keep:
 *   - rungs 1 and 2 only read controller registers, no init, no reset
 *   - rung 3 only writes inside cont_splash_region, after checking the live
 *     FDT that the region really covers the framebuffer; no MDP/DSI writes,
 *     the ABL's command-mode scan-out keeps running and shows the fill
 *   - rung 4 is the only one that changes machine state (secondary cores)
 *   - rung 5 prints mismatches, never panics, so a bad /memory still leaves
 *     the rest of the rung list readable
 *
 * DIAG_STAGE=0 compiles to nothing and lets shim.c run its normal milestone
 * path unchanged.
 */
#include <stdint.h>
#include "console.h"
#include "diag.h"
#include "diaglog.h"
#include "fdt.h"
#include "memtab.h"
#include "mmu.h"
#include "tel.h"
#include "ufs.h"

/* The image is freestanding: clang emits calls to these for struct and array
 * initialisers, so they have to exist. */
void *memset(void *dst, int c, unsigned long n)
{
	volatile uint8_t *d = dst;
	while (n--)
		*d++ = (uint8_t)c;
	return dst;
}

void *memcpy(void *dst, const void *src, unsigned long n)
{
	volatile uint8_t *d = dst;
	const uint8_t *s = src;
	while (n--)
		*d++ = *s++;
	return dst;
}

#ifndef DIAG_STAGE
#define DIAG_STAGE 5
#endif
/* DIAG_LOG=0: never write; the image is then fully read-only on the device. */
#ifndef DIAG_LOG
#define DIAG_LOG 1
#endif
#define STR2(x) #x
#define STR(x) STR2(x)
#if DIAG_STAGE >= 6
#define STAGE_TOTAL 8
#else
#define STAGE_TOTAL 5
#endif
#define STAGE_S "stage " STR(DIAG_STAGE) " of " STR(STAGE_TOTAL)

#define GICD_BASE	0x17a00000UL
/* 0xfe8 is the 4 KiB-frame offset; the GICD frame is 64 KiB and its ID space
 * starts at 0xffd0, so 0xfe8 reads RAZ (measured on avicii 2026-11-12:
 * pidr2=0 while typer answered 0x7b041d). PIDR2 is 0xffe8. */
#define GICD_PIDR2	(GICD_BASE + 0xffe8)
#define GICD_TYPER	(GICD_BASE + 0x004)
#define UFSHCI_BASE	0x1d84000UL
#define UFS_PHY_PCS	0x1d87008UL	/* PHY PCS status, MPHY lane state */

#define HCI_CAP		0x00		/* UFSHCI: CAP is at 0x00, VER at 0x08 */
#define HCI_VERSION	0x08
#define HCI_HCS		0x30		/* bit0 DP, bit3 UCRDY */

#define PSCI_CPU_ON	0xc4000003UL

#define FB_ROW_BYTES	((uint64_t)FB_W * 4)
#define FB_PAD_WORDS	((FB_STRIDE - FB_ROW_BYTES) / 8)
#define MAGENTA64	0xffff00fffff00ffULL

extern void secondary_entry(void);
extern void sec_stub(void);
extern void _start(void);

#if DIAG_STAGE >= 1
static const char *rung_name;
static int diag_mode;
static uint64_t freq, t0;

int diag_active(void)
{
	return diag_mode;
}

const char *diag_stage_name(void)
{
	return rung_name;
}

static uint64_t ticks(void)
{
	uint64_t t;
	__asm__ volatile("isb; mrs %0, cntvct_el0" : "=r"(t));
	return t;
}

static uint32_t __attribute__((unused)) ms_since(uint64_t start)
{
	if (!freq) {
		__asm__ volatile("isb; mrs %0, cntfrq_el0" : "=r"(freq));
		freq /= 1000;
		if (!freq)
			freq = 1;
	}
	return (uint32_t)((ticks() - start) / freq);
}

static void hex8(char *out, uint32_t v)
{
	static const char d[] = "0123456789abcdef";
	for (int i = 7; i >= 0; i--) {
		out[i] = d[v & 15];
		v >>= 4;
	}
	out[8] = 0;
}

static unsigned append(char *dst, unsigned n, const char *s)
{
	while (*s)
		dst[n++] = *s++;
	return n;
}

/* Panel first (no block touch), then the same text into the UFS ring. */
static void say(char kind, const char *label, const char *text)
{
	char buf[80];
	unsigned n = 0;
	n = append(buf, n, label);
	buf[n++] = ' ';
	for (unsigned i = 0; text[i] && n < sizeof(buf) - 1; i++)
		buf[n++] = text[i];
	buf[n] = 0;
	con_str(label, text);
	dlog_line(kind, buf);
}

/* "<tag> <label>0x<hi><lo>" into out; returns length. */
static unsigned hexline(char *out, const char *tag, uint64_t v)
{
	char b[12];
	unsigned n = 0;
	n = append(out, n, tag);
	n = append(out, n, "0x");
	hex8(b, (uint32_t)(v >> 32));
	for (int i = 0; i < 8; i++)
		out[n++] = b[i];
	hex8(b, (uint32_t)v);
	for (int i = 0; i < 8; i++)
		out[n++] = b[i];
	out[n] = 0;
	return n;
}

/* One rung line: this is the marker a hang leaves behind. */
static void rung(int n, const char *name)
{
	rung_name = name;
	char label[3] = { 'D', (char)('0' + n), 0 };
	char text[64];
	unsigned k = append(text, 0, name);
	k = append(text, k, " begin");
	text[k] = 0;
	say('B', label, text);
}

static void park(void)
{
	/* wall-clock guard: a parked image must not need the power button.
	 * `freq` is ticks per *millisecond* (cntfrq/1000), so the ms factor is
	 * 60000, not 60 - with 60 the "60 s" park lasted 58 ms (measured
	 * 2026-11-12: deadline-tick 1 109 313 instead of 1.15e9). */
	uint64_t deadline = ticks() + (60000ULL * (freq ? freq : 19200));
	{
		/* deadline math vs reality: cntfrq claims 19.2 MHz, the park ends
		 * after ~4.5 s of its own stamps (2026-11-12). Print both halves. */
		char b[48];
		hexline(b, "park freq=", freq);
		say('-', "DBG", b);
		hexline(b, "park ticks=", ticks());
		say('-', "DBG", b);
		hexline(b, "park deadline=", deadline);
		say('-', "DBG", b);
	}
	say('-', "END", "park 60 s, then self-reset");
	say('-', "END", "log: tooling/42-log-pull.sh, docs/DIAG.md");
	while (ticks() < deadline)
		__asm__ volatile("wfe");
	say('-', "END", "60 s park over: PSCI reset");
	/* The shim runs at EL2, where the PSCI conduit is HVC; only EL3 sees SMC.
	 * The bare `smc` never reset this unit (measured 2026-11-12: printed, then
	 * hung), so try HVC first and keep SMC as the fallback. */
	__asm__ volatile("mov x0, #0\n	ldr x1, =0x84000009\n	hvc #0" ::: "x0", "x1");
	say('-', "END", "HVC reset returned; trying SMC");
	__asm__ volatile("mov x0, #0\n	ldr x1, =0x84000009\n	smc #0" ::: "x0", "x1");
	for (;;)
		__asm__ volatile("wfe");
}
#endif

#if DIAG_STAGE >= 3
static int prefix(const char *s, const char *p)
{
	while (*p)
		if (*s++ != *p++)
			return 0;
	return 1;
}

static int dstrncmp(const char *a, const char *b, unsigned n)
{
	while (n--) {
		if (*a != *b)
			return (int)(uint8_t)*a - (int)(uint8_t)*b;
		if (!*a)
			return 0;
		a++;
		b++;
	}
	return 0;
}
#endif

/* ---- rung 1: GIC, read-only ------------------------------------------- */
#if DIAG_STAGE >= 1
static void stage1(void)
{
	rung(1, "gic probe read-only");
	uint32_t pidr2 = *(volatile uint32_t *)GICD_PIDR2;
	uint32_t typer = *(volatile uint32_t *)GICD_TYPER;
	char t[40];

	con_hex2("D1 pidr2", "pidr2=", pidr2, "arch=", (pidr2 >> 4) & 15);
	say('K', "D1", "read gicd_pidr2");
	hexline(t, "pidr2=", pidr2);
	say('K', "D1", t);

	con_hex2("D1 typer", "typer=", typer, "grp=", (typer & 0x1f) + 1);
	hexline(t, "typer=", typer);
	say('K', "D1", t);

	if (((pidr2 >> 4) & 15) == 3)
		say('K', "D1", "gicv3 ok, arch nibble 3");
	else
		say('X', "D1", "not gicv3: arch nibble != 3");
	uint32_t grp = (typer & 0x1f) + 1;	/* groups of 32 INTIDs */
	con_hex2("D1 itlines", "groups=", grp, "max_intid=", grp * 32 - 1);
	if (grp >= 8 && grp <= 31)
		say('K', "D1", "itlines sane for an SoC");
	else
		say('X', "D1", "itlines out of range (0x1f = all ones?)");
}
#endif

/* ---- rung 2: UFS registers, read-only --------------------------------- */
#if DIAG_STAGE >= 2
static void stage2(void)
{
	rung(2, "ufs probe read-only");
	uint32_t ver = *(volatile uint32_t *)(UFSHCI_BASE + HCI_VERSION);
	uint32_t cap = *(volatile uint32_t *)(UFSHCI_BASE + HCI_CAP);
	uint32_t hcs = *(volatile uint32_t *)(UFSHCI_BASE + HCI_HCS);
	uint32_t pcs = *(volatile uint32_t *)UFS_PHY_PCS;
	char t[40];
	/* UFSHCI VER is major in [15:8], minor in [7:0]: 0x300 is HCI 3.0, so
	 * comparing it against 0x00010000 reads 3.0 as implausible. */
	uint32_t major = (ver >> 8) & 0xff, minor = ver & 0xff;
	(void)minor;

	con_hex2("D2 hci", "version=", ver, "cap=", cap);
	hexline(t, "version=", ver);
	say('K', "D2", t);
	hexline(t, "cap=", cap);
	say('K', "D2", t);
	hexline(t, "hcs=", hcs);
	say('K', "D2", t);
	if (hcs & 1)
		say('K', "D2", "hcs DP set, device present");
	else
		say('X', "D2", "hcs DP clear: no device seen by the host");

	con_hex2("D2 phy", "pcs=", pcs, "rx_lane=", (pcs >> 16) & 3);
	hexline(t, "pcs=", pcs);
	say('K', "D2", t);
	{
		/* 0x1d87008 has no precedent in any sibling port, so scan the PHY
		 * window read-only instead of trusting one offset. The QMP PCS-ready
		 * status sits high in the serdes block in Qualcomm's own driver. */
		static const uint32_t phy_off[] = { 0x00, 0x08, 0x160, 0x16c, 0x1c0, 0x1d4 };
		for (unsigned i = 0; i < sizeof(phy_off) / sizeof(phy_off[0]); i++) {
			unsigned n = 0;
			t[n++] = 'p'; t[n++] = 'h'; t[n++] = 'y'; t[n++] = '+';
			t[n++] = '0'; t[n++] = 'x';
			static const char hx[] = "0123456789abcdef";
			t[n++] = hx[(phy_off[i] >> 8) & 15];
			t[n++] = hx[(phy_off[i] >> 4) & 15];
			t[n++] = hx[phy_off[i] & 15];
			t[n++] = '=';
			t[n] = 0;
			hexline(t + n, "", *(volatile uint32_t *)(0x1d87000UL + phy_off[i]));
			say('K', "D2", t);
		}
	}

	if (major >= 1 && major <= 3)
		say('K', "D2", major == 3 ? "hci 3.0 plausible" : "hci major 1-3 plausible");
	else
		say('X', "D2", "hci version implausible");
	if (pcs && pcs != 0xffffffffU)
		say('K', "D2", "phy pcs not stuck");
	else if (!pcs && (hcs & 1))
		say('K', "D2", "pcs 0 with DP set: PHY idle or offset, not a fault");
	else
		say('X', "D2", "phy pcs stuck at 0/all-ones");
}
#endif

/* ---- rung 3: splash buffer, one pattern, then hold --------------------- */
#if DIAG_STAGE >= 3
struct resv_chk {
	uint64_t base, size;
	int found;
};

static int resv_cb(void *ctx, const char *parent, const char *name, uint64_t base, uint64_t size)
{
	struct resv_chk *c = ctx;
	if (__builtin_strcmp(parent, "reserved-memory") || prefix(name, "cont_splash_region") == 0)
		return 1;
	c->base = base;
	c->size = size;
	c->found = 1;
	return 0;		/* one is enough */
}

static void stage3(uintptr_t fdt)
{
	rung(3, "splash fill magenta");
	struct resv_chk c = { 0, 0, 0 };
	char t[48];

	if (fdt_reg_walk(fdt, resv_cb, &c) < 0) {
		say('X', "D3", "x0 is not an FDT, splash unchecked");
		return;
	}
	if (!c.found) {
		say('X', "D3", "no cont_splash_region in live fdt");
		return;
	}
	hexline(t, "splash base=", c.base);
	say('K', "D3", t);
	hexline(t, "splash size=", c.size);
	say('K', "D3", t);

	if (c.base != FB_BASE || c.size < (uint64_t)FB_H * FB_STRIDE) {
		say('X', "D3", "region != 0xa0000000/0x2300000, no paint");
		return;
	}
	say('K', "D3", "region matches, painting pattern MAGENTA");

	uint64_t start = ticks();
	con_clear(MAGENTA);		/* also puts the text row back to 0 */
	/* con_clear covers 1080 px; the 120 px panel pad would keep splash
	 * pixels at the right edge, so paint that too */
	volatile uint64_t *base = (volatile uint64_t *)FB_BASE;
	for (uint64_t y = 0; y < FB_H; y++) {
		volatile uint64_t *p = base + y * (FB_STRIDE / 8) + (FB_ROW_BYTES / 8);
		for (uint64_t i = 0; i < (uint64_t)FB_PAD_WORDS; i++)
			p[i] = MAGENTA64;
	}
	char m[48] = "painted, ms=";
	char b[12];
	hex8(b, ms_since(start));
	append(m, 12, b);
	say('K', "D3", m);
	/* Geometry ruler, camera-tolerant: three 4-px vertical bars at x=8,
	 * FB_W/2 and FB_W-8, all FB_H rows. Straight bars = FB_STRIDE is the
	 * panel's real row pitch; each bar slants by FB_H*(error)/4 px if not. */
	for (uint64_t y = 0; y < FB_H; y++) {
		volatile uint32_t *r = (volatile uint32_t *)FB_BASE + y * (FB_STRIDE / 4);
		for (int i = 0; i < 4; i++) {
			r[8 + i] = RED;
			r[FB_W / 2 + i] = WHITE;
			r[FB_W - 8 + i] = BLUE;
		}
	}
	hexline(t, "ruler stride=", FB_STRIDE);
	say('K', "D3", t);
	say('K', "D3", "ruler: 3 bars, straight = correct stride");
	say('-', "D3", "no MDP/DSI writes: ABL scan-out still showing");
}
#endif

/* ---- rung 4: PSCI CPU_ON per core, ack, spin -------------------------- */
#if DIAG_STAGE >= 4
static volatile uint64_t sec_spin[8];
volatile uint64_t sec_probe[8];
static volatile int sec_stop;

void diag_secondary(uint64_t idx)
{
	if (idx < 8) {
		uint64_t n = 0;
		/* bounded: a secondary never outlives the primary's rung */
		while (!sec_stop && n < 0x4000000ULL)
			n++;
		sec_spin[idx] = n;
	}
}

static int64_t smc(uint64_t fn, uint64_t a1, uint64_t a2, uint64_t a3)
{
	register uint64_t x0 __asm__("x0") = fn;
	register uint64_t x1 __asm__("x1") = a1;
	register uint64_t x2 __asm__("x2") = a2;
	register uint64_t x3 __asm__("x3") = a3;
	__asm__ volatile("smc #0" : "+r"(x0), "+r"(x1), "+r"(x2), "+r"(x3) : : "memory");
	return (int64_t)x0;
}

static void stage4(void)
{
	rung(4, "psci cpu_on 0x100-0x700");
	int on = 0;
	/* The image runs wherever ABL put it (0xa7e80000 here), so the entry must
	 * be relocated. Take the offset as a link-time difference between two
	 * text symbols instead of a symbol address: adding the symbol address to
	 * kimg_base came out as 2*base+off and hung the caller in CPU_ON
	 * (measured 2026-11-12). */
	uintptr_t entry = kimg_base + ((uintptr_t)secondary_entry - (uintptr_t)_start);
	uintptr_t stub = kimg_base + ((uintptr_t)sec_stub - (uintptr_t)_start);
	{
		char e[40];
		hexline(e, "kimg=", kimg_base);
		say('-', "D4", e);
		hexline(e, "sec_entry=", (uintptr_t)secondary_entry);
		say('-', "D4", e);
		hexline(e, "entry=", entry);
		say('-', "D4", e);
	}
	/* Only the caller's own sibling: same cluster, so no cluster rail vote is
	 * involved (2026-11-12 probe). */
	uint64_t self;
	__asm__ volatile("mrs %0, mpidr_el1" : "=r"(self));
	self &= 0xffff;
	{
		char m[40];
		hexline(m, "self mpidr=", self);
		say('-', "D4", m);
	}
	int i = (int)((self & 0x100) ? (self >> 8) - 1 : (self >> 8) + 1);
	uint64_t target = (uint64_t)i << 8;
	for (int once = 0; once < 1; once++) {
		int64_t r = smc(PSCI_CPU_ON, target, stub, (uint64_t)i);
		char t[48] = "mpidr=0x";
		char b[12];
		hex8(b, (uint32_t)i << 8);
		for (int k = 0; k < 8; k++)
			t[8 + k] = b[k];
		unsigned n = append(t, 16, " ret=0x");
		hex8(b, (uint32_t)(uint64_t)r);
		for (int k = 0; k < 8; k++)
			t[n++] = b[k];
		t[n] = 0;
		if (!r)
			on++;
		say(r ? 'X' : 'K', "D4", t);
	}
	{
		/* Read the probe before any delay: the run aborts during the spin on
		 * this unit (2026-11-12), so an ack must be captured immediately. */
		char p[40];
		hexline(p, "probe now=", sec_probe[i]);
		say('-', "D4", p);
	}
	say('-', "D4", "spin 200 ms");

	uint64_t start = ticks();
	while (ms_since(start) < 200)
		;
	uint32_t mask = 0;
	if (sec_probe[i])
		mask |= 1u << i;
	sec_stop = 1;

	con_hex2("D4", "released=", (uint32_t)on, "ackmask=", mask);
	char t[48];
	hexline(t, "probe mask=", mask);
	say(mask == 0xfeu ? 'K' : 'X', "D4", t);
	for (int i = 1; i < 8; i += 4) {
		char s[64] = "probe ";
		unsigned n = 6;
		for (int k = i; k < i + 4 && k < 8; k++) {
			s[n++] = (char)('0' + k);
			s[n++] = '=';
			hex8(s + n, (uint32_t)sec_probe[k]);
			n += 8;
			s[n++] = ' ';
		}
		s[n] = 0;
		say('-', "D4", s);
	}
	if (mask == 0xfeu)
		say('K', "D4", "all 7 secondaries reached the stub");
	else
		say('X', "D4", "not every released core reached the stub");
}
#endif

/* ---- rung 5: /memory against the generated table ---------------------- */
#if DIAG_STAGE >= 5
#define MAXMEM 8
struct mem_scan {
	uint64_t base[MAXMEM], size[MAXMEM];
	int n;
};

static int mem_cb(void *ctx, const char *parent, const char *name, uint64_t base, uint64_t size)
{
	struct mem_scan *m = ctx;
	(void)parent;
	/* exactly "memory" or "memory@<unit>" - not memory-controller */
	if (dstrncmp(name, "memory", 6) || (name[6] && name[6] != '@'))
		return 1;
	if (m->n < MAXMEM) {
		m->base[m->n] = base;
		m->size[m->n] = size;
		m->n++;
	}
	return 1;
}

static uint64_t top_end(const struct mem_scan *m)
{
	uint64_t top = 0;
	for (int i = 0; i < m->n; i++)
		if (m->base[i] + m->size[i] > top)
			top = m->base[i] + m->size[i];
	return top;
}

static int covered(const struct mem_scan *m, uint64_t base, uint64_t size)
{
	for (int i = 0; i < m->n; i++)
		if (base >= m->base[i] && base + size <= m->base[i] + m->size[i])
			return 1;
	return 0;
}

static int overlaps(const struct mem_scan *m, uint64_t base, uint64_t size)
{
	for (int i = 0; i < m->n; i++)
		if (base < m->base[i] + m->size[i] && m->base[i] < base + size)
			return 1;
	return 0;
}

static const char *co_name(char tag)
{
	switch (tag) {
	case 'g': return "gicd";
	case 'r': return "gicr";
	case 's': return "splash";
	default: return "ufs";
	}
}

static void stage5(uintptr_t fdt)
{
	static const struct mt_carveout co[] = { MT_CARVEOUTS };
	struct mem_scan m = { { 0 }, { 0 }, 0 };
	char t[48];
	int bad = 0;

	rung(5, "memory map self-check");
	if (!fdt) {
		say('X', "D5", "x0 is null");
		return;
	}
	if (fdt_reg_walk(fdt, mem_cb, &m) < 0) {
		say('X', "D5", "x0 is not an FDT");
		return;
	}
	if (!m.n) {
		say('X', "D5", "no /memory in x0 (fragment without memory node?)");
		return;
	}
	uint64_t total = 0;
	for (int i = 0; i < m.n; i++) {
		hexline(t, "mem base=", m.base[i]);
		say('-', "D5", t);
		hexline(t, "mem size=", m.size[i]);
		say('-', "D5", t);
		total += m.size[i];

		if (m.base[i] < 0x80000000UL) {
			say('X', "D5", "extent below 0x80000000");
			bad++;
		}
		if (m.size[i] < MT_MIN_MEM_SIZE) {
			say('X', "D5", "extent below MIN_MEM_SIZE");
			bad++;
		}
	}
	/* carve-outs are a set question, not a per-extent one */
	for (unsigned c = 0; c < MT_N_CARVEOUTS; c++) {
		if (!overlaps(&m, co[c].base, co[c].size))
			continue;
		if (co[c].tag == 's')
			/* reserved-memory carves out of /memory, so the splash
			 * sitting inside dram is the done thing */
			say('K', "D5", "splash carve inside dram, expected");
		else {
			char w[40] = "extent overlaps ";
			append(w, 16, co_name(co[c].tag));
			say('X', "D5", w);
			bad++;
		}
	}
	con_hex2("D5 total", "hi=", (uint32_t)(total >> 32), "lo=", (uint32_t)total);
	hexline(t, "total=", total);
	say('-', "D5", t);

	if (total < MT_MIN_MEM_SIZE) {
		say('X', "D5", "total dram below MIN_MEM_SIZE");
		bad++;
	}
	uint64_t top = top_end(&m);
	if (top <= MT_4G) {
		say('X', "D5", "dram ends below 4 GiB: no panic log carve");
		bad++;
	} else {
		say('K', "D5", "dram reaches above 4 GiB");
	}
	if (!covered(&m, MT_DEFAULT_PHYS_BASE, MT_DEFAULT_MEM_SIZE)) {
		say('X', "D5", "mkadt fallback 0xb0000000+0x4d000000 outside dram");
		bad++;
	} else {
		say('K', "D5", "mkadt fallback window inside dram");
	}
	if (!covered(&m, top - MT_PANIC_LOG_SIZE, MT_PANIC_LOG_SIZE)) {
		say('X', "D5", "top 1 MiB not inside one extent");
		bad++;
	}
	char r[24] = "RESULT mismatch=";
	r[16] = (char)('0' + bad / 10);
	r[17] = (char)('0' + bad % 10);
	r[18] = 0;
	say(bad ? 'X' : 'K', "D5", r);
}
#endif

#if DIAG_STAGE < 4
void diag_secondary(uint64_t idx)
{
	(void)idx;
}
#endif

#if DIAG_STAGE < 1
int diag_active(void)
{
	return 0;
}

const char *diag_stage_name(void)
{
	return 0;
}
#endif

int diag_run(uintptr_t fdt)
{
#if DIAG_STAGE < 1
	(void)fdt;
	return 0;
#else
	diag_mode = 1;
#if DIAG_STAGE >= 6
	/*
	 * Telemetry first: the ring and the console are both unproven on this
	 * command-mode panel, so every cheap side effect that survives a reset is
	 * laid down before either is touched. The ring then comes *after* the
	 * record (step 2c): a ring line can never be the first evidence, and
	 * dlog_init hanging still leaves "code ran this far" in IMEM.
	 */
	tel_begin(DIAG_STAGE);
	tel_imem_rung();
#if DIAG_STAGE >= 7
	tel_gpio_rung();
	tel_spmi_rung();
#endif
#if DIAG_STAGE >= 8
	tel_haptic_rung();
#endif
	tel_alive_ms(0);
	tel_mark(DIAG_STAGE >= 8 ? TEL_S8_PARK : DIAG_STAGE == 7 ? TEL_S7_PARK : TEL_S6_PARK);
	tel_say('-', "END", "telemetry rungs done; unproven path continues");
#endif
#if DIAG_STAGE < 3
	(void)fdt;
#endif
	__asm__ volatile("isb; mrs %0, cntfrq_el0" : "=r"(freq));
	freq /= 1000;
	if (!freq)
		freq = 1;
	t0 = ticks();

	/* Log first, console second: the console is unproven on this command-mode panel,
	 * so the ring must be up before anything that could fault on the display path. */
	int lrc = 0;
#if DIAG_LOG
	lrc = dlog_init();
	if (!lrc)
		dlog_line('-', "SHIM diag " STAGE_S " start (pre-console)");
#endif
	con_clear(0xff08080aU);
	say('-', "SHIM", "avicii DIAG " STAGE_S);
	say('-', "SHIM", "rungs are cumulative; last line = last step run");
	{
		/* Load base: the header asks for 0x8000. Anything else here is the
		 * first thing to look at when a rung dies early. */
		char b[40];
		hexline(b, "load base=", kimg_base);
		say('-', "SHIM", b);
	}
	{
		/* cntfrq_el0 is what every ms stamp and the park deadline derive
		 * from. Print it raw so the ratio can be measured against a wall
		 * clock instead of trusted (measured 2026-11-12: the stamps run
		 * ~13x fast here, i.e. the register disagrees with the counter). */
		char b[40];
		uint64_t f;
		__asm__ volatile("isb; mrs %0, cntfrq_el0" : "=r"(f));
		hexline(b, "cntfrq=", f);
		say('-', "SHIM", b);
	}
	if (!DIAG_LOG) {
		con_str("LOG", "off (DIAG_LOG=0): image writes nothing");
	} else if (lrc) {
		con_hex2("LOG", "off, ufs/gpt rc=", (uint32_t)lrc, "panel only", 0);
		dlog_line('-', "SHIM log init failed, console only");
	} else {
		con_str("LOG", "on: last 1024 blocks of userdata");
		if (dlog_warn()) {
			char wb[40];
			hexline(wb, "LOG warn rc=", (uint64_t)dlog_warn());
			say('-', "SHIM", wb);
		}
		dlog_line('-', "SHIM console up (pre-console marker present = it crashed here)");
	}

#if DIAG_STAGE >= 1
	stage1();
#endif
#if DIAG_STAGE >= 2
	stage2();
#endif
#if DIAG_STAGE >= 3
	stage3(fdt);
#endif
#if DIAG_STAGE >= 4
	stage4();
#endif
#if DIAG_STAGE >= 5
	stage5(fdt);
#endif

	rung_name = "park";
	park();
	return 1;
#endif
}
