# avicii: Goodix GT9886 touch — port dossier

Status: **adaptation note. Nothing built, nothing booted on avicii.** The base tree's
touch driver already speaks this protocol (it was written for a GT9896 on sweet); this
note fixes what is different on `avicii` and says what the driver does wrong unchanged.

Evidence base, in order of weight:

1. `avicii/xnu-patch-notes/0090-avicii-goodix-gt9886-touch.patch` — the delta this note
   describes. Base-tree line numbers below (`bsd/dev/sweet_touch.c:N`) refer to the file
   as it stands **after** base patches 0060, 0062 and 0063, i.e. the reviewable state.
2. Live dump `logs/dumps/run-20261112-195027/` — the binding resolution of A/B (§1).
3. `refs/lito-dts/` (vendor DT + GCC driver) and `avicii/` DT sources — every hardware
   number in §3.

`VERIFIED` = read from a dump, a DT source, or driver source in this workspace.
`UNVERIFIED` = reasoned, not measured; the first-test section says how each one shows up
in a log.

---

## 1. What is established about this unit

| fact | citation | class |
|---|---|---|
| `4-005d` is **bound** to `Goodix-gt9886` | `logs/dumps/run-20261112-195027/50-i2c-4-005d.txt:2` | VERIFIED |
| `4-005d` `of_node` -> `/soc/i2c@984000/Goodix-gt9886@5D` | same file, `of_node` line | VERIFIED |
| `4-0049` (`st_fts@49`) has an `of_node` and **no** `driver` symlink | `50-i2c-4-0049.txt` (see `avicii/CONSTANTS.md` §4) | VERIFIED |
| the vendor stack runs the Goodix driver, prints `[TP]Goodix-gt9886: ...` per touch | `50-dmesg-touch.txt:9,23,32,55` | VERIFIED |
| contact coordinates up to `x=915`, `y=2391` in the vendor parser | `50-dmesg-touch.txt:34-38` | VERIFIED |
| IRQ 300 = `msmgpio 9`, kernel type **Edge**, 3098 hits, name `touchpanel` | `70-interrupts.txt:300` | VERIFIED |
| DT: `interrupts = <9 0x2002>`, `reset-gpio = <&tlmm 8 0x1>` | `avicii/lito.dtsi:3995,4004` | VERIFIED |
| DT: `vdd_2v8-supply = <&pm8150_l13>`, `vdd_2v8_volt = <3008000>` | `avicii/lito.dtsi:3998-3999` | VERIFIED |
| DT: `register-is-16bit = <1>`, `touchpanel,{,panel-,display-}coords = <1080 2400>` | `avicii/lito.dtsi:4011-4012,4026` | VERIFIED |
| chip identity `GT885`, `module_id = 7`, `project-name = "20801"` | `avicii/lito.dtsi:3990-3992` | VERIFIED |
| same assembly's FTS node: `st,x-flip = <1>`, `st,y-flip = <1>`, `vdd` = S4, `avdd` = L13 | `avicii/mtp.dtsi:350-351,359-360` | VERIFIED |
| 1.8 V load switch: `enable1v8_gpio = <&pm8150l_gpios 1 GPIO_ACTIVE_LOW>` | `avicii/mtp.dtsi:383` | VERIFIED (property exists) |

`qcom,i2c-touch-active = "st,fts"` (`avicii/mtp.dtsi:343`) is a board default and does not
override the dump: the FTS client is instantiated but unbound.

## 2. The protocol as the base driver implements it

Transport: GENI **FIFO** I2C on SE7, 100 kHz, no DMA, no GSI, local `SE_IRQ` status only
(`bsd/dev/sweet_touch.c:508-521`, packing from 0063). A read is two messages: a 2-byte
big-endian pointer write with `STOP_STRETCH` to hold the bus, then a read
(`bsd/dev/sweet_touch.c:307-318`). `wide = true` selects the 2-byte pointer, which is what
`register-is-16bit` means.

Chip id: 12 bytes at `0x4022` (`GOODIX_PID_REG`, `:36`), ASCII product id in bytes 0-3 and
a 4-byte firmware version in bytes 8-11 (`:594-596`). sweet only accepts the literal
`"9896"` (`:603`).

Reset and power: latch low before the pin becomes an output, hold low 2 ms, release, wait
300 ms (`:588-591`); rails are voted through RPMH **before** the release and the reset stays
asserted while they settle (`:575-591`). The RPMH helper writes three commands at
`offset 0 = mV, 8 = mode 7 (HPM), 4 = enable 1` into the address the cmd-db holds for a
resource name (`bsd/dev/sweet_rpmh.c:270-271`, `:331`).

