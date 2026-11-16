# HANDOFF — avicii iOS/XNU port, state at 2026-11-14 16:10 CET (for Claude Code)

Written by the coordinator after six lanes and two stopped sub-agents. Everything below is from a
command that ran; where something is unproven it says so.

## 0. Read these before touching anything

1. `AGENTS.md` — the rules of this port (no phone without permission, `persist`/`modemst1/2`/`fsg`
   never touched, experiments on `boot_a` only, etc.).
2. `docs/STATUS.md` — the long first entry is today's record, in order, with run dirs and sha256s.
3. `docs/CACHE_TRIM.md` — dyld-1067's cache acceptance rules, recovered by disassembling the shipped
   `usr/lib/dyld`. §6 has two hard-won traps, §7 explains how to make a boot print its own reason.
4. `docs/PHONE_TEST.md` — what has been done on the handset, non-destructively.
5. `docs/QEMU_AVICII.md` §1.1 — the mandatory memory-scoped QEMU invocation.

## 1. Where the ladder actually is

QEMU boots to a running userland. With `rootrw=1`, the tier-2 root reaches **71 distinct exec
names**, `SpringBoard` execs and survives, and launchd **does boot tasks**
(`commit-boot-mode`, `init-with-data-volume`, `restore-datapartition` "optional … not present").
Before today it stopped at 8 Programs and never printed a boot-task line.

Two service crash loops remain, one now solved:

- `containermanagerd` — **solved**: `CFDateFormatterCreate` returned NULL because `libicucore`
  hardcodes `/usr/share/icu/` and the root had no `/usr/share` at all. `61 --share` stages
  `/usr/share/icu` + `/usr/share/zoneinfo` (602 files, 31 272 200 B); with it, containermanagerd
  crashes go 13 → **0** and it stays up.
- `passd` — **open**: SIGABRT, uncaught `NSInvalidArgumentException: -[NSBundle initWithURL:]: nil
  URL argument` during PassKitCore's first-use init. Its own image computes the nil URL
  (`0x102beae54`). The root carries only `PassKitCore.framework/passd` and its `Info.plist`, no
  bundle resources.
- Neither is a kernel bug; both were missing files in a synthesized root.

The hypothesis order that matters: everything since the boot rung has been *missing files and
missing write permission*, not kernel defects. Check the root before touching the kernel.

## 2. Artifacts (verify these before use)

| image | bytes | sha256 (16) | what it is |
|---|---|---|---|
| `build/rd-root.skeleton.img` | 33 554 432 | `161b7055cb4f8d08` | 32 MiB, `--no-cache`, stops at dyld libSystem |
| `build/rd-root.img` | 3 090 153 472 | `0e247ac47216a7c2` | minimal set + full cache, the 094151 baseline |
| `build/rd-root.progs.img` | 3 103 784 960 | `4352d893ff2cb5f8` | + tier-1 Programs |
| `build/rd-root.progs.v2.img` | 3 103 784 960 | `b8f0bbab8dac2e4b` | rebuilt with the fixed fstool |
| `build/rd-root.tier2.img` | 3 270 508 544 | `ce8eb192f1232a3e` | + 62 of the 64 ENOENT Programs, 393 entries |
| `build/rd-root.tier2b.img` | 3 270 508 544 | `6f159a3c011adc61` | + `--vardirs` |
| `build/rd-root.tier2c.img` | 3 270 508 544 | `3e50d726e6297cde` | + `--jobenv` (TMPDIR) |
| `build/rd-root.tier2d.img` | 3 305 111 552 | `cd9fdcca4b29ee66` | + `--share` (icu/zoneinfo) — **best QEMU root today** |
| `build/rd-root.cachetrial3.img` | 290 455 552 | `4dd9068132a909c4` | trimmed cache, 19 files, maps fully, dyld then faults |
| `build/ios16-root.img` | 17 179 869 184 | `8654ec2b…70a0` | the real 16 GiB root — **read-only, never written** |

Kernel: `avicii/shim/out/kernel/kernel.development.sweet`, 17 206 080 B,
sha256 `534248682bbc5cbb29e38033be872b3edfbbb84d45476f6cb12ad8e31779cf1e` — carries patch `0105`
(`sweetexeclog`, prints `SWEET EXEC: <path> failed errno N`), default off.

