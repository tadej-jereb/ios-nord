# xnu-avicii — series handoff

Derived series for the OnePlus Nord (`avicii`). Consumer of the series:
`.github/workflows/xnu.yml`; user steps: `docs/KERNEL_CI.md`.

Base: `refs/dipa-studio-ios-sweet/xnu/patches` (SM7150 / Kryo 470, the decided
base tree) plus the OnePlus-6T additions at
`refs/edi194-ios-fajita/xnu/patches` that the fajita port proves and that carry
no board number. Nothing under `refs/` is modified; `tools/make-series.py`
re-derives everything here from those two trees and is the reason the copies are
reproducible rather than hand-edited.

## Contract

* `series` is the only order. One entry per line: `apply <file>` (a patch) or
  `copy <file>` (a stage script — `dxb` runs `patches/*.sh` before any patch,
  and the workflow runs them in series order, from the xnu root).
* Plain files in `patches/`, zero-padded numeric prefixes: glob order equals
  series order, which the workflow re-checks.
* Hunk counts are recounted after every rewrite. `git apply` trusts declared
  counts and drops trailing body lines when a count is short, so
  `tools/check-hunk-counts.py` runs as the first CI step and the first step of
  `tools/preflight.sh`.
* The ADT / live-FDT dram path is preserved end to end: `osfmk/arm/arm_init.c`
  still reads `dram-base` and `dram-size` from `/chosen` (patch 0016), and
  `avicii/tools/mkadt_avicii.py` writes those two properties from
  `logs/mem-live.json`. No patch adds a static `reg` for memory — the memory
  node is a placeholder on this device.

## Carried verbatim (76 files)

| patches | why nothing changed |
|---|---|
| `0001` – `0003` | no board constant anywhere in the diff |
| `0005` – `0009` | no board constant anywhere in the diff |
| `0011` | no board constant anywhere in the diff |
| `0013` – `0017` | no board constant anywhere in the diff |
| `0019` – `0037` | no board constant anywhere in the diff |
| `0039` – `0059` | no board constant anywhere in the diff |
| `0061` | no board constant anywhere in the diff |
| `0064` – `0081` | no board constant anywhere in the diff |

Notes on individual verbatim files worth knowing:

* `0003` (framebuffer serial console) builds its geometry from the ADT node
  `/sweet-fbcon`, so it carries no address. The node name stays `sweet-fbcon`
  because `mkadt_avicii.py` publishes that exact name.
* `0004` was **adapted**, not dropped — see below; the Kryo 475 numbers it needs
  (8 CPUs, `MAX_CPU_CLUSTERS 1`, timer INTID 19, 64-byte cache lines,
  `armv8.2-a+crypto`, no PAC) were already in it.
* `0017` pins `SWEET_VTIMER_INTID 19`, which the ADT parser then overrides from
  `virtual-timer-intid`; avicii's PPI 11 → INTID 19 is the same as sweet's, so
  the default and the ADT agree.
* `0046` needs `disp0` in the ADT (`canvas-width 1080`, `canvas-height 2400`);
  `mkadt_avicii.py` already emits it.
* `0061` presents the 1125×2436 iPhone X display over the 1080×2400 panel —
  identical geometry on both boards, so no number changes.
* `0065`/`0078` are the SMP pair; 0078 accepts `phys_id <= 0x700`, i.e. exactly
  avicii's 0x600 gold / 0x700 prime cores, and clamps `cpus=` at 8.

| patch | tree | note |
|---|---|---|
| `0083-fajita-console-only.patch` | fajita | `sweetfb_console=1` freezes the GUI copy so the kernel console stays visible |
| `0085-fajita-sync-console.patch` | fajita | `sweetecon=1` synchronous console; stops the ring from blocking the printer |
| `0094-fajita-panic-log.patch` | fajita | panic always reaches the panel and the log ring is flushed to UFS before reset |

## Adapted (10 files)

