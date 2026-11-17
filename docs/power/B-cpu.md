# Track B — CPU frequency and asymmetric scheduling

Scope: static audit of `fork/kern-0150` (`0b457c4`); no phone, VM, build or kernel edits. **UNVERIFIED** labels cover code-derived behavior and every proposed gain/policy below; vendor DTS facts are identified separately. Paths in `refs/` refer to the read-only source pool `/home/tadej/ios-nord/refs`; `XNU/` means the inspection tree `/home/tadej/xnu-8796.141.3`, not an assertion that it exactly matches kern-0150. Patch-file citations are authoritative for the proposed baseline. Linux source citations below refer to [LineageOS qcom-cpufreq-hw.c at 9ea68e4dee77be15d37a9044ecae6754fb2ca454](https://github.com/LineageOS/android_kernel_oneplus_sm7250/blob/9ea68e4dee77be15d37a9044ecae6754fb2ca454/drivers/cpufreq/qcom-cpufreq-hw.c).

## Current state and important corrections

- Vendor DTS: six CPUs use frequency domain 0, CPU6 domain 1, CPU7 domain 2 (`avicii/lito.dtsi:62`, `avicii/lito.dtsi:94`, `avicii/lito.dtsi:120`, `avicii/lito.dtsi:146`, `avicii/lito.dtsi:172`, `avicii/lito.dtsi:197`, `avicii/lito.dtsi:222`, `avicii/lito.dtsi:249`). Controller windows are `0x18323000/0x1000`, `0x18325800/0x1000`, `0x18327800/0x1000`; compatible is `qcom,cpufreq-hw`, clocks are XO and alternate, and `qcom,no-accumulative-counter` is present (`avicii/lito.dtsi:1758-1767`; summary `avicii/CONSTANTS.md:43-50`). Actual row frequencies remain **UNVERIFIED** until live LUT read; do not assume advertised maximum GHz.
- **UNVERIFIED, static code:** task text's boot-only 0115 description is incomplete at kern-0150. Patch 0116 persists four domains, adds the L3 domain, defaults CPU and L3 requests on, exposes runtime `kern.sweet_cpufreq_cap` and `kern.sweet_l3_cap`, and exposes per-thread binding (`xnu-avicii/patches/0116-avicii-cpu-placement-l3.patch:35-44`, `:77-91`, `:175-201`, `:314-347`, `:375-429`). A write of one CPU cap currently applies the same row number to all three CPU domains; identical indices need not imply identical frequencies (`:325-331`, `:266-284`). `sweetcpufreq=0` leaves the loader's CPU requests alone; it is not a governor or an idle policy (`:175-196`).
- **UNVERIFIED, static code:** the diagnostic `kern.sweet_cpufreq` actively measures: three 10 ms busy delays plus dependent-add loops with interrupts disabled on each selected CPU. Repeatedly polling it contaminates energy and wakeup measurements (`xnu-avicii/patches/0116-avicii-cpu-placement-l3.patch:214-231`, `:272-279`, `:292-305`). Read it once before and once after a window; add a lightweight cached statistics sysctl before automated governor tests.
- **UNVERIFIED, static code:** scheduler topology is one homogeneous SMP cluster, not P/E: generated nodes use cluster ID 0 and cluster type 0 (`avicii/tools/mkadt_avicii.py:304-320`); SWEET sets `NO_ECORE` (`xnu-avicii/patches/0004-sweet-machine-config.patch:236-237`). A presenter binding defaults to CPU7 and is attempted once per distinct presenter up to the tracked limit (`xnu-avicii/patches/0116-avicii-cpu-placement-l3.patch:438-475`). Therefore reducing prime frequency first is the most direct threat to UI latency.

## OSM programming constraints

**UNVERIFIED, driver-derived hardware layout, not DTS:** standard OSM offsets are ENABLE `0x0`, FREQ_LUT `0x110`, VOLT_LUT `0x114`, PERF_STATE `0x920`, CYCLE_CNTR `0x9c0`; EPSS uses different offsets and must not be copied from SM7325 (`LineageOS drivers/cpufreq/qcom-cpufreq-hw.c:101-118`, `:862-865`; `avicii/CONSTANTS.md:49`). Existing row width/limit are 32 bytes/40 rows (`xnu-avicii/patches/0116-avicii-cpu-placement-l3.patch:20-24`, `:71-73`). Linux decodes source bits 31:30, multiplier bits 7:0, core count and voltage, handles alternate-clock rows separately, and recognizes repeated frequency plus core count as table termination (`LineageOS drivers/cpufreq/qcom-cpufreq-hw.c:464-515`). Do not read source-zero rows as zero-frequency safe idle: the current `osm_mhz()` does that, whereas Linux uses the alternate clock (`xnu-avicii/patches/0115-avicii-cpufreq-max.patch:63-67`; `LineageOS drivers/cpufreq/qcom-cpufreq-hw.c:474-477`). Keep them ineligible until the live alternate rate is established.

**UNVERIFIED, static code:** current `osm_request(d,cap)` selects `min(top,cap)` with no validation of the capped row's core-count eligibility and logs every request (`xnu-avicii/patches/0116-avicii-cpu-placement-l3.patch:140-157`). Build an eligible-row list first: exclude terminator/boost rows, unknown-source rows, zero or invalid frequency, and rows that cannot support the domain's complete enabled core population. Choose by frequency, not index ordering. No driver should write VOLT_LUT, clock PLLs, enable a disabled OSM domain, or replace firmware tables; use the existing request store plus barriers, readback, and optional cycle-rate verification (`:99-137`, `:151-157`; `LineageOS drivers/cpufreq/qcom-cpufreq-hw.c:484-515`, `:603-609`).

**UNVERIFIED:** a PERF_STATE readback is a requested row, not proof of delivered frequency or thermal safety. Linux provides `.target_index` and `.fast_switch`, but avicii transition settling time is not proven by those hooks (`LineageOS drivers/cpufreq/qcom-cpufreq-hw.c:430-438`; existing request readback `xnu-avicii/patches/0116-avicii-cpu-placement-l3.patch:151-157`). Measure request timestamp → stable measured rate in a dedicated calibration run; do not invent a microsecond latency. Hardware LMh is mentioned by the patch, but absence of a full XNU thermal policy must remain a limitation (`xnu-avicii/patches/0116-avicii-cpu-placement-l3.patch:32`; Linux cooling registration `LineageOS drivers/cpufreq/qcom-cpufreq-hw.c:401-425`).

## Recommended sequence

1. **UNVERIFIED proposal: validated per-domain static caps first.** Preserve the present UI prime cap initially, lower little and gold independently by one eligible frequency step, measure energy/frame and UI p95 frame time, then explore prime only if deadlines still pass. Existing shared cap can provide a coarse reversible screening experiment, but it changes three domains at once and cannot isolate savings (`xnu-avicii/patches/0116-avicii-cpu-placement-l3.patch:314-345`). Expected gain: lower active CPU energy when requested frequency/voltage falls; no defensible whole-phone percent before battery measurement. At equal voltage, a frequency ratio `r` implies approximately `r` dynamic switching power during equal busy time, but longer busy time can erase energy savings; voltage changes and the device baseline are unmeasured. Risk: more missed frames, slower USB/log processing, longer active residency; effort small relative to governor work (inference from existing runtime control and presenter binding `:325-345`, `:438-475`).
2. **UNVERIFIED proposal: scheduler-idle governor next.** Per-domain busiest-CPU utilization protects a single loaded presenter; averaging six little CPUs would conceal one saturated CPU. Port the *pattern*, not addresses/topology, from Bergamota's idle-time governor (`refs/ry-diffusion-Bergamota/xnu/patches-11215/0190-beryllium-cpufreq-little-cap.patch:325-380`). Obtain coherent idle residency through a scheduler-owned accessor; XNU recount already records idle start/run transitions and includes the current in-progress idle interval (`XNU/osfmk/kern/recount.c:930-987`). Reader synchronization must be reviewed: copying the reference accessor alone is not proof of a coherent remote CPU snapshot (`refs/ry-diffusion-Bergamota/xnu/patches-11215/0190-beryllium-cpufreq-little-cap.patch:600-615`). Start governor disabled, fixed caps as rollback, use eligible LUT rows and one serialized request owner. Expected gain: greatest CPU-specific opportunity during low/intermittent work; actual watts **UNVERIFIED**, including whether lower requests help when cores are already clock-gated.
3. **UNVERIFIED proposal: defer CLPC-style controller and AMP until after energy evidence.** They are larger scheduler/platform changes, while caps/governor reuse current OSM request machinery (`xnu-avicii/patches/0116-avicii-cpu-placement-l3.patch:140-157`; XNU registration `XNU/osfmk/arm/machine_routines_common.c:172-240`).

**UNVERIFIED: CYCLE_CNTR is diagnostic, not sufficient utilization.** One cycle counter per domain follows the DTS property; Linux reads its delta with wrap handling (`avicii/lito.dtsi:1766`; `LineageOS drivers/cpufreq/qcom-cpufreq-hw.c:248-279`). `delta_cycles / delta_time` conflates delivered clock, clock gating, thermal clamping and work. It does not measure retired useful work, runnable demand, or individual CPU residency. Use idle/run accounting for load, CYCLE_CNTR for consistency/calibration; handle unsigned wrap with samples shorter than a full counter period at the maximum observed rate. Never transplant a literal sampling period without checking that condition. Existing code calls the derived ratio "counter MHz" (`xnu-avicii/patches/0116-avicii-cpu-placement-l3.patch:272-279`).

## Concrete pseudo-diff against kern-0150: per-domain caps

**UNVERIFIED design**, not an applied or compilable patch. Anchors are post-0116 `dom[]`, `osm_probe`, `osm_request`, and the cap handler (`xnu-avicii/patches/0116-avicii-cpu-placement-l3.patch:83-91`, `:99-157`, `:314-347`). All new sysctl names below are proposed and must not be presented as already available.

```diff
--- a/bsd/dev/sweet_cpufreq.c
+++ b/bsd/dev/sweet_cpufreq.c
@@ domain state
+ unsigned eligible[OSM_LUT_MAX], neligible;
+ unsigned requested_row;
+ uint64_t residency_abs[OSM_LUT_MAX], last_change_abs;
+static int domain_cap[3] = { OSM_LUT_MAX, OSM_LUT_MAX, OSM_LUT_MAX };
+/* Serialize cap/sysctl/governor ownership with a kernel mutex. */
@@ osm_probe(d), after reading LUT
+/* Exclude repeated terminator, unsupported source/unknown alternate rate,
+ * invalid frequency and rows with fewer than full-domain cores.
+ * Sort eligible rows by decoded frequency; reject empty/invalid table.
+ * Do not expose source-zero as a zero-MHz OPP. */
@@ osm_request(d, cap)
- unsigned row = dom[d].top;
- if (cap >= 0 && (unsigned)cap < row) row = (unsigned)cap;
+/* Reject invalid negative inputs; legacy max sentinel requests top. */
+unsigned row = highest_frequency_eligible_row_at_or_below_cap(d, cap);
+if (row == INVALID) return EINVAL;
+/* Keep previous validated request on error; only write when row changes. */
+/* Account old requested-row time; ordered PERF_STATE write/readback. */
@@ sysctls
+/* kern.sweet_cpu_cap0 / cap1 / cap2: validated per-domain row ceilings.
+ * One lock for reads/writes, reject out-of-range/ineligible rows EINVAL.
+ * Retain legacy common cap, but validate every domain before any write.
+ * kern.sweet_cpu_stats: cached rows, raw LUT, eligibility, request,
+ * idle/busy totals and requested-row residency. NO benchmark/delay(). */
```

**UNVERIFIED expected output contract:** `domain=0 eligible=... cap_row=... req_row=... changes=... busy_pct=... tis_ns=...`; request-time residency must be named as such, not claimed hardware residency. Existing implementation only guarantees the old `SWEET CPUFREQ: domain ... row ... reads ...` log format (`xnu-avicii/patches/0116-avicii-cpu-placement-l3.patch:155-157`).

## Concrete pseudo-diff: load governor

**UNVERIFIED design:** use a proposed `sweetgov=0` default and `kern.sweet_cpu_governor` switch after validating caps. A 25 ms sample, 80% target, 90% up threshold and three samples before lowering are **UNVERIFIED tuning choices borrowed from a reference implementation**, not avicii constants (`refs/ry-diffusion-Bergamota/xnu/patches-11215/0190-beryllium-cpufreq-little-cap.patch:44-51`). They imply a potential 25 ms reaction delay, longer than some UI deadlines; begin in monitor-only mode and either shorten based on evidence or add event-driven boosts. Count governor wakeups in energy comparisons.

```diff
--- a/osfmk/kern/processor.c
+++ b/osfmk/kern/processor.c
+/* sweet_cpu_idle_snapshot(cpu): scheduler-owned coherent snapshot in
+ * mach absolute units, including an in-progress idle interval; return
+ * invalid for offline/unregistered CPUs. Recount source supplies the model.
+ * No MMIO/logging/allocation or blocking in scheduler-critical contexts. */
--- a/bsd/dev/sweet_cpufreq.c
+++ b/bsd/dev/sweet_cpufreq.c
+/* Boot: probe only; one sleeping worker after selected CPUs register. */
+for each sample deadline:
+  snapshot wall + per-CPU idle coherently;
+  reject first sample, resets, offline changes, idle_delta > wall_delta;
+  for domain d: busy = max(100*(wall_delta-idle_delta)/wall_delta);
+  if monitor_only: cache counters and continue;
+  if busy >= UP_THRESHOLD or interactive_boost_pending: target = cap[d];
+  else target = lowest_eligible_frequency_at_least(cur_freq*busy/TARGET);
+  bound target to [validated_min[d], validated_cap[d]];
+  up immediately; down after DOWN_SAMPLES, by bounded eligible steps;
+  request only on change, through the same serialized cap/request owner;
+  cache stats; rate-limit summaries; never invoke diagnostic loop_mhz();
+/* Disable restores the recorded pre-governor static request, not fmax.
+ * Invalid snapshots freeze at safe static caps; suspend/reset cancels worker.
+ * No change to DDR or L3 policy in this experiment. */
```

## Perfcontrol/CLPC integration and AMP feasibility

**UNVERIFIED, inspected XNU source:** the interface is in `osfmk/arm/machine_routines.h`, not a standalone `machine_perfcontrol` driver. It defines offcore/oncore/context-switch, runnable-latency, work-interval, thread-group and state-update callbacks; `sched_perfcontrol_register_callbacks()` is versioned and bounds private state size (`XNU/osfmk/arm/machine_routines.h:1084-1242`; `XNU/osfmk/arm/machine_routines_common.c:172-240`). Defaults are empty callbacks (`XNU/osfmk/arm/machine_routines_common.c:83-169`). Registration comments explicitly mention resynchronizing existing thread groups with CLPC (`:182-195`). These hooks deliver workload information to a controller; they do not themselves program Qualcomm OSM. A future controller should accumulate event/timestamp/QoS/work-interval demand cheaply, publish atomic domain recommendations, and let the serialized OSM worker write requests. Do not put SPMI, sleeping locks, printf or expensive LUT scans into context-switch callbacks (design constraint based on callback placement/types).

**UNVERIFIED, inspected XNU source:** group recommendations and preferred clusters feed scheduling (`XNU/osfmk/arm/machine_routines.h:1240-1270`); recommended core masks can change processor recommendations (`XNU/osfmk/kern/sched_prim.c:7712-7802`). This is separate from frequency control and does not prove a loaded Apple binary CLPC will work on this SoC. No claim is made here about the iOS binary's actual registration or an undocumented Apple DVFS ABI.

**UNVERIFIED AMP proposal:** map logical CPUs 0–5 to E and 6–7 to P as scheduler policy groups, but preserve their real MPIDRs and retain three separate OSM domains. Two A76 frequency policies can still share a P scheduling class. This requires coordinated SWEET configuration, ADT topology, processor-set creation, cluster IDs/core IDs, scheduler selection, cross-CPU IPI paths, and boot-CPU-in-E testing; changing one ADT property is insufficient (`avicii/tools/mkadt_avicii.py:304-320`; `xnu-avicii/patches/0004-sweet-machine-config.patch:236-237`; `XNU/osfmk/arm64/machine_routines.c:1044-1085`, `:1447-1456`). XNU AMP chooses P/E based on recommendation and online/recommended availability (`XNU/osfmk/kern/sched_amp.c:614-635`, `:656-709`). Background placement is a recommendation with overflow behavior, not an unconditional guarantee that every background task remains on A55. Explicit CPU7 presenter bindings must be audited when evaluating such policy (`xnu-avicii/patches/0116-avicii-cpu-placement-l3.patch:438-475`). Prefer initial opt-in steering on the existing SMP scheduler over enabling Apple's complete AMP platform assumptions without an audit.

## Prior ports: transferable evidence, not measured avicii savings

- **UNVERIFIED cross-phone report:** spacewar measured little-domain loop time improving 65.9 → 55.4 ms after 1516 → 1804 MHz; later notes report max requests on all domains. This is performance evidence for a different SoC, not battery savings or valid avicii register layout (`refs/anonbeat1-ios-sweet/NOTES.md:353-368`, `:404`).
- **UNVERIFIED cross-phone implementation:** Bergamota's 0190 in `patches-11215` and `patches-12377` adds an idle-residency governor, little cap and time-in-state report; its top-level `xnu/patches` max-frequency implementation is older (`refs/ry-diffusion-Bergamota/xnu/patches-11215/0190-beryllium-cpufreq-little-cap.patch:16-82`, `:325-380`, `:600-615`). Patch 0192 subsequently adds an opt-in saturation boost, demonstrating the responsiveness risk of a strict little ceiling (`refs/ry-diffusion-Bergamota/xnu/patches-11215/0192-beryllium-cpufreq-little-boost.patch:9-15`, `:83-100`). Do not import SDM845 addresses, four-plus-four topology, LUT limit or advertised power gain.
- **UNVERIFIED cross-phone implementation:** HakiOS has an EPSS max-request path and optional idle-based load logging; the log counts time not idle, including interrupt work. This supplies an instrumentation pattern, not evidence of a dynamic governor or battery savings (`refs/oosexgang-hakios-xnu-kernel/drivers/power/hakios.cpufreq.c:62-109`, `:251-300`).

## Top items and exact future on-phone checks

All commands below are **future procedures for Claude**, not commands run by this track. They assume an existing authorized SSH session and tool availability; API names in the proposal are **UNVERIFIED** until implemented. Each code block contains one literal command per line. No image installation/boot/flash is included: use the project's separate owner gate and provenance workflow for any later kernel experiment.

1. **Validated caps: gain lower active CPU energy (watts/percent UNVERIFIED), medium UI/USB risk, small effort.** First collect the actual baseline once outside the energy window:

```sh
sysctl kern.sweet_cpufreq
sysctl kern.sweet_cpufreq_cap
ps -A -o pid,pcpu,comm
```

   For a current-kernel shared-cap screening test, record the old cap and inspect the report first (outside the energy window):

```sh
old_cap=$(sysctl -n kern.sweet_cpufreq_cap)
sysctl kern.sweet_cpufreq
read -r candidate_cap
```

   **Gate before the frequency write:** Claude must confirm the entered row is present, known-frequency and full-core eligible in all three domains, and has a lower frequency than the baseline in the domains being compared. If no common row satisfies this, skip this experiment and implement per-domain validation. The variable is supplied from that live inspection; no row number is invented here. After the gate:

```sh
sysctl -w "kern.sweet_cpufreq_cap=$candidate_cap"
sysctl kern.sweet_cpufreq
```

   Expected current code: three `SWEET CPUFREQ: domain ... row ... -> row ... reads ...` log lines and new requests in the diagnostic report (`xnu-avicii/patches/0116-avicii-cpu-placement-l3.patch:155-157`, `:325-345`). Run the standardized A–B measurement window without diagnostic polling. **Gate before rollback:** verify `old_cap` still holds the integer recorded from this boot, then restore:

```sh
sysctl -w "kern.sweet_cpufreq_cap=$old_cap"
sysctl kern.sweet_cpufreq
```

   Existing report should include each domain's `req row`, `top`, LUT and `loop MHz per cpu`, and common cap is an integer (`xnu-avicii/patches/0116-avicii-cpu-placement-l3.patch:266-312`, `:344-347`). **Gate:** before a current-kernel shared-cap write, Claude must inspect every domain LUT and choose a common eligible row; do not assume row 0 is decoded or that one row index is safe on all domains. The literal cap value cannot be supplied honestly before that read. After implementing the sketch, the exact new interface check is:

```sh
sysctl kern.sweet_cpu_stats
sysctl kern.sweet_cpu_cap0 kern.sweet_cpu_cap1 kern.sweet_cpu_cap2
```

   Expected proposed fields: `eligible`, `cap_row`, `req_row`, no measurement loop. Use the measurement track's fixed screen/USB/thermal conditions and record frame p50/p95 plus energy/frame in an A–B–A comparison; reject a cap if UI p95 or USB stability regresses beyond the predeclared acceptance threshold. Restore the exact recorded caps after each test (proposal; not a measured result).

2. **Idle-based governor: gain lower low-load requested-row residency, power UNVERIFIED; medium risk; medium effort.** Run only after the new monitor-only implementation exists:

```sh
sysctl kern.sweet_cpu_stats
sysctl kern.sweet_cpu_governor
```

   Expected proposed output: disabled or monitor-only mode, valid per-domain `busy_pct`, requested row and residency totals; under a fixed workload, monitor predictions should rise on a busy presenter and fall during idle. **Gate:** before enabling, save all caps, establish valid idle snapshots and retain a working fallback; the proposed enabling command is:

```sh
sysctl -w kern.sweet_cpu_governor=1
```

   Expected: mode enabled, changes only at valid LUT rows, quick upward decisions, delayed downward decisions, no extra log flood. Compare the same energy/frame and frame-tail metrics and count governor wakes. Disable after the window using the proposed rollback:

```sh
sysctl -w kern.sweet_cpu_governor=0
```

   Expected: recorded static requests restored, worker stopped. These are interface-design expectations, not existing kern-0150 output.

3. **SMP steering / eventual AMP: gain reduced big-core background residency, power UNVERIFIED; high scheduler/hang risk for full AMP; medium-to-large effort.** Record current scheduler identity before any such future change:

```sh
sysctl kern.sched
sysctl kern.sweet_cpu_stats
ps -A -o pid,pcpu,comm
```

   **UNVERIFIED, static source:** `kern.sched` reports the scheduler name (`XNU/bsd/kern/kern_sysctl.c:4802`); the live value is not known; the planned CPU stats must expose per-core busy/idle and topology, not just per-domain averages. After an explicitly gated scheduler experiment, verify background-core placement, no starving high-QoS threads, and the same UI/USB checks before interpreting any energy result. A read of thread bindings would require the existing `kern.sweet_bind` write-to-list interface, so omit it from an otherwise read-only baseline (`xnu-avicii/patches/0116-avicii-cpu-placement-l3.patch:383-405`).
