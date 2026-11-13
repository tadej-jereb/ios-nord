/*
 * Milestone 4: act as iBoot for xnu.
 *
 * mkpayload.py already resolved the kernel's chained fixups and built the
 * ADT, so this only has to: find the payload in the ABL ramdisk, copy the
 * segments to phys_base + (vmaddr - virt_base), place the ADT and
 * boot_args behind the kernel, and jump to the entry point with the MMU
 * and caches off, x0 = boot_args (physical).
 *
 * Blind boot: from the jump on, nothing returns unless xnu fails, and the
 * panel is repainted by the XNU framebuffer console. So every fact here goes
 * to the UFS ring as well as the panel, and the last line before the jump is
 * written with dlog_last() (no header rewrite behind it).
 */
#include <stdint.h>
#include "console.h"
#include "diaglog.h"
#include "fdt.h"
#include "loader.h"

#define BOOT_LINE_LENGTH	608
#define PAGE_16K		0x4000UL

#define FDT_MAGIC	0xd00dfeed
#define FDT_BEGIN_NODE	1
#define FDT_END_NODE	2
#define FDT_PROP	3
#define FDT_NOP		4

struct payload_seg {
	uint64_t vmaddr, vmsize, file_off, file_size;
};

struct payload {
	char magic[8];
	uint32_t version, nsegs;
	uint64_t virt_base, entry_va, adt_off, adt_size, kernel_end;
	uint64_t phys_base, mem_size;
	char cmdline[BOOT_LINE_LENGTH];
	struct payload_seg segs[];
};

/* pexpert/pexpert/arm64/boot.h, Revision/Version 2 */
struct boot_video {
	uint64_t v_baseAddr, v_display, v_rowBytes, v_width, v_height, v_depth;
};

struct boot_args {
	uint16_t Revision, Version;
	uint64_t virtBase, physBase, memSize, topOfKernelData;
	struct boot_video Video;
	uint32_t machineType;
	uint64_t deviceTreeP;
	uint32_t deviceTreeLength;
	char CommandLine[BOOT_LINE_LENGTH];
	uint64_t bootFlags, memSizeActual;
};

_Static_assert(__builtin_offsetof(struct payload, segs) == 0x2a8, "payload header layout");
_Static_assert(__builtin_offsetof(struct boot_args, Video) == 40, "boot_args layout");
_Static_assert(__builtin_offsetof(struct boot_args, CommandLine) == 108, "boot_args layout");
_Static_assert(sizeof(struct boot_args) == 736, "boot_args layout");

/* MMU off: everything is Device memory, so copy in aligned 8-byte words. */
static void copy64(uintptr_t dst, uintptr_t src, uint64_t n)
{
	volatile uint64_t *d = (volatile uint64_t *)dst;
	volatile const uint64_t *s = (volatile const uint64_t *)src;
	for (uint64_t i = 0; i < (n + 7) / 8; i++)
		d[i] = s[i];
}

static void zero64(uintptr_t dst, uint64_t n)
{
	volatile uint64_t *d = (volatile uint64_t *)dst;
	for (uint64_t i = 0; i < n / 8; i++)
		d[i] = 0;
}

static int magic_ok(const char *m)
{
	static const char want[] = "SWEETXNU";
	for (int i = 0; i < 8; i++)
		if (m[i] != want[i])
			return 0;
	return 1;
}

/* ---- output: every loader line goes to the panel and to the ring ---- */

/*
 * diaglog.h TEXT_MAX is 96 bytes and dlog_line() spends 11 of them on the
 * stamp and the kind, so a full ring text is at most 84.
 */
#define LINE_MAX 84

/*
 * Ring text carries all 64 bits of a PA, sixteen digits: con_hex2() takes
 * uint32_t, so the panel still shows only the low half of a high-bank
 * address. Hex is lower case here, the panel's fmt_hex stays upper.
 */
static char *put_label(char *p, const char *label)
{
	while (*label)
		*p++ = *label++;
	*p++ = ' ';
	return p;
}

static char *put_hex(char *p, const char *tag, uint64_t v)
{
	static const char hex[] = "0123456789abcdef";
	while (*tag)
		*p++ = *tag++;
	*p++ = '0';
	*p++ = 'x';
	for (int s = 60; s >= 0; s -= 4)
		*p++ = hex[(v >> s) & 0xf];
	return p;
}

static void say(const char *label, const char *text)
{
	char b[LINE_MAX], *p = put_label(b, label);
	while (*text && p < b + LINE_MAX - 1)
		*p++ = *text++;
	*p = 0;
	con_str(label, text);
	dlog_line('L', b);
}

static void say_hex(const char *label, uint64_t v)
{
	char b[LINE_MAX], *p = put_hex(put_label(b, label), "", v);
	*p = 0;
	con_hex(label, v);
	dlog_line('L', b);
}

