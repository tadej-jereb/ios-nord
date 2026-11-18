# avicii (OnePlus Nord, SM7250) — hardware constants

Status: **paper constants, pre-device**. Every row below comes from the vendor
device tree in this directory. Rows with no citation are marked `UNVERIFIED`
and must be replaced by a live read before any code depends on them.

Device: OnePlus Nord `avicii`, Qualcomm SM7250-AB (lito), 8×Kryo (2×A76 +
6×A55), 1080×2400 DSC AMOLED, single UFS 3.0 (2 lanes), A/B slots.
Target tree: `dipa-studio/ios-sweet` (XNU + iOS 16 userland), ADT/board layer
adapted from `docs/fajita-PORTING.md`.

> Bring-up is security-off. Keep `boot_a`/`boot_b` backups. Never write
> `persist`, `modemst*`, `fsg`, `xbl`, `abl`, `tz`, `op1`, `op2`.

## Provenance of every citation

All line numbers are against the files in **this directory**. Do not cite a
spec sheet, a wiki, or a review-site "Snapdragon 765G" page — the numbers below
are the ones ABL and the vendor kernel actually use.

| File | Origin |
|---|---|
| `lito.dtsi` | `OnePlusOSS/android_kernel_oneplus_sm7250`, `arch/arm64/boot/dts/vendor/qcom/lito.dtsi`, branch `oneplus/SM7250_Q_10.0` |
| `mtp.dtsi` | same repo, `…/qcom/mtp.dtsi` (MTP reference board for lito) |
| `avicii.dtsi` | same repo, `…/qcom/avicii.dtsi` (board overlay) |
| `a2.dtsi` | same repo, `…/qcom/a2.dtsi` (A2/EVT board overlay) |
| `panel.dtsi` | same repo, `…/qcom/panel/…` — Samsung AMS644VK04 panel definition |
| `lito-pinctrl.dtsi` | same repo, `…/qcom/lito-pinctrl.dtsi` (TLMM node + pinmux) |
| `lito-qupv3.dtsi` | same repo, `…/qcom/lito-qupv3.dtsi` (GENI SE map) |
| `pinctrl-lito.c` | same repo, `drivers/pinctrl/qcom/pinctrl-lito.c` (register layout) |

`lito.dtsi` is the SoC file: it `#include`s `lito-pinctrl.dtsi` (line 3856) and
`lito-qupv3.dtsi` (line 3975), which is why both had to be pulled to verify the
TLMM and touch-bus addresses. Two more includes matter and are **not** on disk:
`lito-pm.dtsi` (line 3857, PMIC/regulator + GPIO controller definitions) and
`lito-sde-display.dtsi` (via `mtp.dtsi:3`, panel power-supply table).

## 1. SoC, CPUs, interrupt controller

| Item | Value | Notes | Citation |
|---|---|---|---|
| SoC / platform | SM7250-AB, `qcom,lito`, 8×Kryo 475 | msm-id list is `<400 0x10000>, <440 0x10000>` — **decimal 400 = 0x190, 440 = 0x1b8**; both SKU ids present | `lito.dtsi:22-23` |
| Little cluster | A55, MPIDR `0x000, 0x100, 0x200, 0x300, 0x400, 0x500` | cores 0–5, `capacity-dmips-mhz = <1024>`, all on `qcom,freq-domain 0` | `lito.dtsi:55,87,113,139,165,190` + `:62` (=`0 6`) |
| Big cluster — Gold | A76, MPIDR `0x600` | core 6, `capacity-dmips-mhz = <1740>`, freq-domain 1 | `lito.dtsi:215,222` |
| Big cluster — Prime | A76, MPIDR `0x700` | core 7, `capacity-dmips-mhz = <1740>`, freq-domain 2 — highest domain index, so the top bin (~2.4 GHz) | `lito.dtsi:242,249` |
| Which big core is the prime | **`0x700`**, not `0x600` | frequency-domain index ascends with tier (1 = gold, 2 = prime), and the thermal table throttles CPU7 from fmax to 1766 MHz but CPU6 only to 1728 MHz, i.e. CPU7 is the faster core. `avicii/tools/mkadt_avicii.py:60` already encodes this; an earlier revision of this table had the two swapped | `lito.dtsi:222,249`, `avicii.dtsi:31-45` |
| Max CPU frequencies | Prime ≈ 2.4 GHz (`0x700`), Gold ≈ 2.2 GHz (`0x600`), A55 ≤ 1.8 GHz | `UNVERIFIED` — no OPP table in the DT; the perf-state table is programmed by ABL into `qcom,cpufreq-hw` (`lito.dtsi:1758`). Read `scaling_max_freq` per policy on the device | `UNVERIFIED` |
| CPU clock source | `qcom,cpufreq-hw` @ `0x18323000`, `0x18325800`, `0x18327800` | one register block per freq-domain | `lito.dtsi:1758-1761` |
| cpufreq-hw (OSM) register layout | `ENABLE 0x0` (bit 0), `FREQ_LUT 0x110`, `VOLT_LUT 0x114`, `PERF_STATE 0x920`, `CYCLE_CNTR 0x9c0`; LUT rows 32 B, ≤ 40; row `[31:30]` src (0 = alternate), `[7:0]` L (MHz = L × 19.2), `[18:16]` core count; end = repeated row | `qcom,cpufreq-hw` → `cpufreq_qcom_std_offsets` (not the EPSS layout spacewar has); `lito.dtsi` sets no `qcom,lut-row-size` override | LineageOS `android_kernel_oneplus_sm7250` `lineage-20` `drivers/cpufreq/qcom-cpufreq-hw.c:22-24,101-107,463-516,862-866` (sha256 `e54e0989…e3a5`) |
| L3 (devfreq-fw) register layout | `en-base 0x18321000` (bit 0), `ftbl-base 0x18321110` (rows 32 B, ≤ 40, `[31:30]` src, `[7:0]` × 19.2 MHz), `perf-base 0x18321920`, `pstate-base 0x18321700`; one perf register shared by all voters (cpu0/cpu6/cpu7/cdsp) | `qcom,devfreq-fw` `qcom,devfreq-l3`; same layout as an OSM CPU domain at 0x18321000; CPU domains have `qcom,no-accumulative-counter` ⇒ one cycle counter per domain at `+0x9c0` | `lito.dtsi:1766,1778-1800`; LineageOS `android_kernel_oneplus_sm7250` `lineage-20` `drivers/devfreq/devfreq_qcom_fw.c:22-28,48-80,147-162,182-196` (sha256 `047deaed…f888`) |
| GIC distributor | GICD `0x17a00000`, 64 KiB | `arm,gic-v3`, `#interrupt-cells = <3>` | `lito.dtsi:599,605` |
| GIC redistributor | GICR `0x17a60000`, 1 MiB (8 frames) + stride `0x20000` | `#redistributor-regions = <1>` | `lito.dtsi:603,604,606` |
| GIC maintenance IRQ | `GIC_PPI 8`, level-high | PPI → INTID 16+8 = 24 | `lito.dtsi:607` |
| Arch timer PPIs | PPI 1 (secure EL1 phys), 2 (NS EL1 phys), 3 (**virt**), 0 (NS EL2 phys) | `arm,armv8-timer`; **PPI 3 ⇒ virtual timer INTID 16+3 = 19** — this is the one XNU's `AppleARMIO` timer uses | `lito.dtsi:648-653` |
| Timer frequency | 19.2 MHz | also `dev-ref-clk-freq = <0>` documented as 19.2 MHz on UFS | `lito.dtsi:654,1858` |
| PDC (wakeup GIC) | `0xb220000` + `0x17c000f0` | `qcom,lito-pdc`, parent `&intc`; slpp/wakeup only | `lito.dtsi:611-619` |

