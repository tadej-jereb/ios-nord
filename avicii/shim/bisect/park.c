/*
 * Bisect rungs 3..5, C body. Each rung adds exactly one layer over the one
 * before it and then parks, so whichever rung dies names its own layer:
 *
 *   BISECT_N=3            identity map over the image, nothing else (the fb
 *                         block is left Device because BISECT_NO_FB is set)
 *   BISECT_N=4            + the splash block mapped Normal non-cacheable
 *   BISECT_N=5            + con_clear() over the whole panel
 *
 * No UFS, no FDT walk, no diag ladder, no console text: N3 and N4 stay
 * independent of the (unproven) panel, and nothing writes flash. Rungs 1 and 2
 * are pure assembly and link no C at all.
 */
#include <stdint.h>
#include "mmu.h"
#if BISECT_N >= 5
#include "console.h"
#endif

static void __attribute__((noreturn)) park(void)
{
	for (;;)
		__asm__ volatile("wfe");
}

void shim_main(uint64_t dtb)
{
	struct mmu_info mi;
	(void)dtb;

	/* rc < 0 = image straddled more blocks than there are L3 tables. Park
	 * either way: with the MMU off a park still proves the prologue. */
	int rc = mmu_enable(&mi);
	(void)rc;

#if BISECT_N >= 5
	con_clear(MAGENTA);
#endif
	park();
}