Key run dirs (all under `logs/qemu/`):

   20261114-094151               baseline: 68 xpcproxy, early boot 31.700474
   20261114-103445-kern0105     0105 + tier-1: 64 SWEET EXEC errno 2 (the missing-Program list)
   20261114-115454-lane9        tier2 on 8G: first services, 53 MH_MAGIC 0xFF000000 crashes
   20261114-133508-econ1-hole   ramdisk moved above the early-console band: 0 MH_MAGIC
   20261114-151140-rootrw-pristine  rootrw=1 alone: 0 tccd crashes, 71 names, boot tasks
   20261114-160008-tier2d       --share: containermanagerd 0 crashes, passd STR nil URL
   20261114-152352-l8cache3d    trimmed cache maps 19/19, then SIGSEGV in libdyld __DATA_DIRTY

## 3. Open thread A — `passd`'s nil NSBundle URL

Evidence: `logs/qemu/20261114-160008-tier2d/msgbuf.txt` — 10 identical
`STR *** Terminating app due to uncaught exception 'NSInvalidArgumentException', reason:
'*** -[NSBundle initWithURL:]: nil URL argument'` blocks, each with a first-throw stack ending
`0x102beae54 0x102858f48 0x1028589b4 0x1028574fc …`. `0x102beae54` is inside `passd`'s own image, so
passd builds the URL itself.

Next actions, in order:

1. Symbolize `passd`'s frames (`0x102beae54`, `0x102858f48`, `0x1028589b4`, `0x1028574fc`) against
   `build/rd-root.tier2d.stage/System/Library/PrivateFrameworks/PassKitCore.framework/passd`
   (`pc − __TEXT.vmaddr` is the file offset for this image, unlike cache addresses).
2. Find which bundle path it wants (`PKPassKitBundle`? a `.bundle` under `PassKitCore.framework/`)
   and stage that bundle's resources. Note `61`'s `--programs` copies only Programs and named
   bundle `Info.plist`s, not resource directories — this is likely the whole cause.
3. Verify with one boot, `rootrw=1 sweetscan=passd`, and read `CRASH passd` count plus `STR` lines.

`passd` is the last thing between today's QEMU state and an uninterrupted service set. `sweetscan`
already dumps its exception reason; do not remove that boot-arg from the test line.

## 4. Open thread B — the trimmed dyld shared cache (phone transport)

Goal: a cache small enough for the phone's `fastboot boot` budget (`max-download-size 805 306 368`)
so the handset can reach the same rung as QEMU without writing `userdata`.

Current state: `build/rd-root.cachetrial3.img` (290 455 552 B, `4dd90681…`) has a **fully accepted
signature** and **maps all 19 files** (`19 × map(…): not in trust cache` in
`logs/qemu/20261114-152352-l8cache3d`), then launchd SIGSEGVs 0.1 s later
(`exit reason namespace 2 subcode 0xb`), with two EL0 **write** aborts in that run's `qemu.log`:

    FAR 0x1e1d345c8   = /usr/lib/system/libdyld.dylib __DATA_DIRTY + 0x8   (seg base 0x1e1d345c0)
    FAR 0x201e1d34628 = same segment, off 0x68

i.e. dyld writing its own data in `libdyld`'s `__DATA_DIRTY` and faulting. The lane that found this
was stopped mid-investigation; its scratch is in
`/home/tadej/.hermes/cache/scratch/lane8/f/` (`analyze.py`, `window.py`, `slide.py`, `launchd.dis`,
`dyld.dis`) and it had begun pulling dyld source (`common__DyldSharedCache.cpp`,
`dyld__JustInTimeLoader.cpp`) to check `hasSlideInfo()`.

Next actions:

1. Compare the mapping records (`address`, `size`, `fileOffset`, `initProt`, `maxProt`) of every one
   of our 19 files against Apple's, focusing on the file that owns `libdyld`'s `__DATA_DIRTY`; a
   `maxProt` R|W with `initProt` R yields exactly this fault.
2. Read the kernel's side: `osfmk/vm/vm_shared_region.c` map path (~2200-2500) — does it honour
   `initProt` from the info array, and are there limits a 55-mapping/19-file shape could trip?
3. Then rebuild + re-sign. **Any byte change invalidates the signature** (`CACHE_TRIM.md` §6.1);
   re-run `kcheck`, `csck`, `triecheck`, `validate3` on the final bytes.