Report frame: 8-byte header at `0x4180` (`GOODIX_EVENT_REG`, `:37`), `buf[0] & 0x80` = new
frame, `buf[0] & 0x40` = firmware/config request that this driver declines with `ENOTSUP`
instead of acknowledging (`:396-401`). Both header and body carry a 16-bit big-endian
trailing sum over the preceding bytes (`:355-366`, `:403`, `:417`); a bad sum returns
`EIO` **without** writing to the IC. Contact count is `buf[2] & 15` (`:406`), body at
`0x4188` with 8 bytes per contact (`:412-413`). Per contact: `id = p[0] >> 4`, low nibble
1 or 3 = pen and rejected, `x = be16(p+2)`, `y = be16(p+4)`, duplicate ids rejected, bounds
1080x2400 (`:422-431`). Then a 3-byte write `{0x41, 0x80, 0x00}` acknowledges the frame
(`:320-325`) and the contacts go to `sweet_hid_touch(id, down, x, y)` (`:368-384`).

Polling: 10 ms period, optional `sweettouchirq` hint that gates reads on the pin level and
still reads every 100 ms (`:614-630`). No GIC handler exists.

Firmware: **none**. No image upload, no config applies; `0x8240` is read once as inert
information (`:327-329,597`). A GT9886 that the vendor firmware left configured keeps that
configuration; this driver only reads reports and writes the ack byte.

## 3. What differs on avicii

| # | item | sweet (base) | avicii | citation |
|---|---|---|---|---|
| 1 | SE base physical address | `0x00a84000` (`:25`) | `0x00984000` | `refs/lito-dts/lito-qupv3.dtsi:370-371` |
| 2 | TLMM base | `0x03900000` (`:27`) | `0x0f000000` + WEST `0x500000` = `0x0f500000` | `refs/lito-dts/lito-pinctrl.dtsi:2-4`, `avicii/pinctrl-lito.c:22` |
| 3 | SE clock branch vote | word `0x5200c` (`:28`), bits 18-21+23 | word `0x52008`, bits 20 (m-ahb), 21 (s-ahb), 23 (S1) | `refs/lito-dts/gcc-lito.c:1799-1804,1917-1920,1930-1933` |
| 4 | SE RCG | `0x18148` (`:29`) | `0x18144` = cmd_rcgr `0x18140` + 4 | `refs/lito-dts/gcc-lito.c:542-543` |
| 5 | SE CBCR halt check | `0x18144` in the branch list (`:163`) | `0x1813c` | `refs/lito-dts/gcc-lito.c:1800` |
| 6 | touch 2.8 V rail | `ldoc11` @ 3200 mV (`:578`) | `ldoa13` @ 3008 mV | `refs/lito-dts/lito-regulators.dtsi:353,359-366`; `avicii/lito.dtsi:3998-3999` |
| 7 | touch 1.8 V rail | not voted | `smpa4`, fixed 1800 mV, vote it **first** | `refs/lito-dts/lito-regulators.dtsi:35-49`; `avicii/mtp.dtsi:350` |
| 8 | 1.8 V switch enable | n/a | `&pm8150l_gpios 1`, **active low**; not driven by the patch | `avicii/mtp.dtsi:383` |
| 9 | IRQ flag cell | `0x2008`-style level-low assumption for FTS | `<9 0x2002>` = edge, falling (dump shows kernel type `Edge`) | `avicii/lito.dtsi:3995`; `70-interrupts.txt:300` |
| 10 | reset flag cell | `0x00` (active high) on the FTS node | `0x1` = GPIO_ACTIVE_LOW | `avicii/lito.dtsi:4004` vs `avicii/mtp.dtsi:356` |
| 11 | handedness | none; raw panel coords | mirror **both** axes (`st,x-flip`/`y-flip` = 1) | `avicii/mtp.dtsi:359-360` |
| 12 | geometry / presentation | 1080x2400 panel, presented 1125x2436, centred offset +22/+18 | identical | `avicii/lito.dtsi:4011-4012`; base `0061-sweet-iphone-x-display-size.patch:17-18,106-108,120` |
| 13 | product id | `"9896"` accepted, nothing else | `GT9886`, expect `"9886"`; accept the `98` prefix | `avicii/lito.dtsi:3991`; base `:603` |

RPMH resource names, explicitly: `pm8150_l13` is the DT label of
`regulator-pm8150-l13`, whose `qcom,resource-name` is **`ldoa13`**
(`refs/lito-dts/lito-regulators.dtsi:353-360`). `pm8150_s4` is
`regulator-pm8150-s4`, `qcom,resource-name` **`smpa4`**
(`refs/lito-dts/lito-regulators.dtsi:35-44`). The cmd-db lookup in the helper keys on the
resource name, not the DT label (`bsd/dev/sweet_rpmh.c:274-283`), so passing
`"pm8150_l13"` would miss. Both rails sit on RSC slave 3-5 and the lookup refuses other
slaves (`:280`).

