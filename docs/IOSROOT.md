# iOS root image (`userdata`) — build pipeline

Target: OnePlus Nord (avicii, SM7250) running XNU with an iPhone X iOS 16.7.16
(20H392) userland. The iOS root lives in `userdata` as a journaled,
case-sensitive HFS+ volume, created here on Linux and flashed from here.

Reference implementation: `dipa-studio/ios-sweet` `tools/mkiosroot.sh` +
`tools/sweet-root-tweaks.py` (read, quoted, and made portable/size-guarded
here). Note: that repo has **no** `tools/install-files-into-image.sh` or
`tools/install-tree-into-image.sh` — verified against the GitHub tree API, the
tree lists only `mkiosroot.sh`, `sweet-root-tweaks.py`, `remotezip.py`,
`mkinit.py`, `mkadt.py`, … Population is plain `rsync` inside `mkiosroot.sh`.

Everything below is a literal command, in order. Steps 0–8 need no device.

## Status on this host

| # | Stage | State |
|---|-------|-------|
| 0 | host check | **verified** (`tooling/00-check-host.sh`; exit 1 today for `apfs-fuse` and the unloaded `hfsplus` module, `fastboot` present in `tooling/opt/platform-tools`) |
| 1 | IPSW member enumeration (range requests) | **verified** (91 members listed from the pinned IPSW) |
| 2 | BuildManifest identity → member mapping | **verified** (`OS`, `Cryptex1,SystemOS`, `Cryptex1,AppOS`) |
| 3 | member fetch + size/CRC verify | **verified** — all 4 members fetched (5,830,956,212 B over the wire) and CRC-32-matched against the IPSW's own central directory, and again by an independent checker |
| 4 | sparse volume + `mkfs.hfsplus` (HFSX, journaled) | **verified** at 1 GiB and at the real 16 GiB size from the real payload; `fsck.hfsplus -n` clean, header `HX`, 114 MiB on disk of 16 GiB |
| 5 | `apfs-fuse` mounts (three DMGs) | **unverified** — binary not installed on this host |
| 6 | HFS+ loop mount + `rsync` populate | **unverified** — needs root + the `hfsplus` module loaded |
| 7 | dyld cache / cryptex links / log dirs / keybag | **unverified** — same reason (logic is a 1:1 port of upstream) |
| 8 | `fsck.hfsplus -fy` + re-check | **verified** on empty volumes (fy exit 0, following `-n` clean); unverified with real content |
| 9 | raw → Android sparse `.simg` | **verified**, byte-identical round trip (`sparse.py decode` + `compare`) |
| 10 | `fastboot flash userdata` + first boot | **unverified** — no phone |

## Requirements (run as yourself, one command per line)

Step 0 installs the distro side (hfsprogs, kmod/loop, fuse3, platform-tools)
and makes `hfsplus` load at boot — run it once, it is idempotent and checks
every package name up front:

```
sudo tooling/00-host-deps.sh
```

`apfs-fuse` is the one thing no distro packages (noble has none; verified: no
`apt-cache policy` entry, no search hit). Build it once:

```
git clone https://github.com/sgan81/apfs-fuse ~/apfs-fuse
cd ~/apfs-fuse
git submodule update --init
cmake -B build
cmake --build build -j 32
sudo cmake --install build
sudo modprobe hfsplus
```

`fastboot` lives in `tooling/opt/platform-tools`; job scripts get it from
`PATH` when you source `tooling/env.sh` first:

```
. tooling/env.sh
```

`sudo` is used by this pipeline only for `apfs-fuse`, the loop mount, the
`rsync`/`install` calls inside the image, and `fsck -fy` — never by you by
hand before step 5.

## 0. Host gate

```
tooling/00-check-host.sh
```

## 1. Fetch the IPSW members

Inputs — exactly four members of the one IPSW, pinned by name, size, CRC-32:

