/*
 * Rung 7a: TLMM pin pattern.
 *
 * A pin toggle is two stores and no clock vote, no controller init, no DMA. It
 * is invisible on a finished phone, so the *measurement* here is not the pin -
 * it is whether the TLMM block answers at all, i.e. whether the pad block is
 * still clocked and writable after the ABL handed off. That answer is put in
 * the IMEM record: the ctl value read back from gpio 71 must equal what was
 * written, and the raw pre-existing value is kept next to it.
 *
 * Pins: 71 is `aw_reset` of the haptic chip (mtp.dtsi:128-131), the one pad
 * with no running consumer a shim can own without changing anything the user
 * can see; 70 is `aw_irq` (mtp.dtsi:119-126) and is driven as well so the
 * pattern is two adjacent pads and not a single one. Both are left as inputs at
 * the end (rung 8 re-muxes 71 anyway when it wants the motor).
 *
 * Count: 8 pulses, 100 ms high, 100 ms low, on both pads together. Documented
 * so the pattern can be counted on a scope or a multi-meter beep, and so a
 * half-finished pattern is distinguishable from a random one.
 */
#include <stdint.h>
#include "tel.h"

#define TLMM_BASE	0xf000000UL	/* lito TLMM; stride 0x1000 per pin */
#define TLMM_CTL(p)	(TLMM_BASE + 0x1000UL * (p))
#define TLMM_IO(p)	(TLMM_CTL(p) + 0x04UL)

#define CTL_FUNC(f)	((uint32_t)(f) << 2)
#define CTL_DRV_MA(m)	((uint32_t)((m) / 2 - 1) << 6)
#define CTL_PULL_UP	3u
#define CTL_OE		(1u << 9)
#define IO_OUT		(1u << 1)

#define PIN_RESET	71
#define PIN_IRQ		70
#define PULSES		8

static uint32_t rd(uintptr_t a)
{
	return *(volatile uint32_t *)a;
}

static void wr(uintptr_t a, uint32_t v)
{
	*(volatile uint32_t *)a = v;
	__asm__ volatile("dsb sy" ::: "memory");
}

void tel_gpio_rung(void)
{
	uint32_t before = rd(TLMM_CTL(PIN_RESET));

	tel_mark(TEL_S7_GPIO_CTL);
	tel_result(TEL_R_GPIO_CTL, before);

	/* output, 2 mA, function 0 (plain gpio), output enable */
	wr(TLMM_CTL(PIN_RESET), CTL_FUNC(0) | CTL_DRV_MA(2) | CTL_PULL_UP | CTL_OE);
	wr(TLMM_CTL(PIN_IRQ), CTL_FUNC(0) | CTL_DRV_MA(2) | CTL_PULL_UP | CTL_OE);
	wr(TLMM_IO(PIN_RESET), IO_OUT);
	wr(TLMM_IO(PIN_IRQ), IO_OUT);

	tel_mark(TEL_S7_GPIO_RUN);
	for (int i = 0; i < PULSES; i++) {
		wr(TLMM_IO(PIN_RESET), 0);
		wr(TLMM_IO(PIN_IRQ), 0);
		tel_msleep(100);
		wr(TLMM_IO(PIN_RESET), IO_OUT);
		wr(TLMM_IO(PIN_IRQ), IO_OUT);
		tel_msleep(100);
	}

	/* ctl as read back: bit 9 (OE) and function 0 are the two signs the block
	 * took the write; 0 or 0xffffffff means it did not answer. */
	tel_result(TEL_R_GPIO_CTL, rd(TLMM_CTL(PIN_RESET)));
	tel_mark(TEL_S7_GPIO_OFF);
	wr(TLMM_CTL(PIN_RESET), CTL_FUNC(0) | CTL_DRV_MA(2) | CTL_PULL_UP);
	wr(TLMM_CTL(PIN_IRQ), CTL_FUNC(0) | CTL_DRV_MA(2) | CTL_PULL_UP);
}