| patch | what changed |
|---|---|
| `0004-sweet-machine-config.patch` | header comment Redmi/SM7150/Kryo 470 → avicii/SM7250/Kryo 475. |
| `0010-sweet-early-framebuffer-debug.patch` | `0x9c000000` → `0xa0000000` (start.s band paint, start.s bootstrap block TTE, `EARLY_FB`); header comment; `2368 * 4320` and `EARLY_STRIDE` 4320 kept as sweet had them - nothing pads an ABL row, the earlier 4800 sheared every scanline by 120 px. |
| `0012-sweet-keep-debug-console-after-ttbr0.patch` | `0x9c000000` → `0xa0000000` (final VA=PA block TTE, `early_fb`); `EARLY_STRIDE` kept at 4320; quotes 0010's header comment. |
| `0018-sweet-boot-cpu-driver.patch` | `IONameMatch` `qcom,kryo470` → `qcom,kryo475`. |
| `0038-sweet-applekeystore.patch` | `qcom,kryo470` → `qcom,kryo475` (context line). |
| `0060-sweet-keys-touch-drivers.patch` | touch: `TOUCH_SE_PA` 0xa84000 → 0x984000 (lito qupv3_se7 = i2c4), `TOUCH_NORTH_PA` 0x3900000 → 0xf000000 (lito TLMM is one flat window), `TOUCH_RCG` 0x18148 → 0x18140, `TOUCH_GCC_VOTE` 0x5200c → 0x52008 (gcc-lito wrap1 S1), chip id `'9','8','9','6'` → `'9','8','8','6'`. keys: one `KEYS_GPIO_RT 0xc110` block becomes `KEYS_VOLUP_RT 0xc510` (PM8150L SID 4 gpio5) + `KEYS_VOLDN_RT 0xc310` (PM7250B SID 2 gpio3); PPIDs 0x4c1 / 0x4b1 (UNVERIFIED, printed at probe). Unchanged: `0x5d`, IRQ gpio 9, reset gpio 8, PON PPID 0x008, PON RT 0x0810. |
| `0062-sweet-touch-power-battery.patch` | RPMh: `RH_RSC_PA` 0x18220000 → 0x18200000, `RH_TCS_PA` 0x18220d00 → 0x18200d00 (CONSTANTS §5), `RH_DICT_PA` 0x0c3f000c → 0x80860000 (live FDT `qcom,cmd-db`), `ldoc11`/3200 mV → `ldo13`/3008 mV (CONSTANTS §4), `L11C` text → `L13`. |
| `0063-sweet-goodix-geni-packing.patch` | chip-id compare and identity comments; keeps the 16-bit register packing GT9886 needs (`register-is-16bit`). |
| `0084-fajita-panel-console.patch` | `0x9d400000` → `0xa0000000`. |
| `0086-fajita-cpu-match.patch` | `qcom,kryo385` / `qcom,kryo470` → `qcom,kryo475` on both sides; `FAJITA:` → `AVICII:`. |

Splash geometry, reasoned rather than copied: fajita paints at `0x9d400000`, 20
MiB into a 32 MiB block at `0x9c000000`. avicii's splash starts at a fresh
32 MiB-aligned `0xa0000000` (`cont_splash_region`, 35 MiB, fenced by
`dfps_data_region` at `0xa2300000`), so the +20 MiB arithmetic does not carry
over and the block base is used directly. The early band paint and the final
alias both land inside the first 32 MiB of the region, which is where the panel
buffer lives.

## Dropped, with reason

Four classes, and what each one means here:

1. **Xiaomi ABL header v4** — no patch in either series packs a header; that is
   the shim's job (`avicii/tools/mkbootimg_v1.sh`, header **v1** +
   `Image.gz-dtb`). Only numbers *derived* from the Xiaomi ABL hand-off were
   rewritten: 0010/0012/0084 (splash base), i.e. nothing was dropped for this
   class. 0010's assumption "all bring-up RAM is below 4 GB" holds on avicii:
   the live FDT's low bank ends at `0xbba00000` and the next bank starts at
   `0x180000000`.
2. **ARMv8.0 LSE emulation** — nothing to drop: sweet is native LSE/PAN on
   ARMv8.2, which is exactly why it was chosen over topaz. `LDXR/STXR`
   single-copy atomics and `LDAPR` stay as they are; the topaz
   emulation/hand-off patches are not in this tree at all.
