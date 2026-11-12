# avicii: Goodix GT9886 touch — port dossier

Status: **adaptation note. Nothing built, nothing booted on avicii.** The base tree's touch
driver already speaks this protocol (it was written for a GT9896 on sweet), and the live
avicii series has already carried part of the port. This note fixes the rest and says
plainly what still goes wrong.

Evidence base, in order of weight:

1. `avicii/xnu-patch-notes/0095-avicii-goodix-gt9886-touch.patch` — the delta this note
   describes. Line numbers `bsd/dev/sweet_touch.c:N` and `bsd/dev/sweet_rpmh.c:N` are the
   files **as they stand in the live series** after `xnu-avicii/patches/0060`, `0062`,
   `0063`, i.e. the reviewable state **before** 0095. Those three are already avicii-adapted
   relative to `refs/dipa-studio-ios-sweet` (SE base, RPMH bases, `"9886"` gate); the ref
   copies do **not** have them, so a ref-based reading shifts every line number here.
2. Live dump `logs/dumps/run-20261112-195027/` — the binding A/B resolution (§1).
3. `refs/lito-dts/` (vendor DT + GCC driver) and `avicii/` DT sources — every hardware
   number in §3.

`VERIFIED` = read from a dump, a DT source, or driver source in this workspace.
`UNVERIFIED` = reasoned, not measured; §6 says how each one shows up in a log.

---

## 1. What is established about this unit

| fact | citation | class |
|---|---|---|
| `4-005d` is **bound** to `Goodix-gt9886` | `logs/dumps/run-20261112-195027/50-i2c-4-005d.txt:2` | VERIFIED |
| `4-005d` `of_node` -> `/soc/i2c@984000/Goodix-gt9886@5D` | same file, `of_node` line | VERIFIED |
| `4-0049` (`st_fts@49`) has an `of_node` and **no** `driver` symlink | `50-i2c-4-0049.txt`; `avicii/CONSTANTS.md` §4 | VERIFIED |
| the vendor stack runs the Goodix driver, prints `[TP]Goodix-gt9886: ...` per touch | `50-dmesg-touch.txt:9,23,55` | VERIFIED |
| contact coordinates up to `x=915`, `y=2391` in the vendor parser | `50-dmesg-touch.txt:34-38` | VERIFIED |
| IRQ 300 = `msmgpio 9`, kernel type **Edge**, 3098 hits, name `touchpanel` | `70-interrupts.txt:300` | VERIFIED |
| DT: `interrupts = <9 0x2002>`, `reset-gpio = <&tlmm 8 0x1>` | `avicii/lito.dtsi:3995,4004` | VERIFIED |
| DT: `vdd_2v8-supply = <&pm8150_l13>`, `vdd_2v8_volt = <3008000>` | `avicii/lito.dtsi:3998-3999` | VERIFIED |
| DT: `register-is-16bit = <1>`, `touchpanel,{,panel-,display-}coords = <1080 2400>` | `avicii/lito.dtsi:4011-4012,4026` | VERIFIED |
| chip identity `GT885`, `module_id = 7`, `project-name = "20801"` | `avicii/lito.dtsi:3990-3992` | VERIFIED |
| same assembly's FTS node: `st,x-flip`/`st,y-flip` = 1, `vdd` = S4, `avdd` = L13 | `avicii/mtp.dtsi:350-351,359-360` | VERIFIED |
| 1.8 V load switch: `enable1v8_gpio = <&pm8150l_gpios 1 GPIO_ACTIVE_LOW>` | `avicii/mtp.dtsi:383` | VERIFIED (property exists) |

`qcom,i2c-touch-active = "st,fts"` (`avicii/mtp.dtsi:343`) is a board default and does not
override the dump: the FTS client is instantiated but unbound.

## 2. The protocol as the driver implements it

Transport: GENI **FIFO** I2C on SE7, 100 kHz, no DMA, no GSI, local `SE_IRQ` status only.
A read is two messages: a 2-byte big-endian pointer write with `STOP_STRETCH` to hold the
bus, then the read (`bsd/dev/sweet_touch.c:307-318`). `wide = true` selects the 2-byte
pointer — that is what `register-is-16bit` means, and it is on for every access here.

Chip id: 12 bytes at `0x4022` (`GOODIX_PID_REG`, `:36`), ASCII product id in bytes 0-3, a
4-byte firmware version in bytes 8-11 (`:594-596`).

