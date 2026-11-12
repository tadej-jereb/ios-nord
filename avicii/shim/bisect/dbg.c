/*
 * Instrumented rung for the host harness (not built by bisect.sh, not a boot
 * image to flash): runs mmu_enable, records what it produced at 0x9ff00000,
 * paints the panel, then reads an unmapped address on purpose and parks.
 *
 * Build at BISECT_N=5 and run under
 *   qemu-system-aarch64 -M virt,virtualization=off -cpu cortex-a76 -m 4G \
 *       -nographic -kernel Image -monitor unix:/tmp/mon,server,nowait -d int -D /tmp/e.log
 * then `xp /8gx 0x9ff00000` and `xp /4wx 0xa0000000` on the monitor.
 *
 *   [0] 0x1111 marker       [4] mmu_enable() rc
 *   [1] kimg_base           [5] SCTLR_EL1 after
 *   [2] img_lo              [6] 0x7777 once con_clear returned
 *   [3] img_hi
 */
#include <stdint.h>
#include "console.h"
#include "mmu.h"

void shim_main(uint64_t dtb)
{
	struct mmu_info mi;
	(void)dtb;

	volatile uint64_t *o = (volatile uint64_t *)0x9ff00000ULL;
	o[0] = 0x1111;
	o[1] = kimg_base;

	int rc = mmu_enable(&mi);
	o[2] = mi.img_lo;
	o[3] = mi.img_hi;
	o[4] = (uint64_t)rc;
	o[5] = mi.sctlr_after;

	con_clear(MAGENTA);
	o[6] = 0x7777;

	o[7] = *(volatile uint64_t *)0x300000000ULL;	/* mapped nowhere on purpose */
	for (;;)
		__asm__ volatile("wfe");
}