MPIDR formula is `core << 8` (0x0-0x700), exactly as `tools/mkadt.py` in the
sweet tree assumes. fajita needed the same fix; nothing to change here, but the
cluster split for the ADT is 6 little + 2 big, **not** 4+4.

## 2. Memory map

| Item | Value | Notes | Citation |
|---|---|---|---|
| Splash / boot framebuffer | `0xa0000000`, size `0x2300000` (35 MiB) | `cont_splash_region`; ABL composes the boot logo here and keeps scanning out | `lito.dtsi:504-506` |
| `disp_rdump_region` | `0xa0000000`, `0x2300000` | same window, read-dump alias | `lito.dtsi:514-516` |
| `dfps_data_region` | `0xa2300000`, `0x100000` | sits **immediately after** the splash region; the FB block is exactly 35 MiB, do not round up | `lito.dtsi:509-511` |
| RAM `memory` node | `reg = <0 0 0 0>` — **placeholder** | filled per-SKU by ABL; the DT carries no size. See §6 | `lito.dtsi:28` |
| `mem-offline` | `0x1 0x40000000 0x0 0x40000000`, `0x1 0xc0000000 0x0 0x80000000`, `0x2 0xc0000000 0x1 0x40000000` | three carve-out shapes ⇒ **two RAM SKUs exist** (see §6) | `lito.dtsi:31-35` |
| PS_HOLD | `0xc264000` | 4 bytes, `qcom,pshold`; second reg `0x1fd3000` = `tcsr-boot-misc-detect` | `lito.dtsi:1326-1328` |
| IMEM base | `0x146ab000`, 4 KiB | `qcom,msm-imem`; `ranges` maps children to this base | `lito.dtsi:716-719` |
| IMEM restart reason | `0x146ab65c` (`0x146ab000` + `0x65c`) | 4 bytes; `0x77665500` = bootloader (shim-proven, `avicii/shim/shim.c:18`). **Not enough alone from the kernel:** a 0133 reset with only this word booted `boot_a` normally (`logs/phone/20261116-0133-reboot-test/ring-post.txt`) | `lito.dtsi:718,728-730` |
| PON reboot reason | PM8150 SID 0 periph `0x08`, `SOFT_RB_SPARE` reg `0x8f`, bits 7:1; `2` = bootloader, `1` = recovery (UNVERIFIED on avicii); subtype reg `0x05` (4/5 = gen2) | ABL reads it at reset. Linux `qcom-pon` reason shift 1 (`refs/ry-diffusion-Bergamota/docs/REBOOT_MODE.md:10-14`); proven on PM8150 by raphael 0114 (`refs/marnov999-raphael-ios-gpu/NOTES.md:365-366`). Used by patch 0134 | `avicii.dtsi:341-342` |
| IMEM other | `mem_dump_table@0x10`, `dload_type@0x1c`, `boot_stats@0x6b0`, `kaslr_offset@0x6d0`, `pil@0x94c` | needed if the shim logs boot stats | `lito.dtsi:723,733,738,743,748` |
| Apps RSC | `0x18200000`, three 64 KiB drv blocks (`drv-0/1/2`) | `qcom,rpmh-rsc`, `qcom,drv-id = <2>` | `lito.dtsi:2148-2156` |
| Apps RSC TCS | `0x18200d00` (`0x18200000` + `tcs-offset 0xd00`) | TCS layout `ACTIVE 2 / SLEEP 3 / WAKE 3 / CONTROL 1` — all RPMh clocks and regulator votes go through here | `lito.dtsi:2148,2158-2162` |
| RSC IRQs | SPI 3, 4, 5 | level-high | `lito.dtsi:2157-2159` |
| SPMI arbiter | `0xc440000` (core, `0x1100`) | chnls `0xc600000`/`0x2000000`, obsrvr `0xe600000`, intr `0xe700000`, cnfg `0xc40a000`; `qcom,ee = <0>`, `qcom,channel = <0>` | `lito.dtsi:1804-1815` |
| TLMM base | `0xf000000`, window `0x1000000` (16 MiB), `qcom,lito-pinctrl` | single flat window, **no `qcom,tile-size` property and no tile sub-nodes** on this SoC | `lito-pinctrl.dtsi:2-4` |
| TLMM register stride | `0x1000` per GPIO: `ctl_reg = base + 0x1000*id`, `io_reg = +0x4`, `intr_cfg_reg = +0x8`, `intr_status = +0xc` | that is the "tile stride" — pin *n* lives at `0xf000000 + n*0x1000` | `pinctrl-lito.c:25,44-48` |
| TLMM GPIO count | 146 | `ngpios`; pins ≥146 are invalid | `pinctrl-lito.c:1626` |
| TLMM IRQ | `GIC_SPI 208` | plus a PDC `irqdomain-map` for wakeup-capable pins (e.g. gpio 9 → PDC 104, gpio 10 → PDC 54) | `lito-pinctrl.dtsi:5,17,18` |

## 3. Display

| Item | Value | Notes | Citation |
|---|---|---|---|
| Panel | Samsung **AMS644VK04**, `"samsung ams644vk04 fhd cmd mode dsc dsi panel"` | `SAMSUNG` / `DSC`, `dsi_cmd_mode` | `panel.dtsi:14-19` |
| Resolution | 1080×2400 | physical 67×149 mm, 24 bpp, `burst_mode`, lanes 0-3 | `panel.dtsi:84-85,43-44,22,28,32-35` |
| Rate / clock | 60 fps, `832000000` Hz | `mdp-transfer-time-us = 12000`; timing@1 is the 90 fps variant | `panel.dtsi:78-81` |
| DSC | 2 encoders, slice 540×48, 2 slices/pkt, 8 bpc / 8 bpp, block prediction | `qcom,compression-mode = "dsc"` | `panel.dtsi:478-486` |
| Topology | `<2 2 1>` default (index 1) — **dual-DSI** | not `<1 1 1>`; the shim/MDP must drive both DSI controllers | `panel.dtsi:920-922` |
| TE | `&tlmm 10` | TE pin select, TE DCS command, `te-check-enable`, `te-using-te-pin` | `panel.dtsi:906,39-40,46,48` |
| Panel reset | `&pm8150l_gpios 3` | PMIC GPIO, **not** a TLMM pin — the shim needs the SPMI path, not the TLMM path | `panel.dtsi:907` |
| Panel power | `dsi_panel_pwr_supply_samsung` | table lives in `lito-sde-display.dtsi` (not pulled) ⇒ `UNVERIFIED`; likely 1.8 V vddi + 3.0 V avdd (pm8150_l13 family) | `panel.dtsi:902` — `UNVERIFIED` for the rail list |
| Reset sequence | `<1 10>, <0 10>, <1 10>` ms | | `panel.dtsi:38` |
| Brightness | min 1, max 2047, default 320, `bl_ctrl_dcs` | 11-bit DCS backlight | `panel.dtsi:41-42,903-905` |
| HDR | enabled, peak 5 400 000, avg 2 000 000, blackness 2000 | | `panel.dtsi:55-59` |
| ESD check | `reg_read` on DCS `0x0A`, expect `0x9C`, 1 byte, LP mode | | `panel.dtsi:70-75` |
| **Panel selection conflict** | `panel.dtsi:897` marks the AMS644 active, but `mtp.dtsi:486` still sets `sde_dsi` default to `dsi_sw43404_amoled_video`, and the ST touch node's `panel` list (`mtp.dtsi:362-363`) names only sw43404 panels | the AMS644 is the avicii panel; treat sw43404 as the MTP leftover. Which panel a given retail unit actually has is a **live-only** value (§9) | `panel.dtsi:897`, `mtp.dtsi:362-363,416,486` |

