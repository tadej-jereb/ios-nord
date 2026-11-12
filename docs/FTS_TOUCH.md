# avicii: ST FTS touch on GENI I2C 0x49 — port note

> **Fallback path only — read `docs/GOODIX_GT9886.md` first.** This unit is a **Goodix
> GT9886**, not FTS. The dump that resolved it is
> `logs/dumps/run-20261112-195027/50-i2c-4-005d.txt` (`5d`'s `driver` symlink points at
> the `Goodix-gt9886` driver) against `50-i2c-4-0049.txt` (the `st_fts@49` client has an
> `of_node` but no `driver` symlink, i.e. it never bound). See also `avicii/CONSTANTS.md`
> §4. Keep this note for a unit that really does populate FTS; its transport, clock and
> rail half (SE7 base 0x984000, TLMM 0x0f000000, `GCC_QUPV3_WRAP1_S1_CLK`, both rails) is
> shared with the Goodix path and was correct as far as it went. `qcom,i2c-touch-active =
> "st,fts"` (`avicii/mtp.dtsi:343`) is the board default, not this unit's answer.

Status: **fallback adaptation note, nothing built or booted on avicii.** Sources: anonbeat1 patch 0089
(FTS on SE13 **SPI**, FT3680, Spacewar) and rrrd-jpg patches 0080-0085 (FTS on **PM6150 I2C 0x49**,
Pixel 4a/sunfish). The transport we need on avicii is neither: it is the GENI **FIFO I2C** path
already written for **SE7** in anonbeat1 patch 0060. Vendor protocol backing comes from the stock
`drivers/input/touchscreen/st` driver in `refs/st-fts/`.

Cited patch lines are patch lines; `refs/anonbeat1/patches/0089.patch:N` addresses the new file
`bsd/dev/sweet_fts_spi.c`.

---

## 1. avicii facts

| fact | citation |
|---|---|
| `qcom,i2c-touch-active = "st,fts"` on `&qupv3_se7_i2c` | `avicii/mtp.dtsi:343` |
| `st_fts@49`, `compatible = "st,fts"`, `reg = <0x49>` | `avicii/mtp.dtsi:345-347` |
| IRQ `gpio 9` (`0x2008` = GPIO_ACTIVE_LOW, pull-up, IRQ) | `avicii/mtp.dtsi:355` |
| reset `gpio 8` (`0x00` = active high, no pull) | `avicii/mtp.dtsi:356` |
| `vdd-supply = <&pm8150_s4>` (DVDD, fixed 1.8 V) | `avicii/mtp.dtsi:350`, `refs/lito-dts/lito-regulators.dtsi:43-49` |
| `avdd-supply = <&pm8150_l13>` (3.008-3.304 V) | `avicii/mtp.dtsi:351`, `refs/lito-dts/lito-regulators.dtsi:359-366` |
| **`st,x-flip = <1>`, `st,y-flip = <1>`** | `avicii/mtp.dtsi:359-360` |
| I2C pads: `gpio6` (SDA) / `gpio7` (SCL), function `qup11`, 2 mA, `bias-disable` | `refs/lito-dts/lito-pinctrl.dtsi:1211-1221` |
| reset/IRQ pads: `gpio8`/`gpio9`, function `gpio`, 8 mA, pull-up | `refs/lito-dts/lito-pinctrl.dtsi:1706-1718` |
| `qupv3_se7_i2c: i2c@984000`, `reg = <0x984000 0x4000>`, GIC_SPI 354 | `refs/lito-dts/lito-qupv3.dtsi:370-372` |
| wrapper `qupv3_1` at 0x9c0000, `iommus = <&apps_smmu 0x023 0x0>` (SID 0x23) | `refs/lito-dts/lito-qupv3.dtsi:301-308` |
| SE7 clock `GCC_QUPV3_WRAP1_S1_CLK` (branch vote bit 23 of 0x52008, CBCR 0x1813c, RCG 0x18140) | `refs/lito-dts/gcc-lito.c:1799-1804,542-543` |
| TLMM is **0x0f000000** (not 0xf100000) | `refs/lito-dts/lito-pinctrl.dtsi:2-4` |
| SPMI core 0xc440000, channels 0xc600000 | `avicii/lito.dtsi:1804-1807` |
| panel 1080x2400, command mode, DSC `slice-height = 48` | `avicii/panel.dtsi:84-85,481,496-497` |

