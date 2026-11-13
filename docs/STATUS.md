# Status — 2026-11-13, first userland rung

Read `HANDOFF-CLAUDE-USERLAND.md`. The loader blindness, the jump and the boot chain are
closed; `docs/IMAGE_PROVENANCE.md` is the boot log of record for p1-p6. The wall is the empty
root volume: the kernel mounts it and panics on the missing `/sbin/launchd`. Populate the
image (`tooling/33b`, no sudo) and validate it (`tooling/34-check-bootstrap.sh`) before the
next boot.

# Status — 2026-11-11 (evening), host preparation

Bootloader unlock is planned for **2026-11-12**. Until then: no device writes, only host-side
preparation, reference harvest and the dump/backup tooling that runs the moment the phone is reachable.

## Decided

- Base tree: `dipa-studio/ios-sweet` (SM7150, ARMv8.2, 16K granules, native LSE/PAN).
  Rejected `ios-topaz` (ARMv8.0, needs LSE emulation + Gold-cluster hand-off).
- Reference port with the same bootloader family: `edi194/ios-fajita` (OnePlus 6T).
- Boot chain: header **v1** with `Image.gz-dtb`; `boot_a` carries experiments, `boot_b` keeps
  a bootable LineageOS + Magisk as fallback and as the dump/log host.
- iOS root: the existing `userdata` partition, HFS+ case-sensitive journaled, no GPT change.

## Root image: everything unprivileged is done (2026-11-12)

The 16 GiB volume `build/ios16-root.img` is fsck-clean, HFSX, journaled and empty;
its baseline sha256 is recorded in `build/ios16-root.img.sha256.pre-populate`.
Filling it is now a single root command, `tooling/33-populate-root.sh`.

- `tooling/32-build-apfsfuse.sh` builds apfs-fuse from a pinned commit into
  `tooling/opt/apfs-fuse` - unprivileged, re-runnable, verified with `--check`
  (mount + unmount of a real DMG, no loop device, no root).
- `tooling/33-populate-root.sh --dry-run` reaches the loop mount and stops:
  144 341 files / 11.30 GB measured through the DMG mounts, 68.5 % of the volume.
- Verified: apfs-fuse build and all three DMG mounts, image header/fsck/sha gate,
  `00-check-host.sh` exit 0, `31-mkiosroot.sh --phase-image` unaffected.
- Unverified: the `sudo` half (modprobe, loop mount, rsync, links, tweaks, fsck)
  - no sudo password on the build host. Transcript: `docs/ROOTFS_READY.md`.

## Proven on paper (cited in `avicii/CONSTANTS.md`)

