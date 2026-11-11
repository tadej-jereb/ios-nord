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
| IMEM restart reason | `0x146ab65c` (`0x146ab000` + `0x65c`) | 4 bytes; write `'b'`-style magic here for "boot to recovery"-class reasons | `lito.dtsi:718,728-730` |
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

## 4. Touch — **supplier-dependent, unresolved**

avicii shipped with two different touch controllers on the same bus, same
IRQ GPIO, same reset GPIO. Both nodes are present and both are `status = "ok"`;
which one is populated depends on the supplier/list. **Do not hardcode one.**

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
| Board DTB source | `dtbo.img`, single-entry big-endian `dt_table`: 337,226 B at `0x40`, `board-id <8 0>`, `oplus,dtsi_no 0x5141`, `pcb_range <0 0x37>` | extracted to `src/avicii-board.dtb`; `model = "Lito MTP 20801"`, `compatible = "qcom,lito-mtp"`; a **fragment overlay**, so no `/memory` in it | `src/dtbo.img` header + entry |
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
2. **Touch controller identity** — `0x49` (ST) vs `0x5D` (Goodix), `§4`. Wrong
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
