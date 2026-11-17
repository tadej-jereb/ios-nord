# Track C — idle, timers and polling (static; kern-0150)

Scope: documentation only. No phone, VM, build, or patch application was run. **UNVERIFIED** labels below include source-derived behavior, estimates and proposed interfaces: none is a new live measurement. `XNU/` means the read-only `/home/tadej/xnu-8796.141.3/` source snapshot (HEAD `6e30f4d43c3bc0b03119e9613c6d0c822d04cbc8`); authoritative port changes are cited to this worktree's patch files. `DTS/` means `/home/tadej/ios-nord/refs/lito-dts/`. `LOS/` means LineageOS `android_kernel_oneplus_sm7250` at commit `9ea68e4dee77be15d37a9044ecae6754fb2ca454`; source links below pin that revision. Proposed timing values are policy choices, **UNVERIFIED**, not hardware constants.

## Current idle path

**UNVERIFIED (source):** the scheduler idle path calls `machine_idle()` bracketed by platform-idle tracking (`XNU/osfmk/kern/sched_prim.c:6402-6410`); `machine_idle()` may follow a WFE recommendation, otherwise enters `Idle_context()` (`XNU/osfmk/arm64/machine_routines.c:343-360`). The assembly branches from Idle_context into `cpu_idle` (`XNU/osfmk/arm64/cswitch.s:375`). `cpu_idle()` invokes optional notification callbacks, resynchronizes deadlines, and finally executes DSB then retention assembly or WFI depending on compile-time configuration (`XNU/osfmk/arm64/cpu.c:541-592`). Therefore say **“WFE/WFI path, no demonstrated PSCI collapse”**, not “measured shallowest state”: WFI itself does not establish actual rail residency.

**UNVERIFIED (source):** the existing port's explicit PSCI wrapper is CPU_ON, using SMC and an EL1/EL2-aware secondary entry, not a suspend/resume protocol (`xnu-avicii/patches/0065-sweet-smp-psci.patch:28-39,345-385`). Merely finding CPU_SUSPEND's function number in diagnostic shim code (`avicii/shim/shim.c:39-46`) does not prove that idle uses it. `ml_arm_sleep()` is a system sleep path that waits for secondary sleep tokens and records wake time, not a drop-in returning idle call (`XNU/osfmk/arm64/cpu.c:1023-1057`). Keep system sleep and per-core idle as separate projects.

## Vendor LPM table and PSCI encodings

The vendor CPU nodes use PSCI; the PSCI node specifies `arm,psci-1.0` and `smc` (`avicii/lito.dtsi:59,91,117,143,169,194,219,246,331-334`). LPM's CPU group is CPU0–5 and CPU6–7 (`DTS/lito-pm.dtsi:60-71,105-111`). The LPM rows below are **vendor DTS facts**, not proof that this kernel can enter them. These LPM constants are not yet catalogued in `avicii/CONSTANTS.md:38-56`; record/review them there before implementation (this task edits docs only).

| State | CPU mode / cluster field | A55 entry / exit / minimum residency, µs | A76 entry / exit / minimum residency, µs | Vendor evidence |
|---|---|---|---|---|
| C1 wfi | CPU `0x1` | 61 / 60 / 121 | 55 / 66 / 121 | `DTS/lito-pm.dtsi:73-79,113-119` |
| C3 pc | CPU `0x3`; reset, broadcast timer | 549 / 901 / 1774 | 523 / 1244 / 2207 | `DTS/lito-pm.dtsi:82-90,122-130` |
| C4 rail-pc | CPU `0x4`; reset, broadcast timer | 702 / 915 / 4001 | 526 / 1854 / 5555 | `DTS/lito-pm.dtsi:93-101,133-141` |
| L3 wfi | cluster `0x1` shifted 4 | 660 / 600 / 1260 (cluster-wide) | same cluster row | `DTS/lito-pm.dtsi:11-22` |
| L3 pc | cluster `0x4` shifted 4; reset | 2752 / 3048 / 6118 | same cluster row | `DTS/lito-pm.dtsi:25-34` |
| CX off | cluster `0x224` shifted 4; reset + RPM notification | 3638 / 4562 / 8467 | same cluster row | `DTS/lito-pm.dtsi:36-46` |
| LLCC off / AOSS sleep | cluster `0xc24` shifted 4; reset + RPM notification | 3263 / 6562 / 9826 | same cluster row | `DTS/lito-pm.dtsi:48-58` |