static void say_hex2(const char *label, const char *a, uint64_t va,
		     const char *b2, uint64_t vb)
{
	char b[LINE_MAX], *p = put_hex(put_label(b, label), a, va);
	*p++ = ' ';
	p = put_hex(p, b2, vb);
	*p = 0;
	con_hex2(label, a, (uint32_t)va, b2, (uint32_t)vb);
	dlog_line('L', b);
}

/* Ring only: for numbers the panel cannot show in full, or shows elsewhere. */
static void ring_hex(char kind, const char *label, uint64_t v)
{
	char b[LINE_MAX], *p = put_hex(put_label(b, label), "", v);
	*p = 0;
	dlog_line(kind, b);
}

/* Every refusal puts its own text on the ring before returning it. */
static const char *refuse(const char *why)
{
	dlog_line('X', why);
	return why;
}

static void seg_line(uint32_t idx, const struct payload_seg *s, uint64_t pa_of_va)
{
	char b[LINE_MAX], *p = put_label(b, "SEG");
	char ix[12];
	uint32_t v = idx;
	int d = 0;

	do {
		ix[d++] = (char)('0' + v % 10);
		v /= 10;
	} while (v && d < 11);
	while (d)
		*p++ = ix[--d];
	*p++ = ' ';
	p = put_hex(p, "dst=", s->vmaddr + pa_of_va);
	p = put_hex(p, " fs=", s->file_size);
	p = put_hex(p, " vs=", s->vmsize);
	*p = 0;
	dlog_line('L', b);
}

/* ---- /chosen dump (fdt.c keeps its readers private; this is the walk) ---- */

static uint32_t be32(uintptr_t a)
{
	return __builtin_bswap32(*(volatile uint32_t *)a);
}

static int streq(const char *a, const char *b)
{
	while (*a && *a == *b)
		a++, b++;
	return *a == *b;
}

static uintptr_t align4(uintptr_t a)
{
	return (a + 3) & ~3UL;
}

static uintptr_t skip_str(uintptr_t p)
{
	while (*(volatile char *)p)
		p++;
	return p + 1;
}

/* Struct offset of /chosen's first property, or 0 when there is no /chosen. */
static uintptr_t chosen_props(uintptr_t fdt, uintptr_t end)
{
	uintptr_t p = fdt + be32(fdt + 8);		/* off_dt_struct */
	int depth = 0;

	while (p + 4 <= end) {
		uint32_t tok = be32(p);
		p += 4;
		switch (tok) {
		case FDT_BEGIN_NODE: {
			const char *name = (const char *)p;
			depth++;
			p = align4(skip_str(p));
			if (depth == 2 && streq(name, "chosen"))
				return p;
			break;
		}
		case FDT_END_NODE:
			if (!--depth)
				return 0;
			break;
		case FDT_PROP:
			p = align4(p + 8 + be32(p));
			break;
		case FDT_NOP:
			break;
		default:
			return 0;
		}
	}
	return 0;
}

/*
 * Names and values of everything /chosen actually carries. A missing
 * linux,initrd-start is what the refusal below is about, and from the ring
 * alone there is otherwise no way to tell absent from hung. Ring only: the
 * panel layout does not fit a property dump, and the panel is the channel
 * that dies at the jump.
 */
static void dump_chosen(uintptr_t fdt)
{
	if (!fdt || be32(fdt) != FDT_MAGIC) {
		dlog_line('-', "CHOSEN no fdt magic at dtb");
		return;
	}
	uintptr_t end = fdt + be32(fdt + 4);		/* totalsize */
	uintptr_t strings = fdt + be32(fdt + 12);	/* off_dt_strings */
	uintptr_t p = chosen_props(fdt, end);
	if (!p) {
		dlog_line('-', "CHOSEN absent from the tree");
		return;
	}
	int seen = 0;

	while (p + 8 <= end) {
		uint32_t tok = be32(p);
		p += 4;
		if (tok == FDT_END_NODE)
			break;
		if (tok == FDT_BEGIN_NODE) {		/* a subnode: stay in step */
			p = align4(skip_str(p));
			continue;
		}
		if (tok != FDT_PROP)
			continue;
		uint32_t len = be32(p), nameoff = be32(p + 4);
		uintptr_t val = p + 8;
		p = align4(val + len);
		if (p > end)
			break;
		const char *name = (const char *)(strings + nameoff);
		char b[LINE_MAX], *q = put_label(b, "CHOSEN");
		for (int i = 0; name[i] && i < 32 && q < b + LINE_MAX - 20; i++)
			*q++ = name[i];
		*q++ = '=';
		if (len == 4 || len == 8) {		/* the numeric ones */
			uint64_t v = be32(val);
			if (len == 8)
				v = v << 32 | be32(val + 4);
			q = put_hex(q, "", v);
		} else {				/* text, or bytes as dots */
			for (uint32_t i = 0; i < len && q < b + LINE_MAX - 1; i++) {
				char c = *(volatile char *)(val + i);
				*q++ = c >= 0x20 && c < 0x7f ? c : '.';
			}
		}
		*q = 0;
		dlog_line('-', b);
		seen++;
	}
	ring_hex('-', "CHOSEN props", (uint64_t)seen);
}

