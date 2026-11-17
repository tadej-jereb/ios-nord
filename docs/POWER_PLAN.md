# Power plan for avicii — static audit of kern-0150

Baseline: `fork/kern-0150`, commit `0b457c4`. Tracks A/B/C ran in parallel with
coordinator track D. Only this plan and `docs/power/*.md` are deliverables; no
kernel changes, builds, phone/VM access, root-image mounts or experiments were performed.
Patch sketches below are **UNVERIFIED design**, not applied or tested patches.

## Evidence rules and source locations

Every non-vendor-DTS/non-live assertion, including source-code behavior, prior-port
results, estimates and proposals, is **UNVERIFIED** on avicii. This applies to all
rankings, sketches, expected output and acceptance targets below. A citation proves
what a source says, not that the behavior works on this phone. No battery-life
percentage is established by this audit. Numeric test durations and thresholds are
proposed policy, not hardware constants.

Repository citations use `path:line`; a following `:line` uses the same file.
`refs/` and `build/` refer to read-only inputs under `/home/tadej/ios-nord`, absent
from the clean worktree. `/home/tadej/xnu-8796.141.3` is the local base source;
project patch files are authoritative for kern-0150 deltas. Appendix A records
pinned vendor-driver sources; appendix D defines canonical-XML line numbers for
binary root-image plists. New sysctl names below are proposals unless explicitly
identified as existing. Historical docs are supporting records, not fresh live reads.

## Current state and corrections to the task premise

| Subsystem | Evidence and implication |
|---|---|
| CPU topology | Vendor DTS assigns six A55s to domain 0 and the two A76s to domains 1/2 (`avicii/lito.dtsi:62`, `:222`, `:249`; `avicii/CONSTANTS.md:43`). Keep DVFS domains distinct even if scheduling groups the A76s together. |
| CPU and L3 control | **UNVERIFIED:** 0116 supersedes the 0115-only premise: CPU and L3 default to top-row requests, and existing runtime `kern.sweet_cpufreq_cap`, `kern.sweet_l3_cap`, `kern.sweet_bind` already exist (`xnu-avicii/patches/0116-avicii-cpu-placement-l3.patch:35`, `:90`, `:187`). |
| Observer load | **UNVERIFIED:** reading `kern.sweet_cpufreq` runs timed busy sampling and binds a dependent loop onto each CPU; it must stay outside energy windows (`xnu-avicii/patches/0116-avicii-cpu-placement-l3.patch:216`, `:275`, `:293`). |
| Battery | **UNVERIFIED:** 0062 has an optional PM6150-oriented SPMI/QG implementation as well as the fixed fallback; adapt that integration instead of adding a competing battery service (`xnu-avicii/patches/0062-sweet-touch-power-battery.patch:475`, `:720`). Avicii's PM7250B selection and driver conversion audit are in appendix A. |
| Display | **UNVERIFIED:** power-off is a pixel fade, followed by a continually rearmed software vsync; it does not power the panel down (`xnu-avicii/patches/0079-sweet-display-power.patch:9`, `:38`, `:53`). Dirty-copy suppression already exists (`xnu-avicii/patches/0056-sweet-fb-throttled-present.patch:33`). |
| GPU | Vendor bin-0 lowest active clock is 275 MHz (`avicii/CONSTANTS.md:316`; pinned DTS in appendix D). **UNVERIFIED:** its HFI index is 1, DTS index 3; `sweetgpu=11` is a bring-up stage. The default HFI request already uses the lowest active speed and holds GX powered (`xnu-avicii/patches/0122-avicii-gpu-a620-gmu-boot.patch:720`, `:741`, `:775`, `:790`). |
| DDR and caches | **UNVERIFIED recorded measurements:** inherited DDR vote gives 3850 MiB/s versus 370 on release; own IB-only vote regresses about 15% (`docs/STATUS.md:36`). Keep inherited DDR vote and `sweetddr` off. CPU L3 is a separate devfreq block (`avicii/lito.dtsi:1778`), not the RPMh LLCC SH0 voter (`xnu-avicii/patches/0128-avicii-rpmh-ddr-llcc-bcm-votes.patch:126`, `:185`). |
| Metal/GLES | **UNVERIFIED:** main-checkout `docs/METAL_PLAN.md:64` and `:65` record probe/device tests, while `:68` still lists backboardd integration as pending. A620 compositor battery gains are not established by another GPU's frame-rate result. Compare CPU/GLES/Metal only when each renders the same correct content. |

## One ranking across all tracks

