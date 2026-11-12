# TELEMETRY: evidence that survives a refusal

The panel is a command-mode DSC panel and shows no console text after hand-off,
the UFS ring has never produced a byte because its init is behind the code that
never runs, and the shim dies at a fixed ~6 s. Everything that needs an
initialised controller is therefore downstream of the question, and the question
is upstream of everything: **does the CPU reach our code at all?**

This is the ladder that answers it without the console, the ring or a working
boot, in order of cost, plus the readback for each. `docs/TIMING.md` is the
zero-code half of the same question and stays the cheapest instrument; this
document is what to do when the timing plateau is ambiguous or a reset is slow.

Rungs are `DIAG_STAGE=6`, `7`, `8` (`avicii/shim/diag.c`), cumulative, each
gated in `avicii/shim/tel.h`. They are ordinary boot images: header v1,
`Image.gz-dtb`, built by `avicii/shim/build.sh`, all `--verify`-PASS.

## 0. The channel: IMEM

Every rung writes the same 16-word record first, at **IMEM + 0xb00**
(`0x146abb00`), outside every child the DT declares, and mirrors the same magic
into `restart_reason` (`0x146ab65c`). No MMU, no DMA, no clock vote: a
handful of aligned stores into always-on SRAM that the ABL, the SBL and the PSCI
firmware keep for exactly this purpose.

Record layout, codes and the self-check are in `tel.h`. In short: magic
`0x4c455431` ("1TEL"), stage, a mark sequence, **the last step code**, the load
base ABL used, two timestamps, and a verdict word. The last code names the step
that was running when the phone went; `w14 - w6` gives how long the image lived
in 19.2 MHz ticks.

Guarantees and non-guarantees, stated before anything is measured:

* The record is written and then **read back while running**, and the comparison
  is stored. A record whose verdict is `0xdead` is an address that is not
  writable and must not be trusted.
* The ABL has no documented use for `0xb00`. It *does* use `restart_reason`, and
  may rewrite or consume it on the next boot, so the record is primary and
  `restart_reason` is corroboration. Section 4 measures that survival instead of
  assuming it.
* `0x77665500` ("boot to recovery") is deliberately *not* written: the record
  magic is not a boot mode, so the next boot is an ordinary boot to the log host.

## 1. Ladder

Cost is what the rung risks on a phone that has not yet executed a single
instruction of ours: stores into SRAM, then pad-block writes, then an arbiter
transaction, then a controller bring-up. Each rung marks itself *before* the
step it is about to take, so a hang names its own last step.

| # | rung | signal | cost | expected signature for "code ran" | for "code never ran" |
|---|---|---|---|---|---|
| 0 | `tooling/50-boot-timing.sh` | ms to next USB sighting | none (no code) | 2500-10000 ms plateau, or no sighting at all | < 2500 ms to fastboot |
| 6 | `stage-6` (IMEM) | record + `restart_reason` | 20 SRAM stores, one `dsb` | magic + `0x600d` verdict at `0x146abb00` | all zero, `restart_reason` unchanged |
| 7a | `stage-7` GPIO | TLMM pad pattern, gpio 71+70, 8 pulses | 8 pad-block write pairs, ~1.6 s | `w9` = `0x00000203` (func 0, OE, pull) | `w9` = 0 or `0xffffffff` |
| 7b | `stage-7` SPMI | PMIC revids in `w11` | arbiter read transactions | plausible revid per PMIC | `w10` = 0 / `0xffffffff` |
| 7c | `stage-7` panel reset | PM8150L gpio 3 pulse | 2 SPMI writes, ~30 ms | **screen goes black and stays black** | screen keeps the splash |
| 8 | `stage-8` haptic | AW8697 buzz, 3 x 300 ms | GCC vote, SE0 bring-up, ~1.9 s of I2C | 3 felt buzzes, `w12` ack bits | silence, `w12` = 0 |

Notes that decide whether a rung is worth its cost:

* **The motor is not on the PM8150L.** `aw8697_haptic@5A` sits on
  `qupv3_se0_i2c` (gpio 42/43) with `reset-gpio = <&tlmm 71>` (`mtp.dtsi:119-142`);
  the PMIC is used for the *panel* reset, which is why 7c is a black screen and
  not a buzz. Rung 8 is a GENI-I2C bring-up, the most expensive thing here and
  the most likely to hang, so it is last and everything above it is the fallback.
* **SPMI is reachable this early** - the arbiter is plain MMIO at `0xc440000` and
  we are EE 0 (`qcom,ee = <0>` in the live FDT), so no UFS, no PHY and no DMA are
  involved; only the observer/command registers. Whether the *slave* answers is
  the measurement. Rung 7 must prove that before 7c is trusted, and stops if the
  arbiter version is implausible.
* **A GPIO toggle alone is not visible**: no LED on this phone, and the chosen
  pads are the haptic's reset and IRQ. Its value is `w9` (does the pad block
  answer) plus a scope/multi-meter beep count of 8. The human-visible rungs are
  7c (screen) and 8 (motor).