The voltage argument is millivolts in this codebase (fajita votes its 3.008 V touch rail
as `3008`: `refs/edi194-ios-fajita/xnu/patches/0090-fajita-touch-rmi4.patch:258-259`).
Whether the RPMH RPC itself wants mV or uV is not proven here — the first boot prints
`ACTIVE <n> mV` (`bsd/dev/sweet_rpmh.c:272`), and the rail has to be confirmed with a
meter before the value is trusted (`UNVERIFIED`).

Both DT rails are **fixed-purpose** per the FTS node on the same bus: S4 is `vdd` and L13
`avdd` (`avicii/mtp.dtsi:350-351`). The Goodix node declares only `vdd_2v8` = L13 and has
no S4 property, so the S4 vote is inferred from the shared assembly, not from the Goodix
node (`UNVERIFIED`, harmless: RPMH votes are additive and never disabled here).

## 4. What the unmodified driver does wrong on avicii

1. **Wrong SE**: `ml_io_map(0x00a84000)` (`:25,564`) maps a block that on lito is not SE7;
   the GENI init and every transfer then hit foreign registers. Symptom: no `SE_DONE`,
   aborts, `report err`.
2. **Wrong vote word**: writes mask bits into `0x5200c` (`:141`). The branch enables live
   in `0x52008`, so S1 stays halted and `touch_wait_clear(0x18144, bit 31)` reports
   `GCC branch ... halted` before any probe runs.
3. **RCG off by 4**: `0x18148` is not `CFG_RCGR` on lito; the parent/divider write lands in
   the wrong register and the SE gets no 19.2 MHz XO.
4. **Wrong TLMM base**: reset/IRQ writes go to `0x03900000 + n*0x1000`
   (`:27,576-590`), so the real reset pin is never driven and the PIN dump in the log is
   meaningless.
5. **`ldoc11` does not exist on lito** → `rh_lookup` returns `ENODEV`, the driver prints
   `L11C RPMh enable failed` and skips all probes (`:578-582`). Even if the lookup were
   ignored, the 2.8 V rail would stay off.
6. **FTS-style chip gate**: it only accepts `"9896"` (`:603`). A GT9886 answering `"9886"`
   makes `goodix` false, `fts` false too (0x38 NACKs), so it takes the
   `no unique supported IC` exit (`:605-609`) and stops. Net effect: no touch, and the
   log looks like a broken bus rather than a wrong string.
7. **No flips**: coordinates arrive mirrored on both axes, so the panel is usable but every
   touch lands 180° away — taps look shifted by exactly (1079-x, 2399-y), and edge
   gestures fire from the wrong side.
8. **No 1.8 V vote and no switch handling** (§3 rows 7-8).

## 5. The patch skeleton

`avicii/xnu-patch-notes/0090-avicii-goodix-gt9886-touch.patch`, a unified diff against
`bsd/dev/sweet_touch.c` and `bsd/dev/sweet_rpmh.c` as they stand after 0060/0062/0063. It
applies with `patch -p1` and compiles into the existing `bsd/conf/files` entry — no new
file, no new KEXT. Hunk map:

| hunk | change | why |
|---|---|---|
| header | lito/avicii paragraph | a reader must not think this is still sweet |
| defines | SE `0x984000`, TLMM `0x0f500000`, vote `0x52008` + explicit bit mask, RCG `0x18144`, halt `0x1813c`, `TOUCH_ADDR`, panel W/H, `TOUCH_XFLIP`/`YFLIP` | §3 rows 1-5, 11-12 |
| `touch_clocks` | masked vote, S1 CBCR in the branch list | §4 items 2-3; keeps other users' bits |
| `touch_map` | mirror in panel space, called by both parsers after the bounds check | §3 row 11; bounds are checked *before* mirroring so an out-of-range IC value is still an error |
| power block | vote `smpa4` 1800 then `ldoa13` 3008, abort if either fails | §3 rows 6-7, order = IO before analog |
| probe | `TOUCH_ADDR`, id gate `gid[0..1] == "98"`, full string logged | §3 row 13, §4 item 6 |
| probe-only | `sweettouchprobe` boot-arg exits after the ident | §6 |
| rpmh | accept `ldoa13`/`smpa4` with per-rail voltage windows | the helper hard-rejects anything but `ldoc11` (`sweet_rpmh.c:331`) |

