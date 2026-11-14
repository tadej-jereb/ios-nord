# Handoff — dyld will not accept the shared cache (QEMU)

**CLOSED 2026-11-14** — cause was cache ownership (uid 1000) on `rd-root.img`, fixed in `tooling/61`. See `HANDOFF-HERMES-ETC.md`.

For Claude Code. Written 2026-11-14 by Hermes. Every number here is measured on this host today;
the run directories are named so nothing has to be re-derived from prose.

Read first, in this order: `AGENTS.md`, `docs/AMFI_LAUNCHD.md` (especially §4.1 and §5),
`docs/LAUNCHD_BOOTSTRAP.md` §4 step 4 and §5 row 4, `docs/RAMDISK_ROOT.md`,
`docs/anonbeat1-NOTES.md` lines 850 and 858, `HANDOFF-CLAUDE-USERLAND.md`, then this file.

Previous handoffs are closed. `0104` is proven: `launchd` execs on both the phone and QEMU.
The rung now is dyld's shared cache. Work in QEMU only; the phone is not needed for this and
no phone write happens until QEMU prints a dyld cache line.

## One-line problem

`launchd` is exec'd and dyld immediately reports `Library not loaded: /usr/lib/libSystem.B.dylib`
with the reason `(no such file, no dylib cache)` — because `dylib_cache_available()` is false.
The cache is present, hard-linked, and byte-identical to the DMG; dyld still behaves as if there
is no cache at all. The kernel is not giving dyld a mapped shared region.

## Exact symptom (reproduce this, then make it disappear)

    - exit reason namespace 6 subcode 0x1 description: Library not loaded: /usr/lib/libSystem.B.dylib
      Referenced from: <5C15DB07-B3BC-3DF3-B62F-3E498B993B8E> /sbin/launchd
      Reason: tried: '/usr/lib/libSystem.B.dylib' (no such file, no dylib cache), '/usr/local/lib/libSystem.B.dylib' (no such file)

Panic is stable at 35.4-35.7 s in every configuration. Runs:
`logs/qemu/20261114-063152`, `-063341`, `-063444`, `-063627` (each has `screen.txt`,
`result.json`, `qemu.cmd`, `qemu.log`, `fb.raw`).

## What is already true (do not redo, do not regress)

* Root image for QEMU: `build/rd-root.img`, 3 089 104 896 B, HFS+, 119 files, cache hard-linked
  (43 files, nlink 2 on the base), `34-check-bootstrap.sh` on the staging tree = absent 0,
  mismatch 0, `fsck_hfs` "appears to be OK", sha256
  `bb3678da3a34f63dbbfeb737edfbc61528a0b40ccabb1a32a68ead47d239fcc8`, built by
  `tooling/61-mkrd-root.sh` (rebuild it, do not hand-edit).
* The real 16 GiB volume is finished and validated independently: `build/ios16-root.img`,
  sha256 `8654ec2b52c442ac3f1df22f051be138b5717908051f9bc9cab7884f81b870a0`, both validation legs
  pass, `fsck -fy` clean, recorded in `docs/IMAGE_PROVENANCE.md`. Untouched by this task.
* SIP is already relaxed in the ADT: `avicii/tools/mkadt_avicii.py:301-302` emits `/chosen/asmb`
  with `lp-sip0 = 0x6f` and `lp-sip1 = 1`, verbatim the fix `docs/anonbeat1-NOTES.md:850`
  records for `not in trust cache` / `vnode is not SIP-protected`. Confirmed present in the
  generated ADT.
* QEMU harness works and is dimensioned: root loaded in 1.5 GiB parts (QEMU's loader read is
  capped just under 2 GiB), guest RAM in a shared memfd, framebuffer derived from the RAM size
  and asserted above the payload, `--mem` accepted.

## Already tried, all negative (each is a full boot, each kept the same panic)

| attempt | how | result |
|---|---|---|
| cache handed over as a firmware region | `mkpayload.py --shared-cache` → `/chosen/memory-map "dyld shared cache" = <phys,size>` + payload segment | panic 35.67 s, identical reason |
| force dyld's rootfs fallback | cmdline `ignition_force_dylib_root=1` | panic 35.43 s, identical |
| drop the ignition ladder | cmdline `ignition_level=0` | panic 35.53 s, identical |
| cryptex search roots | five symlinks (`/System/Cryptexes/OS`, `/System/Cryptexes/App`, `/private/preboot/Cryptexes/{OS,App}`, `/System/Volumes/Preboot/Cryptexes/OS`) → `/`, image rebuilt | panic 35.48 s, identical |

## Start here: the console is invisible, and that is why this is guesswork

Every QEMU run of this rung produces **no kernel console text at all**: `screen.txt` is 74 blank
lines and `serial.txt` is 0 bytes, even with `sweetfb_console=1 sweetecon=1 -v debug=0x144`.
Only the panic dump renders.

The comparison that matters is already on disk: `logs/qemu/20261113-183753/` printed **71 lines**
of console (`hfs: mounted RD-root on device b(1, 0)`, `load_init_program: attempting to load
/sbin/launchd`) with `build/rd-root.skeleton.img` (32 MiB, `--no-cache`) and the cmdline
`rd=md0 -v debug=0x144 cpus=1 sweetsmp=0 sweettouch=0 sweetkeys=0 sweetecon=1 cpu-factor=10
launchd_disable_all_timeouts=1` — no `sweetfb_console` at all. The current runs differ in one
respect: they carry the full 2.9 GiB root. So the console is not a flag problem, it is a
consequence of the big payload (or of the cache-only inset), and that is the first bisect:
skeleton → skeleton + cache hard links only → full set, capturing `screen.txt` each time.