Reset and power: latch low before the pin becomes an output, hold low 2 ms, release, wait
300 ms (`:588-591`); rails are voted through RPMH **before** the release and reset stays
asserted while they settle (`:575-591`). The RPMH helper writes three commands at
`offset 0 = mV, 8 = mode 7 (HPM), 4 = enable 1` into the address the cmd-db holds for a
resource name (`bsd/dev/sweet_rpmh.c:270-271`, `:331`).

Report frame: 8-byte header at `0x4180` (`GOODIX_EVENT_REG`, `:37`), `buf[0] & 0x80` = new
frame, `buf[0] & 0x40` = firmware/config request that this driver declines with `ENOTSUP`
instead of acknowledging (`:396-401`). Header and body each carry a 16-bit big-endian
trailing sum over the preceding bytes (`:355-366`, `:403`, `:417`); a bad sum returns `EIO`
**without** writing to the IC. Contact count is `buf[2] & 15` (`:406`), body at `0x4188`
with 8 bytes per contact (`:412-413`). Per contact: `id = p[0] >> 4`, low nibble 1 or 3 =
pen and rejected, `x = be16(p+2)`, `y = be16(p+4)`, duplicate ids rejected, bounds checked
against 1080x2400 (`:422-431`). Then a 3-byte write `{0x41, 0x80, 0x00}` acknowledges the frame
(`:320-325`) and the contacts go to `sweet_hid_touch(id, down, x, y)` (`:368-384`).

Polling: 10 ms period, optional `sweettouchirq` hint that gates reads on the pin level and
still reads every 100 ms (`:614-630`). No GIC handler exists.

Firmware: **none**. No image upload, no config applies; `0x8240` is read once as inert
information (`:327-329,597`). A GT9886 that the vendor firmware left configured keeps that
configuration; this driver only reads reports and writes the ack byte.

## 3. What differs on avicii

"series" = already handled by `xnu-avicii/patches/0060-0063`; "patch" = handled by 0095;
"note" = documented only, no code.

| # | item | sweet (`refs/`) | avicii | where | state |
|---|---|---|---|---|---|
| 1 | SE base physical address | `0x00a84000` (`:25`) | `0x00984000` | `refs/lito-dts/lito-qupv3.dtsi:370-371` | series |
| 2 | GPIO window | one flat base `0x03900000`, offset `pin*0x1000` | config blocks are per quadrant: 6/7/8/9 WEST `0x500000`, 90 SOUTH `0x100000`, from TLMM `0x0f000000` | `refs/lito-dts/lito-pinctrl.dtsi:2-4`, `avicii/pinctrl-lito.c:20-23,1339-1345,1505` | **patch** (series uses the bare TLMM base, off by 0x500000 for 6-9) |
| 3 | SE clock branch vote | word `0x5200c` (`:28`), bits 18-21+23 | word `0x52008`, bits 20 (m-ahb), 21 (s-ahb), 23 (S1) | `refs/lito-dts/gcc-lito.c:1799-1804,1917-1920,1930-1933` | series has the word, **patch** narrows the mask |
| 4 | SE RCG | `0x18148` (`:29`), used as if it were `CFG_RCGR` | `cmd_rcgr` `0x18140` (`:29`, series) and `CFG_RCGR` = `+4` = `0x18144` | `refs/lito-dts/gcc-lito.c:542` | RCG base series; **patch** makes every CFG access add the +4 |
| 5 | SE CBCR halt check | `0x18144` in the branch list (`:163`) | `0x1813c` | `refs/lito-dts/gcc-lito.c:1800` | **patch** |
| 6 | touch 2.8 V rail | `ldoc11` @ 3200 mV (`:578`) | `ldo13` / `ldoa13` @ 3008 mV | `refs/lito-dts/lito-regulators.dtsi:353,359-366`; `avicii/lito.dtsi:3998-3999` | series calls `ldo13`, **patch** makes the helper accept it (+`ldoa13` retry) |
| 7 | touch 1.8 V rail | not voted | `smpa4`, fixed 1800 mV, vote it **first** | `refs/lito-dts/lito-regulators.dtsi:35-49`; `avicii/mtp.dtsi:350` | **patch** |
| 8 | 1.8 V switch enable | n/a | `&pm8150l_gpios 1`, **active low**; not driven | `avicii/mtp.dtsi:383` | note |
| 9 | IRQ flag cell | FTS note assumed `0x2008` (level low) | `<9 0x2002>` = edge falling (kernel row says `Edge`) | `avicii/lito.dtsi:3995`; `70-interrupts.txt:300` | note (driver polls) |
| 10 | reset flag cell | `0x00` (active high) | `0x1` = GPIO_ACTIVE_LOW | `avicii/lito.dtsi:4004` vs `avicii/mtp.dtsi:356` | note (sequence is physical-level anyway) |
| 11 | handedness | none, raw panel coordinates | mirror **both** axes | `avicii/mtp.dtsi:359-360` | **patch** |
| 12 | geometry / presentation | 1080x2400, presented 1125x2436 with a centred +22/+18 offset | identical | `avicii/lito.dtsi:4011-4012`; `0061-sweet-iphone-x-display-size.patch:17-18,106-108,120` | series (0061) |
| 13 | product id | `"9896"` accepted, nothing else | `"9886"` expected; accept the `98` family | `avicii/lito.dtsi:3991`; `:603` | series pins `"9886"`, **patch** widens |