Deliberately **not** changed: report decoding, checksums, ack, `TOUCH_MAX`, 100 kHz, the
`x > 1079`-style margin now expressed as `>= TOUCH_PANEL_W/H`, GPIO 6/7 mux 1
(`lito-pinctrl.dtsi:1208-1221` matches the base's `qup11`, 2 mA, `bias-disable`).

## 6. First test

Everything downstream of the ident is speculative until the ident works. Keep touch off in
the normal image and add the probe arg only for the probe boot:

```
# normal image, touch inert
... sweettouch=0 sweetts=0
# probe boot
... sweettouch=1 sweettouchprobe=1 sweettouchdelay=45
```

`sweettouch=0` is read at `bsd/dev/sweet_touch.c:647-652` and prints
`SWEET TOUCH: disabled (sweettouch=0)`; `sweettouchdelay` (seconds) delays the MMIO mapping
so the persistent log and the GUI exist before a possible bus hang (`:550-560`).
`sweettouchprobe` runs the ident and the two inert info reads, then terminates the thread
(skeleton hunk; the loop is never entered).

The probe is the smallest possible: 12 bytes at `0x4022` through the 2-byte pointer. What
the log prints (`:594-596` plus the per-transfer line at `:299-302`):

- **correct**: `probe xfer addr=0x5d read len=12 ... err=0` then
  `probe 0x5d err=0 pid=39383836 fw=..` — pid bytes are ASCII `"9886"` (or `"9896"` on a
  relabelled part), bytes 8-11 a plausible firmware version, and the `0x8240`/`0x4022` raw
  dumps are not all `0x00`/`0xa5`.
- **wrong, chip absent / bus dead**: `err=ENXIO`-class failure with `irq` showing `NACK`,
  or `abort failed` and `st.dead`. Nothing at `0x4022`.
- **wrong, rails off**: the same NACK pattern *with* `RPMH` lines before it that show
  `enable failed` or a low `mv` — check the rail lines first, then `enable1v8_gpio`.
- **wrong, addressing**: pid bytes look like a shifted by-one dump (e.g. register data
  echoed back into byte 0) — the pointer is being sent as 1 byte or 3 bytes.
- **wrong, flips**: ident fine, touch fine, but taps land 180° away → `TOUCH_XFLIP`/
  `TOUCH_YFLIP` are the first suspects, not the decoder.

Panel behaviour: the driver draws nothing, so a correct ident is invisible on the panel.
The visible test only starts with reporting enabled (`sweettouch=1` without the probe arg);
then a correct run moves the cursor under the finger and an edge swipe from the bottom
starts the home gesture. `irq` in the probe lines must be quiet at rest
(`st.irq_status` is the raw `SE_IRQ`, not the GPIO) and the TLMM line must show the reset
pin high with pull-up after the sequence.

Record, per attempt: the `RPMH` lines (each carries the resolved address), the full probe
line, both raw dumps, `70-interrupts.txt`-style IRQ state, and the exact boot-args, in
`docs/IMAGE_PROVENANCE.md` style.

## 7. Open items

| item | why it is open | how it resolves |
|---|---|---|
| RCG sub-offset `0x18144` and the whole clock half | derived from `gcc-lito.c:542` + the base's `cmd_rcgr+4` convention; not run | `gcc vote=... rcg=... cfg=... dfs=...` line (`:144-145`): `dfs & 1` must be 0 (no DFS on lito) and the DFS/`RCG update timeout` paths say which register is wrong |
| `smpa4` mode | the DT lists only RET/AUTO for S4 (`lito-regulators.dtsi:40-41`); the helper writes 7 (`HPM`) | if the TCS completes but the rail reads 0 V, try mode 6 (AUTO) at `sweet_rpmh.c:271` |
| `ldoa13` voltage unit | mV-in-argument is the codebase convention, mV-vs-uV on the RPC unproven | meter on the rail; the log prints the number it sent |
| `enable1v8_gpio` (PM8150L GPIO1, active low) | nothing in the tree writes PMIC GPIOs (`sweet_spmi.c` is read-only, `0062:...`), so it relies on ABL having left it asserted | if S4 is voted and the IC still NACKs, this is the next suspect; driving it needs an SPMI write path |
| TLMM GPIO 90 as "board enable" | inherited from sweet (`:583`), avicii's DT has no TLMM power-enable property | the `vdd90` field in the sequence log; harmless if it drives an unrelated pin |
| device is `lito`, patch guards `ARM64_BOARD_CONFIG_SWEET` | the whole base tree is sweet-guarded; `avicii/` has no board config yet | out of this task's scope — the guard must be widened or the ADT must define the sweet token (see `docs/SHIM_BOOT.md`) |
| second touch variant (FTS) | `docs/FTS_TOUCH.md` stays as fallback | untouched here |

## 8. Out of scope

Firmware/config upload, gesture mode, `fw_update`, pen (the decoder still rejects pen
records), pressure, edge-limit commands, any GIC handler, suspend/resume, and the
`st,fts` fallback path.
