# Handoff for Claude Code — ios-avicii, blocked on "our compiled shim is refused, hand-built parks work"

Written 2026-11-12 ~22:10 by the orchestrating agent, for an external coding agent with no
memory of this session. Read this whole file before touching anything. `PROGRESS.txt` and
`docs/STATUS.md` carry the longer history; `docs/SHIM_BOOT.md`, `docs/HYBRID.md`,
`docs/ABL_FORENSICS.md`, `docs/DIAG.md` carry the detail behind every claim here.

## 1. The project and where it stands

Goal: run Apple's open-source XNU (xnu-8796, iOS 16 generation) plus the unmodified iOS
16.7.16 iPhone X userland on a OnePlus Nord (`avicii`, SM7250/lito).

State by milestone:

| # | Milestone | State |
|---|---|---|
| 1 | bootloader unlock | DONE (`flash.locked=0`, `verifiedbootstate=orange`) |
| 2 | root + adb | DONE (Magisk v31.1, `su -c id` = 0) |
| 3 | partition backup | DONE (41 partitions, size+md5, magic-checked, `backup/64f70df8/`) |
| 4 | live hardware dump | DONE (83 files in `logs/dumps/run-20261112-195027/`) |
| 5 | board ADT from live FDT | DONE (`avicii/adt/avicii-live.adt`) |
| 6 | shim executes on hardware | **PARTLY DONE — see §2** |
| 7 | XNU payload | READY but uncompiled: 87-patch series applies clean to xnu-8796.141.3, CI workflow written, needs `gh auth login` + fork |
| 8 | iOS root image | READY but empty: 16 GiB HFSX fsck-clean, populate script dry-run passes, needs one `sudo` run |
| 9 | boot to launchd/SpringBoard | NOT STARTED |

So iOS 16 is **not** running. What runs is LineageOS 21 on slot `b`, used as scaffolding.

## 2. Exactly where the blocker is

Two gates were found and fixed today, both in the packer:

* **`os_version = 0` is refused** by ABL with `secboot=enabled` (anti-rollback). Proven:
  the same stock kernel repacked by us was refused at 0 and **booted in 22 s** once the
  field carried stock's `0x1c000185`. The packer now enforces it.
* **A missing dtb section** is refused. Stock's boot image carries a real DTB at
  `0x2bab000` with `dtb_size 406620` / `dtb_addr 0x1f00000` in the header. Our images
  dropped it. The packer now always appends `src/avicii-board.dtb` at that offset.

With both fixed, these **park successfully** (park = CPU sits in our code, no USB for 90 s):

* `avicii/shim/hybrid/out/h1.img` — stock page 0 verbatim + park at stock's branch target
* `avicii/build/out/S6.img` — our header and our stub, stock everything else
* `avicii/shim/hybrid/out/h4.img` — our image, code0 branching to `+0x80000`, park there

And these are **refused at a constant ~6000 ms** (an untouched stock image boots in 16 s,
so a refusal is unambiguous):

* `avicii/shim/out-diag/off3/shim-boot.img` — the compiled shim, **correct layout**
  (code0 `b +0x80000`, `text_offset 0x80000`, real `_start` at `0x80000`), normal path
* `avicii/shim/out-diag/psm` — park planted at the very top of `shim_main`
* `avicii/shim/out-diag/s0` — `DIAG_STAGE=0`, shim normal path
* `avicii/shim/out-diag/n2`, `n2c` — diag rung 1, with and without `con_clear`
* every earlier build: v1, v2, gzip, raw, with/without footer, with stock or empty ramdisk

**The shape of the fault:** a *hand-built* payload parks; anything produced by compiling our
C sources is refused, even when the container is byte-identical in every field to one that
works. `off3` is the cleanest pair with `h4`: same header, same offsets, same everything
except that `off3`'s body is our real compiled code. Refused.

## 3. What is already ruled out (do not re-test)

By measurement, all refused identically: header v1 vs v2; gzip vs raw kernel; DTB appended
in the kernel stream vs as its own section vs absent; empty (99 B) vs stock (1.9 MB)
ramdisk; `console=null` vs stock cmdline; AVB footer present or absent; `text_offset` 0 vs
`0x80000`; kernel section padded to stock's 43,876,368 B; a matching `vbmeta_b` written
from our own image; `DIAG_LOG` on/off; `con_clear` present or removed.