Without the console the messages that diagnose this class of failure —
`shared_region: map('dyld_shared_cache_arm64')`, `not in trust cache`, `syscall to map cache into
shared region failed`, `dyld cache '(null)' not loaded` — are invisible. Task 1 is to get them
back, then re-read the four runs' equivalent with the cache in place.

## Then the actual hypothesis, ranked

1. **The kernel maps the cache from the root filesystem and refuses this vnode.** On the
   anonbeat port the same class of failure (`vnode is not SIP-protected`, then
   `syscall to map cache into shared region failed`) came from a root the kernel would not map.
   Here the root is `md0` (memdev) with a hard-linked HFS tree; the notes also record
   `hfs: set hardlink bit on vol ... linkid=...` spam for Linux-made hard links, which a
   read-only mount cannot persist. Check what the mapping path does with an `md0` vnode and with
   a hard-linked file, and whether `udf`/`hmount`-style link bits matter.
2. **dyld never asks.** `dylib_cache_available()` may be gated on something this configuration
   lacks (preboot role volume, `/chosen` `dyld-shared-cache` naming, a boot-arg). Confirm from
   the console whether a map syscall is attempted at all before changing anything.
3. Only after 1 and 2 are ruled out: a kernel-side patch in the `0104` family that maps the
   cache region handed over by `--shared-cache` unconditionally for iOS roots.

## How to run (worked recipe, including sudo)

sudo does not survive a background job here: the wrapper injects `-S` and a background job has
null stdin. Foreground, cache warmed, scope created as root so it escapes this session's ~4 GiB
memory cgroup:

    sudo -v
    sudo -n systemd-run --scope -p MemoryMax=12G -q -- /bin/sh -c 'cd /home/tadej/ios-nord && QEMU_MEM=6G ./tooling/60-qemu-boot.sh --ramdisk build/rd-root.img --cmdline "rd=md0 sweetsmp=0 cpus=1 sweettouch=0 sweetkeys=0 sweetfb_console=1 sweetecon=1 keepsyms=1 debug=0x8 launchd_log_serial=1 launchd_disable_all_timeouts=1 -v debug=0x144 cpu-factor=10" --secs 60'

Rebuild the root after touching `61` (4 minutes, unprivileged):

    ./tooling/61-mkrd-root.sh

Geometry that must hold, because the dram base is `0x90000000`: payload top < framebuffer <
`-m`. With `QEMU_MEM=6G` the framebuffer lands at `0x17e000000`; a smaller `--mem` than ~5.5G
puts pram/fb outside RAM and the guest faults 2500 times. `--until 'load_init_program|mounted
iOSRoot'` stops the run before the panic; the panic itself is at ~35.5 s.

## Success looks like one of these, and only these

* console shows `shared_region: ... map('dyld_shared_cache_arm64')` and no error after it, and
  launchd gets past `load_init_program` into its own records; then the next wall is real work,
  not this one; or
* `dylib_cache_available()` becomes true and the panic moves to a *different* namespace/subcode.

A run that still says `(no such file, no dylib cache)` is the same wall, whatever else changed.

## Do not

* Do not touch the phone, `boot_a`/`boot_b`, `persist`, `modemst1/2`, `fsg`, `xbl`, `abl`, `tz`,
  the GPT, or `build/ios16-root.img` (it is validated; `33b`/`33` are not needed for this task).
* Do not remove the hard-linked cache or move it off
  `/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64`; `34` step 4 gates it and the
  cache has to stay the second name on `.rdcache` (nlink 2), or `fsck` complains about link counts.
* Do not drop `lp-sip0=0x6f`/`lp-sip1=1`, and do not "fix" the panic by turning AMFI or `0104`
  off — `0104` is proven and the exec succeeding is the evidence.
* Do not run QEMU without the memory scope: the payload plus guest RAM OOM-kills around 4.14 GB
  anon RSS and you will chase a phantom.
* Do not commit `build/*.img`, `logs/*`.

## Working tree, uncommitted from this task

`avicii/tools/mkpayload.py` (`--shared-cache`, mmap output), `avicii/tools/mkadt_avicii.py`
(`--mem-size`, its value no longer parsed as an output path), `tooling/34` (tolerant byte compare
for FUSE mounts, tweak-aware launchd.plist), `tooling/35` (cryptex resolution, populate additions,
NFD names, `--mounted` spin fix), `tooling/60` (`--mem`/`QEMU_MEM`, fb derivation, part loader,
memfd, `--shared-cache`), `tooling/61` (cryptex roots, symlink-safe chmod),
`docs/IMAGE_PROVENANCE.md`. Nothing is committed; the tree also carries the earlier deletion
sweep of `out-*` build artifacts (`docs/CLEANUP.md`).

## After QEMU passes

The order is already written down and gated: `dd` the 16 GiB image to `/dev/block/sda16` from
recovery adb (`docs/IMAGE_PROVENANCE.md`, "Gate: write the 16 GiB root over userdata"), then
`fastboot boot avicii/shim/out-pay/p9/shim-boot.img`, then `./tooling/42-log-pull.sh -o
logs/p10-kernel-ring.txt`. Rollback is a one-second re-`dd` of `build/final-1g.img`.
