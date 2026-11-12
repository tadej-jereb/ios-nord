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