No `st,max-x-coordinate` / `st,max-y-coordinate` exists in the avicii DT (grep of `avicii/mtp.dtsi`,
`avicii/lito.dtsi` returns nothing) — the resolution has to be a driver constant: **1080, 2400**.
The FTS chip type is **unknown** until the boot-id read (§4); the DT only says "ST FTS". On this
particular unit nothing will bind at 0x49 at all — see the header.

---

## 2. The protocol as the references implement it

### 2.1 SPI framing (anonbeat1 0089) — for reference only

Write: `[cmd, 0x00, len-1 BE16, 0,0,0, data...]`, status byte `rx[3] & 0xA0` must be 0
(`refs/anonbeat1/patches/0089.patch:433-450`). Read: `[cmd, 0xA0, len BE16, 0,0,0, <data>,
<CRC16 kermit LE>]`, then verify `ft_crc(&buf[7], dlen)` against `buf[7+dlen+1 .. 7+dlen]`
(`refs/anonbeat1/patches/0089.patch:452-469`; CRC loop at 416-427). Retries 3x. The CRCs the
peripheral computes over the *app firmware image* are ECC-AL2, not this CRC
(`refs/anonbeat1/patches/0089.patch:478-490`).

I2C has neither the status byte nor the per-transfer CRC (§3).

### 2.2 Boot mode

```c
	for (int i = 0; i < 3; i++) {
		wr(ft.tlmm, GPIO(PIN_RESET) + 4, 0);  /* reset low */
		ft_wait(1);
		wr(ft.tlmm, GPIO(PIN_RESET) + 4, 2);  /* reset high (bit1 = out value) */
		ft_wait(8 + i);
		const uint8_t start = 0x55;
		(void)ft_write(&start, 1);
		ft_wait(8);
		uint8_t id[2] = { 0 };
		if (!ft_read(0x90, id, 2) && id[0] == 0x56 && id[1] == 0x62) {
			printf("SWEET FTS: boot id 0x%02x%02x\n", id[0], id[1]);
			return 0;
		}
	}
```
`refs/anonbeat1/patches/0089.patch:496-510`. Reset pulse, `0x55` = enter boot, `0x90` = release
info/boot id, **expected 0x5662** (that is the FT3680's value; a different chip gives a different
pair, so print and compare rather than hard-failing — see §4).

### 2.3 Firmware upload, blob carried in the driver

The blob is not on the filesystem and not in the ADT on avicii either — the vendor ships it inside
`fts_tp.ko` (stock: `/vendor/lib/modules/fts_tp.ko`, byte array in `.rodata`). Spacewar read it from
an ADT property instead (`firmware` under `/sweet-fts-spi`,
`refs/anonbeat1/patches/0089.patch:761-763`); for avicii, extract the array from `fts_tp.ko` and
compile it in as `static const uint8_t fts_fw[]`. Then:

```c
	unsigned code_len = (unsigned)fw[0x100] << 8 | fw[0x101];
	unsigned code_n = (unsigned)fw[0x102] << 8 | fw[0x103];
	unsigned size = code_len * 4;
	if (code_len + code_n != 0xffff || size > fwlen || size > 128 * 1024) {
		printf("SWEET FTS: bad fw app length %#x\n", size);
		return EINVAL;
	}
```
`refs/anonbeat1/patches/0089.patch:526-532` — header at 0x100: code length (in dwords) and its
one's-complement, must sum to 0xffff.

Per 32 KiB-16 packet: `0xAD` + 24-bit offset, then `0xAE` + payload
(`refs/anonbeat1/patches/0089.patch:537-549`). Then ECC:

```c
	const uint8_t ecc_cmd[7] = { 0xcc, 0, 0, 0, (uint8_t)(size >> 16), (uint8_t)(size >> 8), (uint8_t)size };
	...
	uint16_t tp = (uint16_t)(ev[0] << 8 | ev[1]), host = ft_ecc(fw, size);
	printf("SWEET FTS: fw ecc tp %#x host %#x\n", tp, host);
	if (tp != host) {
		return EIO;
	}
	const uint8_t start = 0x08;  /* fts_pram_start */
```
`refs/anonbeat1/patches/0089.patch:551-568` (ECC 0xCC, wait 7 ms, read 0xCD, compare, `0x08` =
run). Then a 200 ms settle and the app chip id / fw version read (`0xA3`, `0xA6`,
`refs/anonbeat1/patches/0089.patch:725-728`).