3. **Gold-only SMP** — nothing to drop: 0065 (PSCI `CPU_ON`) and 0078 (8 cores,
   `phys_id <= 0x700`) already treat all eight cores as one homogeneous
   cluster. The A76s run plain, without a P/E split, which is documented in
   0078's own comment.
4. **FTS touch** — dropped `0090-fajita-touch-rmi4`, `0095-touch-bisect`,
   `0096-touch-tlmm-east`, `0097-touch-xfer`, `0098-touch-rmi2`: those are the
   Synaptics RMI4 driver and its bisect trail. The unit runs Goodix GT9886
   (`CONSTANTS §4`, live `4-005d` has the driver symlink, `4-0049` has none), so
   0060/0062/0063 keep the Goodix path. `0x38`/`0x49` remain in the probe as
   the FTS fallback read.

Dropped for staging, not incompatibility — re-add from the fajita tree when the
stage comes up:

| fajita patches | reason |
|---|---|
| `0087` empty-ioacceleratores, `0088` sweetsurface-client-memory | GUI: accelerator nubs and client memory, needs the display/GPU stage |
| `0089` keys-probe, `0091` keys, `0092` rpmh-ldoa28, `0093` rpmh-bases | PM8998/PM6150L of that board; superseded by adapted 0060/0062 |
| `0099` – `0210` (all `fajita-gpu-*`, `adreno-*`, `metal-*`, `arena-*`, `ib-*`, `cp-*`) | no GPU work in this stage; 112 patches of bisect trail |
| `0198` – `0206`, `0211` | USB power, reboot reason, log status block/head snapshot, APSS watchdog: they build on `sweet_reboot.c`, introduced by 0199/0201 |
| `0207` – `0210` | nested-IB and fence-timeout diagnostics, only meaningful with the GPU path |

## Verified / unverified

**Verified on 2026-11-12 (host, real tool output):**

* all 89 series entries apply in order to a pristine `xnu-8796.141.3` checkout —
  `tools/preflight.sh` PASS, and again PASS in `--dry` (applies, then resets);
* `tools/check-hunk-counts.py` clean over all 86 patch files;
* every one of the 76 verbatim files is byte-identical to its `refs/` source
  (`sha256`, checked with the manifest);
* the two build-host preconditions the workflow pins are real: macOS 13.5 maps
  to `xnu-8796.141.3` in Apple's `macos-135` release.json (not 8796.101.5), and
  the headers are fetched by the stage scripts from immutable commits.

**Unverified — hardware settles these:**

* `EARLY_STRIDE` 4320 (`0010`/`0012`) — matches `FB_STRIDE` in
  `mkadt_avicii.py` and the ADT node, so all three move together. 4320 =
  panel width * 4 with no padding: the shim console proved it on the panel
  (4800 sheared every scanline by 120 px, 4320 rasterises pixel-exact);
* keys PPIDs 0x4c1 (PM8150L gpio5) and 0x4b1 (PM7250B gpio3) and the derived
  block offsets — no PMIC datasheet on hand; the driver logs every APID it
  resolves, so one boot settles it. Keys are non-blocking: `sweetkeys=0`;
* `0062`'s rail name `ldo13` and the `0x80860000` cmd-db address are cited but
  the RPMh enable vote itself has never been exercised on this PMIC family;
* GT9886 register semantics (product-id at `0x4022`, 16-bit packing) — the
  protocol is Goodix's, but the chip is not the one sweet ran. `sweettouch=0`
  keeps it out of the first boot;
* nothing in this series has been compiled yet: the first compile is the first
  CI run (`docs/KERNEL_CI.md`).

## Regenerating / provenance

    python3 xnu-avicii/tools/make-series.py          # rewrite patches/ + series
    python3 xnu-avicii/tools/make-series.py --check  # fail if disk drifted

Every rewrite asserts its expected occurrence count, so an upstream change to a
source patch fails loudly instead of silently adapting the wrong line. `SHA256SUMS`
records the current bytes of `series` and `patches/`.

Source trees were read at their current tips:
`refs/dipa-studio-ios-sweet` @ `45263be` (81 patches, 3 stage scripts) and
`refs/edi194-ios-fajita` @ its `patches` tip (214 patches, of which 5 are here).