* **7c costs the splash** - the panel is not re-initialised, so it stays black.
  That is why it is the last step of rung 7 and why the record is already fully
  written by then.

## 2. Build and gate

```sh
. tooling/env.sh
```

```sh
cd avicii/shim
```

```sh
DIAG_STAGE=6 OUT=../../out-telem/stage-6 DTB=../../src/avicii-board.dtb ./build.sh
```

```sh
cd ../..
```

```sh
avicii/tools/mkbootimg_v1.sh --verify out-telem/stage-6/shim-boot.img
```

Last line must be `PASS`. The images already built and verified on
2026-11-12, sha256 in `out-telem/SHA256SUMS`:

| image | stage | ring | sha256 |
|---|---|---|---|
| `stage-6` | 6 | yes | `8429032133608bf3a3740dd5ccb0d77ab2eda8a1723001cce2e67c75f554edca` |
| `stage-6-ro` | 6 | **no writes at all** | `f65665c69a986906f0d5e37b4e2abc7a8937c18b201db47c42c518061cdb773d` |
| `stage-7` | 7 | yes | `22165dc07adcd2b8a657e5a46988af7b93cd6f00f7f6d1cecc097437ad5b5cc8` |
| `stage-8` | 8 | yes | `b0dc568409bce492e418f535614d1860c53c0bd2f1819adf33d313cfff4f9af5` |
| `anchor-park` | 6 + `-DPARK_AFTER_ENTRY`, ring off | - | `b005174a5f0f6ff7068167365fe381a8fbacb1f454fb7891672e1eccb0818f35` |
| `anchor-refuse` | `stage-6` with the gzip magic broken | yes | `e3a5372769c395870150ed9b9f11154506ab7c4570a90cc7bdb16660da814674` |

The two anchors are the §5 controls: `anchor-park` parks in `start.S` before any
C, `anchor-refuse` is byte 0x1000 of `stage-6` flipped from `1f` to `1e` so the
kernel section is neither gzip nor a raw Image - it therefore **fails `--verify`
on purpose**, so it is flashed by hand and timed with `--no-flash` (§5 E1).

`stage-6-ro` is the one to boot while the write question is still open: it writes
only IMEM, never `userdata`. Rung 6 is deliberately the same in both.

## 3. Readback

Two channels, and the split is the point.

**Needs a normal boot afterwards** (nothing at fastboot time can read IMEM -
`fastboot` has no memory-read command on this ABL):

```sh
tooling/51-imem-read.sh
```

Decodes the record, prints the last step by name and a verdict. Exit 3 =
`/dev/mem` refused (`CONFIG_STRICT_DEVMEM`); then:

```sh
adb shell su -c 'toybox devmem 0x146abb00'
```

```sh
adb shell su -c 'dd if=/dev/mem bs=4 skip=85634752 count=16 | od -An -tx4'
```

The UFS ring, once something proves the code path, still comes from the same
place as always:

```sh
tooling/42-log-pull.sh
```

**Needs no boot at all** (fastboot is up, phone is not):

```sh
bash tooling/50-boot-timing.sh --image <img> --runs 5
```

```sh
fastboot getvar all
```

**Needs a human at the device** (no readback exists): the screen going black
(7c) and the buzzes (8).

## 4. Interpretation table

`w3` is the last step code, not a claim about the whole run: a record with a high
code and a `0x600d` verdict is *proof of execution*; a record with a high code
and a `0xdead` verdict is proof of a run at an address whose content cannot be
believed.

| what you see | meaning | next move |
|---|---|---|
| nothing at `0x146abb00`, `restart_reason` unchanged, fastboot < 2.5 s | **refused**: no code ran | the packer, not the shim (`docs/BISECT.md`) |
| nothing at `0x146abb00`, fastboot 2500-10000 ms | code ran, but not the 20 stores; something before `tel_mark` faults | `start.S`/prologue; try the `PARK_AFTER_ENTRY` anchor (§5, E2) |
| magic + `0xdead` | record address not writable | re-read at `restart_reason` only; fix the offset before trusting anything |
| magic + `0x600d`, `w3` = `0x0600`-`0x0601` | executed, died in the record write | SError/SKU issue on IMEM, not the ladder |
| magic + `0x600d`, `w3` = `0x0604`/`0x0605` | **rung 6 complete**: the panel-clear or the ring killed it | panel path (`con_clear`) or `dlog_init` (UFS), in that order |
| `w3` = `0x0700`-`0x070a` | TLMM/SPMI rungs, no UFS involved | read `w9`,`w10`,`w11`: pad block and PMIC are separately decidable |
| `w3` = `0x0800`-`0x080f` | haptic already; the CPU, pads, clocks and I2C path all work | the bug is in the buzz sequence (register map) |
| `w3` = park code, phone still off USB after 90 s | **ran and parked** | success of the measurement; proceed to payload |
| record present but `w5:w4` base is odd/unaligned | ABL loaded us somewhere the header did not ask for | packaging |
| control run in fastboot instead of adb at 16 s | slot, flash path or battery - not the shim | fix, then repeat |

