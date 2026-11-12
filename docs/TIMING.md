# TIMING: is the ~6 s a refusal or a self-reset?

The blocker is stated as "the shim dies ~6 s in". Before any code can be blamed,
the 6 s has to be identified: **ABL refusing the image** (our code never runs) and
**our code running and resetting the phone** (ABL hands over, the shim faults,
PSCI or the watchdog brings the phone back) look identical on a bench and are
different problems with different next steps. They do not look identical on a
millisecond clock, because the first happens *before* hand-off and the second
*after* it.

This document is the measurement, `tooling/50-boot-timing.sh` is the instrument.
It needs no code on the phone, no working shim, and no panel.

## 1. What is measured

Per run, exactly one number: **milliseconds from the ABL hand-off to the phone's
next USB appearance**.

- **t0 is the USB node disappearing**, not the moment `fastboot reboot` returns
  (that is 100-300 ms early and noisy). The device dropping off USB is the
  hand-off or the refusal, whichever it is; the clock starts there.
- **t1 is the first `lsusb` sighting of the phone's own serial**, polled every
  ~20 ms, up to a 90 s timeout. Match is on the serial, not on a VID:PID, so it
  works for fastboot (`18d1:4ee0`), adb and anything else the ABL exposes.
- `adb kill-server` runs before every run. A live adb daemon holds the port and
  makes an appearing device look 1-3 s slower or missed entirely - the existing
  16.1 s control figure is an *adb* figure and includes exactly that cost, this
  harness is faster and also records *what* was sighted (fastboot vs adb).

The timeout of 90 s is deliberate: "no USB sighting inside 90 s" is the signature
of a core that parked, and it must be longer than any ABL retry or watchdog.

## 2. Expected signature per outcome

Thresholds are in the table; they come from the two measured controls in
`PROGRESS.txt:146-153` (stock 16.1 s to adb, our images ~6 s to fastboot, both
with the adb server killed) and from the ladder's own definition of a park
(`docs/BISECT.md:14-17`: a park is *no* re-enumeration for 90 s).

| outcome | who runs | first sighting | kind | adb later | expected spread |
|---|---|---|---|---|---|
| **ABL refuses the image** | nothing of ours | **< 2500 ms** | fastboot | never | tight; a refusal is a decision, not work |
| **our code ran and died** | our code, then a reset | **2500-10000 ms** | fastboot | never | tight *at a plateau*, not at 6.0 s exactly |
| **our code ran and parked** | our code, spins | **none in 90 s** | - | never | the phone stays off USB |
| **control: untouched stock** | stock kernel + Android | **> 12000 ms** | adb (composite) | yes | wide, depends on userspace |

Two things the table encodes that impressions do not:

* **Refused and ran-and-died are separated by *when*, not by *whether*.** Both end
  in fastboot with no adb. A single run cannot tell them apart with certainty;
  five runs can, because the refusal plateau sits below 2.5 s while no reset path
  on this SoC gets back to a USB device that fast (ABL itself needs ~1.5-2 s just
  to bring its fastboot interface up, *after* its decision).
* **The park row is the one that matters most.** If any image produces no
  sighting at all, code executed and the port is unblocked: the remaining work
  becomes "why did it park instead of booting XNU", not "why is it refused".

### What invalidates a run

- The sighting kind is `other` (a charging-only or descriptor-less enum): note
  it, do not classify on it.
- `flash` prints an error, or the device never leaves USB: the run is void,
  `runs.tsv` records `NA` and the summary ignores it.
- Battery below 20 %: a re-enumeration can be slower. Record the level.

## 3. Protocol

Everything below is literal, one command per line. The phone must be in fastboot
and the current slot must be **b** (the experiment slot since `boot_a` lost its
metadata, `docs/STATUS.md`).

Gate: the image must pass `--verify` (the script refuses to flash otherwise) and
its sha256 goes into `docs/IMAGE_PROVENANCE.md` before the run.

```sh
bash tooling/00-check-host.sh
```

```sh
fastboot devices
```

```sh
fastboot getvar current-slot
```

Expect `_b`. Set it back if a failure flipped slot a:

```sh
fastboot --set-active=b
```

Control first, five runs (this also calibrates the harness on this unit today):

```sh
bash tooling/50-boot-timing.sh --control --runs 5
```

Then the image under test, five runs:

```sh
bash tooling/50-boot-timing.sh --image out-telem/stage-6/shim-boot.img --runs 5
```

A parked phone does not come back to fastboot; the script says so and stops.
Power-cycle (hold power ~10 s) and continue the remaining runs by hand with
`--no-flash` after re-flashing once.

Interleave the two series if the whole set is being done in one sitting
(control, image, control, image...): a run takes ~25 s and the phone warms up
under 3 consecutive boots, which is the largest single confounder.

Restore before finishing:

```sh
fastboot flash boot_b backup/64f70df8/boot_b.img
```

## 4. Reading the numbers

`out-telem/timing/<stamp>/` holds `runs.tsv` (one row per run), `ms.txt`,
`summary` (n, min, median, max, mean) and `verdict`.

1. **Hard gate: the control series must reproduce > 12000 ms** with `kind=adb`.
   If the control itself lands in fastboot, the flash path or the slot is wrong
   and no shim number means anything yet.
2. Compare *medians*, never single runs, and quote min/max.
3. If the image's median is < 2500 ms → **refused**. Next move: the packer, not
   the shim (a `for(;;) wfe` two instructions in has already been refused; see
   `docs/BISECT.md`).
4. If the image's median is 2500-10000 ms and the spread is small → **ran and
   died**. Next move: the early-boot crash; the IMEM record and IMEM `w14 - w6`
   give the alive time and the last step (`docs/TELEMETRY.md`).
5. If the image produces no sighting in 90 s → **ran and parked**. The port
   executes; telemetry rungs are now measurable, then the payload.
6. If the image reaches `adb` → it booted. That is the goal state for the shim.

A median that sits between two rows, or a spread wider than 40 % of the median,
means the series is confounded (slot, battery, thermal, cable) - repeat it
before drawing a conclusion. Do not round 6.0 s and 6.4 s into "the same 6 s"
without the plateau: the plateau *is* the claim.

This harness is the *state* instrument and stays valid whatever the packer does.
`avicii/build/MATRIX.txt` is the complementary *shape* instrument (stock control
vs footer-only vs our packer at stock shape vs park payload): if a matrix image
refuses, run it through this harness before and after the shape fix, and the
plateau will say whether the fix moved the state at all.

## 5. What this cannot tell you

- It cannot say *where* code died, only that it ran. That is `docs/TELEMETRY.md`.
- It cannot see a reset that never re-enumerates USB (the phone reboots into a
  dead state): that also reads as "parked". The IMEM record separates them.
- It does not work over `fastboot boot` - this ABL drops back 4/4 on that path
  (`docs/STATUS.md`), so every run flashes `boot_b`.
