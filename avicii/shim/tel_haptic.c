/*
 * Rung 8: the motor. The only signal on this phone a human can feel rather than
 * measure, so it is worth the cost - and it is also the most expensive rung, so
 * it comes last and everything it needs is marked before it is touched.
 *
 * Note on the premise: the motor is NOT on a PM8150L pin. The haptic amplifier
 * is an AW8697 on I2C (`aw8697_haptic@5A`, mtp.dtsi:137-142) behind
 * qupv3_se0_i2c, pins gpio42/43, with `reset-gpio = <&tlmm 71>`; the PM8150L
 * path in rung 7 drives the *panel* reset, not the motor. So this rung is
 * GENI I2C + a vendor register sequence, and no SPMI at all.
 *
 * Cost, in order, and each step is a mark, so a hang names itself:
 *   pins (42/43 mux, 71 out) -> GCC vote for SE0 -> GENI FIFO mode ->
 *   reset pulse -> chip id -> soft reset -> buzz/delay/buzz.
 * A bounded failure at any step leaves the buzzer silent but the record with
 * every ack it got, which is the actual measurement.
 *
 * Every register number below is from the awinic aw8697 driver's register map
 * and is UNVERIFIED on this unit; the chip-id read is what says whether the
 * I2C path is even up. GENI command encoding follows the qcom geni-se
 * convention (opcode in [31:27], params in [26:0], the I2C address in
 * params[15:1]); the 2-byte register writes are MSB first, as the driver does.
 */
#include <stdint.h>
#include "tel.h"

#define GCC		0x00100000UL
#define GCC_VOTE	0x52008UL	/* APCS branch enable vote, bit per branch */
#define GCC_SE0_CBCR	0x1700cUL	/* gcc_qupv3_wrap0_s0_clk halt */
#define GCC_W0_M_AHB	0x17004UL
#define GCC_W0_CORE	0x23000UL
#define BIT_SE0		10
#define BIT_W0_M_AHB	6
#define BIT_W0_CORE	8

#define SE0		0x00880000UL
#define SE(o)		(SE0 + (o))
#define M_CMD0		0x600UL
#define M_CMD_DONE	0x610UL
#define M_IRQ_CLEAR	0x618UL
#define S_IRQ_CLEAR	0x648UL
#define M_TX_FIFO	0x700UL
#define M_RX_FIFO	0x780UL
#define M_TX_STATUS	0x800UL
#define M_RX_STATUS	0x804UL
#define GENI_HW_VER	0xe24UL
#define DMA_GEN_CFG	0xe30UL
#define CGC_CTRL	0x28UL
#define OUTPUT_CTRL	0x24UL

#define OP_I2C_WRITE	0x6U
#define OP_I2C_READ	0x7U

#define TLMM_BASE	0xf000000UL
#define TLMM_CTL(p)	(TLMM_BASE + 0x1000UL * (p))
#define TLMM_IO(p)	(TLMM_CTL(p) + 0x04UL)
#define CTL_FUNC(f)	((uint32_t)(f) << 2)
#define CTL_DRV_MA(m)	((uint32_t)((m) / 2 - 1) << 6)
#define CTL_OE		(1u << 9)
#define IO_OUT		(1u << 1)

#define AW_ADDR		0x5aU
#define REG_ID		0x00U
#define REG_SYSCTRL	0x01U
#define REG_RTP_LOOP	0x02U
#define REG_RTP_DATA	0x06U
#define REG_RTP_MODE	0x0aU
#define REG_RTP_AMP	0x0bU

static unsigned acks;		/* bit n = transfer n was accepted */

static uint32_t rd(uintptr_t a)
{
	return *(volatile uint32_t *)a;
}

static void wr(uintptr_t a, uint32_t v)
{
	*(volatile uint32_t *)a = v;
	__asm__ volatile("dsb sy" ::: "memory");
}

static int m_done(void)
{
	for (unsigned i = 0; i < 20000; i++) {
		if (rd(SE(M_CMD_DONE)) & 1u)
			return 0;
		tel_msleep(1);
	}
	return -1;
}

/* One I2C transfer, FIFO mode. Returns 0 only on a completed command. */
static int se_xfer(uint32_t op, const uint8_t *tx, unsigned n, uint8_t *rx)
{
	uint32_t hw;
	unsigned sent = 0, got = 0, nt = tx ? n : 0;

	wr(SE(M_IRQ_CLEAR), 0xffffffffu);
	hw = (rd(SE(GENI_HW_VER)) >> (op == OP_I2C_READ ? 24 : 16)) & 0x3f;	/* rx / tx depth */
	if (!hw)
		hw = 4;
	while (sent < nt && sent < hw)
		wr(SE(M_TX_FIFO), tx[sent++]);

	/* opcode, byte count, address, direction */
	wr(SE(M_CMD0), (op << 27) | (n << 8) | (AW_ADDR << 1) | (op == OP_I2C_READ));

	for (unsigned spin = 0; spin < 20000; spin++) {
		while (sent < nt && (rd(SE(M_TX_STATUS)) & 0x0fffffffU) < hw)
			wr(SE(M_TX_FIFO), tx[sent++]);
		while (rx && (rd(SE(M_RX_STATUS)) & 0x1ffffffU)) {
			uint32_t w = rd(SE(M_RX_FIFO));
			for (unsigned j = 0; j < 4 && got < n; j++)
				rx[got++] = (uint8_t)(w >> (8 * j));
		}
		if (sent >= nt && (!rx || got >= n))
			break;
		tel_msleep(1);
	}
	return m_done();
}