RPMH resource names, explicitly: `pm8150_l13` is the DT label of `regulator-pm8150-l13`,
`qcom,resource-name` **`ldoa13`** (`refs/lito-dts/lito-regulators.dtsi:353-360`);
`pm8150_s4` is `regulator-pm8150-s4`, `qcom,resource-name` **`smpa4`**
(`refs/lito-dts/lito-regulators.dtsi:35-44`). The cmd-db keys on the resource name, not the
DT label (`bsd/dev/sweet_rpmh.c:274-283`), so `"pm8150_l13"` would miss. Both rails are on
RSC slave 3-5 and the lookup refuses other slaves (`:280`).

The series votes the LDO as `"ldo13"`, the DT spelling is `"ldoa13"`. Which string the live
cmd-db actually holds is not proven (no cmd-db dump exists), so the patch votes `"ldo13"`
and retries `"ldoa13"` on `ENODEV`, logging the address each time. Both are the same rail.

The voltage argument is millivolts in this codebase (fajita votes its 3.008 V touch rail as
`3008`: `refs/edi194-ios-fajita/xnu/patches/0090-fajita-touch-rmi4.patch:258-259`).
Whether the RPC itself wants mV or uV is unproven — the first boot prints
`ACTIVE <n> mV` (`bsd/dev/sweet_rpmh.c:272`) and the rail needs a meter before the value is
trusted (`UNVERIFIED`).

Both rails are fixed-purpose per the FTS node on the same bus: S4 is `vdd`, L13 `avdd`
(`avicii/mtp.dtsi:350-351`). The Goodix node declares only `vdd_2v8` = L13 and has no S4
property, so the S4 vote is inferred from the shared assembly, not from the Goodix node
(`UNVERIFIED`; harmless, RPMH votes are additive and never released here).

## 4. What still goes wrong with the series as it stands

1. **No rail is actually enabled.** `:578` calls `sweet_rpmh_vreg_enable("ldo13", 3008)`
   but the helper still accepts only `"ldoc11"` and `2950..3400` (`sweet_rpmh.c:331`), so
   the call returns `EINVAL`, prints `expected ldoc11`, and the probe is skipped. S4 is never
   voted at all. Symptom: `touch rail RPMh enable failed 22`, nothing on the bus.
2. **The GPIO window is off by `0x500000`.** `TOUCH_NORTH_PA 0x0f000000` (`:27`) with
   `pin*0x1000` (`:30-31`) lands reset (8) at `0x0f008000` and IRQ (9) at `0x0f009000`;
   those belong to the NORTH window, while both pins are WEST
   (`avicii/pinctrl-lito.c:1343-1345`). The reset pin is never driven and the printed
   `reset=`/`irq=` values are foreign registers. `TOUCH_NORTH_PA` also cannot reach GPIO 90
   (SOUTH, `pinctrl-lito.c:1505`) inside its `0x5b000` map (`:563`), and `touch_gpio()`
   hardcodes `st.gpio` for every pin, so a SOUTH base would be needed there too.