Expected gains are **UNVERIFIED** mechanisms or bounds, not measured whole-device savings.
S/M/L mean relative implementation effort, not elapsed promises. Measurement is a
mandatory prerequisite; the top three *power reductions* are numbered 1–3.

| Rank | Exact change | Expected gain and reasoning | Risk | Effort / before-after measure | Evidence |
|---|---|---|---|---|---|
| 0 | Read-only avicii fuel-gauge adapter, passive CPU/wakeup/frame counters | No direct saving; enables signed battery power and avoids tuning blindly | SPMI arbitration, stale/wrong-sign readings, fake SOC | M; compare with vendor baseline, freshness and unplug sign | `xnu-avicii/patches/0062-sweet-touch-power-battery.patch:475`; appendix A |
| 1 | Validated per-domain CPU caps; later idle-accounting governor | Reduced active dynamic power if voltage/frequency fall; unknown total watts and possible longer execution time | UI stutter, invalid LUT rows, thermal clamping confused with policy | S–M; paired power, per-domain residency and frame-tail latency | `xnu-avicii/patches/0116-avicii-cpu-placement-l3.patch:141`; appendix B |
| 2 | Adaptive USB polling, then interrupt-driven idle | Reduce empty USB polls from nominal ~1000/s toward ~250/s with proposed 4 ms empty-poll ceiling; up to 75% fewer such polls, not a whole-device power percentage | USB/SSH latency, event-ring races, lost recovery channel | M; idle-poll counts, event latency, SSH/replug stability, power | `docs/power/C-idle.md:41`, `:54` |
| 3 | Quiesce display software timer after off fade; rearm on on | Nearly all display timer callbacks removed during sustained off residency; unknown watts | Lost wake notification, SwapWait timeout, black-screen resume | S–M; off callback count, repeated lock/unlock and power | `xnu-avicii/patches/0079-sweet-display-power.patch:53`; appendix D |
| 4 | Confirm and exclude one optional costly launchd job at a time | Its measured CPU/wakeup contribution; zero if already dormant | Client retry storms, lost media/update/pairing features | S; per-PID CPU-time deltas and launch counts | `docs/power/D-devices.md:91` |
| 5 | Touch/key polling backoff and safe timer coalescing | Fewer nominal 100/s touch, 50/s key polls while quiet; unknown watts | Missed first touch, key-combo latency | M; wake histogram and edge/long-press latency | `docs/power/C-idle.md:43` |
| 6 | Real DSI panel sleep and brightness policy | Physical panel/DSI savings beyond black pixels; unknown magnitude | DSC/ULPS/rail resume failure, display loss | L; paired off current and repeated resume | `avicii/panel.dtsi:193`, `:903`, `:908`; appendix D |
| 7 | Complete and measure Metal compositor / remove avoidable CPU frame work | Lower CPU work per correct frame, conditional on implementation; no A620 saving measured | Rendering defects, GPU hangs | L; identical warmed GLES/Metal scenes, CPU time, power and presented frames | main-checkout `docs/METAL_PLAN.md:64`, `:68`; appendix D |
| 8 | L3 cap independent of CPU policy | Potential cache-clock saving versus increased memory stalls; can worsen energy/frame | Latency/bandwidth regression | S; separate cap sweep with DDR unchanged | `xnu-avicii/patches/0116-avicii-cpu-placement-l3.patch:27`, `:41`; appendix B |
| 9 | GMU-mediated idle/slumber and resume | Idle GX power reduction, unknown magnitude; already at lowest active clock | Full hang, lost context, DMA/fence failure | L; idle residency, failures, first-frame latency | `xnu-avicii/patches/0122-avicii-gpu-a620-gmu-boot.patch:790`; appendix D |
| 10 | CPU retention, then core/cluster collapse and AMP | Potential deeper idle and background placement savings, unknown magnitude | GIC/timer/context loss, incompatible scheduler topology | L; residency and wake tests only after timer/GIC audit | `docs/power/C-idle.md:11`; `docs/power/B-cpu.md:100` |
| Defer | DDR/LLCC frequency reduction | No supported gain while an inherited higher floor remains; never release it | Severe throughput/UI/USB regression | Research only; inspect ownership and demand, no vote mutation | `docs/STATUS.md:36`; appendix D |

## Measurement protocol

Use appendix A's full read-only fuel-gauge/charger map and procedure. First validate
units, sign, freshness and charger status; raw voltage-derived percent is not charge
integration. Keep unknown SOC/charge invalid rather than publishing fabricated capacity.
A static audit cannot supply a calibrated avicii power baseline.

