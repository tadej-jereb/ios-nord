/*
 * Just enough flattened-device-tree parsing to find what ABL put in
 * /chosen (initrd location). Big-endian, 4-byte aligned tokens.
 */
#include "fdt.h"

#define FDT_MAGIC	0xd00dfeed
#define FDT_BEGIN_NODE	1
#define FDT_END_NODE	2
#define FDT_PROP	3
#define FDT_NOP		4
#define FDT_END		9

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
	/* byte loads are fine on Device memory as long as they are aligned to 1 */
	while (*(volatile char *)p)
		p++;
	return p + 1;
}

int fdt_chosen_u64(uintptr_t fdt, const char *prop, uint64_t *out)
{
	if (!fdt || be32(fdt) != FDT_MAGIC)
		return 0;
	uintptr_t p = fdt + be32(fdt + 8);		/* off_dt_struct */
	uintptr_t strings = fdt + be32(fdt + 12);	/* off_dt_strings */
	int depth = 0, in_chosen = 0;

	for (;;) {
		uint32_t tok = be32(p);
		p += 4;
		switch (tok) {
		case FDT_BEGIN_NODE: {
			const char *name = (const char *)p;
			depth++;
			in_chosen = depth == 2 && streq(name, "chosen");
			p = align4(skip_str(p));
			break;
		}
		case FDT_END_NODE:
			if (in_chosen)
				return 0;
			depth--;
			break;
		case FDT_PROP: {
			uint32_t len = be32(p), nameoff = be32(p + 4);
			uintptr_t val = p + 8;
			if (in_chosen && streq((const char *)(strings + nameoff), prop)) {
				if (len == 4)
					*out = be32(val);
				else if (len == 8)
					*out = (uint64_t)be32(val) << 32 | be32(val + 4);
				else
					return 0;
				return 1;
			}
			p = align4(val + len);
			break;
		}
		case FDT_NOP:
			break;
		default:	/* FDT_END or garbage */
			return 0;
		}
	}
}

static uint32_t be32_at(uintptr_t a, uintptr_t end, int *ok)
{
	if (a + 4 > end) {
		*ok = 0;
		return 0;
	}
	return be32(a);
}

/*
 * Walk every reg entry two levels down. Node names live inside the struct
 * block, so the callback can read them directly; they stay points into the
 * tree, which is fine for the duration of the call.
 */
int fdt_reg_walk(uintptr_t fdt, fdt_reg_cb cb, void *ctx)
{
	if (!fdt || be32(fdt) != FDT_MAGIC)
		return -1;
	uintptr_t end = fdt + be32(fdt + 4);		/* totalsize */
	uintptr_t p = fdt + be32(fdt + 8);
	uintptr_t strings = fdt + be32(fdt + 12);
	int depth = 0, ac = 2, sc = 1, seen = 0, ok = 1;
	char nm[5][64] = { { 0 } };
	char parent[64], node[64] = "";

	if (!be32(fdt + 4) || be32(fdt + 4) < 256)
		return -1;

	while (ok) {
		if (p + 4 > end)
			break;
		uint32_t tok = be32(p);
		p += 4;
		switch (tok) {
		case FDT_BEGIN_NODE: {
			uintptr_t start = p;
			p = align4(skip_str(p));
			if (p > end)
				return seen;
			char *dst = nm[depth < 5 ? depth : 4];
			int i = 0;
			for (; i < 63 && *(volatile char *)(start + i); i++)
				dst[i] = *(volatile char *)(start + i);
			dst[i] = 0;
			depth++;
			break;
		}
		case FDT_END_NODE:
			depth--;
			if (!depth)
				return seen;
			break;
		case FDT_PROP: {
			if (p + 8 > end)
				return seen;
			uint32_t len = be32(p), nameoff = be32(p + 4);
			uintptr_t val = p + 8;
			const char *pn = (const char *)(strings + nameoff);
			p = align4(val + len);
			if (p > end)
				return seen;
			if (depth == 1 && pn[0] == '#') {
				uint32_t v = len == 4 ? be32(val) : 0;
				if (streq(pn, "#address-cells") && v && v <= 2)
					ac = (int)v;
				if (streq(pn, "#size-cells") && v <= 2)
					sc = (int)v;
				break;
			}
			if (depth < 2 || streq(pn, "reg") == 0)
				break;
			/* node is the one whose BEGIN got us here, parent the one
			 * above it; both live in the name stack */
			{
				const char *nsrc = nm[depth - 1 < 5 ? depth - 1 : 4];
				int i = 0;
				for (; i < 63 && nsrc[i]; i++)
					node[i] = nsrc[i];
				node[i] = 0;
				parent[0] = 0;
				if (depth >= 3) {
					const char *psrc = nm[depth - 2 < 5 ? depth - 2 : 4];
					for (i = 0; i < 63 && psrc[i]; i++)
						parent[i] = psrc[i];
					parent[i] = 0;
				}
			}
			unsigned cells = (unsigned)(ac + sc) * 4;
			if (!cells || len < cells || len % cells)
				break;
			for (uint32_t o = 0; o + cells <= len; o += cells) {
				uint64_t base = 0, size = 0;
				int good = 1;
				for (int i = 0; i < ac; i++)
					base = base << 32 | be32_at(val + o + (uint64_t)i * 4, end, &good);
				for (int i = 0; i < sc; i++)
					size = size << 32 | be32_at(val + o + (uint64_t)(ac + i) * 4, end, &good);
				if (!good)
					break;
				seen++;
				if (!cb(ctx, parent, node, base, size))
					return seen;
			}
			break;
		}
		case FDT_NOP:
			break;
		default:
			return seen;
		}
	}
	return seen;
}