### 2.4 Report parsing

Two shapes exist in the references. The SPI one reads a full frame from register `0x01` and walks
fixed 6-byte records:

```c
	if (b[1] == 0xff && b[2] == 0xff && b[3] == 0xff) {
		return 0;  /* firmware idle / no frame */
	}
	unsigned fingers = b[1] & 0x0f;
	...
		const uint8_t *p = b + 2 + 6 * i;
		unsigned id = p[2] >> 4, event = p[0] >> 6;
		...
		unsigned px = ((unsigned)(p[0] & 0x0f) << 8) | p[1];
		unsigned py = ((unsigned)(p[2] & 0x0f) << 8) | p[3];
```
`refs/anonbeat1/patches/0089.patch:601-627`: `fingers = b[1] & 0x0f`, records from `b+2`, id =
`p[2]>>4`, event = `p[0]>>6` (1 = lift, 3 = bad), x = `(p[0]&0xf)<<8 | p[1]`, y = `(p[2]&0xf)<<8 |
p[3]`. Event byte values 1/3 (bad) and out-of-range coordinates reject the whole frame.

The I2C one polls the 8-byte FIFO at `0x86` and decodes event ids instead:

```c
			unsigned id = ev[1] >> 4, type = ev[1] & 0x0fu;
			if (ev[0] == 0x13 || ev[0] == 0x23) {
				...
				int x = (int)(((unsigned)(ev[3] & 0x0fu) << 8) | ev[2]);
				int y = (int)(((unsigned)ev[4] << 4) | (ev[3] >> 4));
				px[id] = x > 1079 ? 1079 : x;
				py[id] = y > 2339 ? 2339 : y;
				mask |= 1u << id;
				touch_report(mask, px, py);
			} else if (ev[0] == 0x33) {
```
`refs/rrrd/patches/0085-pixel-fts-driver.patch:81-97`. `0x03` = controller ready (boot),
`0x13`/`0x23` = enter/motion, `0x33` = up; `ev[1]` high nibble is the finger id, low nibble the
touch type. The FIFO register is `0x86` = `FIFO_CMD_READALL`, event size 8
(`refs/st-fts/ftsHardware.h:183,191-192`). `0x00`/`0xff` bytes mean an empty FIFO
(`refs/rrrd/patches/0085-pixel-fts-driver.patch:73-75`).

The two differ in pace: 0085 drains up to 32 FIFO events per pass, then sleeps 2 ms while events
keep coming and 10 ms when idle (`refs/rrrd/patches/0085-pixel-fts-driver.patch:60,99`); 0089 reads
one register-`0x01` frame per 8 ms poll (`refs/anonbeat1/patches/0089.patch:742`). Error handling:
0089 drops all fingers after 20 consecutive errors (`refs/anonbeat1/patches/0089.patch:735-737`),
0085 after 50 (`refs/rrrd/patches/0085-pixel-fts-driver.patch:66-69`).

Report dedupe: `touch_report()`/`ft_report()` only emits a HID update when the bitmask or a
coordinate actually changed (`refs/anonbeat1/patches/0089.patch:576-591`).

### 2.5 Coordinate scaling

Neither reference scales: both panels are 1080 px wide, so the SPI path *rejects* `px > 1079 || py >
2399` (`refs/anonbeat1/patches/0089.patch:628-630`) and the I2C path *clamps* to `1079`/`2339` — the
latter because the Pixel 4a panel is 2340 tall (`refs/rrrd/patches/0085-pixel-fts-driver.patch:88-89`).
avicii is 1080x**2400**, so the clamp becomes `2399` and the reject limits stay 1079/2399.

---

## 3. What must be replaced for GENI I2C at 0x49

