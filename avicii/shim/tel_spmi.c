/*
 * Rung 7b: SPMI reachability, and one PMIC-side visible effect.
 *
 * The SPMI arbiter is plain MMIO at 0xc440000 (lito.dtsi, qcom,ee = <0> - we
 * are EE 0) and needs no UFS, no PHY and no DMA: the observer channel is a
 * write-a-command/read-a-status register pair. So the PMIC *is* reachable this
 * early, and the rung proves it by reading the two PMIC revision IDs and keeping
 * them in the IMEM record. A zero or all-ones revid means the bus is not ours,
 * which is itself the answer: it bounds what any later rung may rely on.
 *
 * Transport, PPID->APID map walk and channel layout are the ported read/write
 * paths of xnu patch 0062/0092 (`refs/ry-diffusion-Bergamota/enxerto/pmic.c`),
 * against the live arbiter bases `reg-names` in the live FDT:
 *   core 0xc440000, chnls 0xc600000, obsrvr 0xe600000, cnfg 0xc40a000.
 *
 * SIDs from the live FDT (qcom,pm8150@0, qcom,pm8150@1, qcom,pm7250b@2):
 * 0 = PM8150, 1 = PM8150L, 2 = PM7250B. Peripherals: 0x01 revid, 0x0c gpio.
 *
 * Last step: pulse PM8150L gpio 3 (`qcom,platform-reset-gpio` of every panel
 * node, mtp.dtsi:462) low then high. The panel is not re-initialised, so the
 * screen goes black and *stays* black - that is the visible, unambiguous,
 * human-observable "code ran this far" signal, at the cost of the splash (and
 * of the console, which is dead on this command-mode panel anyway). It is the
 * last step of the last rung that touches the panel for exactly that reason.
 *
 * UNVERIFIED: the PMIC gpio register stride (0x100/pin, dig_out at
 * +0x00 of the pin block at 0xa0) is the qcom spmi-gpio layout, not measured on
 * this unit; the readbacks the rung stores are what settles it.
 */
#include <stdint.h>
#include "tel.h"

#define SP_CORE		0x0c440000UL
#define SP_CFG		0x0c40a000UL
#define SP_OBS		0x0e600000UL
#define SP_CHNL		0x0c600000UL
#define SP_NO_APID	0xffffU
#define SP_SCAN		64U

#define PERIPH_REVID	0x01U
#define PERIPH_GPIO	0x0cU

#define PM8150L		1U
#define PM7250B		2U

#define REVID_ADDR	0x100U
#define PMIC_GPIO(pin)	(0xc000U + 0x100U * (pin))
#define PMIC_DIG_OUT(pin)	PMIC_GPIO(pin)		/* qcom spmi-gpio REG_PIN_CTL */
#define PMIC_EN_CTL(pin)	(PMIC_GPIO(pin) + 0x46U)

static int poisoned[SP_SCAN];

static uint32_t rd(uintptr_t a)
{
	uint32_t v = *(volatile uint32_t *)a;

	__asm__ volatile("dmb sy" ::: "memory");
	return v;
}

static void wr(uintptr_t a, uint32_t v)
{
	__asm__ volatile("dmb sy" ::: "memory");
	*(volatile uint32_t *)a = v;
	__asm__ volatile("dsb sy" ::: "memory");
}

/* PPID = (sid << 8) | periph. Prefer the APID EE 0 owns: on the v5 arbiter one
 * PPID can be mapped more than once. */
static unsigned find_apid(unsigned ppid, unsigned count, unsigned *owner)
{
	unsigned found = SP_NO_APID;

	for (unsigned i = 0; i < count; i++) {
		uint32_t map = rd(SP_CORE + 0x900 + 4 * i);
		if (!map || ((map >> 8) & 0xfff) != ppid)
			continue;
		unsigned own = rd(SP_CFG + 0x700 + 4 * i) & 7;
		if (found == SP_NO_APID || own == 0) {
			found = i;
			*owner = own;
		}
	}
	return found;
}

