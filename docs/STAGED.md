# Staged images and their provenance (2026-11-12)

Every file below is in `src/` (git-ignored, never committed). All LineageOS hashes are
compared against the archive.org item metadata for `lineageos_202408`, the TWRP hash
against TeamWin's published `.sha256`. Nothing here was flashed yet.

| File | Size | md5 / sha256 | Verified against | Status |
|---|---|---|---|---|
| `lineage-21.0-20240619-nightly-avicii-signed.zip` | 1,267,027,843 | `d986dd472a680735cd60710cc2c0a169` | archive.org metadata, exact | READY (installs to inactive slot) |
| `recovery.img` (same build) | 100,663,296 | `4a51f2f2a8ad0200af21aca785973627` | archive.org metadata, exact | READY (`fastboot boot` for sideload) |
| `twrp.img` | 47,124,480 | sha256 `cd84e2eca353858304cf37f703542ad3a274bd950367e22020c674533d242076` | TeamWin `.sha256` | READY (log pulls, not for flashing the ROM) |
| `Magisk-v31.1.apk` | 10,679,283 | — (upstream release asset) | `unzip -l` ok | READY |
| `los21-boot.img` (reference) | 100,663,296 | `3a437aa4f34808a63056d4c0f19710af` | archive.org metadata, exact | reference only |
| `dtbo.img` | 25,165,824 | `1a12260da239c8f6570d7af7aff7d2df` | archive.org metadata, exact | source of `avicii-board.dtb` |
| `vbmeta.img` | 8,192 | `4e23c5d415e0c2dc08154f5718f109ac` | archive.org metadata, exact | fallback only |
| `super_empty.img` | 4,952 | `4f04786aab38aa912ce0604432bdfb40` | archive.org metadata, exact | fallback only |
| `avicii-board.dtb` | 337,226 | — | extracted from `dtbo.img` entry `board-id 8 0` | used by the shim build |

`unzip -t` on the ROM zip: no errors.

## Not yet verified

- Whether `fastboot boot` of `recovery.img` (or `twrp.img`) actually starts on this unit.
  That is the gate before anything is written.
- Whether the installed firmware is at or above the LineageOS floor (OOS 12). Check
  `adb shell getprop ro.build.version.release` first.

## Order

1. Gates: `verifiedbootstate`, firmware version, `getvar unlocked`, `current-slot`,
   `fastboot boot src/twrp.img` shows TWRP.
2. ROM to the inactive slot: `fastboot boot src/recovery.img` -> `adb sideload` the zip.
3. Boot it, then Magisk on the same active boot partition, then `adb shell su -c id`.
4. `tooling/40-backup-by-name.sh` + `41-backup-pull.sh`, then `avicii/tools/dump-live.sh`.
5. `boot_a` stays untouched until the first shim image exists.