All following steps are **future operator procedures**, not actions performed here.
Read-only observation needs no destructive gate. Any later candidate installation,
root overlay or active policy change needs its explicit gate and a SHA256/provenance
record before it runs; preserve the fallback slot and inherited DDR vote. There are
no flashing or protected-partition commands in this plan.

1. On the current iOS kernel, capture the existing log and battery service before any
   policy change. Tool availability is **UNVERIFIED**; appendix A has fallbacks.

```sh
sysctl -b kern.sweetlog
```

```sh
ioreg -r -c SweetBattery -l
```

```sh
ps -A -o pid,time,comm
```

Expected **UNVERIFIED** result: existing CPUFREQ and display records plus either the
fallback power-source values or optional battery-service properties, not new FG sysctls
(`xnu-avicii/patches/0116-avicii-cpu-placement-l3.patch:155`;
`xnu-avicii/patches/0079-sweet-display-power.patch:73`;
`xnu-avicii/patches/0062-sweet-touch-power-battery.patch:720`).

2. After a separately reviewed read-only gauge/counter candidate is installed and
   validated, record monotonic timestamps, valid voltage/current, charger input status,
   sample age and raw bytes at a proposed 1 Hz. Cache reads in a worker; reading a
   sysctl must not initiate long synchronous SPMI traffic or timed CPU busy loops.
   The proposed common snapshot `kern.sweet_power_stats` and gauge
   `kern.sweet_fg.sample` are contracts to implement, not existing commands.

```sh
sysctl kern.sweet_fg.info kern.sweet_fg.sample kern.sweet_fg.errors
```

```sh
sysctl kern.sweet_power_stats
```

Expected **UNVERIFIED schema**: `valid=<mask> age_ns=... voltage_uv=... current_ua=...
usb_present=... soc_valid=... charge_valid=...`; current uses a documented sign,
positive out of the battery (discharge-positive). `charge_valid=0` is correct until a calibrated estimator
or genuinely supported charge source exists. Counters include per-domain requests,
busy/idle time, IRQs/polls, display callbacks/copies, presented frames, GPU waits and
errors. No plausible-looking numeric battery values are prescribed.

3. Compare steady screen-on idle, steady screen-off, the same lock-screen animation,
   and the same warmed compositing workload in GLES and eventually Metal. Use fixed
   brightness/content, identical USB/charging state, similar SOC and temperature,
   warm caches and the same logging settings. Record cold shader compilation separately.
   Proposed policy: settle for 60 seconds, collect 300-second steady windows and
   repeat A–B–A at least three times. Keep fast UI pacing during animations.

4. Connected USB measurements are battery **net charge/discharge**, not total handset
   power. For battery drain, log locally with USB disconnected and retrieve after the
   window; do not leave SSH sampling or UDP streaming active in just one variant.
   An external USB meter measures input power and needs charger/efficiency accounting.
   Integrate signed `V*I` over timestamped intervals; report mWh/window and energy per
   correctly presented frame, CPU time, wakeups, median/p95/p99 frame intervals and
   temperature. Accept a saving only above repeated-run spread with no material
   smoothness/input/USB regression. Proposed UI gate: p95 frame interval no more
   than 5% worse than baseline, no missing glyphs/frames, no new hangs/timeouts.

5. Keep `kern.sweet_cpufreq` and `kern.sweet_bwtest` outside timed windows: the former
   actively measures clocks/loops and the latter executes a memcpy benchmark
   (`xnu-avicii/patches/0116-avicii-cpu-placement-l3.patch:275`, `:293`;
   `xnu-avicii/patches/0128-avicii-rpmh-ddr-llcc-bcm-votes.patch:132`).

### Gauge and battery UI implementation detail (measurement prerequisite)

Vendor selection is PM7250B QG and charger (`avicii/mtp.dtsi:287`, `:321`),
with SID2/QG0x4800 and charger subperipheral bases in pinned
`arch/arm64/boot/dts/vendor/qcom/pm7250b.dtsi:11`, `:27`, `:60`, `:81`, `:100`,
`:222` (full source mapping in `docs/power/A-measure.md:7`).
These new constants need review/cataloguing in CONSTANTS.md before implementation;
this documentation task does not edit that file. Driver offsets/conversions below
remain **UNVERIFIED** and are not promoted to vendor-DTS facts.

