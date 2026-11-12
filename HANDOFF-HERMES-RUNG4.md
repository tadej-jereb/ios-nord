# Handoff for Hermes — close rung 4 (secondary cores)

Written 2026-11-12 by Claude Code. You are the orchestrator: you own the phone and the
sub-agents. This file supersedes `HANDOFF-HERMES.md` (the dtb-section task, done) and
extends `HANDOFF-RUNG4.md` (still the reference for device state, ring pull and build
commands). Read §1–§3, then start §4 and §5 at the same time.

**Stale rules — do not follow them.** `SOUL.md` and `HANDOFF-HERMES.md` §7 say
"`fastboot boot` is broken, always flash `boot_b`". That is reversed now: `fastboot boot`
only, `boot_b` is never written (`AGENTS.md`, `HANDOFF-RUNG4.md` "Rules").

## 1. Finding — the release is probably not fatal; the entry address is wrong

`HANDOFF-RUNG4.md` concludes "the address is no longer in question". The evidence says
the opposite.

- VERIFIED (`llvm-nm avicii/shim/out-diag/l14/shim.elf`): `_head` = `0x0`,
  `_start` = `0x80000`, `secondary_entry` = `0x80054`, `sec_stub` = `0x800a0`.
  `shim.ld` puts the header at 0 and `.text` at `0x80000`.
- VERIFIED (`avicii/shim/start.S:37-42`): `kimg_base` is the runtime address of
  **`_head`**, not of `_start`.
- VERIFIED (`logs/diag-l14.txt`): `kimg=0xa7e80000`, `sec_entry=0xa7f00054`,
  `entry=0xa7e80054`. The C expression `(uintptr_t)secondary_entry` is PC-relative and
  already yields the runtime address `0xa7f00054` = `kimg_base + 0x80054`.
- Therefore the "2×base" mystery is closed: `kimg_base + (uintptr_t)secondary_entry`
  = `0xa7e80000 + 0xa7f00054` = `0x14fd80054`. `kimg_base` was never doubled.
- Therefore the workaround at `avicii/shim/diag.c:445-446`
  (`kimg_base + (sym - _start)`) is `0x80000` too low. Images `l10`–`l15` hand PSCI
  `0xa7e80054` / `0xa7e800a0`, which is zero padding between the Image header and
  `.text`. A released core executes zeros there with no vectors.
- VERIFIED (`logs/diag-l6.txt:35-46`, the first version, entry passed as the bare
  symbol): seven `ret=0`, then `spin 1=000c276c … 7=0009dae8`. `sec_spin[idx]` is
  written only by `diag_secondary()`, so **all seven cores ran our C code in `l6`**.
- VERIFIED (`git show 4428fb1:avicii/shim/diag.c`, lines 412-420 and 460-462):
  `diag_secondary()` stores `sec_spin[idx]` only after its loop ends, and the loop ends
  on `sec_stop`. `stage4()` built the ack mask *before* setting `sec_stop = 1`, so the
  mask was always 0. `ack mask=0` in `l6` was a test-ordering bug, not a hardware result.
- HYPOTHESIS (not yet booted): with the entry restored to the bare symbol and the ack
  read after `sec_stop`, rung 4 is green. The five hypotheses in `HANDOFF-RUNG4.md`
  (execution state, EL, cluster power, coherency, stack) are parked until this is tested.
- OPEN, cheap to settle: `start.S:3` says ABL enters at EL1 and the boot core installs
  `vbar_el1`; `HANDOFF-RUNG4.md` says the shim runs at EL2. Print `CurrentEL` once in
  L16 and correct whichever text is wrong.

## 2. State you inherit

- Device: unlocked, slot `b`, LineageOS 21 + Magisk on `boot_b`, nothing flashed.
  Restore image `backup/64f70df8/boot_b.img` (`39ed8eea…`) — only if `boot_b` is ever
  written, which this task does not do.
- Rungs 1, 2, 3, 5 green. Do not re-walk them.
- `HEAD` = `3f8510e`. Working tree: `avicii/shim/start.S` modified (guarded vectors in
  `sec_stub`), `avicii/shim/out-diag/l14/` untracked.
- `out-diag/l15` (`0676f9b5…`) is built, `--verify` PASS, **not booted**. It still
  carries the wrong entry; it is useful only as the negative control for L16.

