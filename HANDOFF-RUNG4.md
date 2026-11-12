# Handoff — rung 4: released cores never run our entry

For the next agent (Claude Code). Everything below is measured on the unit; nothing is
inferred from datasheets. Read `AGENTS.md`, `docs/STATUS.md` (the last section) and
`avicii/CONSTANTS.md` before touching anything.

## One-line problem

`PSCI CPU_ON` is accepted (`ret=0`) for every secondary MPIDR, but the released core never
reaches the entry point we hand it, and after the call the **whole SoC dies within
microseconds** — before the very next `say()`. This blocks the port: XNU needs the six A55s
and the second A76.

## Current device state

- Bootloader unlocked, slot **`b`**, LineageOS 21 + Magisk on `boot_b` — untouched all night,
  nothing flashed. Everything runs with `fastboot boot` (which **works**; the old "flash only"
  doctrine was wrong, see below). `boot_b` still restores in one command from
  `backup/64f70df8/boot_b.img` (`39ed8eea…`) if that ever changes.
- `persist`, `modemst1/2`, `fsg`, `xbl`, `abl`, `tz`, GPT: never touched.
- A ring write makes LineageOS land in **recovery** afterwards. Recovery adbd is root without
  a `su` binary, so `tooling/42-log-pull.sh` fails there (`su -c id -u`); pull by hand:
  `adb exec-out "dd if=/dev/block/sda16 bs=4096 skip=$(( $(adb shell blockdev --getsize64 /dev/block/sda16)/4096 - 1025 )) count=1025" > logs/ring.bin`
  then cut the 4096-byte header off and stop at the first NUL.
- A parked image self-resets after 60 s via HVC (works). `smc` PSCI reset never fires at EL2.

## What already works — do not re-walk it

Rungs 1, 2, 3, 5 are green, read from the ring, on this exact boot shape:

| rung | evidence |
|---|---|
| 1 GIC | `pidr2=0x3b` arch nibble 3, `typer=0x7b041d`, `gicv3 ok`, itlines sane |
| 2 UFS | `version=0x300` (HCI 3.0), `cap=0x1587031f`, `hcs=0x10f` DP set, PHY answering on `0x160/0x16c` |
| 3 splash | `0xa0000000` / `0x2300000`, `region matches`, painted 97 ms, panel goes magenta, `ruler stride=0x10e0` bars straight |
| 5 memory | three extents as tabled, `dram reaches above 4 GiB`, `RESULT mismatch=00` |

Boot chain facts you inherit (all fixed, all in the tree):

- The boot image's `dtb` section must be the **SoC base tree** `src/avicii-soc.dtb`
  (406620 B, `48b0902a…`), never the dtbo overlay `src/avicii-board.dtb` (620 fragments, no
  `qcom,msm-id`). The overlay is what refused every earlier image in ~6 s. `mkbootimg_v1.sh`
  defaults to the right file now and `--verify` fails on an overlay or a missing `msm-id`.
- `park()` waits 60 s (`60000 * freq`, `freq` in ticks/ms — was `60 * freq`, i.e. 58 ms).
- Console `FB_STRIDE` is `FB_W * 4` (4320 B); 4800 sheared every scanline 120 px.
- `start.S` carries `#if PARK_C1/C2/C3` entry-park variants, inert without `-D`.

## Rung 4 — exactly what was measured

`avicii/shim/diag.c`, `stage4()`; `avicii/shim/start.S`, `secondary_entry` + `sec_stub`.

1. **First version** passed the link-time symbol as the entry (`0x80054`). All seven `CPU_ON`
   calls returned `ret=0`, `ack mask=0`, and each `sec_spin[]` slot held a different non-zero
   value — cores released, entered somewhere, never acked. (`out-diag/l5`, `l6`,
   `0fc147dd…`/`0b305f26…`)
2. **Relocating the entry** the obvious way (`kimg_base + (uintptr_t)secondary_entry`) produced
   `0x14fd80054` = `2×base + off`: `kimg_base` read as `2×0xa7e80000` by then, even though the
   same run printed `load base=0xa7e80000` two lines earlier. (`out-diag/l9`/`l10`, `c007a0e9…`)
   Workaround in place: the offset is taken as a link-time difference,
   `kimg_base + ((uintptr_t)secondary_entry - (uintptr_t)_start)`, which yields the correct
   `0xa7e80054`. **The `2×base` mystery is still unexplained** and worth one look
   (`adr x9, secondary_entry` vs the value in the register, `shim.ld` link base 0).
3. With the correct entry the caller **hangs inside the first `CPU_ON`** (`0x100`).
   (`out-diag/l11`)
4. Replaced the target with a naked stub that only does `msr daifset` / `adr` / `str` / `wfe`
   — no stack, no vectors, no C. Still hangs. **So it is not our secondary code.** (`l11`)
5. Released **only `0x700`** instead of all seven: `CPU_ON` now **returns** (`ret=0`) and the
   run dies right after, before the next `say()` — even with the probe read moved ahead of the
   200 ms spin. (`l12` `7d860cbe…`, `l13` `51c3deb9…`)
6. Installed the exception vectors on the released core *first* (`vbar_el2`/`vbar_el1` chosen by
   `CurrentEL`) in case a null `VBAR` was sending it through address 0. Still dies at the same
   instant. (`l14` `ce42870a…`) **So the target code — including vectors — is ruled out; the
   death is in the release or in the state the core starts in, before our first instruction.**

Conclusion: the release itself, or the state the core starts in, is fatal. The address is no
longer in question.