| Read-only acquisition | Driver evidence at Lineage commit pinned in appendix A | Validity constraint |
|---|---|---|
| QG type/subtype, present/OK | `drivers/power/supply/qcom/qg-reg.h:9`, `:17` | Fail closed on unsupported revision/subtype. |
| QG +0xc0 voltage word | `qg-reg.h:108`; `qg-util.c:466`; `qg-defs.h:34` | Little-endian raw ×194637/1000 µV; matching reads do not establish conversion freshness. |
| QG +0xc2 signed current word | `qg-reg.h:109`; `qg-util.c:123` | Signed raw ×152588/1000 µA (subtype3) or ×305176/1000 (subtype4); live sign/cadence unproven. |
| USBIN +0x10, DCDC +0x0b, CHGR +0x06/+0x07/+0x0d | `smb5-reg.h:251`, `:153`, `:30` | Distinguish plug-in, selected valid input, charge phase and errors. Cable present alone is not charging. |
| Charge/SOC | `qpnp-qg.c:1761`, `:1799` | Linux uses software/profile state, not a self-contained readable coulomb counter. Report invalid until calibrated. |

**UNVERIFIED sketch:** extract existing observer-read support into a shared,
serialized, allow-listed SID2 helper; add `bsd/dev/sweet_fg.c` with a bounded
cached acquisition worker, raw bytes, monotonic sequence/time and validity/error
masks. Expose read-only `kern.sweet_fg.info`, `.sample`, `.errors`. No HOLD,
status-clear, ADC configuration, FIFO, SDAM or charger-policy writes. Linux's
current getter uses a HOLD write and its `qg_read` can clear sticky state;
copying those calls would violate read-only scope
(`docs/power/A-measure.md:37`; full pseudo-diff `:41`).

Update the existing SweetBattery class from that cache; do not register a second
power source. Preserve `IOPMPowerSource` setters/`updateStatus`, with consistent
units and explicit validity; do not carry over PM6150 nominal capacity or generic
voltage-percent curve. Accurate battery percentage requires profile/calibration
work beyond voltage/current telemetry. Powerd/SpringBoard consumption must be
verified in IORegistry and visible UI during cable changes; exact private ABI is
not proven by static plist inspection (`docs/power/A-measure.md:78`, `:80`, `:82`).

## Concrete sketches for the top three reductions

All sketches target the post-series kern-0150 files and are **UNVERIFIED
pseudo-diffs**, not compilation-ready patches. Deployment, later builds and
experiments belong to the operator's separately gated workflow. Each candidate
gets independent boot/runtime opt-in and counters; change one policy at a time.

### 1. Validated CPU caps, then scheduler-idle governor

Basis: 0116 `osm_probe`, `osm_request`, domain cache and cap sysctl
(`xnu-avicii/patches/0116-avicii-cpu-placement-l3.patch:83`, `:99`, `:141`, `:314`).
Current capped row selection lacks full eligibility validation; alternate-clock
rows cannot be treated as zero-frequency OPPs (`docs/power/B-cpu.md:16`, `:14`).

```diff
--- a/bsd/dev/sweet_cpufreq.c
+++ b/bsd/dev/sweet_cpufreq.c
@@ domain state and osm_probe
+ cache eligible rows sorted by decoded frequency, not row-index assumption
+ reject terminator, invalid source/rate and rows lacking full-domain core support
+ retain current validated request if LUT/alternate-clock decoding is unknown
+ domain_cap[3]; requested-row residency; one serialized policy owner
@@ osm_request and cap handlers
- choose min(top, cap) without validating that capped row
+ validate all requested row ceilings before any multi-domain request
+ choose eligible frequency under ceiling; reject invalid cap with EINVAL
+ update request-time residency; ordered PERF_STATE write/readback on change only
+ add kern.sweet_cpu_cap0, cap1, cap2 (validated RW) and sweet_cpu_stats (passive RD)
+ keep L3/DDR unchanged during CPU experiment; preserve boot defaults until opt-in
```

**Expected gain:** lower active CPU dynamic power when delivered frequency and
voltage fall; watts and whole-device percent unknown. Longer busy time can erase
energy savings. Preserve prime initially because presenter binding targets CPU7
(`docs/power/B-cpu.md:10`, `:22`). Do not write voltage tables or PLLs.

1. Existing-kernel discovery, outside timed windows:

```sh
sysctl kern.sweet_cpufreq
```

```sh
sysctl kern.sweet_cpufreq_cap kern.sweet_l3_cap
```

2. Once the validated-cap candidate exists, record proposed passive interfaces:

```sh
sysctl kern.sweet_cpu_stats
```

```sh
sysctl kern.sweet_cpu_cap0 kern.sweet_cpu_cap1 kern.sweet_cpu_cap2
```

3. **Gate before a frequency mutation:** operator records image SHA256/provenance,
   old caps and requests, confirms a lower full-core eligible row in domain0 from
   the live LUT, and leaves domains1/2 and L3 unchanged. Read an integer row from
   that evidence; no safe literal avicii index is known from this audit.

```sh
old_cap0=$(sysctl -n kern.sweet_cpu_cap0)
```

```sh
read -r candidate_cap0
```

```sh
sysctl -w "kern.sweet_cpu_cap0=$candidate_cap0"
```

```sh
sysctl kern.sweet_cpu_stats
```

Expected **UNVERIFIED** output: domain0 `eligible`, `cap_row`, `req_row`,
`changes`, requested `tis_ns`; domain1/2 requests unchanged. Existing log format
is `SWEET CPUFREQ: domain ... row ... -> row ... reads ...`
(`xnu-avicii/patches/0116-avicii-cpu-placement-l3.patch:155`). Run the standardized
window; only then read the heavyweight report for delivered-rate calibration.

4. **Gate before rollback mutation:** verify saved integer `old_cap0` belongs to
   this boot and is still eligible, then restore and check:

```sh
sysctl -w "kern.sweet_cpu_cap0=$old_cap0"
```

```sh
sysctl kern.sweet_cpu_stats
```

Existing shared-cap exploratory save/write/rollback is documented in
`docs/power/B-cpu.md:128`; skip it if a common eligible row cannot be confirmed.

**UNVERIFIED next phase:** use coherent scheduler idle/run accounting, busiest
CPU per domain, immediate up and delayed bounded down decisions; start disabled
and monitor-only. `CYCLE_CNTR/time` mixes rate, gating and thermal effects and
cannot establish useful utilization. Preserve static caps on invalid snapshots
and cancel the worker on disable. Bergamota's 0190/0192 provide governor and
saturation-boost patterns, not avicii power measurements
(`docs/power/B-cpu.md:23`, `:27`, `:64`, `:105`).
Perfcontrol/CLPC hooks provide scheduler events/recommendations; they need a new
controller and serialized OSM worker. AMP also requires machine config/topology/
processor-set/IPI changes; it is not an ADT-only switch. Keep six A55s as a policy
E group and two A76s as P while preserving three OSM domains only in a later,
measured scheduler project (`docs/power/B-cpu.md:96`, `:98`, `:100`).

### 2. Count USB polls, then bounded quiet backoff

Basis: event thread waits at nominal 1 ms with event interrupts masked
(`xnu-avicii/patches/0073-sweet-usb-device-ep0.patch:341`;
`docs/power/C-idle.md:41`). Keep its recovery channel working.

```diff
--- a/bsd/dev/sweet_usb.c
+++ b/bsd/dev/sweet_usb.c
@@ ud_thread
+ count polls, empty polls, drained events, bytes, pending transfers and sleep time
+ sweetusbbackoff defaults off; count-only mode has no per-loop printf
  drain and acknowledge current event ring with existing ordering
- ud_sleep_ms(1);
+ choose 1 ms when work/control/TX completion is pending
+ after sustained quiet and checked transfer state, choose 2 ms, then at most 4 ms
+ register deadline wait under ud.lock, then recheck GEVNTCOUNT and work generation
+ if work raced, clear wait and drain; otherwise block only after releasing lock
+ TX enqueue increments generation and wakes waiter; RX retains timed fallback
+ keep diagnostics paced by elapsed time, not changed loop iteration count
+ expose passive kern.sweetwake.snapshot; no change to watchdog or DDR
```

Full locking/transfer-state sketch and source anchors:
`docs/power/C-idle.md:54`. This requires actual helpers for EP0/control and
pending TX state; `configured` alone is insufficient. Real IRQ routing/drain/ack
can follow later; backoff does not pretend IRQ support exists.

**Expected gain, UNVERIFIED:** sustained quiet loop 1000→250 polls/s, up to 75%
fewer empty polls; added detection delay roughly 3 ms plus scheduling. It may
save little energy if other work dominates. Enable only after traffic and
recovery checks; fall back to 2 ms if needed (`docs/power/C-idle.md:90`).

1. After an independently gated counter/backoff candidate, with identical USB
   attachment and a proposed 60-second diagnostic window:

```sh
sysctl kern.sweetwake.snapshot
```