3. **The branch-halt check checks the wrong register.** `0x18144` (`:163`) is the RCG's
   `CFG_RCGR`, not a branch CBCR; bit 31 there is always 0, so the loop can never report a
   halted branch. The S1 branch may stay stopped while `touch_clocks()` returns true, and
   the failure only surfaces as a transfer timeout. The same function also writes the
   update bit to `cmd_rcgr` (`:157`) while reading/writing the CFG fields at `+4` (`:143,
   155-156`), so the two halves disagree about which word is the CFG.
4. **Vote mask too wide.** `(0x0fu << 18) | (1u << 23)` (`:140`) also votes bits 18/19,
   which are not SE7's; bits 20/21 (the wrapper AHBs) are only covered by accident.
5. **No flips**: coordinates arrive mirrored on both axes. Touch works, but every point lands
   180° away (taps appear at `1079-x, 2399-y`) and edge gestures fire from the wrong side.
6. **Chip gate pins one string**: `gid[2] == '8' && gid[3] == '6'` (`:603`). A relabelled or
   re-spun part falls through to `no unique supported IC` (`:605-609`) and the driver stops,
   which reads as a bus fault rather than a string mismatch.
7. **No 1.8 V vote and no switch handling** (rows 7-8), and GPIO 90 driving is inherited
   from sweet with no avicii property behind it.

## 5. The patch skeleton

`avicii/xnu-patch-notes/0095-avicii-goodix-gt9886-touch.patch`, a unified diff against
`bsd/dev/sweet_touch.c` and `bsd/dev/sweet_rpmh.c` in the series state. It applies with
`patch -p1` / `git apply`, adds no file and no KEXT. Hunk map:

| hunk | change | why |
|---|---|---|
| header | rails/handedness paragraph | a reader must not think this is still sweet |
| defines | `TOUCH_NORTH_PA 0x0f500000`, `TOUCH_SOUTH_PA 0x0f100000`, explicit vote mask, `TOUCH_RCG_S1_HALT`, `TOUCH_ADDR`, panel W/H, `TOUCH_XFLIP`/`YFLIP` | §3 rows 2-5, 11-12 |
| `st`, `touch_gpio` | second MMIO base `gpio_s` + its map and NULL check; `touch_gpio` picks the base by pin (>= 90 south) | gpio 90 lives in the SOUTH quadrant (`:563`); the function wrote `st.gpio` for every pin |
| `touch_clocks` | masked vote, explicit `TOUCH_RCG_CFG`/`_DFS`/`_DFS0` (cmd_rcgr + CFG offset), update bit written into CFG, S1 CBCR in the branch list | §4 items 3-4; other users' bits stay |
| `touch_map` | mirror in panel space, called by both parsers after the bounds check | §4 item 5; bounds run **before** mirroring so an out-of-range IC value is still an error |
| power block | vote `smpa4` 1800 then `ldo13` 3008 with `ldoa13` retry, abort if all fail | §4 item 1, order = IO before analog |
| probe | `TOUCH_ADDR`, id gate `gid[0..1] == "98"`, full string logged | §4 item 6 |
| probe-only | `sweettouchprobe` boot-arg exits after the ident | §6 |
| rpmh | accept `ldo13`/`ldoa13`/`smpa4` with per-rail voltage windows | the helper hard-rejects anything but `ldoc11` |

Deliberately **not** changed: report decoding, checksums, ack, `TOUCH_MAX`, 100 kHz,
`TOUCH_RCG` itself (already `0x18140` and correct), the `0x5d` address constant already in
the protocol calls, and the GPIO 6/7 mux (function 1 = `qup11`, 2 mA, `bias-disable` —
`refs/lito-dts/lito-pinctrl.dtsi:1208-1221`, which the base sequence already matches).

## 6. First test

Everything downstream of the ident is speculative until the ident works. Keep touch off in
the normal image; use the probe arg only for the probe boot:

```
# normal image, touch inert
... sweettouch=0 sweetts=0
# probe boot
... sweettouch=1 sweettouchprobe=1 sweettouchdelay=45
```

`sweettouch=0` is the documented keep-off switch (`docs/fajita-PORTING.md:90`,
`docs/anonbeat1-NOTES.md:83`) and prints `SWEET TOUCH: disabled (sweettouch=0)`
(`:647-652`). `sweettouchdelay` (seconds) delays the MMIO mapping so the persistent log and
the GUI exist before a possible bus hang (`:550-560`). `sweettouchprobe` runs the ident and
the two inert info reads, then terminates the thread; the reporting loop is never entered.