4. Tools: `/home/tadej/.hermes/cache/scratch/lane8/` — `build_split3.py`, `validate2.py`,
   `validate3.py`, `triecheck.py`, `csck.py`, `cs106/resign.py`, `REPORT-LANE8E.md`.
   Also left behind by the stopped lane 8f, and worth using before re-deriving anything:
   `lane8/f/mapdump.py` with its outputs `ours-maps.txt` (204 lines) and `apple-maps.txt`
   (316 lines) — a per-file dump of main + subcache mapping records, `mappingWithSlide` entries and
   the subCache array, side by side with Apple's; `lane8/f/{analyze,window,slide}.py`,
   `launchd.dis`, `dyld.dis`; and a **dyld source checkout at `lane8/dyld-src/`**
   (`common__DyldSharedCache.cpp` etc., which is where `hasSlideInfo()` at
   `common__DyldSharedCache.cpp:2110` comes from). Two differences already visible in that dump:
   our main mapping is `s=0x4000` vs Apple's `0x5c000`, and our `maxSlide=0x0` vs Apple's
   `0x55214000` — check what dyld does with `maxSlide == 0` before assuming it is harmless.


Unproven beyond that: runtime trie use, chained fixups with `maxSlide` 0, and whether the kernel
accepts the dyn-config mapping at `SR+0x9a0b8000`.

## 5. Open thread C — the handset, and the one decision that is not an agent's

Phone state (`docs/PHONE_TEST.md`): `fastboot boot` of a header-v1 `Image.gz-dtb` image is accepted
**4/4** (`Sending 98304 KB OKAY` / `Booting OKAY`), the shim runs and jumps
(`L JUMP 0x18148c488`, `J ENTRYPA`), and the panel reaches
`dyld: Library not loaded: /usr/lib/libSystem.B.dylib` — the **predicted no-cache stop**, because the
image carries the 32 MiB skeleton.

Two things the phone now needs, both already proven on QEMU:

1. `rootrw=1` in the phone cmdline — its `md0` is read-only exactly like QEMU's, so `confstr` and
   every temp-dir consumer would fail identically. Already added to `docs/PHONE_TEST.md`'s cmdline
   record; the payload/image sha256 must be re-recorded on the next build.
2. A root that contains a dyld cache — either thread B's trimmed cache (fits with 514 MB headroom)
   or the real root on `userdata`.

The `userdata` gate (`docs/STATUS.md` gate section, five options A/A2/B/C/D, none chosen) is the
owner's decision. Do not pick one, do not write `userdata`, no `dd`.

One datapoint that arrived while this handoff was being written, and it kills option D as stated:
an orphaned run launched `build/ios16-root.img` as `md0` with `--mem 22G`, `rootrw=1` and the usual
line (`logs/qemu/20261114-fullroot-d1`, ramdisk PA `0xa1000000` size `0x400000000`). The real 16 GiB
volume **does not mount**:

    BSD root: md0, major 1, minor 0
    hfs_mountfs: buf_meta_bread failed with 22
    hfs_mount: hfs_mountfs returned error=22 for device unknown-dev      (retried every 7 s, 170 s)

So "just boot the real image in QEMU with more RAM" is not a working route yet — the mount fails
with `EINVAL` on the first metadata read, which is a different wall from the dram ceiling lane 5
measured. Nobody has investigated that error; do not assume it is trivial, and do not repeat the run
without a hypothesis.

## 6. Tooling that changed today (already in the tree, uncommitted)

