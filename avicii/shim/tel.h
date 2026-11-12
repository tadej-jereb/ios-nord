#pragma once
#include <stdint.h>

/*
 * Telemetry rungs (DIAG_STAGE >= 6): cheap side effects that leave a mark even
 * when the image is refused, dies before the console, or never reaches the UFS
 * ring. See docs/TELEMETRY.md for the ladder, the readback commands and the
 * interpretation table; docs/TIMING.md is the harness that needs no code.
 *
 * Order is by cost, cheapest first, and every rung marks itself in IMEM
 * *before* it touches anything, so the last code in the record names the step
 * that killed the image. Nothing here needs the MMU: all of it is Device
 * memory and plain stores (no pointer tables - build.sh rejects ABS64).
 *
 * The record is 16 words at IMEM + 0xb00, outside every child the DT declares
 * (highest child ends at 0xa14, diag_dload 0xc8..0x190, boot_stats
 * 0x6b0..0x6d0, kaslr 0x6d0..0x6dc), so the ABL has no business there; the
 * proven-but-consumable restart_reason at +0x65c is mirrored too, and the two
 * are compared in the report. Both addresses are UNVERIFIED as scratch: the
 * self-check below is what turns that into a measurement instead of a belief.
 *
 *   w0  TEL_MAGIC        w8..w11  rung results (see the TEL_R_* names)
 *   w1  stage compiled   w12      last I2C ack bitmap (rung 8)
 *   w2  mark sequence    w13      spare
 *   w3  last code        w14      cntvct at the final mark (with w6 = alive ms)
 *   w4  kimg_base lo     w15      spare
 *   w5  kimg_base hi
 *   w6  cntvct at w0 write (start of the run)
 *   w7  self-check verdict, TEL_OK / TEL_BAD
 */

#define TEL_IMEM_BASE	0x146ab000UL	/* qcom,msm-imem, lito.dtsi:716 */
#define TEL_RR_OFF	0x65c		/* restart_reason@65c */
#define TEL_REC_OFF	0xb00		/* our words, see above */
#define TEL_MAGIC	0x4c455431UL	/* "1TEL", LE: not a boot mode the ABL knows */
#define TEL_OK		0x600dUL
#define TEL_BAD		0xdeadUL

/* Record accessors: immediates only. */
#define TEL_W(i)	(*(volatile uint32_t *)(TEL_IMEM_BASE + TEL_REC_OFF + 4 * (i)))
#define TEL_RR		(*(volatile uint32_t *)(TEL_IMEM_BASE + TEL_RR_OFF))

/* How far the image got. One code per step; the highest code in the record is
 * the step that was running when the phone reset. Ranges are per rung. */
#define TEL_S6_ENTER	0x0600
#define TEL_S6_MAGIC	0x0601
#define TEL_S6_SELFCHK	0x0602
#define TEL_S6_VERIFIED	0x0603
#define TEL_S6_CLEAR	0x0604		/* console clear: panel path, after the record */
#define TEL_S6_PARK	0x0605

#define TEL_S7_ENTER	0x0700
#define TEL_S7_GPIO_CTL	0x0701
#define TEL_S7_GPIO_RUN	0x0702
#define TEL_S7_GPIO_OFF	0x0703		/* pins handed back as inputs */
#define TEL_S7_SPMI_ENTER 0x0704
#define TEL_S7_SPMI_VER	0x0705
#define TEL_S7_SPMI_MAP	0x0706
#define TEL_S7_SPMI_PM8150L 0x0707
#define TEL_S7_SPMI_PM7250B 0x0708
#define TEL_S7_SPMI_PM8150L_GPIO 0x0709
#define TEL_S7_PARK	0x070a

#define TEL_S8_ENTER	0x0800
#define TEL_S8_GPIO	0x0801		/* reset pin + SE0 pins muxed */
#define TEL_S8_CLOCKS	0x0802		/* GCC vote, SE0 branch */
#define TEL_S8_GENI	0x0803		/* GENI FIFO mode */
#define TEL_S8_RESET	0x0804		/* AW8697 reset pulse */
#define TEL_S8_ID	0x0805		/* read reg 0x00 */
#define TEL_S8_RST	0x0806		/* SYSCTRL soft reset */
#define TEL_S8_ON	0x0807		/* buzz n (0x0807..0x0809) */
#define TEL_S8_PARK	0x080f

/* Result slots. */
#define TEL_R_SELFCHK	0	/* w8: TEL_OK/TEL_BAD, duplicated from w7 */
#define TEL_R_GPIO_CTL	1	/* w9: ctl value read back from gpio 71 */
#define TEL_R_SPMI_VER	2	/* w10: arbiter version */
#define TEL_R_PMIC	3	/* w11: {pm8150l revid:16, pm7250b revid:16} */
#define TEL_R_I2C	4	/* w12: bit n set = transfer n acked (rung 8) */
#define TEL_R_APID	5	/* w13: pm8150l gpio apid (lo), en_ctl readback (hi) */

/* Record: called before anything in a rung touches hardware. */
void tel_begin(unsigned stage);
void tel_mark(uint32_t code);
void tel_result(unsigned slot, uint32_t v);
void tel_alive_ms(uint32_t ms);
/* Write the magic, read the whole record back, store the verdict. 0 = intact. */
int tel_selfcheck(void);

/* Rungs. Each one marks itself, never returns a value, and is bounded. */
void tel_imem_rung(void);
void tel_gpio_rung(void);
void tel_spmi_rung(void);
void tel_haptic_rung(void);

/* Panel/text output that also feeds the (maybe dead) ring. */
void tel_say(char kind, const char *label, const char *text);

void tel_msleep(unsigned ms);
uint64_t tel_ticks(void);