static int aw_write(unsigned reg, uint32_t val)
{
	uint8_t b[4] = { (uint8_t)reg, (uint8_t)(val >> 8), (uint8_t)val };

	return se_xfer(OP_I2C_WRITE, b, 3, 0);
}

static int aw_read(unsigned reg, uint8_t *out)
{
	uint8_t r = (uint8_t)reg;

	if (se_xfer(OP_I2C_WRITE, &r, 1, 0))
		return -1;
	return se_xfer(OP_I2C_READ, 0, 1, out);
}

static void note(int rc)
{
	acks = (acks << 1) | (rc ? 0u : 1u);
	if (acks & 0xff)				/* first failure: stop early */
		;
}

void tel_haptic_rung(void)
{
	uint8_t id = 0;

	tel_mark(TEL_S8_ENTER);

	/* pins: SE0 (42/43) as qup00 func 1, no pull, 2 mA */
	tel_mark(TEL_S8_GPIO);
	wr(TLMM_CTL(42), CTL_FUNC(1) | CTL_DRV_MA(2));
	wr(TLMM_CTL(43), CTL_FUNC(1) | CTL_DRV_MA(2));
	wr(TLMM_CTL(71), CTL_FUNC(0) | CTL_DRV_MA(2) | CTL_OE);
	wr(TLMM_IO(71), 0);

	tel_mark(TEL_S8_CLOCKS);
	wr(GCC + GCC_VOTE, rd(GCC + GCC_VOTE) | 1U << BIT_SE0 | 1U << BIT_W0_M_AHB | 1U << BIT_W0_CORE);
	for (int t = 0; t < 100000 && (rd(GCC + GCC_SE0_CBCR) & (1U << 31)); t++)
		;
	if (rd(GCC + GCC_SE0_CBCR) & (1U << 31)) {
		tel_result(TEL_R_I2C, 0x80000000U);		/* SE0 clock never came up */
		return;
	}
	tel_result(TEL_R_I2C, 0x40000000U);

	tel_mark(TEL_S8_GENI);
	wr(SE(M_IRQ_CLEAR), 0xffffffffu);
	wr(SE(S_IRQ_CLEAR), 0xffffffffu);
	wr(SE(CGC_CTRL), rd(SE(CGC_CTRL)) | 0x7f);
	wr(SE(DMA_GEN_CFG), rd(SE(DMA_GEN_CFG)) | 0xf);
	wr(SE(OUTPUT_CTRL), 0x7f);

	/* reset pulse: out of reset is the chip's power-on path */
	tel_mark(TEL_S8_RESET);
	wr(TLMM_IO(71), 0);
	tel_msleep(2);
	wr(TLMM_IO(71), IO_OUT);
	tel_msleep(6);

	tel_mark(TEL_S8_ID);
	note(aw_read(REG_ID, &id));
	tel_result(TEL_R_I2C, (rd(SE(M_IRQ_CLEAR)) & 0xffffU) << 16 | id << 8 | 0x40000000U);
	if (!id) {
		acks = 0;
		return;
	}

	/* soft reset, then a 3 x (300 ms on, 200 ms off) pattern */
	tel_mark(TEL_S8_RST);
	note(aw_write(REG_SYSCTRL, 0x0080));
	tel_msleep(1);
	note(aw_write(REG_SYSCTRL, 0x0000));
	tel_msleep(10);

	for (int i = 0; i < 3; i++) {
		tel_mark(TEL_S8_ON + i);
		note(aw_write(REG_RTP_LOOP, 0x0001));
		note(aw_write(REG_RTP_MODE, 0x0000));
		note(aw_write(REG_RTP_AMP, 0x0060));
		note(aw_write(REG_RTP_DATA, 0x0000));
		note(aw_write(REG_SYSCTRL, 0x0002));	/* RTP go */
		tel_msleep(300);
		note(aw_write(REG_SYSCTRL, 0x0000));
		tel_msleep(200);
	}
	tel_result(TEL_R_I2C, acks & 0xffffU);
	wr(TLMM_IO(71), 0);
	tel_mark(TEL_S8_PARK);
}