## 3. Agent plan — one device lane, everything else in parallel

You solve this with sub-agents, not in your main thread. The phone is a single serial
resource: exactly **one** agent touches USB.

| agent | starts | touches device | job | deliverable |
|---|---|---|---|---|
| **Fixer** | t=0 | no | §5.1 entry + ack fix, build L16 and L17 | two images, sha256 list |
| **Reviewer** | t=0 | no | §5.2 independent check of §1 and of Fixer's diff | CONFIRMED / REFUTED per claim, with the command |
| **Flasher** | when Fixer and Reviewer agree | YES, sole owner | §4 queue, one image at a time | one result line per image (§7) |
| **Cleaner** | after rung 4 is green | no | §6 clean-up and optimisation pass | one commit per concern |
| **Scribe** | on first result | no | §5.3 docs | provenance rows, `docs/STATUS.md` |

Rules that keep it cheap and honest:

- Spawn Fixer and Reviewer in one message. Give each only its own section plus §1 and
  §8. Give paths, never pasted file contents.
- The Reviewer gets the code and the logs, **not** the Fixer's reasoning. It must
  re-derive the addresses itself. If it refutes §1, stop and report; do not boot.
- Agents return a result table and file paths, never dumps or disassembly.
- The Flasher never builds. Builders never touch USB. The Flasher takes images only
  from a list with a sha256 per line and re-hashes before booting.
- One boot per question. Repeat a run only if its result contradicts the prediction.
- If L16 is not green, do not improvise: fall back to the hypothesis order in
  `HANDOFF-RUNG4.md`, one sub-agent per hypothesis, one image per variable.

## 4. Flasher queue (device lane)

Gate before every boot: `--verify` PASS, dtb section hashes to `48b0902a…`, image
`sha256sum` equals the listed value, `fastboot devices` answers.

```
1. cd /home/tadej/ios-nord
2. source tooling/env.sh
3. avicii/tools/mkbootimg_v1.sh --verify avicii/shim/out-diag/l16/shim-boot.img
4. sha256sum avicii/shim/out-diag/l16/shim-boot.img
5. adb reboot bootloader
6. fastboot devices
7. fastboot boot avicii/shim/out-diag/l16/shim-boot.img
```

The image parks and self-resets after 60 s. The phone then lands in recovery; pull the
ring with the `adb exec-out dd` line in `HANDOFF-RUNG4.md` (not `42-log-pull.sh`).
`adb devices` = `unauthorized` needs a human at the screen.

| L16 result | meaning | next |
|---|---|---|
| `probe mask=0xfe` | entry address was the bug | boot L17 |
| caller survives, mask partial | some cores differ | name the missing MPIDRs, test cluster power (`HANDOFF-RUNG4.md` hyp. 3) |
| dies as before | §1 hypothesis wrong | boot `l15` once as control, then hyp. 1 |

L17 passes when `ack mask=0xfe` and every `sec_spin[]` is non-zero. That is acceptance
items 1–2 of `HANDOFF-RUNG4.md`; rung 4 is then green.

## 5. Host-side work (parallel, no device)

### 5.1 Fixer

One variable per image, both from the current `diag.c`:

| image | change | expects |
|---|---|---|
| L16 | entry = `(uintptr_t)sec_stub`, release all seven (`0x100`–`0x700`), print `CurrentEL` | `probe mask=0xfe` |
| L17 | L16 + target `secondary_entry`; set `sec_stop = 1`, wait 50 ms, then build the mask from `sec_spin[]` | `ack mask=0xfe` |

- Replace `diag.c:445-446` with the bare symbol address. Delete the comment that
  blames `kimg_base`; replace it with one line stating that symbol addresses are
  already runtime addresses and `kimg_base` is `_head`.
- Add a build-time or boot-time assertion that the entry lies inside
  `[_start, _bss_start)`, so a wrong address fails loudly instead of killing the SoC.
- Build exactly as `HANDOFF-RUNG4.md` "Build a rung" (both `DTB` and `DTB_FILE` to the
  soc tree, `DIAG_STAGE=4 DIAG_LOG=1`). `--verify` must PASS.
- Keep the probe log lines (`kimg=`, `sec_entry=`, `entry=`, `probe now=`) until
  rung 4 is closed.