**UNVERIFIED (vendor-driver interpretation):** use the actual vendor encoding, not a generic PSCI v0.2 power-down bit guessed from memory. This branch uses reset at bit 30 and affinity at bits 25:24 ([LOS/drivers/cpuidle/lpm-levels.c:47-49](https://github.com/LineageOS/android_kernel_oneplus_sm7250/blob/9ea68e4dee77be15d37a9044ecae6754fb2ca454/drivers/cpuidle/lpm-levels.c#L47)); it accumulates masked/shifted cluster fields only after synchronized child votes, then adds CPU mode, reset type and affinity ([same file:1315-1384](https://github.com/LineageOS/android_kernel_oneplus_sm7250/blob/9ea68e4dee77be15d37a9044ecae6754fb2ca454/drivers/cpuidle/lpm-levels.c#L1315)). Illustrative core-only pc encoding is `0x40000003`, rail-pc `0x40000004`; synchronized L3-pc plus rail-pc gives `0x41000044`. These are **UNVERIFIED derived examples, never an instruction to issue SMC**; firmware feature results and synchronized state selection must be checked first. Default index 0 takes `cpu_do_idle()` rather than calling suspend; broadcast-timer entry/exit surrounds deeper states ([same file:1361-1391](https://github.com/LineageOS/android_kernel_oneplus_sm7250/blob/9ea68e4dee77be15d37a9044ecae6754fb2ca454/drivers/cpuidle/lpm-levels.c#L1361)). Generic v0.2 type bit 16 and extended type bit 30 are both defined, so blindly choosing one is unsafe ([LOS/include/uapi/linux/psci.h:57-72,97-100](https://github.com/LineageOS/android_kernel_oneplus_sm7250/blob/9ea68e4dee77be15d37a9044ecae6754fb2ca454/include/uapi/linux/psci.h#L57)).

## Why collapse comes after measurement and wakeup reduction

The timer is the virtual timer PPI3 / INTID19; GICD/GICR and PDC wake controller are separately described (`avicii/CONSTANTS.md:51-56`, `avicii/lito.dtsi:599-619,648-653`). C3/C4 explicitly require reset and a broadcast timer (`DTS/lito-pm.dtsi:82-101,122-141`). **UNVERIFIED inference:** current per-CPU virtual-timer delivery cannot simply be assumed to survive these reset states.

**UNVERIFIED (source/design):** the secondary entry establishes EL2 timer access/CNTVOFF and GIC system-register access before EL1 (`xnu-avicii/patches/0065-sweet-smp-psci.patch:347-379`); current GIC initialization wakes its redistributor, establishes Group1 NS, and enables timer/SGI (`XNU/pexpert/arm/pe_fiq.c:149-178`). A suspend resume vector must save/restore registers and exception/MMU/cache state and restore GIC CPU interface/PPI/SGI routing and deadlines; CPU_ON's reset entry does not preserve an interrupted idle context. An independent wake deadline, SGI race protocol and pending interrupt recheck are prerequisites. Never put `smc CPU_SUSPEND` directly where WFI currently appears.

**UNVERIFIED (source/design):** Linux coordinates cluster votes under a synchronization lock and runs system-PM enter/exit hooks for notify-RPM states ([LOS/drivers/cpuidle/lpm-levels.c:1123-1130,1145-1211,1252-1264](https://github.com/LineageOS/android_kernel_oneplus_sm7250/blob/9ea68e4dee77be15d37a9044ecae6754fb2ca454/drivers/cpuidle/lpm-levels.c#L1123)). Our RPMh driver explicitly assumes deep idle disabled and offers no sleep/wake programming (`xnu-avicii/patches/0062-sweet-touch-power-battery.patch:115-116`). Thus defer cluster/CX/LLCC collapse; preserve the inherited bootloader DDR vote. A staged future implementation starts with per-CPU accounting, read-only PSCI_VERSION/FEATURES probes, then a single secondary's guarded core-only reset state with a reviewed resume trampoline and broadcast wake source; boot CPU and all system states stay disabled until each prerequisite is demonstrated. Gain could be substantial idle energy, but **UNVERIFIED, no defensible percentage**; risk high (nonreturn, missed timers/SGIs, display/USB loss); effort large.

## Polling and timer inventory

All rates below are **UNVERIFIED source-derived nominal upper rates**, not measured wake interrupts, CPU utilization or energy; work/scheduling delays and timer coalescing change them. Do not sum them and claim a measured IRQ rate.

| Source | Current mechanism and nominal frequency | Evidence / action |
|---|---|---|
| USB event thread | blocked 1 ms waits, nominal 1000 iterations/s; GEVNT interrupt masked | `xnu-avicii/patches/0073-sweet-usb-device-ep0.patch:341-361`; `XNU/bsd/dev/sweet_usb.c:1064-1085,1233`. Instrument empty polls, events, bytes and time; back off empty polls conservatively, then implement IRQ+drain with poll fallback. |
| Touch | 10 ms wait, nominal 100 iterations/s. IRQ hint reduces I²C reads but not thread wakeups; active finger always read, periodic 100 ms fallback | `xnu-avicii/patches/0060-sweet-keys-touch-drivers.patch:751-766`; `XNU/bsd/dev/sweet_touch.c:1291-1308,1325-1326`. True IRQ wait plus missed-IRQ fallback later; preserve active rate and release handling. |
| Keys | three SPMI reads then 20 ms wait, nominal 50 iterations/s | `xnu-avicii/patches/0060-sweet-keys-touch-drivers.patch:121-127`; `XNU/bsd/dev/sweet_keys.c:115-119,157`. IRQ conversion must preserve reset combo; don't slow indiscriminately. |
| UDP log thread | blocked 100 ms wait, nominal 10 iterations/s, even when unconfigured | `xnu-avicii/patches/0077-sweet-usb-live-log.patch:51,68-74`; `XNU/bsd/dev/sweet_usb.c:1100-1134`. Change-based wake and bounded timeout fallback; `sweetusblog=0` already disables this transport for controlled tests. |
| On-disk ring | default 10 s wait, reads total and skips write if unchanged | `xnu-avicii/patches/0069-sweet-ufs-faster.patch:153-158`; `XNU/bsd/dev/sweet_ufs.c:1124-1138`. Preserve crash diagnostics; align noncritical flush deadline, no reason to flush empty ring. |
| Watchdog | pet interval = half requested bark interval, so `sweetwdt=10` implies nominal 0.2 pets/s | `xnu-avicii/patches/0136-avicii-hang-watchdog.patch:60-75,107-121`. Leave enabled; tiny target compared with USB. |
| UFS completion polling | command-bound, not a free-running idle thread; sleeps after initial spin, zero leeway | `XNU/bsd/dev/sweet_ufs.c:287-318`. Count command time before changing completion latency. |
| Architectural timer | deadline driven; existing timer-count increment at interrupt entry | `XNU/osfmk/arm/rtclock.c:323-334,388-403`. Export deltas; don't equate `hz` with a permanently firing hardware tick. |

**UNVERIFIED (source/design):** XNU has timer coalescing enabled by default (`XNU/osfmk/kern/timer_call.c:197-198`), and explicit wait/timer leeway APIs (`XNU/osfmk/kern/sched_prim.h:774-780`; `XNU/osfmk/kern/timer_call.h:141-147`). Convert noncritical housekeeping to a shared deadline phase and bounded leeway only after latency budgets exist. Keep USB transfer completion, touch-active reporting, frame fences and watchdog margin out of blanket coalescing changes. USB's logging tick is loop-count-based (`XNU/bsd/dev/sweet_usb.c:1082-1085`), so a longer poll must also convert its diagnostics cadence to elapsed time.

## Concrete wakeup-reduction sketch (proposed, not implemented)

**UNVERIFIED design** against the `kern-0150` USB event loop identified in `xnu-avicii/patches/0073-sweet-usb-device-ep0.patch:341-361` and ECM extension `xnu-avicii/patches/0075-sweet-usb-ecm.patch:434-447`. All new sysctls and timing knobs below are proposals; ENOENT is expected on unchanged 0150. Start with counting-only mode, then an opt-in backoff. Connected idle must be tested too: using only `!configured` misses most awake iOS time.

```diff
--- a/bsd/dev/sweet_usb.c
+++ b/bsd/dev/sweet_usb.c
@@ ud_thread loop
+ /* Per-driver relaxed counters; no per-iteration printf. Export RD sysctls:
+  * kern.sweetwake.usb_polls, usb_empty, usb_events, usb_sleep_ms_total.
+  * sweetusbbackoff defaults 0; parse at startup. Policy: 1,2,4 ms only.
+  * Track elapsed quiet time and diagnostics by mach_absolute_time(). */
  uint32_t count = dwc_rd(GEVNTCOUNT) & 0xffff;
+ atomic_counter_add(usb_polls, 1);
+ atomic_counter_add(count ? usb_events : usb_empty, count ? count / 4 : 1);
  if (count) {
      /* existing event drain + acknowledge, unchanged */
+     empty_run = 0;
  }
- ud_sleep_ms(1);
+ if (!count) ++empty_run;
+ unsigned ms = 1;
+ if (sweetusbbackoff && ep0_control_idle() && !tx_completion_pending()) {
+     /* Helpers must reflect actual transfer state under ud.lock.
+      * Recheck state after counting; don't guess that ud.configured means idle.
+      * Receive OUT may remain armed; incoming packet detection is delayed by ms. */
+     ms = empty_run >= QUIET_LONG ? 4 : empty_run >= QUIET_SHORT ? 2 : 1;
+ }
+ atomic_counter_add(usb_sleep_ms_total, ms);
+ /* Under ud.lock: register the deadline wait, then recheck GEVNTCOUNT,
+  * pending TX and a software-work generation counter. If work appeared,
+  * clear the registered wait and drain now; otherwise release the lock
+  * and block only if assert_wait returned THREAD_WAITING.
+  * TX enqueue increments generation and wakes this event waiter.
+  * RX hardware has a bounded timer fallback; this assumes no IRQ. */
+ ud_sleep_ms_rechecked(ms);
```

**UNVERIFIED design estimate:** a sustained quiet 4 ms interval reduces nominal USB loop wakeups from 1000/s to 250/s (75% of that loop, not 75% system battery). Adds up to approximately 3 ms poll delay before subsequent service, plus scheduler delays. Burst traffic returns to 1 ms; compare USB throughput and input/frame latency. Risks: SSH throughput/latency, enumeration/control-transfer timing, event-buffer overflow; first cap backoff at 2 ms if 4 ms fails. Effort small for counters, medium for correct transfer-state gating. A real event IRQ removes empty polling more thoroughly, but requires IRQ routing, drain/ack order, no lost wakeups and disconnect/reconnect tests; defer it behind the measured pilot (`XNU/bsd/dev/sweet_usb.c:1064-1085,1233`).

**UNVERIFIED instrumentation design:** export `kern.sweetwake.snapshot` as one coherent snapshot with timestamp, per-CPU timer/SGI counts, per-driver loop/work counts and cumulative idle elapsed time. Count WFI entry and matching return near `XNU/osfmk/arm64/cpu.c:587-592`, and GIC IRQ IDs at the existing dispatcher, retaining no printf inside IRQ or idle loops. Publish counters without reset to allow host-side deltas; distinguish idle thread elapsed time from hardware collapsed residency. Existing `cpu_stat.timer_cnt` is a suitable timer-count source (`XNU/osfmk/arm/rtclock.c:333`).

## Future on-phone checks (Claude runs; none run for this task)

1. Existing 0150 baseline, read-only over established SSH; record logs once and process activity at the beginning/end of a fixed screen-on-idle window. Commands use the project's wrapper (`README.md:31-33`; `docs/NEXT-2026-11-17.md` in main checkout describes `tooling/75-phone.sh ssh`).

```sh
tooling/75-phone.sh ssh 'sysctl -b kern.sweetlog' > baseline-sweetlog.bin
tooling/75-phone.sh ssh 'ps -A -o pid,comm,%cpu,time' > baseline-processes.txt
```

2. After a separately reviewed instrumented kernel is available, repeat under identical brightness, workload, thermal state and USB attachment. New interfaces below are **UNVERIFIED proposals** and must fail cleanly as ENOENT on 0150. Measure locally buffered fuel-gauge samples over a longer window; avoid a high-rate SSH sampler that creates the work being measured. Comparison window 60 s is **UNVERIFIED test policy**.

```sh
tooling/75-phone.sh ssh 'sysctl kern.sweetwake.snapshot' > wake-before.txt
sleep 60
tooling/75-phone.sh ssh 'sysctl kern.sweetwake.snapshot' > wake-after.txt
tooling/75-phone.sh ssh 'sysctl -b kern.sweetlog' > wake-sweetlog.bin
```

Expected **UNVERIFIED schema**, not expected measured numbers: `time_ns=... timer[...]=... sgi[...]=... usb_polls=... usb_empty=... usb_events=... touch_polls=... keys_polls=... log_polls=... idle_ns[...]=...`. Baseline quiet USB delta should be of order 60000 iterations/60 s, and 4 ms backoff order 15000/60 s; actual deltas decide. Counted timer IRQ reduction need not equal summed driver reductions because deadlines can coalesce (`XNU/osfmk/kern/timer_call.c:197-198`).

3. Compare a recorded before/after idle window and repeated identical lock-screen gestures, then SSH bulk throughput and disconnect/reconnect. Accept only with lower measured battery energy/idle CPU and no lost input, sticky touch release, SSH stalls, overflow/error log, watchdog reset or frame-time regression. Those are **UNVERIFIED acceptance criteria**, grounded in the timing-sensitive USB/touch loops and watchdog above. Candidate boot preparation, provenance and gating belong to the owner; this static task supplies no boot/flash command.

## Top items

1. **Counters then bounded USB quiet backoff:** **UNVERIFIED gain** up to 75% fewer wakeups in that loop at a 4 ms cap; total watts unknown. Risk medium (USB latency/overflow); effort small-to-medium. Check step 2 deltas, energy, and step 3 USB/UI tests. Source and sketch above: `XNU/bsd/dev/sweet_usb.c:1064-1085`.
2. **Event-driven touch + keys, bounded fallback and shared housekeeping deadlines:** **UNVERIFIED gain** removes a portion of nominal 150/s input-thread wakes and 10/s log wakes during inactivity; no battery percentage. Risk medium-to-high (lost input/reset combo); effort medium-to-large. Same snapshot checks, plus press/release every key, touch drag/release, and owner-controlled reset-combo test; expected `touch_polls`/`keys_polls` idle deltas fall while HID delivery remains identical. Source: `XNU/bsd/dev/sweet_touch.c:1291-1308`; `XNU/bsd/dev/sweet_keys.c:115-157`; `xnu-avicii/patches/0077-sweet-usb-live-log.patch:68-74`.
3. **Core PSCI idle after resume/timer prerequisites:** **UNVERIFIED gain** potentially large idle energy reduction, unquantified; risk high, effort large. Check proposed per-core `psci_attempts/returns/errors/residency_ns` plus timer/SGI delivery and energy, initially on one secondary with a reviewed independent wake source; no suspend invocation is safe to prescribe from this static audit. Vendor prerequisite evidence: `DTS/lito-pm.dtsi:82-101,122-141`; missing integration evidence: `xnu-avicii/patches/0065-sweet-smp-psci.patch:28-39,345-385`.