Also established: `fastboot boot` is unusable on this ABL (4/4 attempts) — always flash to
`boot_b`; the untouched stock image is the control and boots every time; `vbmeta_b` is
LineageOS's with `Flags: 3` so verification is off and the footer digest is not consulted.

## 4. Reproduction

```
# toolchain
source tooling/env.sh            # clang 18.1.8, lld, llvm-objcopy, adb, fastboot, dtc

# build the current failing case (compiled shim, correct layout)
cd avicii/shim
DTB=/home/tadej/ios-nord/src/avicii-board.dtb DIAG_STAGE=0 OUT=out-diag/x ./build.sh

# verify (must PASS; fails on os_version 0 or a missing footer)
cd /home/tadej/ios-nord
avicii/tools/mkbootimg_v1.sh --verify avicii/shim/out-diag/x/shim-boot.img

# flash and measure — orchestrator does this, ~6 s refusal = fail, 90 s no-USB = park
adb kill-server
fastboot flash boot_b avicii/shim/out-diag/x/shim-boot.img
fastboot reboot

# restore the working system afterwards, always
fastboot flash boot_b backup/64f70df8/boot_b.img
fastboot reboot
```

Image geometry for reference: partition 100663296 B, header v2, page 4096,
`kernel_addr 0x8000`, `ramdisk_addr 0x1000000`, `tags 0x100`, `dtb_offset 0x1f00000`,
`os_version 0x1c000185`, AVB footer `Algorithm: NONE` via `avicii/tools/avbtool.py`.

## 5. What we want from you — the actual question

Why is a compiled shim body refused where a hand-written `wfe; b .` at the same offset is
accepted, with an otherwise identical container?

Concretely, the current first instructions of `_start` at offset `0x80000` are:

```
msr  daifset, #0xf
mov  x19, x0
msr  spsel, #1
adr  x1, _stack_top
mov  sp, x1
```

and `_head` at offset 0 is `b _start` (`0x14020000`), `text_offset 0x80000`. Candidate
directions we have not tested:

* `msr spsel, #1` / SP_EL1 before any stack exists, versus stock's stub which does much
  more work first (stock's `_head` at 0 is a branch to `+0x2480000`, and real code lives
  there — compare `src/los21-boot.img` bytes at `0x1000` and `0x2481000`).
* The `.text.head` / `.text` split at `0x80000` in `shim.ld` — whether the linker emitted a
  long-branch stub or an absolute reference that is wrong at the load address
  (see `-fno-jump-tables` and the ABS64 ban in `build.sh`).
* Whether ABL needs more than a branch at the entry (e.g. a valid-looking prologue, or the
  PE/`res5` header fields), since a payload of pure `wfe` never exercises them.
* Anything in `avicii/shim/{start.S,shim.ld,mmu.c,shim.c,console.c}` that assumes the body
  is at the image start rather than at `0x80000` (symbol arithmetic, `adr` range,
  `_stack_top`, `_bss_start`, the `scratch` array).

## 6. Rules if you change things

* Deliver numbered commands, one literal per line, and a pass/fail test per image
  (pass = no USB for 90 s; fail = fastboot within ~10 s; a healthy boot = adb present).
* Experiments go to `boot_b` only. `boot_a` is unusable (no system metadata) and
  `persist`/`modemst*`/`fsg`/`xbl`/`abl`/`tz` must never be written.
* `adb kill-server` before every reboot check, or the previous boot answers and lies.
* Parked images need **Power held 30 s** to reset (the power key has no driver then);
  `park()` in `avicii/shim/diag.c` now self-resets after 60 s.
* Mark every claim verified (with the command) or hypothesis. Do not soften a failure.

## 7. Useful inventory

`PROGRESS.txt` (full state and every ruled-out path), `docs/HYBRID.md` (H-series + F-series
hypothesis tables, expected vs observed), `docs/ABL_FORENSICS.md` (683 lines: field-values
reference, Magisk's patcher, no `/proc/last_kmsg`, pstore transcript, `misc` bootonce),
`docs/DIAG.md` and `docs/TELEMETRY.md` (five diag rungs, IMEM/GPIO/vibration signals),
`avicii/CONSTANTS.md` (cited hardware table), `avicii/build/README.md` + `MATRIX.txt`
(S1–S6 one-variable series; S1 boots, S6 parks), `avicii/shim/hybrid/mk.sh` + `check.py`
(the working hand-built payload generators — read these first, they encode the shape that
works).