Every row is decided by data. Nothing in the table is "flash it again and see".

## 5. The three states, separated

Three states have to be told apart: **refused**, **ran and died**, **ran and
parked**. Each experiment below is exactly two boots; the first produces the
state, the second reads it. The second boot is always the same:

* B2: power-cycle into fastboot, `fastboot reboot`, wait for adb, run
  `tooling/51-imem-read.sh` **first thing** (before anything else touches the
  phone), then restore `boot_b`.

The pair matters because a reset and a refusal can share a fastboot timestamp,
and the record is what breaks the tie. Run them in this order: the two anchors
first, so a later ambiguous number has something to be compared with.

B2 is *always* these four commands, in this order - `boot_b` still holds the
image under test at that point, so the fallback has to be put back **before** the
normal boot, and the flash does not run our code:

```sh
fastboot devices
```

```sh
fastboot flash boot_b backup/64f70df8/boot_b.img
```

```sh
fastboot reboot
```

```sh
tooling/51-imem-read.sh
```

The one race in the whole design: the ABL is already running when the power
cycle reaches fastboot, and may clear IMEM at its own start. E5 measures that;
the record at `0xb00` is chosen to be outside what any bootloader writes.

**E1 - refusal anchor.** Image that *cannot* execute: `anchor-refuse`, which is
`stage-6` with the gzip magic byte flipped (`1f` -> `1e`), so the kernel section
is neither gzip nor a raw Image and the ABL cannot unpack it. It therefore
**fails `--verify` on purpose**, which is why it is flashed by hand and then
measured with `--no-flash`:

```sh
fastboot flash boot_b out-telem/anchor-refuse/shim-boot.img
```

```sh
bash tooling/50-boot-timing.sh --image out-telem/anchor-refuse/shim-boot.img --no-flash --runs 5
```

Expected: fastboot < 2500 ms, and after B2 **no record**. That number and that
empty record are the definition of refused on this unit.

**E2 - park anchor.** `anchor-park` (`-DPARK_AFTER_ENTRY`, start.S `wfe` before
any C, `docs/BISECT.md` §1). Measured the same way as any verified image:

```sh
bash tooling/50-boot-timing.sh --image out-telem/anchor-park/shim-boot.img --runs 1
```

Expected: **no sighting for 90 s**, record absent (no C ran), `restart_reason`
unchanged. This is the "parked" definition with no telemetry code involved, and
it is the control for E3's absent-record row. `--runs 1` because a parked phone
has to be power-cycled by hand anyway.

**E3 - the discriminator.** `stage-6-ro` - ring off, so the only write is IMEM and
a `userdata` change cannot confuse a later readback:

```sh
bash tooling/50-boot-timing.sh --image out-telem/stage-6-ro/shim-boot.img --runs 5
```

Outcome drives everything:

| A1 result | B2 readback | state |
|---|---|---|
| no sighting 90 s | record present, `0x600d` | **ran and parked** (rung 6 done) |
| no sighting 90 s | record absent | ran, parked before the record; go to E2/B2 for the prologue |
| fastboot 2500-10000 ms | record present | **ran and died**, and `w3` names the step |
| fastboot 2500-10000 ms | record absent | ambiguous: compare with E1 and E2; if closer to E1's plateau it is a refusal, and repeat with the IMEM write moved earlier in `start.S` |
| fastboot < 2500 ms | record absent | **refused** |
| fastboot < 2500 ms | record present | refused *after* running: packaging or verification after hand-off, a packaging bug with proof of execution |

**E4 - human confirmation**, only after E3 says ran: `stage-8` on `boot_b`.
Three buzzes and a black screen mean the whole cheap stack works. No readback is
needed for the observation, and the record still carries the codes.

**E5 - survival calibration**, once, when the phone is healthy: read
`0x146ab65c` and `0x146abb00`, boot stock twice, read both again. If the ABL
clears `restart_reason` but leaves `0xb00`, the record is the only channel and
`restart_reason` is decoration. If it clears both, read the record from the
*first* fastboot prompt instead (before a normal boot) with a second phone-side
helper, and say so here.

## 6. Limits

* The record says **how far**, never **why**. The why is `w3` plus the code that
  step runs.
* Rung 8's register map is the awinic driver's, **unverified** on this unit; its
  ack bitmap (`w12`) is data, the buzz is the claim.
* `0xb00` is chosen to be outside every DT child, not by measurement - the
  self-check is what makes that honest. If `w7` = `0xdead`, believe the address
  problem before the content.
* Nothing here is destructive: IMEM is SRAM (not a partition), `userdata` is only
  written by the ring, and `boot_b` is the restore target that already exists
  (`backup/64f70df8/boot_b.img`).
