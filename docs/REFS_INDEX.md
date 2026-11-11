# REFS_INDEX — reference forks for OnePlus Nord (`avicii`, SM7250/lito)

Built 2026-11-11 for patch-by-patch porting work. All clones are shallow (`--depth 1`), read-only,
nothing built or run. Every path below was `ls`/`grep -n`-checked in the local clone at the commit
recorded in the repo table; paths that could not be checked are marked **[UNVERIFIED]**.

Portability tags used in the tables — pick the class before you cherry-pick:

| tag | meaning |
|---|---|
| **A-copy** | applies to avicii unchanged, or only behind an ADT/boot-arg gate |
| **B-addr** | logic transfers, but MMIO base / GPIO / SID / IRQ / rail name must be re-read from avicii's own DT |
| **C-template** | SoC-specific (different IP generation or bus); read for method, do not apply |

avicii ground truth used for the B-addr deltas (all in this workspace):
`refs/lito-dts/lito-usb.dtsi:6` `ssusb@a600000`, `:11` `iommus = <&apps_smmu 0xE0 0x0>`;
`refs/lito-dts/msm-arm-smmu-lito.dtsi:71` `apps-smmu@15000000` (base 0x15000000, same as spacewar's);
`refs/lito-dts/lito-qupv3.dtsi:370` `qupv3_se7_i2c: i2c@984000`;
`avicii/mtp.dtsi:345-363` `st_fts@49`, irq `<&tlmm 9 0x2008>`, reset `<&tlmm 8 0x00>`,
rails `pm8150_s4` (vdd) / `pm8150_l13` (avdd), `st,x-flip/y-flip = <1>`;
`avicii/panel.dtsi:13` `dsi_samsung_ams644vk04_dsc_cmd`.

## Repo table

| local clone | URL | device / SoC | state | HEAD |
|---|---|---|---|---|
| `refs/anonbeat1-ios-sweet` | https://github.com/anonbeat1/ios-sweet | Nothing Phone (1) `spacewar`, **SM7325P/yupik** — lito's direct sibling | **best USB+SMMU reference**; USB CDC-ECM enumerated on a Mac, logging to the host | `6da72f8` |
| `refs/rrrd-jpg-ios-sweet` | https://github.com/rrrd-jpg/ios-sweet | Pixel 4a `sunfish`, SM7150 | **best ST-FTS touch reference**; FTS protocol at I2C 0x49 written from the sunfish fts_touch driver | `08cd985` |
| `refs/PalanBanana-ios-sweet` | https://github.com/PalanBanana/ios-sweet | sweet, SM7150 | WCN3990 wifi skeleton (dormant, no QRTR) + a618 GPU skeleton | clone only |
| `refs/marnov999-raphael-ios-gpu` | https://github.com/marnov999/raphael-ios-gpu | Mi 9T Pro `raphael`, SM8150 | **deepest published a6xx GMU/HFI ladder** (0105→0151), Adreno 640 | clone only |
| `refs/marnov999-ios26-sweet` | https://github.com/marnov999/ios26-sweet | davinci/raphael, iOS 26 | successor tree; userland/tools, thin xnu patch dir | clone only |
| `refs/dipa-studio-ios-sweet` | https://github.com/dipa-studio/ios-sweet | sweet, SM7150 (upstream base) | base tree: shim, tools, ADT generator, 0075-0081 | `45263be` |
| `refs/edi194-ios-fajita` | https://github.com/edi194/ios-fajita | OnePlus 6T `fajita`, SDM845 | other OnePlus port: whole a6xx GMU ladder as patches 0099-0214, PORTING.md | `6592de8` |
| `refs/MakrSas-ios-topaz` | https://github.com/MakrSas/ios-topaz | Redmi Note 12 4G `topaz`, SM6225 | ARMv8.0 sibling: FT5452 touch, modem PAS ladder, Mac-free-ish CI | `347e190` |
| `refs/ry-diffusion-Bergamota` | https://github.com/ry-diffusion/Bergamota | Poco F1 `beryllium`, SDM845, iOS 18 | a630 GPU bring-up patches + 5 GPU design docs + Chlorophyll host | `2fd0dfb` |
| `refs/ry-diffusion-Chlorophyll` | https://github.com/ry-diffusion/Chlorophyll | Metal/AIR→NIR over freedreno | userspace Metal driver; kernel-side only for the ABI | clone only |
| `refs/kusesad-1122-hackios-dodge` | https://github.com/kusesad-1122/hackios-dodge | OnePlus 13 `dodge`, SM8750, iOS 26 | **per-phone SoC layer** (`soc/hakios_soc.c`) + DT-vs-code checkers | `3e02049` |
| `refs/2010475745xie-ios16-xnu-bringup` | https://github.com/2010475745xie/ios16-xnu-bringup | host-side only (no phone) | **Mac-free build**: WSL2 + Actions recipe, rootfs build, QEMU harness | `c29934d` |

Stray dirs already in `refs/`, not clones of their own: `refs/pb` (a bare `.git` of the same
PalanBanana repo), and the extracted-patch/scratch dirs `refs/anonbeat1/patches`, `refs/bergamota`,
`refs/ios-sweet`, `refs/palanbanana`, `refs/topaz-patches`, `refs/upstream`, `refs/lito-dts`
(lito DT split, used as ground truth above).

Not cloned — requested names no longer resolve (all HTTP 404, verified 2026-11-11):

| requested | status | closest live substitute |
|---|---|---|
| `ibraguslan/ios-sweet` | **deleted** (account has only the profile repo) | content survives only as the survey text below **[UNVERIFIED]**; for a618 take `PalanBanana 0082`, for a630 take `Bergamota 0103` |
| `marnov999/ios-sweet` | **renamed/split** into `raphael-ios-gpu` + `davinci-ios-gpu` (private) + `ios26-sweet` | `marnov999-raphael-ios-gpu` cloned; the survey's "0083 v1..v19" numbering predates the rename — current equivalents are 0105/0106/0143 |
| `dips-studio/ios-extra` (also `dipa-studio/ios-extra`) | **404**, the org repo list has no `ios-extra` | survey text below only **[UNVERIFIED]** |

## anonbeat1/ios-sweet — SM7325 USB net + apps_smmu (highest value)

Same lito/yupik family as avicii: GCC 0x100000 with GDSC `usb30_prim` at offset 0xf004, DWC3 at
0xa600000, **apps_smmu at 0x15000000**, USB stream ID **0xe0** — all four match avicii's DT
(`refs/lito-dts/lito-usb.dtsi:6,11`, `msm-arm-smmu-lito.dtsi:71`). The board deltas are passed in
through an ADT node `/sweet-usb`, not hardcoded.

| file | what it is | tag |
|---|---|---|
| `xnu/patches/0091-sweet-spacewar-usb-net-smmu.patch` (403 lines) | adds `bsd/dev/sweet_smmu.c`: builds one translating stage-1 context bank with a 1 GiB-block identity map of DRAM 0x80000000..0x27fffffff and **repoints the SMR that the bootloader already installed for the SID** (a second matching SMR = stream-match conflict = SoC reset); parameterises `sweet_usb.c` via `/sweet-usb` (gdscr-off, master-off, cfgnoc-off, smmu-sid 0xe0, no-qusb2) and raises GCC_SIZE 0x90000→0x1f0000 | **B-addr** (SID/base identical to lito; only `/sweet-usb` node values must come from avicii's ADT, GCC map size must cover 0x1f0000) |
| `bsd/dev/sweet_smmu.c` (created by 0091, lines 40-160) | `sweet_smmu_map_sid()` — CBAR `1<<16|0xf<<12|3<<8`, CBA2R VA64, TCR `25|1<<23`, TCR2 `7<<15|2`, MAIR0 0x44, TTBR0 → L1 table | **B-addr** (base 0x15000000 already correct) |
| `bsd/dev/sweet_rpmh.c` hunk in 0091 / `xnu/patches/0087-sweet-ufs-vcc-rpmh-vote.patch` | RPMh vreg vote by rail *name* from ADT; 0087 is the ldob7 UFS-VCC vote that unblocked UFS on spacewar | **C-template** (avicii's rails are pm8150_s4 / pm8150_l13, names differ) |
| `xnu/patches/0084-sweet-ufs-unit-attention-retries.patch` | autosense key/ASC/ASCQ decode, retry TUR 50×50 ms on UNIT ATTENTION / NOT READY | **A-copy** |
| `xnu/patches/0085-sweet-ufs-start-stop-unit.patch` | on sense 2/04/02 sends START STOP UNIT (power condition ACTIVE) before TUR, as `ufshcd_set_dev_pwr_mode` | **A-copy** |
| `xnu/patches/0086-sweet-ufs-timeout-diagnostics-dma32.patch` | prints IS/HCS/DBR/OCS/UPIU + DMA PA on timeout, `ufsdma32=1` forces DMA below 4 GiB | **A-copy** (UFS 0x1d84000 identical) |
| `xnu/patches/0094-sweet-usblog-from-boot.patch` | usblog streams the whole console ring from boot instead of the last 64 KiB | **A-copy** |
| `xnu/patches/0096-sweet-usblog-wait-for-host.patch` | holds the gadget until an ARP/IPv4 frame from 192.168.7.1 arrives (`host_seen`) | **A-copy** |
| `xnu/patches/0089-sweet-spacewar-fts-spi-touch.patch` | `bsd/dev/sweet_fts_spi.c` — full FTS bring-up over **GPI/SPI** (SE13, GPII 0, SMMU cb for SIDs 0x56/0x43, FT3680 boot-id + FW ECC load) | **C-template** (avicii touch is I2C, not GPI/SPI) |
| `shim/ft_fw.S`, `shim/touchprobe.c`, `shim/build-spacewar.sh` | FTS firmware blob included in the shim; standalone host-side touch probe | **C-template** |
| `tools/mkadt.py` (`--spacewar`, line 5-6; `SPACEWAR_USB` dict line 62) | the ADT profile shape to copy for `--avicii`: RAM/fb/vtimer, UFS VCC rail, `/sweet-usb` node | **C-template** (values all differ: avicii DRAM/fb/vtimer/rails) |

Read `NOTES.md:371-420` before touching USB: it is the honest failure log (read-past-GCC abort,
absolute-vs-offset GDSC, the 4th CBCR external abort, and the SMR-reuse fix).

## rrrd-jpg/ios-sweet — ST FTS touch on I2C 0x49 (highest value for input)

0080-0084 are the power/diagnostic ladder (SPMI PM6150 GPIO4 driving the touch switch, GENI
doorbell tracing); 0085 is the driver. Note the base tree `bsd/dev/sweet_touch.c` already carries a
`TOUCH_FTS` protocol skeleton and `shim/gen_font.py`-style GPIO helpers.

| file | what it is | tag |
|---|---|---|
| `xnu/patches/0085-pixel-fts-driver.patch` (114 lines) | `touch_px_run()`: reset via GPIO8, wait for the 0x03 controller-ready event, scan-mode write `a0 00 <mask>`, then a read loop of 0x0f/0x01 events decoded into `touch_report()` HID touches | **B-addr** (protocol A-copy; avicii IRQ is GPIO9, switch/rail is pm8150_s4+l13 instead of the PM6150 GPIO4 switch, and `TOUCH_SE_PA` must move 0xa84000→0x984000: `refs/rrrd-jpg-ios-sweet/xnu/patches/0060-sweet-keys-touch-drivers.patch:244` vs `refs/lito-dts/lito-qupv3.dtsi:370`) |
| `xnu/patches/0080-pixel-touch-probe.patch` | read-only probe: GPI/PMIC register dumps, no writes — safe first boot on avicii | **B-addr** (only the GPIO list changes) |
| `xnu/patches/0081-pixel-touch-power.patch` | drives PM6150 GPIO4 through the SPMI channel at 0xc600000, 32 KiB stride per APID | **C-template** (avicii rails are RPMh LDOs, not a PMIC GPIO switch) |
| `xnu/patches/0082-pixel-touch-trace.patch` | per-step prints + channel-status read around the GENI doorbell | **A-copy** (diagnostics only) |
| `xnu/patches/0083-pixel-touch-trace2.patch` | narrows the trace after the first steps passed | **A-copy** |
| `xnu/patches/0084-pixel-gpio4-channel.patch` | fixes the channel address to `0x10000 * apid` (spmi-pmic-arb v5 layout) | **C-template** |
| `xnu/patches/0087-pixel-edge-bottom.patch`, `0088-pixel-fb-scale.patch` | edge-coordinate mapping and fb scaling at 1080x2400 | **A-copy** (avicii is 1080x2400 as well) |

## PalanBanana/ios-sweet — WCN3990 wifi

| file | what it is | tag |
|---|---|---|
| `xnu/patches/0083-sweet-wifi-wcn3990.patch` (258 lines) | `iokit/Kernel/arm/SweetWifi.{h,cpp}` + `files.arm64` anchor: WCN3990 modelled as pwrseq → QMI/wlfw → SNOC membase/CE, with ath10k `snoc.c`/`qmi.c` line citations; **skeleton — maps the SNOC block only**, refuses to start because XNU has no QRTR | **C-template** (SNOC at 0x18800000 matches avicii, but nothing powers the rail until QRTR exists) |
| `xnu/patches/0082-sweet-gpu-adreno618.patch` (316 lines) | `SweetGPU.h/.cpp` a6xx skeleton, register offsets cross-checked against Mesa `a6xx.xml` / `msm_gpu.h`; `loadZapFirmware` always fails | **C-template** (same a6xx class as Adreno 620, useful offset table, no GMU boot) |
| `NOTES.md:5,21,29` | build/anchor state, `files.arm64` line-22 anchor confirmation | context |

## marnov999/raphael-ios-gpu — a6xx GMU/HFI (a640, deepest ladder)

Sequential single-idea patches, each a measured register finding. Bootstrap order they converged on
is in `0106`'s header comment; the later series (0108-0151) adds CP rings, KGSL/DRM shims, pool and
vsync work. For avicii (Adreno 620) treat the *order* as the valuable part, not the constants.

| file | what it is | tag |
|---|---|---|
| `xnu/patches/0105-raphael-gpu-a640-probe.patch` (364 lines) | adds `bsd/dev/sweet_gpu.c` + `bsd/conf/files` hook: MMIO map, GCC/GDSC reads, chip-id — probe only | **B-addr** (GPU/GX/GMU bases and GCC offsets are raphael's) |
| `xnu/patches/0106-raphael-gpu-a640-gmu-boot.patch` (895 lines) | the GMU cold boot: CX GDSC + GMU clocks, GMU memory in an SMMU stage-1 CB, `GMU_RPMH_CTRL = 0xf11` (`:58,:108,:850`), HFI queues + `BOOT_SLUMBER` OOB ack bit, `a6xx_start` core init (UCHE/NC_MODE/protect/64-bit), CP ring | **C-template** (a640 constants; BOOT_SLUMBER bit differs a618 vs a640 — do not copy blind) |
| `xnu/patches/0108-raphael-gpu-step-log-sync.patch`, `0109-raphael-gpu-a640-command-processor.patch`, `0110-raphael-gpu-a640-shader-tests.patch`, `0113-raphael-gpu-kgsl-drm.patch` | step-synchronised log, CP submission, shader test vectors, KGSL/DRM shim | **C-template** |
| `xnu/patches/0143-raphael-gmu-ddr-vote.patch` (56 lines) | HFI BW/DDR vote tables that make the GMU keep GX up | **C-template** |
| `xnu/patches/0115-raphael-usb-smmu-stream.patch`, `0121-raphael-usb-rings.patch`, `0122-...-uncached-trbs.patch`, `0127-raphael-usb-recover-bus-reset.patch` | their USB/SMMU stream + ring work — second opinion next to anonbeat1's `sweet_smmu.c` | **B-addr** |
| `xnu/patches/0112-davinci-display-surfaces-panel.patch`, `0117-0119-...pool*`/`...contiguous`, `0120-raphael-mdp-smmu-scanout.patch`, `0124-0126-...surface*` | surface pool sizing, contiguous allocation, MDP scanout with SMMU, scanout of real layers — closest thing to avicii's DSC command-mode panel path | **B-addr** |
| `xnu/patches/0111-davinci-kernel-deltas.patch` | the **davinci a618** delta set folded in (conf/files, sched_dualq, amfi, sleh) — closest a-number to avicii | **B-addr** |
| `NOTES.md`, `AGENTS.md`, `CREDITS.md` | per-boot GMU findings | context |

## dipa-studio/ios-sweet — upstream base tree (shim + tools + ADT generator)

| path | what it is | tag |
|---|---|---|
| `tools/mkadt.py` (250 lines) | Apple Device Tree generator: RAM 0xb0000000+0x4d000000, panic-log carve from the top of DRAM (see `--highmem`, `PANIC_LOG_SIZE`), `/sweet-rpmh` cmd-db, no spacewar profile | **B-addr** (structure A-copy, every address avicii-specific) |
| `tools/adt.py` (128 lines) | ADT writer library (`node()`, `ph()`, `u32`, `cstr`) used by mkadt | **A-copy** |
| `tools/mkpayload.py`, `tools/xnu-cc.py`, `tools/check-exports.py` (and `tools/mkbootimg_v3.py`, anonbeat1 only) | payload packer, boot image builder, kernel-config generator, export checker | **A-copy** |
| `tools/sweet-log.py`, `tools/sweet-usbnet.sh`, `tools/sweet-log-pull.sh` | host side of the usblog path (UDP :5140, 192.168.7.0/24) | **A-copy** |
| `shim/loader.c`, `shim/mmu.c`, `shim/fdt.c`, `shim/ufs.c`, `shim/console.c`, `shim/shim.c`, `shim/build.sh` | the bare-metal pre-kernel shim (ELF loader, MMU, FDT, UFS reader, framebuffer console) | **B-addr** (no UDC in shim; fb/UFS bases and CPU PSCI shape are avicii's) |
| `docs/QEMU_TESTING.md`, `AGENTS.md`, `NOTES.md` | QEMU harness notes, agent rules, the master porting log | context |

`refs/anonbeat1-ios-sweet/{shim,tools}` is the same tree plus
`refs/anonbeat1-ios-sweet/shim/ft_fw.S`, `refs/anonbeat1-ios-sweet/shim/touchprobe.c`,
`refs/anonbeat1-ios-sweet/shim/build-spacewar.sh`, `--spacewar` support in
`refs/anonbeat1-ios-sweet/tools/adt.py` and `refs/anonbeat1-ios-sweet/tools/mkbootimg_v3.py` —
that is the newer base, and the one to diff from.

## ry-diffusion/Bergamota + Chlorophyll — GPU method and ABI

| path | what it is | tag |
|---|---|---|
| `xnu/patches/0103-beryllium-gpu-a630-bringup.patch` | `sweet_a630.c` stages 1-7 + `sweet_a630_pas.c` TZ-PAS zap loader, hooked from `sweet_ufs.c`, plus a 64-bit `pmap_sync_page_attributes_phys` fix | **C-template** |
| `docs/GPU_A630_BRINGUP.md` (128 lines) | stage list and boot-arg gating (`sweetgpu=N`) around that patch | **C-template** |
| `docs/GPU_KERNEL.md` (276 lines) | stage 8: keep-alive + msm-style IOKit user client, xnu-11215 0180-0182 | **C-template** |
| `docs/GPU_PHASE0_DISCOVERY.md` (137 lines) | what Metal actually requires of the kernel, from the 20H392 dyld cache (static only) | **C-template** (ABI list is SoC-neutral, useful) |
| `docs/GPU_RESEARCH.md` (109 lines), `docs/METAL_ADRENO630.md` (419 lines) | prior art, evidence-tagged `[V]/[I]/[M]`, Metal design | **C-template** |
| `docs/GPU_EAGL.md` (382 lines) | OpenGLES.framework replacement over Mesa | **C-template** |
| `gpu/kernel-test/{sweetgpu.c,adreno_uc_test.c,build.sh}` | host-side GMU/UC test harness | **C-template** |
| Chlorophyll `air/`, `src/bgmtl.m`, `patches/*.patch` (9), `docs/FIXES.md`, `README.md:1-10` | AIR-bitcode→NIR frontend, `MTLDevice` shim, Mesa patches, injected renderer; needs the kernel BO/`IOSurface` ABI only | **C-template** (userspace, Adreno 630 ir3) |

## kusesad-1122/hackios-dodge — per-phone SoC layer

| path | what it is | tag |
|---|---|---|
| `soc/hakios_soc.c` (230 lines) + `soc/hakios_soc.h` (69) | the one place that knows which phone it is: reads `/arm-io` `device_type` in a `__startup_func` and exports that phone's MMIO windows, replacing per-driver `static bool dada` boot-args | **C-template** — but the *pattern* is what avicii needs instead of a 90th `sweet*=` boot-arg |
| `README.md:26-40` | the reasoning (two phones, one SoC, ADSP window size is the only disagreement) | context |
| `check-soc.py`, `check-dodge.py`, `check-adsp-block.py`, `check-kernel-dodge.py` | assertions that code addresses match the phone's own DT — 23/27 checks, run before every build | **C-template** (rewrite for lito; the idea is directly reusable) |
| `soc/` wiring: `kernel/xnu-12377.121.6-dodge.patch` | first converted driver (`redwood_adsp.c`) and the loader `device_type` write (`base/xnuloader/loader.c:4151`) | **C-template** |

## 2010475745xie/ios16-xnu-bringup — Mac-free build

| path | what it is | tag |
|---|---|---|
| `docs/03-kernel.md` | fork + enable Actions + dispatch: builds XNU on `macos-14` GitHub runners, ~8 min, no local Mac | **A-copy** (process; needs the fork, not the code) |
| `docs/01-environment.md`, `scripts/setup-wsl.sh`, `scripts/wsl-go.sh`, `scripts/wsl-check.sh` | Windows 11 + WSL2 host bring-up | **A-copy** |
| `docs/02-rootfs.md`, `scripts/prep-iosroot.py`, `scripts/finish-iosroot.sh`, `scripts/verify-dmgs.sh` | root filesystem build on HFS+ from your own IPSW | **A-copy** |
| `docs/04-qemu.md` | QEMU harness for kernel changes before hardware | **A-copy** |
| `docs/05-pitfalls.md` | the traps that cost hours | **A-copy** |
| `patches/mkadt-panic-region.diff` | the `/pram` panic-log carve as a patch on `tools/mkadt.py` (the break it documents: kernel hangs after `kdp_core zlib memory` without it) | **A-copy** |
| `scripts/check-hunk-counts.py` | per-patch hunk-count assert, useful as a pre-apply gate | **A-copy** |
| `analysis/porting-landscape.md` | 2026-10-21 snapshot of the port family and its splits | context |

There is no `.github/` in the clone (verified `ls -a`); the workflow lives in the upstream fork only.

## Survey context (from `docs/BERGAMOTA-FORKS-SURVEY.md`)

Copied here because it is the only surviving record of the two dead repos:

- **USB (§A1, `BERGAMOTA-FORKS-SURVEY.md:6-14`)**: spacewar is "the only confirmed hardware success
  on a USB3-capable Qualcomm DWC3". The plain upstream gadget sequence works there — **no PIPE clock
  or PHY touching needed on SM7325**; the only functional additions are the `/sweet-usb` board
  params and the SMMU CB. Measured: DWC3 GSNPSID `0x5533330a` (v3.30a), HS PHY is `snps-femto` at
  0x88e3000, GDSC/clocks left ON by ABL. Uptime result: enumerates as `en7` on a Mac, `ping
  192.168.7.2` 0.9-2.7 ms. The fix commits are `437941ceb` (GCC map), `99ddd1117` (read only
  cross-SoC CBCRs), `1035e53d5` (**reuse the ABL SMR** — the actual fix).
- **SMMU restart hazard**: the first DMA of the ep0 SETUP TRB reset the SoC, because the hypervisor
  turns an SMMU global fault into a reset. avicii has the same hypervisor behaviour and its USB SID
  0xe0 is behind `apps_smmu` — expect it at the first STARTTRANSFER, not at the register commands.
- **ibraguslan/ios-sweet (§C, `:65`) — [UNVERIFIED, repo gone]**: nabu (Xiaomi Pad 5, SM8150,
  Adreno 640). `xnu/patches/0085-nabu-adreno-gpu-and-alpha-blend.patch` (~47 KB,
  `bsd/dev/nabu_adreno.c`) is described as a full GMU bring-up (HFI GX power domain, SMMU, CP + 2D
  blit, TZ SCM PIL PAS 13, then `CP_SET_SECURE_MODE(0)`); SSMUU fixes `fc85e1bf5`, `1f1ea7d09`,
  `09f1cc750`, TZ fix `3022cca21`. Commits `fb713b63b`, `970606050`. Also `0081-sweet-hfs-no-hotfiles`
  (`05c6e7778`) — disables HFS hotfile recording, worth taking if you mount a macOS-built HFSX root,
  and `0082-sweet-fb-scale-to-panel` (`8fa43c38c`).
- **dipa-studio/ios-extra (§C, `:64`) — [UNVERIFIED, repo gone]**: upstream's A618 GPU sandbox
  (patches 0080-0098). HANDOFF.md says GMU CM3 was never released and GX never powered; it proved
  RSC wake/stop and AO IRQ masks. Docs `docs/GPU_GMU_BOOT.md`, `GPU_POWER_SEQUENCE.md`, `GPU_LOG.md`;
  last commit seen `edab65c99`.
- **marnov999 "0083 v1..v19"** (`:66`) — the numbering from the old fork name. Register findings
  worth grepping for in `0106`: BOOT_SLUMBER OOB ack bit (a618 bit23 vs legacy bit30),
  `RPMH_CTRL=0xF11` (GFX_VOTE_ENABLE), `GX_VOTE_IDX=2` (MIN_SVS) as the real ARC vote.
- **edi194/ios-fajita (§A5, `:50`)**: no USB driver at all — console is the framebuffer. Its value
  is the GMU ladder (`0123-0130` stage 3/4 + `0131-0214`), which is why `0125-fajita-gpu-smmu-impl`
  and `0130-fajita-gpu-stage4` matter more than its USB.

## Notes / porting / agent files, by repo (read before editing)

- `refs/anonbeat1-ios-sweet/NOTES.md` (largest, per-boot log; USB section starts `:371`), `AGENTS.md`
- `refs/rrrd-jpg-ios-sweet/NOTES.md` (`:18-23` touch chain), `AGENTS.md`
- `refs/PalanBanana-ios-sweet/NOTES.md`, `ROADMAP.md`, `AGENTS.md`, `CI-PRECHECK.md`, `CI-TRIGGER.md`, `CI-FAILURE-PLAYBOOK.md`
- `refs/marnov999-raphael-ios-gpu/NOTES.md`, `AGENTS.md`, `CREDITS.md`; `refs/marnov999-ios26-sweet/README.md`
- `refs/dipa-studio-ios-sweet/NOTES.md`, `AGENTS.md`, `docs/QEMU_TESTING.md`
- `refs/edi194-ios-fajita/{PORTING.md, NOTES-FAJITA.md, NOTES.md, AGENTS.md}`, `docs/fajita-touch-rmi4-spec.md`
- `refs/MakrSas-ios-topaz/{NOTES.md, RECOVERY.md, CREDITS.md, AGENTS.md}`
- `refs/ry-diffusion-Bergamota/{NOTES.md, AGENTS.md}`, `docs/HANDOFF-2026-10-25.md`, `docs/STATIC_REVIEW.md`, `docs/TOPAZ_MERGE.md`, `docs/FORKS_SURVEY.md`
- `refs/ry-diffusion-Chlorophyll/README.md`, `docs/FIXES.md`, `NOTICE.md`
- `refs/kusesad-1122-hackios-dodge/README.md`
- `refs/2010475745xie-ios16-xnu-bringup/{README.md, docs/05-pitfalls.md, analysis/porting-landscape.md}`
- also in the workspace: `docs/anonbeat1-NOTES.md` (278 KB dump of the above NOTES),
  `docs/BERGAMOTA-FORKS-SURVEY.md`, `docs/fajita-PORTING.md`

## Paths that are *not* files in any clone (so they are not 404s)

Cited bare names that only exist **inside a patch's diff** and appear in the tree once that patch is
applied — never hunt for them with `ls`: `bsd/dev/sweet_smmu.c` (0091), `bsd/dev/sweet_fts_spi.c`
(0089), `bsd/dev/sweet_gpu.c` (0105), `bsd/dev/sweet_a630.c` + `sweet_a630_pas.c` (0103),
`iokit/Kernel/arm/SweetWifi.{h,cpp}` (0083), `iokit/Kernel/arm/SweetGPU.{h,cpp}` (0082), and the
patched-in-tree files `bsd/dev/sweet_touch.c`, `sweet_usb.c`, `sweet_ufs.c`, `sweet_rpmh.c`,
`bsd/conf/files`.

Cited but only reachable through the *dead* repos: `xnu/patches/0085-nabu-adreno-gpu-and-alpha-blend.patch`,
`bsd/dev/nabu_adreno.c`, `docs/GPU_GMU_BOOT.md`, `GPU_POWER_SEQUENCE.md`, `GPU_LOG.md`.
Cited but outside the clones: `snoc.c` / `qmi.c` / `msm_gpu.h` (upstream Linux/Mesa sources the patches
quote), `redwood_adsp.c` and `base/xnuloader/loader.c` (dodge's un-cloned base tree — see the
`[UNVERIFIED]` note).

## Verification log

Checked with `ls`/`grep -n` at the recorded HEAD: every repo directory, every `xnu/patches` filename
above, `shim/*` and `tools/*` listings for both base trees, all doc paths, and the avicii/lito DT
anchors at the top of this file. Cross-SoC address claims (SMMU 0x15000000, USB SID 0xe0, GCC GDSC
0xf004) are checked against `refs/lito-dts/*`, not against avicii's live DT — re-read
`avicii/avicii.dtsi`/`lito.dtsi` before flashing.

**[UNVERIFIED]**: everything under the ibraguslan and ios-extra bullets (repos 404 at clone time);
the claim that dodge's `soc/` layer wiring exists as described (only the 230-line `soc/hakios_soc.c`
and one `kernel/` patch were grep-confirmed, the loader line 4151 was not opened); marnov's
"0083 v1..v19" as *patch files* (only the renumbered 0105/0106/0143 exist in the live clone); nothing
in this index was compiled or booted.