The probe is the smallest possible: 12 bytes at `0x4022` through the 2-byte pointer. What
the log prints (`:594-596` plus the per-transfer line at `:299-302`):

- **correct**: `probe xfer addr=0x5d read len=12 ... err=0`, then
  `probe 0x5d err=0 pid=39383836 fw=..` — pid bytes are ASCII `"9886"`, bytes 8-11 a
  plausible firmware version, and neither raw dump is all `0x00`/`0xa5`.
- **chip absent / bus dead**: `err` with `NACK` in `irq`, or `abort failed` and `st.dead`.
  Nothing readable at `0x4022`.
- **rails off**: the same NACK pattern, but preceded by `RPMH` lines that show `enable
  failed`, `lookup matches=0` or a wrong voltage — read the RPMH lines first, then suspect
  `enable1v8_gpio`.
- **addressing wrong**: the pid bytes look like shifted register data (a byte of the pointer
  or a neighbouring register echoed into byte 0) — the 2-byte pointer is not being sent.
- **flips wrong**: ident fine and touch fine, but taps land 180° away → `TOUCH_XFLIP`/
  `TOUCH_YFLIP`, not the decoder.

Panel behaviour: the driver draws nothing, so a correct ident is invisible. The visible test
starts only with reporting on (`sweettouch=1` without the probe arg): then a correct run
moves the cursor under the finger, and a bottom-edge swipe starts the home gesture
(`refs/dipa-studio-ios-sweet/xnu/patches/0071-sweet-touch-edge.patch:5-15`). At rest the
TLMM line must show the reset pin high with pull-up, and `sweettouchirq=1` must not spin.

Per attempt record: the `RPMH` lines (each carries the resolved address), the full probe
line, both raw dumps, the IRQ row from a `70-interrupts.txt`-style dump, and the exact
boot-args — in the `docs/IMAGE_PROVENANCE.md` form.

## 7. Open items

| item | why it is open | how it resolves |
|---|---|---|
| which cmd-db string the LDO really has (`ldo13` vs `ldoa13`) | DT says `ldoa13`, series says `ldo13`, no cmd-db dump exists | the `SWEET RPMH: <res> addr=...` line (`sweet_rpmh.c:196-197`) shows which one matched; drop the loser afterwards |
| `smpa4` mode | the DT lists only RET/AUTO for S4 (`lito-regulators.dtsi:40-41`); the helper writes 7 (HPM) | if the TCS completes but the rail reads 0 V, try mode 6 (AUTO) at `sweet_rpmh.c:271` |
| rail voltage unit | mV-in-argument is the codebase convention, mV-vs-uV on the RPC unproven | meter on the rail; the log prints the number sent |
| `enable1v8_gpio` (PM8150L GPIO1, active low) | nothing in the tree writes PMIC GPIOs (the SPMI path is read-only), so it relies on ABL having left it asserted | if S4 is voted and the IC still NACKs, this is the next suspect; driving it needs an SPMI write path |
| GPIO 90 as "board enable" | inherited from sweet (`:583`); avicii's DT has no such property, and pin 90 is SOUTH | the `vdd90` field in the sequence log; harmless if it drives an unrelated pin |
| the `CFG_RCGR` offset (`cmd_rcgr + 4`) | the base wrote the divider one word off relative to its own RCG id; the `+4` is the Linux `clk_rcg2` layout, not measured here | `gcc vote=... rcg=... cfg=... dfs=...` (`:144-145`): `dfs & 1` must be 0 (lito has no DFS RCG) and `DFS level0`/`RCG update timeout` name the wrong-register case |
| device is `lito`, driver is guarded `ARM64_BOARD_CONFIG_SWEET` | the whole base tree is sweet-guarded | out of scope: widen the guard or have the ADT define the sweet token (`docs/SHIM_BOOT.md`) |
| second touch variant (FTS) | `docs/FTS_TOUCH.md` stays as fallback | untouched here |

## 8. Out of scope

Firmware/config upload, gesture mode, `fw_update`, pen (the decoder still rejects pen
records), pressure, edge-limit commands, any GIC handler, suspend/resume, and the `st,fts`
fallback path.