## 4. Touch — **RESOLVED on this unit: Goodix GT9886**

avicii shipped with two different touch controllers on the same bus, same IRQ
GPIO, same reset GPIO. Both nodes are present in the DT and both instantiate.
**On this device the Goodix is the bound one** — live dump 2026-11-12:
`/sys/bus/i2c/devices/4-005d/driver -> ../../bus/i2c/drivers/Goodix-gt9886`,
while `4-0049` has `of_node` but **no `driver` symlink**, i.e. the ST FTS client
sits unbound. The `qcom,i2c-touch-active = "st,fts"` property is a board default,
not what this unit runs. Port the Goodix GT9886 path; keep FTS only as fallback.
Citation: `logs/dumps/run-20261112-195027/50-i2c-4-005d.txt`, `50-i2c-4-0049.txt`.

Porting note: the base tree's `sweet_touch.c` is already a Goodix driver
(GT9896), so the avicii delta is the chip id/`0x5D` address, the `register-is-16bit`
flag and the `0x2002` IRQ flag cell — not a new vendor protocol.

| Item | Value | Notes | Citation |
|---|---|---|---|
| Controller A | STMicroelectronics **FTS** @ I²C `0x49`, `st,fts` | node named `st_fts@49`; this is the board's *selected* touch (`qcom,i2c-touch-active = "st,fts"`) | `mtp.dtsi:343,345-347` |
| Controller B | Goodix **GT9886/GT885** @ I²C `0x5D`, `Goodix-gt9886` | `project-name = "20801"`, `chip-name = "GT885"`, `module_id = <7>`, `register-is-16bit` | `lito.dtsi:3987-3992,4009` / `mtp.dtsi:369-373` |
| Bus | GENI SE7 I²C, `0x984000`, `GIC_SPI 354`, alias `i2c4` | 400 kHz default; SE7 is in QUPv3 wrapper 1 | `lito-qupv3.dtsi:370-373`, `lito.dtsi:48` |
| IRQ | `&tlmm 9` | A: `<9 0x2008>`; B: `<9 0x2002>` — same pin, different flag cell | `mtp.dtsi:349,355`, `lito.dtsi:3995,4003` |
| Reset | `&tlmm 8` | A: active-low `0x00`; B: `0x1` | `mtp.dtsi:356`, `lito.dtsi:4004` |
| Rails (A) | `vdd` = `pm8150_s4`, `avdd` = `pm8150_l13` | | `mtp.dtsi:350-351` |
| Rails (B) | `vdd_2v8` = `pm8150_l13` (3.008 V) + `enable1v8_gpio` = `&pm8150l_gpios 1` (active-low) | B has no `vdd`/S4 rail; the 1.8 V is switched by a PMIC GPIO | `lito.dtsi:3998-4000`, `mtp.dtsi:380-381` |
| Geometry | 1080×2400, 15×34 TX/RX, 10 points | identical for both | `lito.dtsi:4009-4012` |
| Pinmux | `ts_int_active` (`gpio9`), `ts_reset_active` / `ts_reset_suspend` (`gpio8`); `ts_active` + `ts_int_suspend` come from the common pinctrl file | all four are plain `gpio` muxes with `bias-disable` / pull-down | `mtp.dtsi:416,431,442`, `lito-pinctrl.dtsi:1795,1810` |

Consequence for the port: the sweet tree has a Goodix protocol driver and
`sweettouch=0` leaves touch off. Bringing avicii up on the **ST FTS** path means
a new driver anyway (ST's `fts` protocol, not Goodix's), so plan for ST and
detect the chip by I²C ACK at `0x49` / `0x5D` and by `/sys/bus/i2c/devices/*/name`.

## 5. Keys

| Item | Value | Notes | Citation |
|---|---|---|---|
| Power / PON | SPMI `pm8150@0` slave 0, `qcom,power-on@800` | `kpdpwr` / `resin` / `kpdpwr-resin-bark` on `0x0 0x8 0x0` / `0x1` / `0x5`; S1 6720 ms, S2 2000 ms, hard-reset | `avicii.dtsi:341-347,349-355` |
| S3 source | `kpdpwr-and-resin` | PMIC S3 (X_VDD_RPM) gating | `avicii.dtsi:347` |
| Volume up | `&pm8150l_gpios 5`, active-low | gpio-keys, `KEY_VOLUMEUP`, wakeup | `mtp.dtsi:16-19` |
| Volume down | `&pm7250b_gpios 3`, active-low | gpio-keys, `KEY_VOLUMEDOWN`, wakeup | `mtp.dtsi:26-28` |
| Alert slider | `oneplus,tri-state-key`: `pm7250b_gpios 10` + `&tlmm 83` + `&tlmm 69` | three positions, not a plain key | `mtp.dtsi:52-60` |

Both volume keys are **PMIC** GPIOs (PM8150L / PM7250B) reached over SPMI —
there is no TLMM GPIO for them. The sweet tree's key driver already talks SPMI
(`sweetkeys`), but the slave/GPIO numbers change.

## 6. RAM / SKU — the open question

The memory node is literally `reg = <0 0 0 0>` (`lito.dtsi:28`). ABL patches it
per SKU. Nothing on paper gives the split. What the DT does say:

- `mem-offline` (`lito.dtsi:31-35`) gives three `<bank offset size>` shapes:
  `0x1 0x40000000 0x40000000`, `0x1 0xc0000000 0x80000000`, and
  `0x2 0xc0000000 0x40000000`. The third one addresses **bank 2**, so at least
  one SKU has memory above `0x1_00000000`. The exact installed sizes are not in
  the DT — that is an inference from the shapes, not a stated value.
- The frozen `offline-sizes` are per-SKU and are *not* the RAM size.

Port consequence: `HIGH_MEM_SIZE` and the `memory` node handed to XNU must come
from the live FDT. Guessing a single flat bank gives either a truncated RAM map
or a phantom bank that faults on first touch. `avicii.dtsi`/`a2.dtsi` contain no
`memory` override at all (grep: no `memory` node in either file), so the
placeholder is all there is.

## 7. Storage (UFS 3.0, single host, 2 lanes)