The FIFO-I2C message layer already exists, for exactly the right SE: patch 0060 is titled
`SWEET SE7 FIFO I2C` and uses `TOUCH_SE_PA 0x00a84000` (sweet's SE7)
(`refs/anonbeat1/patches/0060.patch:244`), `TOUCH_RCG 0x18148` for wrapper-1 local S1
(`refs/anonbeat1/patches/0060.patch:248`) and the same `gpio6`/`gpio7` "qup11" pads
(`refs/anonbeat1/patches/0060.patch:716`). That is the template; adapt, do not rewrite.

### 3.1 Constants that differ

| item | patch 0060 (sweet) | avicii | citation |
|---|---|---|---|
| SE base | 0x00a84000 | **0x00098400** | `refs/lito-dts/lito-qupv3.dtsi:372` |
| wrapper SID (if DMA/GSI is ever used) | 0x43 | **0x23** | `refs/lito-dts/lito-qupv3.dtsi:308` |
| RCG / CBCR | 0x18148 / (CBCR implied) | **0x18140 RCG, 0x1813c CBCR** | `refs/lito-dts/gcc-lito.c:542-543,1799-1800` |
| APCS branch vote | `0x5200c` bits 27/21/20 | **0x52008, bit 23** (WRAP1_S1) | `refs/anonbeat1/patches/0060.patch:247`, `refs/lito-dts/gcc-lito.c:1803-1804` |
| TLMM base | 0x03900000+0x500000 | **0x0f000000** | `refs/lito-dts/lito-pinctrl.dtsi:2-4` |
| SE clock name | WRAP1 S1 on sdmmagpie | `GCC_QUPV3_WRAP1_S1_CLK` | `refs/lito-dts/lito-qupv3.dtsi:377` |
| rails | L11C 3.0 V (PM6150L) | **S4 1.8 V + L13 3.008 V, both PM8150** | `avicii/mtp.dtsi:350-351` |
| touch address | 0x38 (Focaltech) / 0x5d (Goodix) | **0x49** | `avicii/mtp.dtsi:347` |
| reset / IRQ pin | 105 / 81 | **8 / 9** | `avicii/mtp.dtsi:355-356` |

### 3.2 Wire framing — the real transport difference

The ST I2C protocol puts **two address bytes and one length byte in front of every access** and
reads back `len` or `len+1` bytes (the `+1` is a discarded dummy):

```c
	//write msg
	I2CMsg[0].addr = (__u16)I2CSAD;
	I2CMsg[0].flags = (__u16)0;
	I2CMsg[0].len = (__u16)cmdLength;
	I2CMsg[0].buf = buf;

	//read msg
	I2CMsg[1].addr = (__u16)I2CSAD;
	I2CMsg[1].flags = I2C_M_RD;
	I2CMsg[1].len = byteToRead;
	I2CMsg[1].buf = buf + cmdLength;

	memcpy(buf, cmd, cmdLength);
```
`refs/st-fts/ftsIO.c:124-136`, with `byteToRead` already including the dummy byte
(`refs/st-fts/ftsIO.c:350` → `fts_readCmd(rCmd, 3, buff, toRead + 1)` then `memcpy(outBuf, buff + 1,
toRead)`, `refs/st-fts/ftsIO.c:350-356`). `rCmd` is `{cmd, addr_hi, addr_lo}`
(`refs/st-fts/ftsIO.c:323-328,347-348`).

Patch 0060's `touch_read()` is already the pointer-write + repeated-START shape, but **one** address
byte wide:

```c
static int
touch_read(uint8_t addr, uint16_t reg, bool wide, uint8_t *buf, unsigned len)
{
	uint8_t ptr[2] = {(uint8_t)(reg >> 8), (uint8_t)reg};
	int err = touch_msg(addr, wide ? ptr : ptr + 1, wide ? 2u : 1u,
	    NULL, 0, true);
	if (err) {
		return err;
	}
	/* STOP_STRETCH on the pointer write retains the bus for a repeated START. */
	return touch_msg(addr, NULL, 0, buf, len, false);
}
```
`refs/anonbeat1/patches/0060.patch:483-494`, with `wide = true` for 2-byte registers — so **pass
`wide = true` everywhere for FTS** and keep the `STOP_STRETCH` bit (bit 2, `stretch ? 4u : 0u` in
`SE_CMD`, `refs/anonbeat1/patches/0060.patch:423-424`).

**Short accesses fit the existing helper as-is.** Every ST register access is a 3-byte pointer
write `{cmd, addr_hi, addr_lo}` — writes carry their payload in the same message with no length
byte (`refs/st-fts/ftsIO.c:157-186`), and reads answer with `len` followed by `len` payload bytes,
the first of which is that length echo, not data. So TX never exceeds 3 bytes (the helper's cap,
`refs/anonbeat1/patches/0060.patch:414`) and a FIFO drain of 32 events is 1+256 bytes on the wire
with a 1+8*n read (`refs/st-fts/ftsHardware.h:183,186-188`).

The one place the helper is **not** enough is the firmware upload: `0xAE` + up to 32 KiB of payload
in a single message (`refs/anonbeat1/patches/0089.patch:543-549`), while `touch_msg()` pushes its
TX into the FIFO exactly once (`refs/anonbeat1/patches/0060.patch:447-454`). Two ways out:

- extend the TX path into a watermark loop like `i2c_geni_fifo_write` (watch the TX-write IRQ bit
  per 32-byte FIFO word, `SE_FW` depth is 32 at `refs/anonbeat1/patches/0060.patch:649-650`), or
- keep GSI for the upload only, which then also needs the wrapper SID 0x23 mapped (§3.3, and see
  `docs/USB_SMMU.md` for the SMMU half).

Also required for every read: keep the received length byte and start payload at `buf[1]`
(`touch_read(0x49, 0x0086, true, buf, 1 + 8*n)`, then use `buf + 1`). Dropping it makes the first
payload byte look like a valid event.

### 3.3 Steps to keep / drop from 0089

Keep: the boot pulse and `0x55`/`0x90` (§2.2), the fw header check, `0xAD`/`0xAE`/`0xCC`/`0xCD`,
`0xA3`/`0xA6` (§2.3), the record decoder (§2.4).

Drop: everything GPI/GSI — `GPI_PA`, `gpi_setup()`, the event-ring recycling, `gsi_xfer()`
(`refs/anonbeat1/patches/0089.patch:300,383,654-720`) — and the SMMU bank for the reporting path:
avicii's SE7 I2C runs in **FIFO mode**, so the wrapper never DMAs and SID 0x23 is only needed if the
firmware upload is left on GSI (§3.2). The chip-id probe of §4 needs neither. Also drop
`ft_crc()`/status bytes and the `0xA0` read flag (§2.1).

Keep from 0060: `touch_se_init()` programming order and `SE_SCL` (100 kHz)
(`refs/anonbeat1/patches/0060.patch:640-687,670`) — FTS tops out around 400 kHz; 100 kHz for
bring-up. Note the `SE_FW` protocol check `(fw>>8)&0xff != 3` at
`refs/anonbeat1/patches/0060.patch:648`: it verifies the ABL-loaded I2C firmware, and on avicii SE7
must be muxed to I2C by ABL. If it is not, `0x400` from `SE_FW` will read garbage — that is the
first thing to look at.

### 3.4 Panel mapping — 1080x2400 with both flips set

The DT sets both flips (`avicii/mtp.dtsi:359-360`), so the chip's native origin sits opposite the
display's. Apply the vendor driver's transform, i.e. mirror both axes on the panel's own limits:

```c
	/* st,x-flip = 1, st,y-flip = 1, panel 1080x2400 (avicii/mtp.dtsi:359-360,
	 * avicii/panel.dtsi:84-85) */
	if (px > 1079 || py > 2399) {
		return EIO;
	}
	if (x_flip) px = 1079 - px;
	if (y_flip) py = 2399 - py;
```

The 1080x2400 limits are the panel's, not the chip's: FTS reports in whatever space its own
config was flashed for, so a first run should log raw `px/py` before transforming and confirm the
extremes. `st,x-flip`/`st,y-flip` are ABI documented in the vendor binding
(`arch/arm64/boot/dts/vendor/bindings/input/touchscreen/st,stmfts.txt` in the stock tree; not copied here).

> If the framebuffer is *also* driven 180° rotated relative to natural portrait, the flip must be
> dropped — decide with §4 step 3, not by guessing.

---

## 4. First test — smallest probe that proves the chip answers

Read three chip-id registers and print. No firmware upload, no reporting, no IRQ. The registers are
`0xA3` (chip id), `0xA6` (fw version) and `0x90` (boot/release info), 1 byte each, 2-byte register
address, from `0x49`.

Prerequisites, all blocking: SE7 clock, pads, both rails. Order: pads (gpio6/7 "qup11", gpio8 reset
low, gpio9 input) → S4 1.8 V → 1 ms → L13 3.008 V → SE clock → `touch_se_init()`.

```c
/* bsd/dev/sweet_touch.c — avicii first probe. Print, do not interpret yet. */
static void
avicii_fts_ident(void)
{
	static const uint16_t regs[] = { 0x0090, 0x00a3, 0x00a6 };
	uint8_t b[2];

	for (unsigned i = 0; i < sizeof(regs) / sizeof(regs[0]); ++i) {
		b[0] = b[1] = 0xee;
		/* wide = true: 2-byte register address; the read is length byte + 1 data byte */
		int e = touch_read(0x49, regs[i], true, b, 2);
		printf("SWEET FTS: reg %#06x err=%d byte=%#x seen=%#x\n", regs[i], e, b[1],
		    st.irq_status);
		touch_wait(5);
	}
}
```

Run it from `touch_thread()` right after `touch_se_init()` succeeds, before anything else.

**Correct answer.** All three reads succeed with no NACK and no abort:

```
SWEET FTS: reg 0x0090 err=0 byte=0x56 seen=0x...
SWEET FTS: reg 0x00a3 err=0 byte=0x36 seen=0x...
SWEET FTS: reg 0x00a6 err=0 byte=0x.. seen=0x...
```

`0x90` returning `0x56` means the reset pulse landed the chip in boot mode and the boot-id path in
§2.2 will work as written. **Any chip-id byte is progress** — record it; 0x36/0x70 and 0x39/0x6C are
values the vendor tree knows (`refs/st-fts/ftsHardware.h:45-49`), a different value means avicii's
IC is a variant whose fw header must be re-checked before §2.3. On the panel: the probe line
appears and the console keeps running.

**Incorrect answers and what they mean.**

- `err = ENXIO` (`SE_NACK`, `refs/anonbeat1/patches/0060.patch:431`) on all three: nothing answers
  at 0x49 — wrong SE (check `SE_FW`/`0x400` for I2C firmware), wrong pads, or rails down. The panel
  shows `err=20`/`err=6` with `seen=...NACK bit...` and nothing else.
- `err = 0` but `byte = 0x00` or `0xff` on every register: ACK with a stuck/low bus — pull-ups
  missing or SDA/SCL muxed to the wrong function (compare against
  `refs/lito-dts/lito-pinctrl.dtsi:1213-1214`: function must be `qup11`, not `gpio`).
- `ETIMEDOUT` with `st.dead = 1`: the SE aborted; console shows `abort failed status=... irq=...`
  (`refs/anonbeat1/patches/0060.patch:393-397`) and stays dead until reboot.
- `0x90` = `0x00`: chip is not in boot mode — reset pulse too short or the `0x55` never went out.
  The panel shows the other two registers also `0x00`.

**Step 3, separate run:** drag a finger diagonally and log raw `px/py`. Then enable the flips of
§3.4 and drag again; the reported path must follow the finger in the same direction as the
on-screen pointer, and touch down at the top-left must read near `(0,0)`, not `(1079,2399)`.

---

## 5. GPIO / rail / clock inventory

| item | owner | who must supply it | notes |
|---|---|---|---|
| gpio6 SDA / gpio7 SCL | TLMM 0x0f000000, function `qup11` | **ADT pinctrl on the controller node** `pinctrl-0 = <&qupv3_se7_i2c_active>` (`refs/lito-dts/lito-qupv3.dtsi:383-384`); GENI then drives them, from XNU write TLMM directly | `refs/lito-dts/lito-pinctrl.dtsi:1211-1221` |
| gpio8 reset | TLMM, function `gpio`, out | **ADT pinctrl `ts_active`** (`avicii/mtp.dtsi:353`) covers it; `pinctrl-1` names `ts_reset_suspend` (`avicii/mtp.dtsi:354`, node at `refs/lito-dts/lito-pinctrl.dtsi:1736-1749`). The driver then drives it | `refs/lito-dts/lito-pinctrl.dtsi:1706-1718` |
| gpio9 IRQ | TLMM, input, pull-up, active-low | **ADT** `interrupts = <9 0x2008>` (`avicii/mtp.dtsi:349,355`); TLMM direct in XNU, GIC_SPI via PDC mapping | `refs/lito-dts/lito-pinctrl.dtsi:1706-1718` (ts_active), `:1721-1734` (ts_int_suspend) |
| `pm8150_s4` 1.8 V (DVDD) | **PM8150** (main), RPMH resource `smpa4` | **SPMI/RPMH VRM** — `sweet_rpmh_vreg_enable("smpa4", 1800)` | `refs/lito-dts/lito-regulators.dtsi:37-49`; DT supply `avicii/mtp.dtsi:350` |
| `pm8150_l13` 3.008-3.304 V (AVDD) | **PM8150** (main), RPMH resource `ldoa13` | **SPMI/RPMH VRM** — `("ldoa13", 3008)` | `refs/lito-dts/lito-regulators.dtsi:351-366`; DT supply `avicii/mtp.dtsi:351` |
| `GCC_QUPV3_WRAP1_S1_CLK` | GCC: vote bit 23 @0x52008, CBCR 0x1813c, RCG 0x18140 | **ADT/GCC MMIO**, the driver votes it | `refs/lito-dts/gcc-lito.c:1799-1804,542` |
| `GCC_QUPV3_WRAP_1_M_AHB_CLK` / `_S_AHB_CLK` | GCC | **ADT** (`clocks` cell list `refs/lito-dts/lito-qupv3.dtsi:377-379`); already voted by whoever brings the wrapper up | `refs/lito-dts/gcc-lito.h:93` |
| SE7 core clock gate | GENI `SE_MCLK` 0x048 ← `SE_CLK_SEL` 0x07c | driver MMIO | `refs/anonbeat1/patches/0060.patch:668-669` |
| SE7 sleep/bus clock | GCC WRAP1_1 branch | ADT; **not voted by the touch path** | — |

**PM8150, not PM8150L, owns both touch rails** — S4 and L13 are main-PMIC RPMH resources. This
matters twice: the resource names (`smpa4`, `ldoa13`) are not the PM8150L-style `ldob*`/`ldoc*`
names already whitelisted in `sweet_rpmh.c`
(`refs/anonbeat1/patches/0089.patch:778-786` accepts only `ldoc11`/`ldob7`/`ldoc8`/`ldoc3`), and
the PMIC index in the SPMI frame differs from PM8150L. **Nothing in this block touches PM8150L** — the SE7 pads are
on `tlmm` (SoC), not on a PMIC GPIO; the only PM8150L item anywhere in this port is the USB PHY's
ELDO13 (see `docs/USB_SMMU.md` §7).

SPMI is used only for the two rails; everything else is ADT/TLMM/GCC. The SPMI arbiter
(`0xc440000`, channels `0xc600000`, `avicii/lito.dtsi:1804-1807`) is the right path should anyone
prefer raw SPMI writes over RPMH — the Pixel probe did exactly that for a PM6150 GPIO
(`refs/rrrd/patches/0081-pixel-touch-power.patch:9-31,44-56`, channel stride `0x10000 * apid`
corrected in `refs/rrrd/patches/0084-pixel-gpio4-channel.patch:8`).

---

## 6. Open items / unverified

- Chip identity and boot id on avicii (§4) — the FT3680 values 0x5662 / fw header in §2.3 are
  **untested** on this IC.
- Whether the vendor `fts_tp.ko` blob's header even matches §2.3 (0x100, code_len+code_n = 0xffff).
  Check before trusting the upload path.
- `st,x-flip`/`st,y-flip` semantics relative to a *non-rotated* XNU framebuffer (§3.4).
- IRQ delivery: 0089 and 0085 both **poll** and only read the IRQ pin state
  (`refs/anonbeat1/patches/0089.patch:733`, `refs/rrrd/patches/0085-pixel-fts-driver.patch:36-46`);
  a real GIC IRQ is not wired in any reference.
- **Two touch clients are enabled on the same SE7 in this DT**: `Goodix-gt9886@5D`
  (`avicii/lito.dtsi:3987-4049`) has no `status` of its own (the `status = "ok"` at
  `avicii/lito.dtsi:3986` is the bus), so it is live next to `st_fts@49` — and
  `qcom,i2c-touch-active = "st,fts"` (`avicii/mtp.dtsi:343`) is what picks ST. A probe must expect
  NACKs from whichever address is unpopulated, and any owner/arbitration logic has to tolerate the
  other client on the bus.
- `SE_FW` protocol check, `SE_SCL` timing and the 100 kHz value are inherited from sweet and
  unverified against lito's GENI revision.