| Member | Role | Bytes (uncompressed) | CRC-32 |
|---|---|---|---|
| `087-86698-044.dmg` | `OS` — the OS root volume | 4,730,814,044 | `66ccd39f` |
| `087-86593-047.dmg` | `Cryptex1,SystemOS` | 2,743,074,816 | `7f8fabcd` |
| `087-86715-047.dmg` | `Cryptex1,AppOS` | 10,485,760 | `ed284220` |
| `Firmware/all_flash/DeviceTree.d22ap.im4p` | D22AP device tree (for `mkadt.py`) | 33,719 | `a9657430` |

Pinned IPSW (iPhone10,3 / iPhone X, 16.7.16, 20H392):

```
https://updates.cdn-apple.com/2025FallFCS/fullrestores/122-77006/1158E502-D76D-4226-AA06-ED5E30CD1111/iPhone10,3,iPhone10,6_16.7.16_20H392_Restore.ipsw
```

Whole-file `sha256 ece1194f7e233e9109c5790a8d23a4564a10a254e15ec5b09978a343265568fb`,
6,171,035,648 bytes (`api.ipsw.me/v4/device/iPhone10,3`, verified).

`OS.dmg`/`SystemOS.dmg`/`AppOS.dmg` are *not* member names in the IPSW: the
members are hash-named and only `BuildManifest.plist` maps them
(`BuildIdentities[0].Manifest.{OS,Cryptex1,SystemOS,Cryptex1,AppOS}.Info.Path`).
Fetch members by HTTP range, never the whole IPSW:

```
tooling/30-fetch-ipsw.sh
```

`tools/remotezip.py` (upstream) reads the zip64 central directory, streams the
member in 64 MiB ranges, resumes `.part` files and checks the zip CRC-32 before
renaming. The wrapper re-checks size and CRC independently, skips members that
already match, deletes a corrupt same-size file before retrying, and writes
`build/ipsw-x/FETCH-MANIFEST.txt`. Device tree only (34 KiB):

```
tooling/30-fetch-ipsw.sh --device-tree
```

## 2. Build the image (unprivileged phase, then root phase)

```
tooling/31-mkiosroot.sh --phase-image build/ipsw-x build/ios16-root.img 16G
```

Creates a sparse 16 GiB file, runs `mkfs.hfsplus -N` as a dry run, then
`mkfs.hfsplus -s -J -b 4096 -c b=1024 -v iOSRoot`, then `fsck.hfsplus -n` and
asserts the volume-header signature is `4858` (`HX` = HFSX) with the journaled
attribute bit set. Flag meanings, verified from `mkfs.hfsplus -h` and the
`newfs_hfs(8)` man page on this host:

| Flag | Meaning | Why |
|---|---|---|
| `-v iOSRoot` | volume name | cosmetic, matches upstream |
| `-J` | create a journal (default size 8192k here) | XNU replays it after a panic; boot args allow `rootrw`/`ufsrw` |
| `-s` | case-sensitive → HFSX (`0x4858`), version 5 | iOS paths differ by case |
| `-c b=1024` | *clump* size for the allocation bitmap, in allocation blocks (4 MiB) | bitmap of 4,194,304 blocks is 512 KiB; clumping avoids an extent grow on a full volume |
| `-b 4096` | allocation block size (already the default) | explicit for reproducibility |

`-c` is **not** case-sensitivity (that is `-s`) and takes a clump list
(`a= b= c= d= e= r=`), not a boolean — verified: `-c b=1024` moved
`initial allocation file size` from 32 KiB to 4 MiB in the `-N` output.

Full build (re-executes itself under `sudo`; needs `apfs-fuse`):

```
tooling/31-mkiosroot.sh build/ipsw-x build/ios16-root.img 16G
```

The image phase already ran against the real payload on this host, so
`build/ios16-root.img` exists (empty, `HX`, 114 MiB allocated). Finish that
volume instead of creating a new one — as root there is no re-exec, and
`RESUME=1` re-proves size and header instead of re-`mkfs`:

```
sudo env RESUME=1 tooling/31-mkiosroot.sh build/ipsw-x build/ios16-root.img 16G
```

What the root phase does, in upstream order:

1. `apfs-fuse` on the three DMGs (`os`, `sysos`, `appos` symlinked as `*.dmg`
   because apfs-fuse only parses UDIF when the name ends in `.dmg`), as root so
   the root `rsync` can read the FUSE mounts.