- `tooling/60-qemu-boot.sh` — dumps patch `0047`'s `_sweet_log_ring` to `sweetlog.txt`/`.raw`
  (dyld's own messages live there, not in msgbuf); detects a wrapped ring and reports `window` /
  `MISSING`; per-16 KiB page walk + RAM-scan fallback for `msgbuf=`; exit 5 if a ring reports bytes
  but dumps none.
- `tooling/61-mkrd-root.sh` — `--programs FILE` (Mach-O → 0755, else 0644, dirs recurse, fatal if
  neither DMG has it), `--vardirs`, `--jobenv LABEL:VAR=VALUE`, `--share` (icu/zoneinfo).
- `tooling/62-msgbuf-summary.sh` (new) — run judgment: early boot, exec table, SWEET lines, wrap and
  empty-dump handling, baseline diff.
- `tooling/70-phone-boot.sh` (new) — phone wrapper, `--pull`, `--recover`, 20 s settle.
- `avicii/tools/mkpayload.py` — ramdisk placed at `0xa1000000` when `kernel_end < 0xa0200000`
  (early-console band is 10 MB at `0xa0000000`), `--ramdisk-addr` override, ADT memory-map kept
  consistent.
- `tooling/opt/fstool/bin/fstool` — patched 0.5.4 (`f837e4d1…`) fixing `chown`/`chmod` on
  hard-linked files (they wrote the `hlnk` placeholder instead of the `iNode`); old binary kept as
  `bin/fstool.prev-45edb6ce`, fix-only patch at `tooling/opt/fstool/fstool-0.5.4-hardlink-chown.patch`.

## 7. Traps that have already cost hours — do not relearn them

1. **A read-only `md0` breaks userland.** `confstr()` gates on `access(W_OK)`; without `rootrw=1`
   every temp-dir job dies (`tccd`: `brk #1` at `pc − mh = 0x2E390`) no matter what the tree holds.
2. **The `CRASH … pc` in msgbuf is slid**: unslid = `pc − 0x32a3c000`. And `ns 2` is
   `OS_REASON_SIGNAL`, not `EXC_BAD_ACCESS`: `code 0xb` = SIGSEGV, `code 0x6` = SIGABRT.
3. **`screen.txt` is blank** in the `--ramdisk` layout; read `msgbuf.txt`, and `sweetlog.txt` for
   anything launchd/dyld wrote to `/dev/console` (console output is disabled,
   `disableConsoleOutput: 1`, but patch `0047` captures the bytes).
4. **The 128 KiB ring wraps** under a service storm; `62` now says so, and a wrapped window is not
   evidence of absence.
5. **`avicii/shim/build.sh` defaults to `DIAG_STAGE=8`**, which parks 60 s and `PSCI reset`s instead
   of jumping. Payload boots need `DIAG_STAGE=0`.
6. **QEMU must run in a memory scope**: `systemd-run --user --scope -p MemoryMax=12G`; a bare run is
   OOM-killed around 4.1 GiB anon. At most three QEMU processes host-wide. Long Claude Code runs
   (cargo test, dyld analysis) also need the scope — the default worker cgroup is ~4 GB.
7. **A checker that shares the builder's wrong convention passes happily.** Lane 8c's trie validator
   agreed with its broken builder. Validate any reader against Apple's own artifact first.
8. **Any cache byte change invalidates its signature** (`EBADEXEC`, and dyld then reports
   `no dyld cache`, one stage earlier than a trie miss).

## 8. Running it

    systemd-run --user --scope -p MemoryMax=12G -q -- /bin/sh -c 'cd /home/tadej/ios-nord && \
      DISPLAY= QEMU_MEM=8G ./tooling/60-qemu-boot.sh --ramdisk build/rd-root.tier2d.img \
      --out logs/qemu/<stamp>-<lane> --cmdline "rd=md0 sweettouch=0 sweetkeys=0 \
      sweetfb_console=1 sweetecon=1 keepsyms=1 launchd_log_serial=1 \
      launchd_disable_all_timeouts=1 sweetexeclog=1 rootrw=1 -v debug=0x144 cpu-factor=10" \
      --secs 150'

`QEMU_MEM=8G` gives a 5 735 MiB dram window (needed for the 3.3 GiB tier-2 roots); `QEMU_MEM=6G`
gives 3.74 GiB (enough for the 3.0 GiB roots). Judge with
`./tooling/62-msgbuf-summary.sh <run> logs/qemu/20261114-094151`.

## 9. Git state

`master` is at `457e669` ("rd-root: stage launchd job table and job plists; docs cleanup"). Everything
from today is **uncommitted**: modified `AGENTS.md`-adjacent docs (`STATUS.md`, `QEMU_AVICII.md`,
`PHONE_TEST.md` new, `CACHE_TRIM.md` new), `avicii/tools/mkpayload.py`, `tooling/60`, `tooling/61`,
`xnu-avicii/series`, plus untracked `tooling/62`, `tooling/70`, `avicii/rd-root/`,
`xnu-avicii/patches/0105-sweet-exec-fail-log.patch`, `.hermes-lanes/`, `photos/`. Nothing has been
committed deliberately — the coordinator offered to split it into per-topic commits and the owner has
not said yes yet. Do not commit on their behalf without asking.

## 10. What I would do next, in order (not a decision, just the queue)

1. `passd`'s missing bundle resources (thread A) — it is the last crash loop, and the fix is a
   staging change, not code.
2. Then a long, clean run (`--secs 300`, tier2d + `rootrw=1`) to see how far launchd gets once no
   service is dying: this is the first time that question is askable.
3. The trimmed cache's data-mapping fault (thread B) — it is the only route that puts a cache on the
   phone without the `userdata` gate.
4. The phone boot itself, once 1–3 settle, with `rootrw=1` and either a cache-carrying root or the
   owner's gate decision.