| Item | Value | Notes | Citation |
|---|---|---|---|
| UFS host (UFSHCI) | `0x1d84000`, `0x3000` | `qcom,ufshc`, `GIC_SPI 265`, `lanes-per-direction = <2>` | `lito.dtsi:1849-1852,1857` |
| UFS PHY | `0x1d87000`, `0xe00` | `qcom,ufs-phy-qmp-v4-lito`, `qcom,rpmh-resource-name = "qphy.lvl"` | `lito.dtsi:2182-2183,2189` / `mtp.dtsi:164` |
| UFS ICE | `0x1d90000`, `0x8000` | `qcom,ice`, `qcom,enable-ice-clk`, `op-freq 300 MHz`, `instance-type = "ufs"`; wired as `ufs-qcom-crypto` into both host and PHY | `lito.dtsi:1823-1836,1855,2186` |
| Boot image geometry (stock) | header **v2**, page `4096`, kernel_addr `0x8000`, ramdisk_addr `0x1000000`, tags `0x100`, kernel = raw uncompressed `Image` (43,876,368 B), **no appended DTB** | parsed from `src/los21-boot.img`; v2 boots here, v1 is what the port packs (see `docs/SHIM_BOOT.md`) | `src/los21-boot.img` byte 0x08..0x2c |
| SoC base DTB (dtb-section source) | `boot.img` dtb section: 406,620 B, `qcom,msm-id <190 10000 1b8 10000>`, 0 `fragment@` nodes | `src/avicii-soc.dtb`, sha256 `48b0902a…40ce`; **this** is what the image's dtb section must carry (ABL needs the base tree, not the overlay) | `src/los21-boot.img` `dtb_size` @0x670 = `0x6345c`, section @0x2bab000 |
| Board DTB source | `dtbo.img`, single-entry big-endian `dt_table`: 337,226 B at `0x40`, `board-id <8 0>`, `oplus,dtsi_no 0x5141`, `pcb_range <0 0x37>` | extracted to `src/avicii-board.dtb`; `model = "Lito MTP 20801"`, `compatible = "qcom,lito-mtp"`; a **fragment overlay**, so no `/memory` in it and no `qcom,msm-id` | `src/dtbo.img` header + entry |
| Boot partition | image padded to 96 MiB | 356 KiB shim fits with room; a full 43 MiB kernel also fits | `src/los21-boot.img` total size |
| UFS clocks | core ≤200 MHz, unipro ≤150 MHz, ICE ≤300 MHz | `freq-table-hz`; `dev-ref-clk-freq = <0>` ⇒ 19.2 MHz ref | `lito.dtsi:1883-1896,1858` |
| UFS rails | vcc `pm8150a_l7` 2.95-2.96 V, vccq2 `pm8150_s4`, vdda-phy `pm8150_l5`, vdda-pll `pm8150_l9`, vddp-ref-clk `pm8150_l9` 1.152-1.2 V | GDSC `ufs_phy_gdsc` | `mtp.dtsi:163-183` |
| Partition path | `/dev/block/platform/soc/1d84000.ufshc/by-name/…` | the number is the host MMIO address — the by-name dir path is derived, not fixed | `lito.dtsi:317-320` |
| Storage notes | single UFS, UFS **3.0** (lito), 2 lanes, ICE inline | No SD card. `sdhc_1` (eMMC/SD) exists in the SoC but is not wired for boot on avicii. ICE must be **bypassed or key-cleared** for a foreign root, else the iOS volume reads as ciphertext | `lito.dtsi:1849,1857,1963-1966` |

## 8. WLAN / IPA

| Item | Value | Notes | Citation |
|---|---|---|---|
| WCN3990 host (icnss) | `0x18800000`, `0x800000` | `qcom,icnss`, `iommus = <&apps_smmu 0xC0 0x1>` | `lito.dtsi:3756-3759` |
| IPA IOVA pool | `0xb0000000`, `0x10000` (`smmu_iova_ipa` second reg) | fixed IPA doorbell window handed to the WLAN firmware | `lito.dtsi:3759-3760` |
| WLAN DMA pool | `0xa0000000`, `0x10000000` | **overlaps the splash FB base** — 256 MiB window; the splash only occupies the first 35 MiB of it, so the FB must be reserved before icnss maps its pool | `lito.dtsi:3775,504-506` |
| WLAN FW carve-out | `pil_wlan_fw_region` @ `0x8ba00000`, `0x200000` | `no-map`; referenced as `qcom,wlan-msa-fixed-region` | `lito.dtsi:414-418,3774` |
| WLAN CE IRQs | SPI 132, 81, 415, 416, 417, 86, 94, 96, 82, 119, 120, 87 (CE0-CE11) | | `lito.dtsi:3761-3773` |
| IPA core | `qcom,ipa@1e00000`, IPAv4.7 (`qcom,ipa-hw-ver = <18>`) | | `lito.dtsi:3649-3658` |
| MPSS PAS peripheral ID | 4 | Signed modem firmware | `lito.dtsi:2861-2880` |
| ICNSS supply resource IDs in vendor order | `ldoa1`, `ldoa14`, `ldoc2`, `ldoc10`, `ldoc11` | Command database availability requires a live lookup | `lito.dtsi:3778-3782`, `refs/lito-dts/lito-regulators.dtsi:95,371,588,732,750` |
| MPSS/ADSP carve-outs | `pil_ipa_fw` `0x8bc00000`, `pil_ipa_gsi` `0x8bc10000`, `modem_wlan` `0x8c000000`/`0xf800000` | | `lito.dtsi:420-433,444-447` |

## 9. Values that exist ONLY as a live read — guessing them breaks the port silently

Collect all of §9 with `avicii/tools/dump-live.sh` (root adb), then read the
results before touching code.

Each of these has a plausible-looking wrong answer that boots far enough to look
healthy. All must come from `avicii/tools/dump-live.sh` output or the live FDT.

1. **RAM base/size per SKU** — `lito.dtsi:28` is `reg = <0 0 0 0>`. Guess 4 GiB:
   XNU maps a phantom bank. Guess 8 GiB: adds a bank past the real top and
   panics on the first page beyond it, usually inside the pmap bootstrap with no
   message. Take it from `/proc/device-tree/memory/reg` + `/proc/iomem`.
2. **Touch controller identity** — `0x5D` Goodix on this unit (resolved, `§4`). Wrong
   guess = the driver probes, gets no ACK, and the bring-up "just has no touch".
   Worse: the two use different IRQ flag cells (`0x2008` vs `0x2002`), so a
   mismatched config can leave the line latched and storm the GIC.
3. **Panel model / supplier** — the DT carries a Samsung AMS644VK04 *and* an
   sw43404 default (`§3`). A unit with the other panel shows a black screen with
   a clean boot log, because the DSI init sequence is panel-specific. Read the
   panel name and the DSI `0xDA`/`0xDB` ids.
4. **DTB board id / `qcom,board-id`** — `lito.dtsi` sets only `qcom,msm-id`
   (0x190/0x1b8); the per-unit board-id and platform-id are appended by ABL. A
   hand-built DTB whose ids don't match the unit is rejected or mismatched by
   ABL/`boot.img` selection.
5. **CPU max frequencies** — not in the DT (`§1`); read `scaling_max_freq` per
   policy. Guessing the bin gives wrong ADT `clock-frequency` values and either
   a low-performance boot or an unstable one.
6. **UFS gear/lane state and ICE provisioning** — what ABL leaves the host in,
   plus whether ICE is keyed. Read the host attributes and `by-name` presence; a
   wrong assumption reads the root as noise.
7. **Touch rail voltage actually set** — `pm8150_l13`'s programmed voltage is a
   runtime regulator state; the DT only gives the nominal 3.008 V request
   (`lito.dtsi:4000`).

## 10. Diff checklist vs sweet / fajita — every row needs a code change

sweet (SM7150, Redmi Note 10 Pro) and fajita (SDM845, OnePlus 6T) are the two
reference trees. Anything marked **same** needs no edit but must still be
confirmed on the live FDT before trusting it.

- [ ] **IMEM base/restart reason**: sweet `0x146aa65c` / fajita `0x146bf65c` →
      avicii **`0x146ab65c`** (`lito.dtsi:718,728-730`). Edit
      `shim/shim.c` restart-reason writes and any panic-path reset.