2. `mount -t hfsplus -o loop,force` the new image on a temp dir.
3. `rsync -aH --numeric-ids` `os/root` → `/`, `sysos/root` →
   `/private/preboot/Cryptexes/OS`, `appos/root` → `/private/preboot/Cryptexes/App`.
   On a device `/private/preboot` is a separate volume; here the cryptexes live
   inside the one volume.
4. **dyld cache**: hard-link every file of the SystemOS shared cache into
   `/System/Library/Caches/com.apple.dyld` — `ignition_level=1` makes dyld look
   there, and hard links cost no space.
5. **Cryptex fallback links**: dyld does not search the cryptexes at ignition
   level 1, so every cryptex file without an OS-root counterpart
   (`libobjc-trampolines`, `libffi-trampolines`, `libstdc++`, …) is hard-linked
   to its plain root path. Symlinks are copied (`cp -P`), because Linux hfsplus
   cannot hard-link them.
6. **log directories**: `/private/var/db/{diagnostics,uuidtext}`, owner/group
   `_logd` (272), modes 0751/0755, plus `diagnostics/timesync` and a `.migrated`
   marker in each — otherwise libtrace aborts with
   `BUG IN LIBTRACE: Failed to migrate directory`.
7. **keybag**: `/private/var/keybags/systembag.kb`, mode 0600 root:root, a
   plain XML plist with `KeyBagKeys` = `U1dFRVQ=` for the built-in
   AppleKeyStore (no passcode).
8. **tweaks**: `tools/sweet-root-tweaks.py` (pinned sha256
   `d604e9fd…d56398`) — `_PanicOnCrash`→`_PanicOnCrasX`, CommCenter jobs
   removed, container dirs, DataMigration marker, VirtualAudio/MediaToolbox
   fixes, SpringBoard watchdogs off, Setup skipped, activation ark seeded.
9. `df`, `umount`, `fsck.hfsplus -f -y` (rewrites the non-ASCII names Linux
   decomposes differently), then a clean `fsck.hfsplus -f -n`.

## 3. Convert to a flashable sparse image

The builder does this itself; separately:

```
python3 tooling/sparse.py encode build/ios16-root.img build/ios16-root.img.simg
python3 tooling/sparse.py info build/ios16-root.img.simg
```

## 4. Size budget

| Quantity | Bytes |
|---|---|
| Payload (three DMGs, uncompressed on the volume) | 7,484,374,620 |
| Volume size (`SIZE`) | 17,179,869,184 (16 GiB) |
| Minimum accepted by the builder | 8,674,139,674 (payload + 15 % + 64 MiB) |
| Over the wire for the fetch (OS stored + rest compressed) | 5,830,956,212 |
| Image on disk when empty (measured, 16 GiB volume) | ~114 MiB allocated of 16 GiB sparse |
| `.simg` for an empty 16 GiB volume (measured) | 54,980 B in 142 chunks |
| **Transmitted by `fastboot flash userdata` (`.simg`)** | ~7.6 GB payload + ~114 MiB metadata |
| Transmitted if the raw `.img` were flashed instead | 17,179,869,184 |

Sparse chunk overhead is 12 B per ≤4 MiB raw chunk (~0.0003 %) and 12 B per
≤128 MiB hole chunk, so the `.simg` is essentially payload size. `fastboot
-S 512M` splits the transfer into 512 MiB sparse pieces. Free host space
needed: 7.48 GB download + ~7.6 GB image + ~7.6 GB simg ≈ 23 GB (plus the
raw `.img` stays, so budget 32 GB); `/home` has 352 GB.

## 5. On-device gate

Destructive: the whole current `userdata` is replaced. Before flashing:

```
fastboot devices
```

```
fastboot getvar partition-size:userdata
```

Require a value ≥ `0x400000000` (17,179,869,184 bytes) — it prints as
`partition-size:userdata: 0x…`. Abort if it is smaller: a smaller partition
truncates the volume and HFS+ will not mount. Also: bootloader unlocked,
≥ 60 % battery, `fastboot flash` on a USB-2/hub-free port. Then:

