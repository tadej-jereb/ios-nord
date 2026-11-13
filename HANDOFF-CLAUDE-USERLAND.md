# Handoff — first userland boot on avicii (launchd)

For Claude Code. Written 2026-11-13 17:40 by Hermes. Every number below is measured on this
unit today. Read `AGENTS.md`, `docs/STATUS.md`, `docs/IMAGE_PROVENANCE.md` (the whole file —
it is the boot log of record), `avicii/CONSTANTS.md`, `docs/IOSROOT.md` and
`docs/ROOTFS_READY.md` first.

`HANDOFF-XNU.md` is closed: the loader blindness is fixed, the jump is proven, the kernel
boots. This file is the rung after it.

## One-line problem

The kernel mounts the root volume and then panics because the volume is **empty**:
`load_init_program: opening of /sbin/launchd failed, errno 2`. Nothing is wrong with the
boot chain any more. The missing thing is the iOS userland itself — 11.3 GB of it, which
lives in the DMGs and has to be written into the HFSX volume on `userdata`.

## Where the boot is right now (p6, do not regress it)

    SWEET UFS: "userdata" on LUN 0: first block 0x3c1f88, 103184 MiB, read-write, DMA at 0x1846f8000
    SWEET LOG: console log to the last 4100 KiB of the partition
    BSD root: ufsroot0, major 1, minor 0
    hfs: Initializing the journal (joffset 0x402000 sz 0x800000)...
    hfs: mounted iOSRoot on device b(1, 0)
    SWEET: root volume is not authenticated (error 25); continuing unsealed
    devfs_kernel_mount: kernel_mount failed: 2
    No POST boot-arg set.
    load_init_program: attempting to load /usr/appleinternal/sbin/launchd.development
    VM Swap Subsystem is ON
    load_init_program: attempting to load /sbin/launchd
    <panic, 6392 bytes flushed to the ring>

Full log: `logs/p6-kernel-ring.clean.txt` (ring binary `logs/p6-both-rings.txt`). Panel photo
`photos/p6-panel.jpg`. The UFS **write** path ran here for the first time on this SoC — the
8 MiB HFS journal was created through it — so writes, DMA above 4 GiB and the 512-over-4096
sector mapping all work in the write direction.

## What is on the phone right now

| item | state |
|---|---|
| `userdata` (`/dev/block/sda16`, 108 196 737 024 B) | first 1 GiB overwritten with `build/final-1g.img` (fsck-clean HFSX, volume sig `HX` at 0x400, sha256 `d0bdf0fac3e2d66beb5950e96e157a10c916efbb7708bff984edf501a5aae1f7`), volume name `iOSRoot`, journal present and initialised, **empty** |
| the rest of `userdata` | still the old Android/Magisk bytes, no filesystem there any more (Android data is intentionally gone; `boot_b` LineageOS still boots with fresh data) |
| `boot_a` | untouched throughout, everything is `fastboot boot` |
| `persist`, `modemst1/2`, `fsg`, `xbl`, `abl`, `tz`, GPT | untouched |

The 1 GiB image was written as a **mount test**, not as the root. The real root is 16 GiB
(`build/ios16-root.img`, same builder) and 11.3 GB of it is files.

## The actual blocker: populating the image without sudo

`tooling/33-populate-root.sh` loop-mounts the image and rsyncs — host root. This host has
**no passwordless sudo** and the user is often not at the keyboard, so every boot round-trip
stalls on that. An agent is currently proving an unprivileged route (userspace HFS+ writer
or a FUSE image mount) and will deliver `tooling/33b-populate-root-unprivileged.sh`; the
result must be verified with a file/byte count against the measured 144 341 files / 11.30 GB
and an `fsck`-equivalent pass on the image file before anything is written to the phone.

Constraints that came out of `docs/ROOTFS_READY.md`: the DMGs mount read-only through
`tooling/opt/apfs-fuse` (unprivileged, verified), the tree is 68.5 % of the 16 GiB volume, and
the shared cache is in **no trust cache** (see `lp-sip1`/`asmb` in the ADT and patch 0015).