```sh
sleep 60
```

```sh
sysctl kern.sweetwake.snapshot
```

2. Compare counters against the baseline build/opt-in-off run. Expected
   **UNVERIFIED**, conditional on sustained empty polling: about 60000 vs 15000
   polls per 60 seconds; active bursts return to 1 ms. Require matching RX/TX work,
   no event overflow/control timeout, working replug/enumeration/SSH bulk transfer,
   and unchanged input/frame latency before interpreting power. Log check:

```sh
sysctl -b kern.sweetlog
```

Rollback is the separately prepared default-off image/boot-arg policy, not a
new write into unknown DWC3 state. Keep local crash logs and watchdog.

### 3. Stop display software vsync during sustained display-off

Basis: current fade/off rearm, notify loop and SwapWait contract
(`xnu-avicii/patches/0079-sweet-display-power.patch:34`, `:53`, `:63`;
`xnu-avicii/patches/0130-avicii-fb-swapwait-until-shown.patch:63`).

```diff
--- a/iokit/Kernel/arm/SweetFramebuffer.cpp
+++ b/iokit/Kernel/arm/SweetFramebuffer.cpp
@@ AppleCLCD state/start
+ sweetfb_offidle opt-in default off; generation and timer-armed state
+ passive cumulative callbacks_on/off, copies, off_ns, resumes, wait_timeouts
@@ RequestPowerChange through an IOWorkLoop command gate
+ serialize power state, timer arm/cancel and generation on the workloop
+ off: start existing fade, wake all shown-ID waiters to recheck power state
+ on: dirty=true, reset fade; arm exactly one immediate callback, wake waiters
@@ vsyncFired
+ under gate, count callback and snapshot power/generation
+ if off and fade complete and opt-in: cancel/no rearm; leave callback disarmed
+ do not emit off-state notifications indefinitely after fade completion
+ else preserve current on/fade cadence and active-client notifications
+ after any unlock/copy: recheck generation before arm/cancel or counter update
+ publish cached stats via kern.sweet_power_stats (display fields)
```

**UNVERIFIED design constraint:** never hold fLock while invoking client
notifications or copying pixels; preserve existing unlock boundaries and use a
single gate for timer lifecycle. Power changes must wake already sleeping
SwapWait callers, not merely make future calls skip sleep. No DSI commands or
panel rail changes in this candidate. Dirty-frame suppression already avoids
unneeded copies; do not claim every suppressed callback saves a full frame copy
(`xnu-avicii/patches/0056-sweet-fb-throttled-present.patch:33`;
`xnu-avicii/patches/0130-avicii-fb-swapwait-until-shown.patch:65`).

**Expected gain, UNVERIFIED:** nearly eliminate the nominal 16667 µs software
vsync callback while off after fade, around 60/s of this source; active cadence
unchanged. Watts unknown; this is not physical panel sleep
(`xnu-avicii/patches/0046-sweet-iosurface-iomfb.patch:1057`;
`docs/power/D-devices.md:11`).

1. In the separately gated candidate, capture counters while on, then press the
   physical power key to lock/off and repeat after a proposed 60-second window:

```sh
sysctl kern.sweet_power_stats
```

```sh
sleep 60
```

```sh
sysctl kern.sweet_power_stats
```

Expected **UNVERIFIED** fields: after fade `display_callbacks_off` stops growing,
`off_ns` increases; on/unlock causes exactly one rearm and presented frames
resume. Counter implementation must compute in-progress off residency at read
time without generating periodic work. Current kernel evidence of requested
state remains `SWEET FB: display off/on`, not proof of physical sleep
(`xnu-avicii/patches/0079-sweet-display-power.patch:73`).

2. Repeat lock/unlock, touch, key and animation tests at least 20 times (proposed
   test policy), inspect log and counters for wait timeouts, ensure clock/glyphs
   and first frame are correct, and compare standardized unplugged off-window
   energy. Read-only log check:

```sh
sysctl -b kern.sweetlog
```

Any missed wake, new timeout, black-screen resume or watchdog reset rejects the
candidate. Roll back to the default-off candidate/image through the operator's
existing deployment gate; no panel register manipulation is a rollback procedure.

## Remaining ladder: idle, timers, devices and iOS

**UNVERIFIED source finding:** XNU reaches WFE/WFI/optional retention paths;
there is no demonstrated PSCI collapse through the current port. `ml_arm_sleep`
is system sleep, not a substitute returning idle call; CPU_ON's secondary entry
does not preserve an interrupted idle context (`docs/power/C-idle.md:7`, `:9`).
Vendor LPM data describe the following choices, not proven live residency
(`refs/lito-dts/lito-pm.dtsi:73`, `:82`, `:93`, `:113`, `:122`, `:133`):