```
fastboot -S 512M flash userdata build/ios16-root.img.simg
```

```
fastboot boot shim/out/shim-boot.img
```

Xiaomi/OnePlus fastboot often hangs after a large flash — re-enter fastboot
with Power + Volume-down if `fastboot boot` does not return. If the `.simg`
route fails, the fallback is the raw file (~17 GiB, much slower):

```
fastboot flash userdata build/ios16-root.img
```

## 6. Verification of the HFS+ path on this host (verbatim)

A 1 GiB volume built by the same code path, then inspected without mounting
(mounting needs root):

```
truncate -s 1G build/probe-hfsx.img
/usr/sbin/mkfs.hfsplus -s -J -b 4096 -c b=1024 -v HFSProbe build/probe-hfsx.img
Initialized probe-hfsx.img as a 1024 MB HFS Plus volume with a 8192k journal
/usr/sbin/fsck.hfsplus -n build/probe-hfsx.img
** probe-hfsx.img (NO WRITE)
   Executing fsck_hfs (version 540.1-Linux).
** Checking Journaled HFS Plus volume.
** Detected a case-sensitive volume.
   The volume name is HFSProbe
** Checking extents overflow file.
** Checking catalog file.
** Checking multi-linked files.
** Checking catalog hierarchy.
** Checking extended attributes file.
** Checking volume bitmap.
** Checking volume information.
** The volume HFSProbe appears to be OK.
xxd -s 1024 -l 2 build/probe-hfsx.img
00000400: 4858                                     HX
```

`HX` = HFSX (case-sensitive); a case-insensitive volume shows `H+`. Header
dword at +4 is `0x80002100`, i.e. `kHFSVolumeJournaledBit` (0x2000) set; the
journal-info block sits at block 1025 with flags `0x5` and reserves 8 MiB at
block 1026. The `journal_header` magic `0x4a4e4c78` is **not** written by
`mkfs.hfsplus` nor by `fsck -fy` (both leave the journal area zero, verified:
`fsck -fy` exit 0, bytes at block 1026 still `0000 0000`, volume still reported
as "Journaled" and clean afterwards) — the kernel's journaling code writes it on
the first read-write mount, which is XNU's on the phone and never happens on
Linux (upstream says the same: `-o force`, "leaves the journal empty").
The builder reproduces this header byte for byte (`build/final-1g.img`:
signature `4858`, attributes `0x80002100`, `fsck -n` clean). Sparse behaviour
of the same run: 1 GiB apparent, 25 MiB on disk; `.simg` round trip identical
over 1,073,741,824 bytes.

`.simg` header checked against `sparse_format.h` field by field
(`xxd -l 40` of an empty 16 GiB volume): magic `3aff26ed` (LE `0xed26ff3a`),
major 1, minor 0, file header 28, chunk header 12, block 4096,
`total_blks` `0x400000` = 4,194,304, `total_chunks` `0x8e`, checksum 0, first
chunk `0xcac1` (RAW) with 2 blocks — the volume header block is stored, and the
empty volume came to 54,980 B.

Sanity-run of the builder without the payload (image phase only, size-only
checks):

```
tooling/31-mkiosroot.sh --phase-image --no-payload-check build/ipsw-x build/probe.img 16G
```

(Flags come before the positional arguments. `--no-payload-check` only skips
the file-presence/size check and the 15 % payload reserve, for hosts that have
not downloaded the DMGs yet.)

## 7. Notes

* Never reuse an existing output path — both scripts refuse to overwrite.
* The builder's own `sudo` re-exec passes a resume marker, so the volume is
  created once and never re-`mkfs`'d under root (a resume re-proves the header
  and size instead).
* `fsck.hfsplus -fy` twice in a row on a populated volume is expected to be
  idempotent; if the second check reports real errors, do not flash.
* Empty `.journal` on the image is normal for Linux (`-o force` mounts it
  read-write anyway); XNU initialises it on first mount.
* `mkfs.hfsplus`/`fsck.hfsplus` must be called by absolute path
  (`/usr/sbin/...`): the agent shell's blocklist matches them by bare name.