- [ ] **Splash framebuffer**: sweet paints at `0x9c000000`; fajita's FB sits at
      `0x9d400000` (36 MiB) on a 32 MiB block at `0x9c000000` → avicii
      **`0xa0000000`, 35 MiB**, with `dfps_data` fencing it at `0xa2300000`. Edit `shim/console.h`,
      `shim/mmu.h`, `tools/mkadt.py` FB node, `xnu/patches/0010`, `0012`.
- [ ] **Bootstrap block**: fajita keeps a 32 MiB block at `0x9c000000` with a
      20 MiB FB offset. avicii's splash starts at a fresh `0xa0000000` and the
      `dfps_data` region fences it at `0xa2300000` — the 20 MiB offset logic must
      be re-derived, not copied.
- [ ] **Panel**: 1080×2340 ARGB8888 (fajita) → **1080×2400, DSC, dual-DSI,
      command mode** (`panel.dtsi:84-85,478-486,920-922`). Framebuffer stride,
      MDP topology, `xnu/patches/0061` height, and the ADT display node all
      change. 2400 ≠ 2340 — a copy-paste of 2340 crops 60 rows.
- [ ] **Panel reset path**: fajita uses TLMM GPIO6 → avicii uses **PM8150L
      GPIO3** (`panel.dtsi:907`). The reset helper must go over SPMI, not TLMM.
      TE stays TLMM GPIO10 — same as fajita, confirm only.
- [ ] **Touch IC + protocol**: sweet Goodix (one chip) / fajita Synaptics RMI4 →
      avicii ST FTS **or** Goodix GT9886 (`§4`). `sweettouch=0` must stay set
      until an ST driver exists; the Goodix driver cannot be reused blind.
- [ ] **Touch bus + rails**: sweet Goodix on GENI I²C with a `pm8150_l13`-style
      rail → avicii addresses `0x49`/`0x5D` on SE7 `0x984000`, rails `pm8150_s4`
      (vdd) + `pm8150_l13` (avdd) / `pm8150l_gpios 1` for the 1.8 V switch.
- [ ] **Keys**: sweet/fajita PM8998 GPIO5/6 + PM8998 PON → avicii
      `pm8150l_gpios 5`, `pm7250b_gpios 3`, PM8150 PON at SPMI `0x0/0x8`
      (`mtp.dtsi:19,28`, `avicii.dtsi:341-347`). PMIC slave ids and the PON
      register offset both differ from PM8998.
- [ ] **Alert slider**: new on avicii (`mtp.dtsi:52-60`) — no sweet/fajita
      equivalent; needs its own tri-state input mapping.
- [ ] **PMIC set + regulator names**: PM8998/PM8005 (sweet/fajita) →
      PM8150/PM8150L/PM8150B/PM7250B. Every `LDOxx` reference in the shim's
      regulator votes and in `xnu/patches/0062` (RPMh touch-rail vote) must be
      re-mapped (`pm8150_l13`, `pm8150_s4`, `pm8150a_l7`, …).
- [ ] **SoC identity**: `qcom,kryo385`/SDM845 → SM7250 (`qcom,lito`, msm-id
      `0x190`/`0x1b8`). Keep the `xiaomi,sweet` compatible string and the
      `sweet-fbcon`/`sweet-ufs` node names XNU matches on, but the ADT
      `cpu`/`platform` block needs 8 cores with a 6+2 split and the lito ids.
- [ ] **XNU machine config**: 16K pages — fajita had it on **both** clusters
      (ARMv8.2). Verify A55/A76 on SM7250 accept 16K with the same patches; do
      not assume the fajita result transfers.
- [ ] **CPU count/cluster split**: sweet/fajita 4+4 assumption → avicii 6 little
      (0x000-0x500) + 2 big (0x600 gold, 0x700 prime). Any `MAX_CPUS`/MPIDR
      table with 4 big cores is wrong.
- [ ] **RAM**: sweet single known bank → avicii placeholder + 3 offline shapes
      (`§6`). `HIGH_MEM_SIZE`, the ADT memory node, and the payload load address
      must be computed from the live FDT.
- [ ] **UFS encryption**: fajita/sweet bring-up leaves ICE aside → avicii needs
      an explicit ICE decision (`0x1d90000`, `lito.dtsi:1823`). Also check the
      lane count assumption (2) and gear before reusing sweet's UFS 3.0 code.
- [ ] **GIC**: GICD `0x17a00000` / GICR `0x17a60000` / stride `0x20000` — **same
      as sweet** (`lito.dtsi:604-606`), so `shim/shim.c` GIC setup is unchanged;
      confirm on the live FDT only. Note 8 redistributor frames, not 4.
- [ ] **UFS host / PS_HOLD**: `0x1d84000`, `0xc264000` — same as sweet, no edit;
      confirm only.
- [ ] **DWC3/USB, ADSP, modem carve-outs**: lito map differs from both trees;
      re-derive from `lito.dtsi` before enabling anything beyond console+UFS.

## 11. Refresh

Live collection: `avicii/tools/dump-live.sh` writes a timestamped directory
under `logs/dumps/` with the FDT, `iomem`, `memory/reg`, panel/touch identity,
per-policy max frequencies, `by-name`, and md5sums of everything.

Re-pull the four missing includes before the next code change — `lito-pm.dtsi`
(PMIC GPIOs 1, 3, 5 and the regulator list), `lito-sde-display.dtsi` (panel
supply table), `lito-gdsc.dtsi`, `msm-arm-smmu-lito.dtsi`. Until `lito-pm.dtsi`
is on disk, every `pm8150*_gpios` number above is quoted from the consumer side
only and the GPIO *controller* base is `UNVERIFIED`.

## GPU — Adreno 620 (layer 1, patch 0119; layer 2, patch 0122)