static int spmi_read(unsigned apid, unsigned addr, uint32_t *out)
{
	uintptr_t off = 0x80UL * apid;

	if (apid >= SP_SCAN || poisoned[apid & (SP_SCAN - 1)])
		return -1;
	wr(SP_OBS + off, (1u << 27) | ((addr & 0xff) << 4));	/* EXT_READL, 1 byte */
	for (unsigned i = 0; i < 2000; i++) {
		uint32_t st = rd(SP_OBS + off + 0x08);
		if (st & 1u) {
			if (st & 0x0e)
				return -1;
			*out = rd(SP_OBS + off + 0x18) & 0xff;
			return 0;
		}
		tel_msleep(1);
	}
	poisoned[apid & (SP_SCAN - 1)] = 1;
	return -1;
}

/* EXT_WRITEL through the APID's write channel, only when EE 0 owns it. */
static int spmi_write(unsigned apid, unsigned addr, uint32_t data)
{
	uintptr_t ch = SP_CHNL + 0x10000UL * apid;

	if (apid >= SP_SCAN || poisoned[apid & (SP_SCAN - 1)])
		return -1;
	if ((rd(SP_CFG + 0x700 + 4 * apid) & 7) != 0)
		return -1;
	wr(ch + 0x10, data & 0xff);
	wr(ch + 0x00, ((addr & 0xff) << 4) | 0);		/* opcode 0, 1 byte */
	for (unsigned i = 0; i < 2000; i++) {
		uint32_t st = rd(ch + 0x08);
		if (st & 1u)
			return (st & 0x0e) ? -1 : 0;
		tel_msleep(1);
	}
	poisoned[apid & (SP_SCAN - 1)] = 1;
	return -1;
}

void tel_spmi_rung(void)
{
	unsigned count, o1 = 0, o2 = 0;
	uint32_t ver, v1 = 0, v2 = 0;
	unsigned a1, a2;

	tel_mark(TEL_S7_SPMI_ENTER);
	ver = rd(SP_CORE);
	count = rd(SP_CORE + 4) & 0x7ff;
	tel_result(TEL_R_SPMI_VER, ver);

	/* v5 arbiter: version 0x5xxxxxxx and a plausible APID count, else stop
	 * before touching a channel. */
	if (ver < 0x50000000U || ver >= 0x70000000U || !count || count > 512) {
		tel_result(TEL_R_APID, 0);
		return;
	}
	if (count > SP_SCAN)
		count = SP_SCAN;

	tel_mark(TEL_S7_SPMI_MAP);
	a1 = find_apid((PM8150L << 8) | PERIPH_REVID, count, &o1);
	a2 = find_apid((PM7250B << 8) | PERIPH_REVID, count, &o2);
	tel_result(TEL_R_APID, (a1 == SP_NO_APID ? 0xffffU : a1) | (a2 == SP_NO_APID ? 0xffff0000U : a2 << 16));

	tel_mark(TEL_S7_SPMI_PM8150L);
	if (a1 != SP_NO_APID && !spmi_read(a1, REVID_ADDR, &v1))
		;
	tel_mark(TEL_S7_SPMI_PM7250B);
	if (a2 != SP_NO_APID && !spmi_read(a2, REVID_ADDR, &v2))
		;
	tel_result(TEL_R_PMIC, (v1 & 0xffffU) | (v2 << 16));

	/* Panel reset pulse: only if both the gpio PPID and EE 0 ownership check
	 * out. A failed write leaves the splash in place, nothing worse. */
	tel_mark(TEL_S7_SPMI_PM8150L_GPIO);
	a1 = find_apid((PM8150L << 8) | PERIPH_GPIO, count, &o1);
	if (a1 == SP_NO_APID || o1 != 0)
		return;
	if (spmi_write(a1, PMIC_DIG_OUT(3), 0x00))
		return;
	tel_msleep(30);
	if (spmi_write(a1, PMIC_DIG_OUT(3), 0x01))
		return;
	/* en_ctl of the same pin, read-only: bit 7 set = output driven */
	{
		uint32_t en = 0;

		if (!spmi_read(a1, PMIC_EN_CTL(3), &en))
			tel_result(TEL_R_APID, (a1 & 0xffffU) | (en << 16));
	}
}