| Vendor state | A55 entry/exit/minimum µs | A76 entry/exit/minimum µs | Integration implication |
|---|---|---|---|
| C1 WFI | 61/60/121 | 55/66/121 | Account first; WFI alone does not prove rail state. |
| C3 core pc | 549/901/1774 | 523/1244/2207 | Reset and broadcast-timer support required by DTS. |
| C4 rail pc | 702/915/4001 | 526/1854/5555 | Same prerequisite, greater wake cost. |

Cluster L3 pc, CX off and LLCC/AOSS sleep add synchronized cluster votes and,
for system states, RPM notification (`refs/lito-dts/lito-pm.dtsi:25`, `:36`, `:48`).
**UNVERIFIED driver-derived encoding:** vendor Linux composes CPU mode, shifted
cluster fields, affinity and reset bit30. Example core-pc `0x40000003` is not
permission to issue SMC; generic bit16 guesses are unsafe. Before any entry,
review PSCI features/firmware convention, independent broadcast wake source,
resume trampoline with MMU/register/cache restoration, redistributor/PPI/SGI
state and timer deadlines, pending-interrupt races, and synchronized RPMh sleep
programming (`docs/power/C-idle.md:25`, `:29`, `:31`, `:33`). Start with accounting
and one guarded secondary only after those prerequisites. No collapse command
is supplied because a safe resume path is not established by this audit.

**UNVERIFIED timer plan:** input threads nominally wake at 10/20 ms, UDP logging
at 100 ms, ring flush at 10 s (skipping unchanged data), and watchdog petting at
half its configured timeout. Watchdog is not the first target. XNU's architectural
timer is deadline driven, and coalescing already exists; blanket tick-rate
changes would not solve polling. Count driver loop/work deltas and IRQs, make
quiet input/log work event driven with bounded fallback, and coalesce only
housekeeping with explicit latency budgets (`docs/power/C-idle.md:42`, `:43`,
`:44`, `:45`, `:46`, `:48`, `:50`). Keep touch-active rate and reset-combo timing.

**UNVERIFIED device plan:** current GPU active clock already sits at the lowest
published bin-0 level; focus on proper GMU slumber rather than inventing a lower
OPP. Serialize idle/fences, GMU handshake and wake under one power lock, retain
timeouts and context recovery, and never equate clearing GX GDSC with valid
power collapse (`docs/power/D-devices.md:39`, `:52`). CPU L3 cap testing stays
separate from LLCC SH0 and DDR MC0. A lower new vote is not proof of lowering an
inherited higher floor; preserve the inherited vote (`docs/power/D-devices.md:58`).
DSI panel sleep/ULPS and physical refresh policy follow a proven resume state
machine, after the software off-timer candidate; DCS brightness and off commands
are published, but safe execution against the splash-owned panel is unproven
(`avicii/panel.dtsi:193`, `:903`, `:908`; `docs/power/D-devices.md:20`).

**UNVERIFIED iOS plan:** inspect per-process CPU time and restart counts before
excluding launchd jobs. Root plists make photoanalysisd/mediaanalysisd useful
optional candidates (maintenance and CPU-intensive flags), then update/pairing
jobs if active. Wifid/CommCenter have DT gates and may already be absent; killing
them can increase clients' retries. Keep powerd, thermal policy, core UI,
security, launchd and SSH services. Stage one reversible overlay exclusion with
its own provenance gate; never delete the full daemon set based on names
(`docs/power/D-devices.md:91`, `:92`, `:93`, `:94`, `:95`, `:97`, `:108`).
Battery UI integration uses the existing power-source service and honest
validity, not a fabricated 100% hardware sample (`docs/power/A-measure.md:78`, `:80`).

## Reconciliation decisions