### 5.2 Reviewer

Independently confirm or refute, each with the command used:

1. `secondary_entry` runtime address for load base `0xa7e80000`.
2. What sits at file offset `0x54` and `0xa0` of `out-diag/l14/Image`.
3. Whether `(uintptr_t)sym` compiles to `adrp`/`add` under the flags in
   `avicii/shim/build.sh:85` (`-fno-pic`), from the `l14` disassembly.
4. Whether the `l6` ack mask could ever be non-zero given the `4428fb1` source.
5. Fixer's diff: one variable per image, no change to the dtb gate, `FB_STRIDE`, or
   ring layout.

### 5.3 Scribe

After each Flasher result: sha256 + outcome row in `docs/IMAGE_PROVENANCE.md`, dated
entry in `docs/STATUS.md`. On green: correct `HANDOFF-RUNG4.md` ("address no longer in
question", "2×base unexplained", the EL claim) and the `fastboot boot` lines in
`SOUL.md`. Commit docs only; never commit under `refs/`.

## 6. Code standard — clean, efficient, optimised where it pays

This applies to every agent that writes code, and is the Cleaner's whole job once
rung 4 is green.

Clean:

- Smallest diff that answers the question. No drive-by refactors inside a probe image.
- One function, one job. `stage4()` currently mixes address maths, release, formatting
  and verdict; split it after green, not before.
- Remove dead code as soon as its question is answered: the `for (once …)` loop, the
  `#if PARK_C1/C2/C3` variants, the duplicated EL-guarded vector install in
  `secondary_entry` and `sec_stub` (make it one macro).
- No duplicated constants or helpers. `PSCI_*` is defined in both `shim.c` and
  `diag.c`; `sec_probe` names two different objects (`shim.c:64`, `diag.c:412`). One
  header, one name each.
- Name things for what they do: `smc()` in `diag.c` is the PSCI conduit — call it that,
  and make the conduit (SMC vs HVC) one decision in one place.
- Comments state the constraint or the measured fact with its date, never the history
  of attempts. A comment that turned out wrong is deleted, not amended.
- Every hardware number comes from `avicii/CONSTANTS.md` with its citation; anything
  else carries `UNVERIFIED`.
- Zero warnings under `-Wall -Wextra`. `host_test` passes before any image is packed.

Efficient:

- Replace the hand-rolled `hex8` + byte-copy blocks in `stage4()` with the existing
  `hexline()`/`append()` helpers or one small formatter.
- No busy-wait where an event exists: secondaries park in `wfe`, the primary polls the
  generic timer, not a counted loop.
- Bounded everything: every wait has a deadline, every array index is checked.
- Keep the image small and the build quiet: no new dependency, no new section without
  a reason.

Optimise — only measured, only after correctness:

- State the metric and the before/after number in the commit message (boot-to-park ms
  from the ring stamps, image size, instructions on the secondary path). No number, no
  optimisation commit.
- Known candidates, in order of value: enable the MMU and caches before the timed
  loops (`l6` spin counts show the cores run uncached); release the seven cores before
  the splash paint so they come up in parallel with it; drop the 200 ms fixed wait for
  an ack-or-deadline loop; make `park()` a `wfi` on the timer interrupt instead of a
  poll.
- Never trade away a gate, a `--verify` check or a ring log line for speed.

## 7. Result line format (Flasher → orchestrator)

```
<id> <sha256[:16]> <PARK|DIED|REFUSED> probe=<mask> ack=<mask> el=<n> ring=<path>
```

PARK = ring complete through `park`. DIED = ring stops inside D4 (quote the last line).
REFUSED = fastboot re-enumerates within ~10 s.

## 8. Hard rules

- `fastboot boot` only. Never `fastboot flash` anything in this task.
- Never write `persist`, `modemst1/2`, `fsg`, `xbl`, `abl`, `tz`, or the GPT.
- One USB owner. One variable per image. One boot per question.
- A rung that will not build or will not `--verify` gets fixed, never substituted.
- Do not change the dtb section source, the DTB gate, `FB_STRIDE`, or the ring layout.
- Mark every claim VERIFIED (with the command) or HYPOTHESIS. Do not soften a failure.
- Commit as each piece stabilises; no single blob. Never commit under `refs/`.