SoC 0x190/0x1b8, MPIDR split, GIC 0x17a00000/0x17a60000 (same as sweet), timer virtual INTID 19
(same as sweet — Spacewar's 27 does not apply), UFS 0x1d84000/PHY 0x1d87000/ICE 0x1d90000,
TLMM 0xf000000, PS_HOLD 0xc264000, IMEM restart 0x146ab65c, apps RSC 0x18200000/TSC 0x18200d00,
splash 0xa0000000 +0x2300000, panel AMS644VK04 1080x2400 DSC **command mode**, TE gpio 10,
panel reset PM8150L GPIO3, FTS @0x49 / GT9886 @0x5D on qupv3_se7 with gpio 9/8, rails L13+S4,
WCN3990 icnss 0x18800000 + WLFW carve-out + IPA, SPMI arbiter 0xc440000.

## Open, and blocking the first boot

- Touch supplier (FTS vs Goodix) — live i2c read only.
- RAM ranges and the high bank — live FDT only.
- Whether `fastboot boot` accepts an unsigned recovery on this ABL revision (fajita precedent
  says yes, verify on the unit).
- Widevine L3, no SEP, no cellular — accepted for bring-up.

Resolved 2026-11-11 by the stock image: boot geometry and board DTB (header v2 / page 4096 /
kernel 0x8000 / ramdisk 0x1000000 / tags 0x100; board DTB from `dtbo.img` entry `board-id 8 0`,
`dtsi_no 0x5141`). Shim rebuilt against the real DTB and `--verify` PASSes at 356 KiB.
v2 is stock-accepted on this ABL, so v1 is a deliberate conservative choice, not a
requirement — see `docs/SHIM_BOOT.md`.

## Host tasks delivered (2026-11-11, all present in the repo)

| Task | Output |
|---|---|
| host deps + unprivileged toolchain | `tooling/00-host-deps.sh`, `tooling/10-user-toolchain.sh`, `tooling/env.sh`, `docs/TOOLCHAIN.md` |
| reference harvest | `refs/*`, `docs/REFS_INDEX.md` |
| iOS root image pipeline | `tooling/30-fetch-ipsw.sh`, `tooling/31-mkiosroot.sh`, `docs/IOSROOT.md` |
| shim/ADT/pack retarget | `avicii/shim/build.sh`, `avicii/tools/{extract-dtb.py,mkbootimg_v1.sh,mkadt_avicii.py}`, `docs/SHIM_BOOT.md` |
| constants + live dump | `avicii/CONSTANTS.md`, `avicii/tools/dump-live.sh` |
| recovery, backups, provenance | `docs/RECOVERY.md`, `tooling/4*.sh`, `docs/IMAGE_PROVENANCE.md` |
| WLAN map | `docs/WLAN_MAP.md`, `docs/WLAN_ORDER.md` |
| USB SMMU + FTS adapt notes | `docs/USB_SMMU.md`, `docs/FTS_TOUCH.md` |
| stock avicii image for header values | `src/los21-boot.img`, `src/dtbo.img` -> `src/avicii-board.dtb` |

## Tomorrow, in order

1. `bash tooling/00-host-deps.sh` (root), re-login, `source tooling/env.sh`.
2. Unlock: OEM toggle, `adb reboot bootloader`, `fastboot oem unlock`, confirm on device.
3. Flash LineageOS + Magisk to `boot_b`, boot it, then `tooling/40-backup-by-name.sh` + pull.
4. `avicii/tools/dump-live.sh` and fill every `UNVERIFIED` cell in `CONSTANTS.md`.
5. Only then the first diag shim on `boot_a`.
## Fixed after the first consolidation pass (2026-11-11 late)

- `mkadt_avicii.py` unpacked ADT props as 2-tuples; `adt.parse` yields `(name, flags, value)`.
  `/product` now lands in the ADT (63 props) and the no-`/product` warning is gone.
- `mkadt_avicii.py` looked for `d22ap.adt` under `avicii/build`; path is now `../../build/ipsx`
  (and `D22AP_ADT=` overrides).
- `mkpayload.py` only understood `LC_UNIXTHREAD`; `LC_MAIN` is now accepted too, and the
  `__TEXT` lookup skips `__PAGEZERO`.
- New `avicii/tools/im4p-adt.py`: unwraps the IPSW `DeviceTree.d22ap.im4p` (BER + LZFSE) into
  the ADT and validates `/product`. Needs `/usr/bin/python3` (the `lzfse` module lives there).
- Proven end to end with a synthetic Mach-O: `fdt-mem` -> `mkadt` -> `mkpayload` -> `build.sh`
  -> `--verify` PASS, image 417,792 B with a 62,912 B payload ramdisk. A real XNU kernel is
  still only obtainable from the macOS CI run.

---

# 2026-11-12, device day — unlock, LOS, root, backups

Bootloader is **unlocked** (`flash.locked=0`, `verifiedbootstate=orange`, `getvar unlocked: yes`).
LineageOS 21 + Magisk v31.1 is on slot **b**, root over adb. Nothing is bricked; `b` restores from
`backup/64f70df8/boot_b.img` in one command.

Verified today: 41 partitions dumped with size+md5 (`tooling/44-backup-stream.sh`), 83 live dump
files (`avicii/tools/dump-live.sh`), `logs/mem-live.json`, `avicii/adt/avicii-live.adt`.
`tooling/42-log-pull.sh` fixed to go through `su`. `mkbootimg.py` now accepts an empty `--dtb` for
v2, matching the stock image (`dtb_size=0`, tree from `dtbo`).

Plan changes, all verified, all recorded in `docs/SHIM_BOOT.md`:

- **Slot `a` is unusable as a test slot** (no system metadata) → experiments go to `boot_b`.
- **`fastboot boot` does not work** on this ABL (4/4 fallbacks, both header versions) → flash only.
- A fallback from a payload-less shim is the shim's own reset, not a rejection.
- **Touch is Goodix GT9886 @ 0x5D** (driver bound); FTS @ 0x49 unbound. FTS docs = fallback only.
- Panel is command-mode DSC and shows **no console text**; the UFS ring is the only observer, and
  it is empty because the crash precedes its init.

Blocker: the shim dies ~6 s in, before its first C statement (`for(;;) wfe`-only build also fails).
Bisect images `bisect-N` are being produced (N1 = header+park, MMU off → N5 = console clear).
Next: flash them in order with a restore between each.

Measurement and telemetry, independent of the packer: `docs/TIMING.md` +
`tooling/50-boot-timing.sh` decide refused-vs-died on a millisecond plateau with
the stock control, and `docs/TELEMETRY.md` + `avicii/shim/tel_*.c`
(`DIAG_STAGE=6/7/8`) leave evidence that survives a refusal (IMEM record, then
TLMM/SPMI, then the motor). Rebuilt images and their sha256: `out-telem/`.

Complementary line, 2026-11-12 late: `avicii/build/` holds a six-image controlled series (S1 stock
control, S2 footer-only, S3/S4 our packer at stock shape, S5/S6 park payload) that separates packer
shape from payload; flash order, expectations and the single fix per failure are in
`docs/PAYLOAD_ORDER.md`. Measured while building it: the stock image carries a **real dtb section**
(`dtb_size 406620` at `0x1f00000`, blob at `0x2bab000`), and our packer reproduces stock byte for
byte up to `original_image_size` except the sha1 `id`.

Second complementary line, 2026-11-12 late: `docs/HYBRID.md` + `avicii/shim/hybrid/` — 8
build-and-verify-checked images that start from byte-identical agreement with stock's first
page and localise the entry convention. Measured while building it: stock's `code0` branches
to **+0x2480000** (`imm26` counts words, so the earlier "+0x92000" reading was 4x short) and
stock's `os_version` `0x1c000185` is **14.0.0 / 2024-05**, not 12.0.0/2023-09.


---

# 2026-11-12 late — the ladder runs, and two doc claims are wrong

**`fastboot boot` works on this ABL.** The earlier "4/4 fallbacks, flash only" was not a `boot`
limitation: every one of those images carried a dtbo *overlay* in the dtb section and ABL refused
them ~6 s. With the stock SoC base tree in the section, `fastboot boot` sends 98 MiB in 2.2 s and
the code runs. The whole ladder ran this way, ~20 boots, nothing flashed, `boot_b` never touched.

Root cause of every refusal to date: `mkbootimg_v1.sh` defaulted `DTB_FILE` to
`src/avicii-board.dtb`, which is the dtbo overlay (620 fragments, no `qcom,msm-id`). ABL needs the
base tree: `src/avicii-soc.dtb`, 406620 B, `48b0902a…`, extracted from `src/los21-boot.img`
`0x2bab000`. `--verify` now fails on a missing `qcom,msm-id` or any `__overlay__`, and T1 vs stock
differs in `kernel_size`/`ramdisk_size` only — every other header field is stock's. Proven on
hardware: T1 (park at 0x80000) and L0 (park inside `shim_main`) both hold >200 s / >60 s with no
USB re-enumeration, where a refusal re-enumerates in ~6 s.

## Rungs 1, 2, 3, 5 green (ring reads)

| rung | result |
|---|---|
| 1 GIC | `pidr2=0x3b` arch nibble 3, `typer=0x7b041d`, gicv3 ok, itlines sane |
| 2 UFS | `version=0x300` (HCI 3.0), `cap=0x1587031f`, `hcs=0x10f` **DP set**, PHY answers (`+0x160=0x7f`, `+0x16c=0xa`) |
| 3 splash | base `0xa0000000`, size `0x2300000`, `region matches`, painted 97 ms, screen turns magenta off ABL scan-out |
| 5 memory | three extents as tabled, `dram reaches above 4 GiB`, `RESULT mismatch=00` |
| 4 SMP | all seven secondaries 0x100-0x700 released, `probe mask=0xfe` (each slot holds its own index) and, with the real entry, `ack mask=0xfe` with live spin counts — every core runs our code |

Rung 4 is closed (2026-11-12 23:31 / 23:37, `out-diag/l16` and `l17`). Two bugs in the shim, both
host-visible, and neither in PSCI:

1. The entry was built as `kimg_base + (sym - _start)`. `(uintptr_t)sym` is *already* a runtime
   address (`adr`/`adrp` under `-fno-pic`) and `kimg_base` is `_head`, not `_start`, so every
   release landed `0x80000` low in the zero padding before `.text` and took `udf #0` at its first
   fetch. PSCI returned 0 for all seven every time; the "release is fatal" signature was the caller
   wedging on the faulted core, not the core dying in our code. `out-diag/l6` had it right by
   accident (bare symbol) and its ack mask of 0 was the second bug.
2. The ack mask was read before `sec_stop = 1`, while `diag_secondary()` stores `sec_spin[]` only
   after its loop exits — a perfect release still printed `mask=0`.

`CurrentEL` at the caller is `0x4` (EL1), so the EL2-vector hypothesis is dead: PSCI starts a
secondary at the caller's EL, and the EL1 `vbar_el1` install in `sec_stub` was correct all along.
stage4 now refuses to release if the entry is outside `[_start, _bss_start)`.

## Four bugs the ladder found in the shim, all fixed

1. `dlog_init` returned 5 when the header read-back mismatched — the read-back lies on this medium
   while Linux reads the same block fine. Now a warning (`dlog_warn()`, panel `LOG warn rc=`).
2. `GICD_PIDR2` was `0xfe8` (4 KiB-frame offset) in a 64 KiB frame, which is RAZ — now `0xffe8`.
3. `HCI_VERSION`/`HCI_CAP` were swapped vs UFSHCI (CAP 0x00, VER 0x08, as `ufs.c` has it) and the
   version test compared a major/minor-packed VER against 0x10000.
4. `park()`'s deadline was `60 * freq` with `freq` in ticks/ms → every "60 s" park was 58 ms; now
   `60000 * freq`, measured 60 s. `smc` never resets at EL2, `hvc` does — reset is HVC-then-SMC.

Console: `FB_STRIDE` was 4800 B for a 1080-px row (4320 B), shearing every scanline 120 px. Fixed
and confirmed on the panel with a bar ruler (`ruler stride=0x10e0`, bars straight, glyphs resolve).

## Next

**The ladder is green; the next rung is the XNU payload on this shape** (`fastboot boot`, nothing
flashed, `boot_b` untouched), then the iOS root in `userdata`. Stage-4 images `l16`/`l17` stay in
`out-diag/` as the SMP reference: `l17` (`ack mask=0xfe`, real entry) is the one to reuse when the
shim has to bring secondaries up for real.

Notes for whoever continues: after a ring write LineageOS usually lands in **recovery**, where adbd
is root without `su` (pull with `adb exec-out dd`, skip `size/4096-1025`), but it landed on **Android
with Magisk** twice tonight — `adb devices` answers `unauthorized` there until `ADB_VENDOR_KEYS` is
exported, then `su -c` is root and the same `dd` goes through `adb exec-out "su -c '…'"`. Do not
assume the recovery. `park()` needs the power button only if the HVC reset itself fails.