A second deliverable exists now: `docs/LAUNCHD_BOOTSTRAP.md` +
`tooling/34-check-bootstrap.sh` — the ordered minimal file/devfs set launchd needs for its
first exec, derived statically from the binaries. Validate a populated root with
`34-check-bootstrap.sh` **before** wasting a boot; do not boot a root that has not passed it.

## Hypotheses for the two failures that are not just "empty volume"

1. ~~**`devfs_kernel_mount: kernel_mount failed: 2`**~~ **ANSWERED** by
   `docs/LAUNCHD_BOOTSTRAP.md` §1 and §5 step 1: `devfs_init` already creates console, tty,
   null, zero, urandom, klog and fd *before* `bsd_init:977` calls `kernel_mount`; the only
   missing piece is the `/dev` directory on the volume. No code change. The populate step must
   create `/dev` empty, root-owned, 0755 — `tooling/34-check-bootstrap.sh` step 1 checks it.
2. **`root volume is not authenticated (error 25); continuing unsealed`** — `lp-sip0 = 0x6f`
   with `lp-sip1 = 1` from the ADT `/asmb` node is what allows this to continue instead of
   refusing. If a later stage refuses anyway, the CSR knobs are there; do not "fix" it by
   turning authentication off wholesale without recording which bit changed.

## Reproduction, literally

    cd /home/tadej/ios-nord
    DTB=$PWD/avicii/shim/hybrid/sections/dtb-stock DIAG_STAGE=0 DIAG_LOG=1 OUT=$PWD/avicii/shim/out-pay/p7 ./avicii/shim/build.sh $PWD/avicii/shim/out-pay/pay0/payload-p6.bin
    fastboot boot avicii/shim/out-pay/p7/shim-boot.img

`Image` is byte-identical across p3–p6 (`774764bd…`, recorded in `docs/IMAGE_PROVENANCE.md`);
only the payload cmdline changes. p6's cmdline is the current baseline and must be kept:

    sweetsmp=1 cpus=8 sweettouch=0 sweetkeys=0 sweetfb_console=1 sweetecon=1 rd=ufsroot0
    ufsroot=userdata ufsrw=1 rootrw=1 -v debug=0x144 keepsyms=1

Gate before every destructive step: sha256 into `docs/IMAGE_PROVENANCE.md`, and re-dd
`build/final-1g.img` is a 1-second undo for the volume start.

## Getting the evidence out (no serial port on this phone)

The panel is the only live channel; XNU kills USB at the jump, so adb is not available while
the kernel runs. The ring is the durable one and it survives a reset.

1. Reset: hold **power + volume-down** ~12 s until fastboot.
2. **Fastboot cannot read the ring.** `fastboot reboot recovery`, then the user enables adb in
   the recovery menu (root adbd, no `su` needed — the pull tool handles both).
3. `./tooling/42-log-pull.sh -o logs/<name>.txt` — reads the shim ring (parked 1025 blocks
   before the kernel's) **and** the kernel console ring, labelled separately.
4. Panel screenshots are read by OCR: `tesseract` is not installed, it lives unpacked in
   `~/.hermes/cache/scratch/ocr/root` with `LD_LIBRARY_PATH` and `TESSDATA_PREFIX` pointing
   into it; rotate the photo 270° first (`photos/p*-panel.jpg` are pre-rotated).

## Do not

- Do not touch `boot_b`, `persist`, `modemst1/2`, `fsg`, `xbl`, `abl`, `tz`, or the GPT.
- Do not change the ADT dram base — `0x180000000` works and is the high bank the live FDT
  reports; `--phys-base 0x80000000 --allow-high` exists as an A/B lever only.
- Do not "simplify" the cmdline. `cpus=1` with `sweetsmp=0` hangs `dlil_init` forever (p3).
- Do not write the 16 GiB image over `userdata` until the populated image has passed
  `tooling/34-check-bootstrap.sh` and an `fsck` of the image file; a bad 16 GiB write is a
  30-minute recovery instead of a 1-second one.
- Do not commit `build/*.img`, `src/*`, `logs/*` binaries.
