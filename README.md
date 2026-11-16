# ios-avicii — iOS 16 on the OnePlus Nord

This project runs Apple's open-source XNU kernel (xnu-8796.141.3) with the **unmodified iOS 16.7.16
iPhone X userland** on a OnePlus Nord (`avicii`, Snapdragon SM7250/lito, Adreno 620).

**State (2026-11-15):**
- The phone boots iOS from its own flash (`boot_a`).
- It shows the full UI with touch and keys.
- The UI is composited on the **GPU** through Mesa freedreno: 38–48 fps while scrolling.
- SSH over USB works when the phone is started with `fastboot boot`. On a boot from flash it does
  not work yet: patch 0132 fixes it but is untested.

Experimental, security-off bring-up: the iOS root lives on `userdata`.

## If you are an agent, read in this order

1. **`AGENTS.md`**: the hard rules (partitions you never touch, gates before writes, where
   experiments go).
2. **`docs/NEXT-2026-11-16.md`**: where the last session stopped, the exact next commands, the
   undo steps, and a map of the GPU stack. **Start work here.**
3. **`docs/STATUS.md`**: the log of record, newest entry first. Each wall hit is named with its log.
4. **`avicii/CONSTANTS.md`**: every hardware constant, each with its device-tree citation. Never use
   a number that isn't in it.
5. **`docs/IMAGE_PROVENANCE.md`**: sha256 of every image that ran or was flashed, plus the
   restore procedure.

Then read whatever the task needs. The map below says which docs are current and which are history.

## How a boot is built

```
xnu-avicii/series + patches/NNNN-*.patch   kernel patches on xnu-8796.141.3 (127 entries)
        │  push to branch kern-NNNN on remote "fork" → GitHub Actions (.github/workflows/xnu.yml)
        ▼
avicii/shim/out/kernel-NNNN/               kernel.development.sweet (downloaded CI artifact)
        │  tooling/71-phone-image.sh --preset usb --kernel … --extra "sweetgpu=11 sweetgles=1"
        ▼
build/phone/ufsroot.<name>.img             boot image: shim + kernel + ADT + firmware payload
        │  --boot → `fastboot boot` (RAM only)   or   `fastboot flash boot_a` (needs the owner's OK)
        ▼
phone: iOS root on userdata, SSH at root@192.168.7.2 over USB Ethernet (host 192.168.7.1)
```

The per-patch workflow, the SSH command and the reboot and log-pull commands are in
`docs/NEXT-2026-11-16.md`. Kernel logs come from the on-disk ring:
`tooling/70-phone-boot.sh --pull --out DIR`, with the phone in recovery and adb on.

## Repository layout

| Path | What it is |
|---|---|
| `AGENTS.md` | rules for working on the port |
| `xnu-avicii/` | **the kernel**: `series`, `patches/` (0001–0132), `tools/preflight.sh` (applies the series to `~/xnu-8796.141.3`; `--dry` to check) |
| `avicii/` | board support: `CONSTANTS.md`; `shim/` (the boot shim the bootloader starts; kernels are downloaded into `shim/out/`); `tools/` (ADT generator, `mkpayload.py`, `mkbootimg`); device-tree sources |
| `tooling/` | numbered host scripts: `0x` host setup, `3x` build/populate the iOS root image, `4x` backups and log pulls, `6x` QEMU, `7x` phone images and boot |
| `tooling/gpu/` | **GPU userland**: `mksysroot.sh` (+ `sysroot-fixups.sh`): iOS SDK-less sysroot; `mesa-patches/` + `mesa-build.sh`: Mesa 25.0.7 for iOS; `sweeteagl/`: EAGL shim; `sweetgles/`: the `SweetGLES.bundle` that iOS loads; `drmtest/`, `osmesatest/`: GPU tests |
| `docs/` | notes, research, provenance (map below) |
| `docs/gpu-research/`, `docs/perf-research/` | research reports (QuartzCore, EAGL ABI, Mesa on Darwin, DDR, thermal, …) |
| `docs/history/` | superseded handoffs, research prompts, old progress notes (kept as evidence) |
| `refs/` | read-only clones of other ports and vendor sources. **Never commit into them.** `docs/REFS_INDEX.md` says which holds what |
| `logs/` (not in git) | every boot and test log; `logs/phone/<date>-<name>/` per run |
| `build/` (not in git) | root images, boot images, `build/gpu/` (sysroot, Mesa trees), `build/phone/` |
| `backup/` (not in git) | full partition backup of the phone (`backup/64f70df8/`), the restore source |
| `src/` (not in git) | downloaded stock images, GPU firmware (`src/gpu-fw`) |

## Docs map

**Current, read when relevant:**

| Topic | Doc |
|---|---|
| Next steps, GPU stack | `NEXT-2026-11-16.md` |
| Log of record | `STATUS.md` |
| Image hashes, restore | `IMAGE_PROVENANCE.md` |
| Recovery | `RECOVERY.md` |
| Boot image rules | `SHIM_BOOT.md` (header v1, slot behaviour) |
| GPU compositing | `gpu-research/README.md` (rounds 1–4; why `'b3a8'`, `CAEnableDeepFramebuffer`) |
| Performance | `perf-research/README.md` |
| Touch | `GOODIX_GT9886.md` |
| USB networking and SMMU | `USB_SMMU.md` |
| iOS root image | `IOSROOT.md`, `ROOTFS_READY.md`, `CACHE_TRIM.md` (dyld cache rules) |
| launchd and AMFI | `LAUNCHD_BOOTSTRAP.md`, `AMFI_LAUNCHD.md` |
| Kernel CI | `KERNEL_CI.md` |
| Toolchain | `TOOLCHAIN.md` |
| QEMU | `QEMU_AVICII.md` |
| Reference ports | `REFS_INDEX.md`, `fajita-PORTING.md` (the OnePlus 6T port of the same tree), `anonbeat1-NOTES.md` |

**History** (how earlier walls were solved; don't take current facts from them):
`ABL_FORENSICS.md`, `BISECT.md`, `TIMING.md`, `TELEMETRY.md`, `DIAG.md`, `HYBRID.md`,
`PAYLOAD_ORDER.md`, `RAMDISK_ROOT.md`, `POPULATE-ROUTE-FUSE.md`, `ROOTRW-REVIEW.md`, `UFS_WRITE_AUDIT.md`,
`PHONE_TEST.md`, `BERGAMOTA-FORKS-SURVEY.md`, `FTS_TOUCH.md`, `WLAN_MAP.md`, `WLAN_ORDER.md`,
`docs/history/*`.

## Facts that cost a day each

1. **`fastboot boot` works** and is the normal test path. Some old notes say otherwise; they're wrong.
2. **Slot `a` boots from flash.** `boot_b` holds LineageOS and is never written by iOS work.
3. **backboardd runs as `mobile`.** Anything it must write goes in `/private/var/tmp`.
4. **QuartzCore ends each frame with `glFlush` only.** The shim must wait for the GPU there,
   because the kernel's panel copy has no GPU fence.
5. **IOSurface seeds don't change on CPU writes** (lock and unlock never enter the kernel). Import
   surfaces zero-copy; don't copy them.
6. **Never release the boot loader's DDR vote.** Memory drops to 370 MiB/s.
7. **Host `192.168.7.1` drops after every USB re-enumeration.** Re-add it with
   `ip addr replace 192.168.7.1/24 dev enx02005e77ee01`.