typedef void (*xnu_entry_t)(uint64_t boot_args_pa);

const char *loader_boot(uintptr_t dtb)
{
	uint64_t rd_start = 0, rd_end = 0;

	dump_chosen(dtb);

	int have_lo = fdt_chosen_u64(dtb, "linux,initrd-start", &rd_start);
	int have_hi = have_lo && fdt_chosen_u64(dtb, "linux,initrd-end", &rd_end);
	ring_hex(have_lo ? 'L' : 'X', "INITRD lo", rd_start);
	ring_hex(have_hi ? 'L' : 'X', "INITRD hi", rd_end);
	if (!have_lo || !have_hi)
		return refuse("no initrd in /chosen");
	say_hex2("INITRD", "lo=", rd_start, "hi=", rd_end);

	const struct payload *p = (const struct payload *)rd_start;
	if (!magic_ok(p->magic))
		return refuse("no SWEETXNU payload");
	if (p->version != 1 || (p->adt_off & 7) || (rd_start & 7))
		return refuse("bad payload header");

	uint64_t pa_of_va_base = p->phys_base - p->virt_base;	/* pa = va + this */
	say_hex2("PHYS", "base=", p->phys_base, "size=", p->mem_size);
	say_hex("VIRT", p->virt_base);
	say_hex("ENTRY", p->entry_va);

	/* The payload must not overlap where the kernel goes. */
	if (rd_end > p->phys_base && rd_start < p->phys_base + p->mem_size)
		return refuse("ramdisk overlaps kernel memory");

	/* One line per segment before the first copy: a bad destination is on
	 * the ring before anything writes to it. */
	for (uint32_t i = 0; i < p->nsegs; i++)
		seg_line(i, &p->segs[i], pa_of_va_base);

	for (uint32_t i = 0; i < p->nsegs; i++) {
		const struct payload_seg *s = &p->segs[i];
		uintptr_t dst = s->vmaddr + pa_of_va_base;
		copy64(dst, rd_start + s->file_off, s->file_size);
		if (s->vmsize > s->file_size)
			zero64(dst + ((s->file_size + 7) & ~7UL), s->vmsize - ((s->file_size + 7) & ~7UL));
	}
	say_hex2("SEGS", "n=", p->nsegs, "end=", p->kernel_end + pa_of_va_base);

	/* ADT, then boot_args, behind the kernel; everything below topOfKernelData is ours. */
	uintptr_t adt_pa = p->kernel_end + pa_of_va_base;
	copy64(adt_pa, rd_start + p->adt_off, p->adt_size);
	uintptr_t ba_pa = (adt_pa + p->adt_size + PAGE_16K - 1) & ~(PAGE_16K - 1);
	uintptr_t top = ba_pa + PAGE_16K;

	zero64(ba_pa, PAGE_16K);
	volatile struct boot_args *ba = (volatile struct boot_args *)ba_pa;
	ba->Revision = 2;
	ba->Version = 2;
	ba->virtBase = p->virt_base;
	ba->physBase = p->phys_base;
	ba->memSize = p->mem_size;
	ba->topOfKernelData = top;
	ba->Video.v_baseAddr = FB_BASE;
	ba->Video.v_display = 1;
	ba->Video.v_rowBytes = FB_STRIDE;
	ba->Video.v_width = FB_W;
	ba->Video.v_height = FB_H;
	ba->Video.v_depth = 32;
	ba->deviceTreeP = adt_pa - pa_of_va_base;	/* xnu reads it with the MMU on: a VA */
	ba->deviceTreeLength = (uint32_t)p->adt_size;
	for (int i = 0; i < BOOT_LINE_LENGTH; i++)
		ba->CommandLine[i] = p->cmdline[i];
	/* A hand-built payload need not terminate; keep PE_parse_boot_argn in bounds. */
	ba->CommandLine[BOOT_LINE_LENGTH - 1] = 0;
	ba->memSizeActual = p->mem_size;
	say_hex2("BOOTARG", "pa=", ba_pa, "top=", top);

	uintptr_t entry_pa = p->entry_va + pa_of_va_base;
	say_hex("JUMP", entry_pa);
	say("XNU", "jumping (fbcon clears screen)");

	/* Everything was written with the MMU and caches off; drop any stale I-cache lines too. */
	__asm__ volatile("dsb sy; ic iallu; dsb sy; isb" ::: "memory");

	/* Written last, header untouched: if this never returns, the entry PA is
	 * the newest line in the ring and no UFS command is left in flight. */
	{
		char b[LINE_MAX], *q = put_hex(put_label(b, "ENTRYPA"), "", entry_pa);
		*q = 0;
		dlog_last(b);
	}
	((xnu_entry_t)entry_pa)(ba_pa);

	dlog_last("LOADER xnu returned");
	return "xnu returned";
}
