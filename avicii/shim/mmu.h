#pragma once
#include <stdint.h>

#define FB_PHYS	0xa0000000UL

/*
 * Load base, published by start.S (runtime address of _head; the header asks
 * ABL for 0x8000). The image is linked at 0 and never relocated, so a symbol
 * used as an address only stays correct because clang emits adrp/adr - both
 * pc-relative - and build.sh refuses ABS64 relocations in C. kimg_base is
 * therefore telemetry, not something to add to a symbol: `(uintptr_t)sym` is
 * already the runtime address. It is what a crash report needs to say where
 * ABL actually put us.
 */
extern uint64_t kimg_base;

struct mmu_info {
	uint64_t img_lo, img_hi, ttbr;
	uint64_t sctlr_before, sctlr_after;
	int n_l3;
};

int mmu_enable(struct mmu_info *info);
uint64_t mmu_probe(uintptr_t va);