| Apparent conflict | Coordinator resolution |
|---|---|
| Task says 0115 only; B finds 0116 runtime controls | Use post-0116 kern-0150. Reuse controls but fix validation before automated lowering (`docs/power/B-cpu.md:8`, `:16`). |
| Task says no gauge; A finds optional SID0 PM6150 implementation | Default avicii hardware telemetry is still unproven; adapt the existing class to DTS-selected PM7250B SID2 rather than duplicate it (`docs/power/A-measure.md:11`, `:13`, `:15`). |
| DTS GPU level3 versus kernel speed1/stage11 | Distinct namespaces. Same lowest active bin-0 frequency; no unsupported lower clock recommendation (`docs/power/D-devices.md:42`). |
| “Panel off” versus software black | Top item3 only stops software wakeups. Physical DSI sleep remains a separate high-risk project (`xnu-avicii/patches/0079-sweet-display-power.patch:9`). |
| Core idle versus system sleep/collapse | WFE/WFI evidence does not establish hardware residency; defer PSCI reset states until wake/resume integration exists (`docs/power/C-idle.md:7`, `:31`). |
| A uses 120 s pilots, C uses 60 s counter deltas | Use 60 s diagnostic deltas and 300 s standardized energy windows here; A's 120 s commands remain optional pilots, not comparable final datasets (`docs/power/A-measure.md:126`; `docs/power/C-idle.md:103`). Durations are UNVERIFIED test policy. |
| Gauge sign/interface variants | Adopt A's nested `kern.sweet_fg.*`, discharge-positive µA and raw sign validation. Power-source UI conversion is separate; positive battery `V*I` means discharge (`docs/power/A-measure.md:74`, `:78`). |
| Per-track counters versus common snapshot | Preserve B's passive `kern.sweet_cpu_stats` and C's `kern.sweetwake.snapshot`. Coordinator's proposed `kern.sweet_power_stats` aggregates these with display counters; timestamp each component and disclose skew. No benchmark or MMIO busy measurement on read (`docs/power/B-cpu.md:58`; `docs/power/C-idle.md:92`). |
| DTS facts described as “hardware-verified” in A | Interpret strictly as vendor configuration evidence only; no track made a live read. Live node/PMIC/APID/subtype validation still required (`docs/power/A-measure.md:5`, `:13`). |
| Root image parsed despite 7z Headers Error | Parsed members support only the inspected fields; completeness and launchd runtime state remain UNVERIFIED. No Apple binary or full plist extraction is committed (`docs/power/A-measure.md:82`; `docs/power/D-devices.md:84`). |

## Open questions and gates to resolve them

All are **UNVERIFIED** until future evidence is collected.

- Does the live arbiter expose a readable SID2 QG lane, and does LAST_ADC update
  without configuration writes? Resolve raw revision, transport errors, sign,
  cadence and coherence against vendor sysfs before treating V×I as power
  (`docs/power/A-measure.md:15`, `:24`, `:26`, `:28`).
- Which battery profile/capacity/temperature path applies to this unit, and what
  SOC/charge algorithm survives reboot? Absolute charge and real UI percentage
  remain separate from minimally valid voltage/current (`docs/power/A-measure.md:33`).
- Which LUT rows are fully eligible and what delivered-rate/thermal response
  follows a request? Calibrate outside the energy window; no transition latency
  or max GHz is assumed (`docs/power/B-cpu.md:14`, `:18`).
- How much idle time is scheduler idle versus actual clock/rail residency, and
  can a coherent remote recount accessor be exposed? How much demand is due to
  IRQ/poll overhead rather than useful frame work (`docs/power/B-cpu.md:23`, `:27`;
  `docs/power/C-idle.md:92`)?
- Can quiet USB backoff preserve replug/control-transfer and bulk-transfer
  latency, and which GIC/IRQ integration permits true interrupt-driven idle
  (`docs/power/C-idle.md:54`, `:90`)?
- Which panel timing/bin is selected in live DT, and can its full off/on/DSC
  state be restored without losing splash display (`docs/power/D-devices.md:20`)?
- Can GMU slumber preserve BO/SMMU/ring state and first-frame correctness, and
  what owns each bus vote? No DDR vote replacement until that ownership is
  understood; inherited vote stays (`docs/power/D-devices.md:52`, `:58`).
- Which launchd candidates actually consume CPU or restart, and do dependent
  clients become busier after suppression? Root plist presence alone is not load
  (`docs/power/D-devices.md:86`, `:108`).
- Does correct warmed Metal compositing reduce energy/frame on A620? Confirm
  text/layer parity before any performance claim (main-checkout
  `docs/METAL_PLAN.md:68`; `docs/power/A-measure.md:126`).

## Retained appendices

- [A — measurement, charger, power-source UI](power/A-measure.md).
- [B — CPU/L3 control, governor, CLPC and AMP](power/B-cpu.md).
- [C — PSCI idle, polling inventory and USB sketch](power/C-idle.md).
- [D — display, GPU/memory and root-image daemons](power/D-devices.md).