`l15` (`0676f9b5…`, verify PASS, **not booted yet**) is the next measurement rather than another
target-side guess: it prints the caller's own `MPIDR_EL1` and releases only that core's sibling
(`caller ^ 0x100`), the one release that stays inside the caller's cluster. Read its ring like any
other; if the sibling also dies, cluster power is out and hypothesis 3 is next; if it acks, the
split is by cluster, not by code.

## Hypotheses, in the order to test them, with the discriminator for each

1. **Wrong execution state at the entry (AArch32 vs AArch64, or EL).** A core entering in
   AArch32 executes `msr daifset, #0xf` (A64) as garbage and can write anywhere → instant SoC
   death fits this well.
   *Discriminator:* before releasing anything, print `CurrentEL`, `HCR_EL2` (bit 31 = `RW`),
   `SPSR_EL2`, `SCR_EL3` if readable, and the **boot core's own `MPIDR`**. If `HCR_EL2.RW` is 0,
   either set it to 1 for the release or add a 2-instruction A32 trampoline and re-test. Print
   the same registers **on the secondary** from the stub (read-only, before any `msr`).
2. **The core does not come up in the EL we assume.** PSCI starts a secondary at the *caller's*
   EL; the shim is at EL2, so `vbar_el1`/`spsel` semantics differ from an EL1 caller. The stub
   currently sets no vectors at all — if hypothesis 1 is cleared, add `vbar_el2` and a stack
   before anything else and see whether the death moves.
3. **Cluster power.** `CONSTANTS.md:43-45`: `0x000-0x500` A55, `0x600` Gold A76, `0x700` Prime
   A76, all three on *different* `qcom,freq-domain`s. If the released core's cluster is not
   powered after ABL yields, `CPU_ON` can still "succeed" and the core then stalls or faults.
   *Discriminator:* release only `0x100` (same cluster as a `0x000` boot core?) and only
   `0x600`, and compare which ones return vs hang. Then read the APCS/RSC side: APCS RSC
   `0x18200000`, TCS `0x18200d00` (`CONSTANTS.md:73-75`), three drv blocks; a warm-up write
   (RPMh `WAKE`/`ACTIVE` on the cluster rail) may be required before the release.
4. **Coherency / stub writes.** MMU off means Device-nGnRnE for the caller *and* the secondary;
   a store to `.bss` from the secondary is the first thing the stub does. Test a stub that does
   no store at all (`wfe; b .` only) to see whether the death is tied to the write.
5. **Stack/cache state of the released core** — only relevant once a stub acks.

## Acceptance

1. `probe mask=0xfe` — all seven cores reach the stub and write their MPIDR into `sec_probe[]`.
2. Repoint `stage4` to `secondary_entry` (`vbar_el2` branch, per-core stack) and get `ack mask=0xfe`
   with a non-zero `sec_spin[]` for each core after the 200 ms window.
3. Then rung 4 is green and the ladder is complete.

## Reproduction, exactly

```sh
cd /home/tadej/ios-nord
adb reboot bootloader
fastboot devices                       # wait for the serial, it lags ~8 s
fastboot boot avicii/shim/out-diag/l13/shim-boot.img
```

Ring read: `adb shell` may be unauthorized for a few seconds and the phone lands in
**recovery**, not Android — use the exec-out `dd` above. `adb devices` showing
`unauthorized` means an "Allow USB debugging?" dialog is on screen: it needs a human.

Build a rung (always both `DTB` and `DTB_FILE`, both to the **soc** tree):

```sh
cd avicii/shim
DTB=/home/tadej/ios-nord/avicii/shim/hybrid/sections/dtb-stock \
DTB_FILE=/home/tadej/ios-nord/avicii/shim/hybrid/sections/dtb-stock \
DIAG_STAGE=4 DIAG_LOG=1 OUT=/home/tadej/ios-nord/avicii/shim/out-diag/<name> ./build.sh
../tools/mkbootimg_v1.sh --verify out-diag/<name>/shim-boot.img
sha256sum out-diag/<name>/shim-boot.img
```

`--verify` must PASS and the dtb section must hash to `48b0902a…` before booting; the packed
image hash goes into `docs/IMAGE_PROVENANCE.md` with the result. `DIAG_LOG=0` builds write
nothing to userdata.

Existing images worth booting as-is: `l13` (last, single core, immediate probe), `l12`
(single core), `l11` (stub, all seven), `l10` (relocated entry, all seven), `l9` (component
print), `l6` (full ladder as it stood), `dtbfix-park` (T1, entry park), `l0` (park in
`shim_main`). `out-diag/SHA256SUMS*` and `docs/IMAGE_PROVENANCE.md` carry every hash.

## Rules

- `fastboot boot` only. `boot_b` is the fallback; `boot_a` is the experiment slot if a flash
  ever becomes necessary (`fastboot flash boot_a`, never unslotted `fastboot flash boot`).
- One variable per image. A rung that will not build or will not `--verify` gets fixed, never
  substituted silently.
- Do not "clean up" the probe logging (`kimg=`, `sec_entry=`, `entry=`, `probe now=`,
  `DBG park …`) while rung 4 is open — it is the evidence.
- Do not change the dtb section source, the DTB gate, `FB_STRIDE`, or the ring layout as part
  of rung 4.
- The console is readable on the panel now; a photo of the screen is a valid second witness, and
  the ring is the first.

## Commits

`4428fb1` is the dtb-section fix + the ladder to rung 5 green + the console stride + four probe
fixes. The rung-4 work after it (`sec_stub`, `sec_probe`, EL2 vectors, relocated entry,
single-core probe) is uncommitted in the working tree on purpose — it is a live investigation,
so commit it as it stabilises rather than one big blob.