Same inside layout as SM8150 (raphael-ios-gpu's A640), every block 0x1100000 higher.
Sources: LineageOS `android_kernel_oneplus_sm7250` `lineage-20`.

| Item | Value | Note | Citation |
|---|---|---|---|
| GPU core (kgsl-3d0) | `0x3d00000` size `0x40000`, IRQ SPI 300 | chipid `0x06020000`, highest-bank-bit 14, ubwc-mode 3 | `lito-gpu.dtsi:67-82` (sha256 `a699812d…1c9e`) |
| GMU | `0x3d6a000` size `0x30000`; PDC cfg `0xb290000`, seq `0xb490000`; IRQ SPI 304 (hfi), 305 (gmu) | SMMU streams 0x4 (user), 0x5 (kernel), mask 0x400 | `lito-gpu.dtsi:403-451` |
| GPU SMMU | `0x3da0000` size `0x10000` | `qcom,kgsl-smmu-v2` | `lito-gpu.dtsi:368-370` |
| Zap shader | PAS id 13, firmware `a620_zap` | TZ loads it (`qcom,pil-tz-generic`) | `lito-gpu.dtsi:2-6` |
| GPU clock levels | 625 / 500 / 400 / 275 MHz (bin 0), initial level 3 | speed-bin tables follow | `lito-gpu.dtsi:191-301` |
| GPUCC | `0x3d90000` size `0x9000` | | `lito.dtsi:1708-1710` |
| GPU GDSCs | CX `0x3d9106c`, GX `0x3d9100c`, cx_hw_ctrl `0x3d91540`, gx domain `0x3d91508`, gx sw_reset `0x3d91008` | | `lito-gdsc.dtsi:99-133` (sha256 `d3bbb3cb…ec13`) |
| GPUCC branches | ahb `0x1078`, cx_gmu `0x1098`, cxo `0x109c`, gx_gmu `0x1064`, smmu vote `0x5000`; gmu_clk_src rcgr `0x1120` (src 6 = gpll0_main_div, 200 MHz at /1.5) | | `drivers/clk/qcom/gpucc-lito.c:48-55,105-278` (sha256 `7ca7d70e…eb25`) |
| GCC GPU branches | cfg_ahb `0x71004`, memnoc_gfx `0x7100c`, snoc_dvm_gfx `0x71018`, ddrss_gpu_axi `0x71154`; gpll0 vote `0x52000` bit 15, div bit 16 | SM8150 votes at `0x52004` | `drivers/clk/qcom/gcc-lito.c:1125-1345` (sha256 `9ceaf56a…93ff`) |
| Mesa support | `GPUId(620)`: A6xx gen1, 1 CCU, tile align 32×16 | Mesa 24.2.8 | `src/freedreno/common/freedreno_devices.py:507-531` |
| GPU firmware (from LOS 21 `vendor`, `/firmware`) | `a620_zap.{mdt,b00,b01,b02,elf}`, `a650_gmu.bin` (41548 B), `a650_sqe.fw` (31632 B) | copies in `src/gpu-fw/` (not in git) with `SHA256SUMS`: sqe `b4c27420…0487`, gmu `df79fa84…b01c`, zap.mdt `fb7d0580…693f` | `src/lineage-21.0-20240619-nightly-avicii-signed.zip` → `payload.bin` → `vendor` (EROFS) |
| RSCC (A650 family: own block) | `0x3de0000` size `0x1000`; sequencer program `0xeaaae5a0 0xe1a1ebab 0xa2e0a581 0xecac82e2 0x0020edad` | not GMU+0x23000 as on the A640 | live FDT `qcom,kgsl-3d0@3d00000` reg "rscc"; vendor `adreno_a6xx_gmu.c:71-113` (LineageOS `android_kernel_oneplus_sm8250` lineage-21) |
| A620 GMU boot specifics | DTCM at GMU address `0x10004000`; firmware up = `FW_INIT_RESULT[8:0] == 0x100` (a650_gmu.bin core version `0x20010008` > `0x20010004`); `CX_FAL_INTF` (GMU word `0x1f8f0`) = 1; PDC programmed by the host (no `pdc_in_aop`), TCS3 cx vote 2 | | vendor `adreno-gpulist.h:1054-1080`, `adreno_a6xx_gmu.c:364-405,1041-1160`; a650_gmu.bin blocks parsed on the host |
| a650_gmu.bin memory requests | `0x4000`+`0x8000`, `0x144000`+`0x13000`, `0x157000`+`0x9000`, `0x60000000`+`0x1000` (type 7); TCM: ITCM `0x0..0x4000`, DTCM `0x10004000..0x10008000` | | block headers of `src/gpu-fw/a650_gmu.bin` |
| cmd-db | reserved-memory `0x80860000` size `0x20000`, `compatible = "qcom,cmd-db"`, magic `0x0c0330db` at +4 | below XNU's RAM (`0x180000000`) | live FDT `/reserved-memory/reserved-memory@80860000` |
| GPU SMMU ACTLR | `0x32b` for every GFX context (`<0x0 0x3ff 0x32B>, <0x400 0x3ff 0x32B>`) | `qcom,skip-init`, 3-level tables | `msm-arm-smmu-lito.dtsi:4-49` |
| GPU OPP RPMh levels (bin 0) | 275 MHz LOW_SVS (64), 400 SVS (128), 500 SVS_L1 (192), 625 NOM (256) | GMU's own: 200 MHz | `lito-gpu.dtsi:21-62,196-245` |
| Zap shader load | `a620_zap.mdt` = `.b00`+`.b01` (ELF32 header + hash); one load segment `.b02` (0x68c B, paddr 0x5000, relocatable, **p_align 0x100000**). PAS_MEM_SETUP needs a 1 MiB-aligned base: `pil_gpu_region@8bc15400` is refused (`0xffcfffba`), kernel memory on a 1 MiB boundary accepted (0124) | `qcom,kgsl-hyp` names no memory-region | program headers of `src/gpu-fw/a620_zap.mdt`; `logs/phone/gpu-0123-sweetgpu9.txt`, `gpu-0124-sweetgpu9.txt` |
| A620 core registers (layer 3, verified) | PC_DBG_ECO_CNTL 0x10200, RB_NC_MODE 0x12, TPL1 0x2, SP 0x22, UCHE_MODE 1<<21, hang 0x3ffff, CP_APRIV_CNTL 0x6e, RB_CNTL 0x800020c; no UCHE GMEM range | ME_INIT + CP_MEM_WRITE verified | vendor `adreno_a6xx.c` a6xx_start/a6xx_rb_start; `lito-gpu.dtsi` ubwc-mode 3, hbb 14 |

| USB GCC constant (0135) | Value | Notes | Citation |
|---|---|---|---|
| USB master CBCR | `0xf010` | GCC-relative; enable bit 0; CLK_OFF bit 31 (task E status contract) | `refs/lito-dts/gcc-lito.c:2302-2306` |
| USB sleep CBCR | `0xf018` | GCC-relative; enable bit 0; CLK_OFF bit 31 (task E status contract) | `refs/lito-dts/gcc-lito.c:2338-2342` |
| USB mock_utmi CBCR | `0xf01c` | GCC-relative; enable bit 0; CLK_OFF bit 31 (task E status contract) | `refs/lito-dts/gcc-lito.c:2320-2324` |
| USB cfg-noc-axi CBCR | `0xf07c` | GCC-relative; enable bit 0; CLK_OFF bit 31 (task E status contract) | `refs/lito-dts/gcc-lito.c:1062-1066` |
| USB aggre-axi CBCR | `0xf080` | GCC-relative; enable bit 0; CLK_OFF bit 31 (task E status contract) | `refs/lito-dts/gcc-lito.c:973-977` |
| USB pipe CBCR | `0xf05c` | GCC-relative; enable bit 0; CLK_OFF bit 31 (task E status contract) | `refs/lito-dts/gcc-lito.c:2400-2404` |
| USB clkref CBCR | `0x8c010` | GCC-relative; enable bit 0; CLK_OFF bit 31 (task E status contract) | `refs/lito-dts/gcc-lito.c:2351-2355` |
| USB GCC mapping | base `0x00100000`, size `0x00090000` | Driver maps a prefix of the vendor `0x1f0000` span; covers all USB CBCRs | `avicii/lito.dtsi:1662-1664` |

| Watchdog constant (0136) | Value | Notes | Citation |
|---|---|---|---|
| APSS watchdog mapping | `0x17c10000`, `0x1000` bytes | qcom,msm-watchdog | `avicii/lito.dtsi:1465-1468` |
| WDT0_RST | `0x04` | Offset from watchdog base | [SM7250 watchdog_v2.c, commit `9ea68e4dee77be15d37a9044ecae6754fb2ca454`, line 46](https://github.com/LineageOS/android_kernel_oneplus_sm7250/blob/9ea68e4dee77be15d37a9044ecae6754fb2ca454/drivers/soc/qcom/watchdog_v2.c#L46) |
| WDT0_EN | `0x08` | Offset from watchdog base | [SM7250 watchdog_v2.c, commit `9ea68e4dee77be15d37a9044ecae6754fb2ca454`, line 47](https://github.com/LineageOS/android_kernel_oneplus_sm7250/blob/9ea68e4dee77be15d37a9044ecae6754fb2ca454/drivers/soc/qcom/watchdog_v2.c#L47) |
| WDT0_STS | `0x0c` | Offset from watchdog base | [SM7250 watchdog_v2.c, commit `9ea68e4dee77be15d37a9044ecae6754fb2ca454`, line 48](https://github.com/LineageOS/android_kernel_oneplus_sm7250/blob/9ea68e4dee77be15d37a9044ecae6754fb2ca454/drivers/soc/qcom/watchdog_v2.c#L48) |
| WDT0_BARK_TIME | `0x10` | Offset from watchdog base | [SM7250 watchdog_v2.c, commit `9ea68e4dee77be15d37a9044ecae6754fb2ca454`, line 49](https://github.com/LineageOS/android_kernel_oneplus_sm7250/blob/9ea68e4dee77be15d37a9044ecae6754fb2ca454/drivers/soc/qcom/watchdog_v2.c#L49) |
| WDT0_BITE_TIME | `0x14` | Offset from watchdog base | [SM7250 watchdog_v2.c, commit `9ea68e4dee77be15d37a9044ecae6754fb2ca454`, line 50](https://github.com/LineageOS/android_kernel_oneplus_sm7250/blob/9ea68e4dee77be15d37a9044ecae6754fb2ca454/drivers/soc/qcom/watchdog_v2.c#L50) |
| Watchdog control values | RST `1`, EN `1` enable / `0` disable | Plain MMIO writes | [same pinned driver, lines 187-215](https://github.com/LineageOS/android_kernel_oneplus_sm7250/blob/9ea68e4dee77be15d37a9044ecae6754fb2ca454/drivers/soc/qcom/watchdog_v2.c#L187) |
| Watchdog counter | 20 bits (`0xfffff`) | Policy: accept S=1..26 so (S+5)*32768 fits | [same pinned driver, line 390](https://github.com/LineageOS/android_kernel_oneplus_sm7250/blob/9ea68e4dee77be15d37a9044ecae6754fb2ca454/drivers/soc/qcom/watchdog_v2.c#L390) |
| Watchdog tick conversion | `32768` ticks/s nominal, as task F requests | NOT a measured watchdog rate: Linux uses **32765** by default; nominal sleep counter is 32768 Hz (`avicii/lito.dtsi:1454-1457`). Timeout labels are nominal seconds. | [same pinned driver, lines 147-151](https://github.com/LineageOS/android_kernel_oneplus_sm7250/blob/9ea68e4dee77be15d37a9044ecae6754fb2ca454/drivers/soc/qcom/watchdog_v2.c#L147) |

0136 source file SHA256: `531285a9a9df68f5aa5ac1ba26aaa41f2a983985c9352419b55f8033c820d8a5`. Fajita 0211 uses EN +0x04 / BITE +0x24 at 0x17980000; those offsets are not used on lito.

## USB cold power-up (0140): pinned source ledger

All addresses below are lito addresses; register layouts come from the matching
vendor driver, checked against mainline. Source keys in the table expand to the
immutable URLs below. Vendor sources use commit `9ea68e4dee77be15d37a9044ecae6754fb2ca454`; mainline is Linux v6.12
commit `adc218676eef25575469234709c2d87185ca223a`; CLO msm-4.19 uses commit
`1f946a612986353e1484dbde8e7ed2eb6b0b456b`. The fetched GCC and USB DTS files are byte-identical
to `refs/lito-dts/gcc-lito.c` and `lito-usb.dtsi` (SHA256 `9ceaf56acd15e6e94cedad190ee5be9f60c56d59f2cc3a7bd57265974ca693ff`
and `9131ad628fcb1c22a3d141c8345a462d722b1c541983d632425876f22bc46760`).

- **GCC**: [gcc-lito.c](https://github.com/LineageOS/android_kernel_oneplus_sm7250/blob/9ea68e4dee77be15d37a9044ecae6754fb2ca454/drivers/clk/qcom/gcc-lito.c)
- **RCG**: [clk-rcg2.c](https://github.com/LineageOS/android_kernel_oneplus_sm7250/blob/9ea68e4dee77be15d37a9044ecae6754fb2ca454/drivers/clk/qcom/clk-rcg2.c)
- **F**: [clk-rcg.h](https://github.com/LineageOS/android_kernel_oneplus_sm7250/blob/9ea68e4dee77be15d37a9044ecae6754fb2ca454/drivers/clk/qcom/clk-rcg.h)
- **B**: [clk-branch.c](https://github.com/LineageOS/android_kernel_oneplus_sm7250/blob/9ea68e4dee77be15d37a9044ecae6754fb2ca454/drivers/clk/qcom/clk-branch.c)
- **RESET**: [reset.c](https://github.com/LineageOS/android_kernel_oneplus_sm7250/blob/9ea68e4dee77be15d37a9044ecae6754fb2ca454/drivers/clk/qcom/reset.c)
- **GDSC**: [gdsc-regulator.c](https://github.com/LineageOS/android_kernel_oneplus_sm7250/blob/9ea68e4dee77be15d37a9044ecae6754fb2ca454/drivers/clk/qcom/gdsc-regulator.c)
- **DT**: [lito-usb.dtsi](https://github.com/LineageOS/android_kernel_oneplus_sm7250/blob/9ea68e4dee77be15d37a9044ecae6754fb2ca454/arch/arm64/boot/dts/vendor/qcom/lito-usb.dtsi)
- **GD**: [lito-gdsc.dtsi](https://github.com/LineageOS/android_kernel_oneplus_sm7250/blob/9ea68e4dee77be15d37a9044ecae6754fb2ca454/arch/arm64/boot/dts/vendor/qcom/lito-gdsc.dtsi)
- **REG**: [lito-regulators.dtsi](https://github.com/LineageOS/android_kernel_oneplus_sm7250/blob/9ea68e4dee77be15d37a9044ecae6754fb2ca454/arch/arm64/boot/dts/vendor/qcom/lito-regulators.dtsi)
- **CLO**: [phy-msm-snps-hs.c](https://git.codelinaro.org/clo/la/kernel/msm-4.19/-/blob/1f946a612986353e1484dbde8e7ed2eb6b0b456b/drivers/usb/phy/phy-msm-snps-hs.c)
- **OP**: [phy-msm-snps-hs.c](https://github.com/LineageOS/android_kernel_oneplus_sm7250/blob/9ea68e4dee77be15d37a9044ecae6754fb2ca454/drivers/usb/phy/phy-msm-snps-hs.c)
- **ML**: [phy-qcom-snps-femto-v2.c](https://github.com/torvalds/linux/blob/adc218676eef25575469234709c2d87185ca223a/drivers/phy/qualcomm/phy-qcom-snps-femto-v2.c)
- **MSM**: [dwc3-msm.c](https://github.com/LineageOS/android_kernel_oneplus_sm7250/blob/9ea68e4dee77be15d37a9044ecae6754fb2ca454/drivers/usb/dwc3/dwc3-msm.c)
- **QCOM**: [dwc3-qcom.c](https://github.com/torvalds/linux/blob/adc218676eef25575469234709c2d87185ca223a/drivers/usb/dwc3/dwc3-qcom.c)
- **CORE**: [core.h](https://github.com/torvalds/linux/blob/adc218676eef25575469234709c2d87185ca223a/drivers/usb/dwc3/core.h)

| Register / request | Value used | Exact source |
|---|---|---|
| GCC mapping | `0x00100000`, prefix size `0x90000` | 0135 table above, `avicii/lito.dtsi:1662-1664` |
| USB GDSCR | GCC `+0xf004`; SW_COLLAPSE bit 0 clear, PWR_ON bit 31 set | GD:10-14; GDSC:29,35,289-319 |
| Master RCG | CMD `+0xf020`, CFG `+4`; source 1 = GPLL0 main, HID `2*4.5-1=8`, mode 0; CFG masked value `0x108` = 133333333 Hz | GCC:49-53,866-893; F:10; RCG:25-41,508-547 |
| Mock UTMI RCG | CMD `+0xf038`, CFG `+4`; source 0 = TCXO, HID `2*1-1=1`, mode 0; CFG masked value `0x001` = 19200000 Hz | GCC:49-53,815-818,896-912; F:10; RCG:25-41,508-547 |
| RCG update and field mask | CMD bit 0 (poll clear); CFG mask `0x10371f` = HID `[4:0]`, source `[10:8]`, mode `[13:12]`, HW control bit 20 | RCG:25-41,108-128,508-547; both lito RCGs hid_width=5 |
| USB30_PRIM BCR | GCC `+0xf000`, bit 0 assert 1 / release 0 | GCC:2606; RESET:32-57 (omitted map bit initializer = 0) |
| QUSB2PHY_PRIM BCR | GCC `+0x12000`, bit 0 assert 1 / release 0 | GCC:2601; RESET:32-57 |
| Six CBCRs | master `0xf010`, sleep `0xf018`, mock_utmi `0xf01c`, cfg `0xf07c`, aggre `0xf080`, clkref `0x8c010`; enable bit 0, CLK_OFF bit 31 | GCC:2302-2355,1062-1066,973-977; B:47-67; DT:29-36; 0135 table above |
| DWC3 mapping | `0x0a600000`; prefix `0xd000` covers globals/device registers | DT:6-9; CORE:99-160 |
| GSNPSID guard | `+0xc120`, mask `0xffff0000`, expected `0x55330000` | CORE:80-82,105,1246 |
| HS PHY mapping | `0x088e3000`, span `0x110` | DT:99-104 |
| EUD mapping / guard | `0x088e2000`, 4 bytes; nonzero => abort without writes | DT:102-105; CLO:346-349; OP:408-411 |
| Rail votes | L5 `ldoa5` 880 mV; L12 `ldoa12` 1800 mV; L2 `ldoa2` 3075 mV | DT:106-109; REG:119-123,172-176,331-335; existing patch 0113 uses exactly these requests via `sweet_rpmh_vreg_enable` |
| PHY CFG0 | `+0x94`, common override bit 1 set then clear | CLO:57-59,359-361,455-457; ML:60-62,417-419,464-466; OP:57-59 |
| PHY UTMI_CTRL5 | `+0x50`, POR bit 1 set then clear | CLO:34-35,363-364,449-450; ML:30-31,420-421,458-459 |
| PHY COMMON0 | `+0x54`, FSEL mask `0x70` clear to 0 (not unused FSEL_DEFAULT `0x30`) | CLO:37-40,366-367; ML:33-37,422-424 |
| PHY COMMON1 | `+0x58`, PLLBTUNE bit 5 and VBUSVLDEXTSEL0 bit 4 set | CLO:42-44,369-370,375-376; ML:39-41,425-427,430-432 |
| PHY CTRL1 | `+0x60`, VBUSVLDEXT0 bit 0 set | CLO:49-50,378-379; ML:46-47,433-435 |
| PHY tuning | `+0x6c=0x63`, `+0x70=0x85`, `+0x74=0x17`, full 32-bit writes (mask `0xffffffff`) | DT:116-118; CLO:70-73,381-384 and `hsusb_phy_write_seq`; ML:54-56 (offsets) |
| PHY COMMON2 | `+0x5c`, VREGBYPASS bit 0 set | CLO:46-47,439-440; ML:43-44,444-446 |
| PHY CTRL2 | `+0x64`, SUSPEND_N bit 2 and SUSPEND_N_SEL bit 3 set; clear bit 3 after POR | CLO:52-55,442-444,452-453; ML:49-52,448-450,461-462 |
| PHY UTMI_CTRL0 | `+0x3c`, SLEEPM bit 0 set | CLO:24-28,446-447; ML:20-24,452-453 |
| PHY REFCLK_CTRL (read only here) | `+0xa0`; definitions mask `3`, default `2` agree, init calls disagree, so no write | CLO:61-63,372-373; ML:64-66,428-429 and helper:169-180 |
| QSCRATCH mapping | DWC3 `+0xf8800` = `0x0a6f8800`; prefix `0x100` | DT:6-9; MSM:74-94 |
| QSCRATCH GENERAL_CFG | `+0x08`; bit 8 set, bits 0 and 3 set (`9`), bit 8 clear | MSM:75,87-90,2066-2085; QCOM:35-38,517-532 |
| QSCRATCH HS_PHY_CTRL | `+0x10`; VBUS valid bit 20 and session select bit 28 (`0x10100000`) set before ep0 | MSM:92-94; QCOM:30-33,119-131; existing 0073 override moved earlier in cold path |
| GUSB2PHYCFG | `+0xc200=0x2400`, full write; 8-bit UTMI, turnaround 9, ENBLSLPM/SUSPHY clear | CORE:137,299-312; hardware ABL values in `docs/STATUS.md` 0132 flash-boot entry, existing 0132 |

**Layout comparison and deliberately omitted steps.** CLO and OnePlus msm-4.19
match mainline for all PHY offsets used above. Mainline adds COMMON0 SIDDQ bit 2
and clears it during init (ML:34,455-456); neither downstream defines/uses it:
0140 omits that write and logs why. REFCLK definitions match, but mainline's
mask/value call is `(2,3)` while CLO/OnePlus use `(3,2)`. Per task instruction,
0140 leaves REFCLK untouched and logs its value. It does not silently select one.
No SS PHY/PIPE setup: USB2 uses QSCRATCH UTMI-as-PIPE, and the DT's six core
clocks are the only branches enabled by this new function. Rain's ahb2phy branch
has no counterpart sourced in gcc-lito.c and is omitted/logged. Existing 0135
behavior remains unchanged after this function returns.

No new GCTL overwrite: the existing 0132 device-mode/global-init sequence runs
later. No debugfs tuning overrides, RCAL fuse override, EUD disable, or new PLL/
CX voltage programming: the lito USB DT supplies only its three tune pairs and
rail requests; the task's sequence does not source additional per-device values.
EUD nonzero aborts as in CLO. A stuck GDSC/RCG/CBCR or failed RPMh vote aborts
before the PHY reset; a bad final GSNPSID prevents gadget start.

Timing values are bounded software waits, not new hardware constants: GDSC,
RCG and branch polls cap at 10 ms; BCR assert/release settle 100 us (CLO reset
uses 100..150 us); POR settles 10 us, final PHY settles 1 ms (rain template);
QSCRATCH settles 200 us, inside upstream's 100..1000 us range.
Rail requests preserve 0113 policy. L12 1800/L2 3075 mV are DT-range-valid
requests, **UNVERIFIED as exact vendor set points**, not a claim of voltage
readback. RPMh API returns status only, so rail lines report results instead of
inventing PMIC before/after values. All new configuration MMIO writes log
before/after readback. These changes have no hardware validation yet.

Fetched PHY SHA256: ML `b3ada16f3fce7e5600b063016dfe2e81f66d8f092d2051c01f392010a8868f92`;
CLO `0397d6a8986d7a4df4718bb0539a1518c11c3d7cb1931c428535f5d050059c3f`;
OnePlus `3a2bf09ef6e6965e054c9f7502503998fb77f82f7fa4475bc7e0e14efb7fe69c`.
