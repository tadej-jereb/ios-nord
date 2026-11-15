# Lane B — CPU idle states and a frequency governor

Scope: idle states + frequency governor. Thermal trips are lane E, idle current is lane F
(needs its gauge), overnight drain is lane G. Everything here is a plan; nothing was run on
the phone.

## 1. Summary

- Before 0115 the A76s sat at LUT row 0 (652 / 806 MHz) and the A55 at row 6 (1516 MHz); 0115
  pins every domain at the highest row that still allows all cores (8 = 1804, 7 = 2208, 7 = 2400)
  and 0116 pins the L3 at row 11 (1516) — **measured**, 0116 boot ring. That is above idle need
  and below what one busy thread could reach: rows past the max-core row are boost rows
  (`qcom-cpufreq-hw.c:490-505`), currently unreachable.
- Idle today is `dsb; wfi`, skipped for a WFE poll whenever a timer is armed (`cpu.c:528-537`,
  `:587-591`; `cpu_idle_latency=0`). No `CPU_SUSPEND` anywhere in the tree, only `CPU_ON` (0065).
- The DT has no `idle-states`/`arm,psci-suspend-param` at all — idle is `qcom,lpm-levels` and the
  suspend parameter is Qualcomm's own encoding (`lpm-levels.c:48-49`); the ladder is reusable
  verbatim (`refs/lito-dts/lito-pm.dtsi:16-142`).
- Plan: (A) instrument, (B) governor on PERF_STATE, (C) PSCI C1, (D) C3/C4 per CPU plus the GIC
  restore XNU lacks, (E) cluster collapse last. Expect 0 fps lost (**estimated**), A76-rail and L3
  idle power down ~4-7x and a few °C (**estimated**; mW needs lane F, trips lane E). Hard numbers
  today: 1.2-1.6 % of one core idle load, bench 2.51-3.01 s.
- Risk is the resume path, not the governor: a reset wake needs a SWEET entry vector and per-CPU
  GIC restore; a wrong entry point hangs a core silently.

## 2. What the vendor does

**There is no DT idle-state table.** `grep -n "idle-states\|arm,psci-suspend-param"` over
`live.dts` (29 817 lines) and over `avicii/lito.dtsi` returns nothing. `psci` is
`compatible = "arm,psci-1.0"`, `method = "smc"` (`live.dts:363-366`), so the extended
power-state encoding (`uapi/linux/psci.h:68-72`, type = bit 30 = loses context) is in force.

**The ladder** (`refs/lito-dts/lito-pm.dtsi`, decimal values in `live.dts`; µs, entry / exit /
min-residency):

| node | label | psci mode | entry | exit | min resid | flags |
|---|---|---|---|---|---|---|
| `pm-cluster-level@0` | `l3-wfi` | 0x1 | 660 | 600 | 1260 | — |
| `pm-cluster-level@1` | `l3-pc` | 0x4 | 2752 | 3048 | 6118 | `is-reset`, `min-child-idx 2` |
| `pm-cluster-level@2` | `cx-off` | 0x224 | 3638 | 4562 | 8467 | `is-reset`, `min-child-idx 2`, `notify-rpm` |
| `pm-cluster-level@3` | `llcc-off` | 0xc24 | 3263 | 6562 | 9826 | `is-reset`, `min-child-idx 2`, `notify-rpm` |
| silver `pm-cpu-level@0` | `wfi` | 0x1 | 61 | 60 | 121 | — |
| silver `pm-cpu-level@1` | `pc` | 0x3 | 549 | 901 | 1774 | `is-reset`, bc timer |
| silver `pm-cpu-level@2` | `rail-pc` | 0x4 | 702 | 915 | 4001 | `is-reset`, bc timer |
| gold `pm-cpu-level@0` | `wfi` | 0x1 | 55 | 66 | 121 | — |
| gold `pm-cpu-level@1` | `pc` | 0x3 | 523 | 1244 | 2207 | `is-reset`, bc timer |
| gold `pm-cpu-level@2` | `rail-pc` | 0x4 | 526 | 1854 | 5555 | `is-reset`, bc timer |

(`lito-pm.dtsi:16-58` cluster, `:73-102` silver, `:113-142` gold; live copies at
`live.dts:11064-11106`, `:11120-11149`, `:11160-11189`. Note the two A76 cores are their own
PSCI clusters — MPIDR Aff1 0x600/0x700, `avicii/CONSTANTS.md` §1 — yet the vendor hangs both
`pm-cpu` groups off the single `L3` cluster node, because that node is the shared CX/L3 domain,
not a hardware cluster.)

**The parameter encoding** is built by `psci_enter_sleep()`
(`drivers/cpuidle/lpm-levels.c:1353-1394`, branch `lineage-21`):

```
state_id  = sum(cluster_mode & mask << shift)   /* shift 4, mask 0xfff for the L3 node */
          + cpu_level.psci_id                    /* shift 0, mask 0xf */
          | is_reset << 30                        /* lpm-levels.c:48 */
          | (affinity_level & 3) << 24            /* lpm-levels.c:49, ++ per collapsed level */
```

then `arm_cpuidle_suspend(state_id)` → `psci_cpu_suspend(state, entry_point)` →
`invoke_psci_fn(0xC4000001, state, entry, 0)` (`arch/arm64/kernel/cpuidle.c:39-44`,
`drivers/firmware/psci.c:176-182, 436-453`). Because bit 30 is set on every `is-reset` level,
Linux routes those through `cpu_suspend()` and passes `__pa_symbol(cpu_resume)` as the entry
point (`psci.c:447-450`). Exact values for our ladder, computed with the formula above:

| state | value |
|---|---|
| `wfi` | `0x00000001` |
| `pc` (either cluster) | `0x40000003` |
| `rail-pc` (either cluster) | `0x40000004` |
| `l3-wfi` + `wfi` | `0x01000011` |
| `l3-pc` + `pc` | `0x41000043` |
| `cx-off` + `rail-pc` | `0x41002244` |
| `llcc-off` + `rail-pc` | `0x4100c244` |

**Cluster levels are aggregated, never taken unilaterally.** `cluster_prepare()` only lets a
level be used once `num_children_in_sync` equals every CPU of the cluster, and `min_child_idx 2`
means every CPU must already be at `rail-pc` or deeper (`lpm-levels.c:1144-1210`, exit side
`:1225-1283`). The cluster `default_level` is fixed at 0 and contributes no bits while the
cluster stays there (`lpm-levels-of.c:377-378`, `lpm-levels.c:1331`).

**Selection** (`cpu_power_select`, `lpm-levels.c:666-790`): expected sleep is
`tick_nohz_get_sleep_length()` and the next armed event timer minus the level's exit latency;
the level is rejected if `PM_QOS_CPU_DMA_LATENCY` is below the exit latency, and a level is
only kept while the predicted/expected sleep stays under its `max-residency-us`. Prediction is
a 5-sample histogram of past sleeps and IPIs, overridden by min/max residency. No level is
entered when the CPU is isolated.

**Per-CPU state that a reset level must restore.** `cpu_prepare()` calls `cpu_pm_enter()` for
every `is_reset` level (`lpm-levels.c:1301-1302`). The notifiers that hang off it:
ICCs — on our SoC `GICD_CTLR.DS` is 0 (two security states, patch 0004 on `pe_fiq.c`), so
`gic_cpu_pm_notifier()` does nothing on ENTER and on EXIT runs `gic_cpu_sys_reg_init()`
unconditionally: SRE, PMR (0xF0), BPR1 = 0, ICC_CTLR EOImode, AP1R0-3 = 0, IGRPEN1 = 1
(`drivers/irqchip/irq-gic-v3.c:971-985` and `:671-780`); redistributor wake is only done when
DS = 1, so at `cx-off` we own that handshake ourselves. Timers — `CNTKCTL_EL1` save/restore
only (`drivers/clocksource/arm_arch_timer.c:1100-1114`). The CPU levels also switch to the
broadcast timer before entry (`qcom,use-broadcast-timer` + `tick_broadcast_enter()`,
`lpm-levels.c:1370-1373`).

**Frequency.** The only control is an index write to the domain's `PERF_STATE`
(`writel_relaxed(index, REG_PERF_STATE)`, `drivers/cpufreq/qcom-cpufreq-hw.c:283-298`; register
at `0x18323000/0x18325800/0x18327800 + 0x920`). Rows are 32-byte `[31:30] src, [7:0] L
(MHz = L*19.2), [18:16] cores` (`:444-470`); rows allowing `max_cores-1` are boost rows and
the driver jumps to `index+1` for them (`:490-505`), everything shallower is
`CPUFREQ_BOOST_FREQ`. Level choice is schedutil out of utilisation; on top of it `cpu-boost`
applies an input-event floor: min = `input_boost_freq` for `input_boost_ms = 40` after any
input, rate-limited to one boost per 150 ms (`drivers/cpufreq/cpu-boost.c:57, 64, 232-247`).
The L3 equivalent is a devfreq-fw voter set under one lock that takes the max vote
(`drivers/devfreq/devfreq_qcom_fw.c:70-80`).

Thermal: LMh clamps the domains in hardware regardless of what we write
(`qcom,lmh-dcvs` on every CPU node, `lito.dtsi:64`; 0116's header comment). Trips and the
software cap are lane E's.

## 3. What we do today

- 0115 requests the top non-boost row of every domain at boot and prints the table
  (`xnu-avicii/patches/0115-avicii-cpufreq-max.patch:114-131`). Measured rows before/after:
  A55 `row 6 (1516) -> row 8 (1804)`, gold `row 0 (652) -> row 7 (2208)`, prime
  `row 0 (806) -> row 7 (2400)` (`logs/phone/20261115-092905-usb-kernel-0116/ring-pre.txt`).
  0116 adds the L3 as a fourth domain and pins it too: `(L3) row 7 (1209) -> row 11 (1516)`
  (same ring; base `0x18321000`, perf `0x920` per `0116-...:79`).
- 0116 also exposes `kern.sweet_cpufreq` (whole table, `req row`, measured domain cycle counter,
  `loop MHz per cpu`, tsens), the rw caps `kern.sweet_cpufreq_cap` / `kern.sweet_l3_cap`, and
  `kern.sweet_bind`; `sweet_fb_bind_presenter()` binds the presenting thread to `sweetbind`
  (default 7) (`0116-...:236-345, 441-476, 485`).
- Nothing recomputes anything: after the one-shot write the register keeps the value. Idle is
  plain WFI (`osfmk/arm64/cpu.c:587-591`) — `HAS_RETENTION_STATE` is not defined for SWEET
  (`pexpert/pexpert/arm64/SWEET.h`, patch 0004:220-260, only `HAS_GIC_V3`), so the Architected
  retention form is not used either.
- `MAX_CPU_CLUSTERS 1` (`patch 0004:319`) and `hw.nperflevels 1` — XNU sees one cluster for all
  eight cores, so `ml_cluster_wfe_timeout(0)` is always 0 and per-cluster logic never fires.
- `PE_arm64` idle actually goes the WFE route whenever a deadline is armed:
  `cpu_proximate_timer()` = `!SetIdlePop()` (`cpu.c:372-375`), `SetIdlePop()` returns TRUE for
  any `rtcPop > now` because `cpu_idle_latency` is 0 (`osfmk/arm/rtclock.c:412-436`;
  `cpu_idle_latency` is set from the ADT's `powergate_latency`,
  `osfmk/arm64/machine_routines.c:1394`, and `avicii/tools/mkadt*.py` emits no such key). So a
  "replace the `wfi`" hook alone would run on almost no idle entry.
- PSCI exists only for `CPU_ON` = `0xC4000003` (`patch 0065:30-42`). `CPU_SUSPEND` is unused.
  A reset-wake path *does* exist and is unused: `resume_idle_cpu` → `arm_init_idle_cpu()`
  (restores the active thread, PAN, user TTB, TLB, `cpu_idle_exit(TRUE)`;
  `osfmk/arm64/start.s:283-287`, `osfmk/arm/arm_init.c:788-830`) with the physical address kept
  in `cpu_data_ptr->cpu_reset_handler` (`cpu.c:1229`). It expects Apple's monitor convention
  (x20 = BootArgs PA, x21 = cpu_data PA, `start.s:306-308`), which `NO_MONITOR 1` never sets up.
- `sched_perfcontrol_*` are all no-op defaults; `sched_perfcontrol_register_callbacks()` is
  never called (`osfmk/arm/machine_routines_common.c:121-130, 165-175`).
- Load today, measured: idle 1.2-1.6 % of one core total, backboardd 61-71 % while scrolling
  and 21 % right after (`logs/phone/cpu-scroll-20261115-0115.txt`), 30 M dependent adds
  2.51-3.01 s (`logs/phone/bench-20261115-0115.txt`).

## 4. Plan

Each step is independent, sits behind a boot-arg, and is safe to ship without the next one.
Nothing touches partitions.

### Step A — instrumentation (no behaviour change)

1. Extend the `kern.sweet_cpufreq` report (`bsd/dev/sweet_cpufreq.c`, 0116 `:250-290`): print
   `VOLT_LUT` (`0x114`, `[11:0] µV×1000`, `qcom-cpufreq-hw.c:470-471`) next to every row, print
   rows up to the last non-boost row instead of capping at `top`, and add per-CPU idle counters
   (entries, µs in each state, longest) filled by the step-B/C hooks.
2. Boot-arg `sweetgov=0|1` (default 0 for the first boot), and make the governor refuse to
   request a row above `min(cap, thermal cap)`.
3. Measure: `sysctl kern.sweet_cpufreq` gives rows, volts, per-CPU counters, `loop MHz per cpu`
   and temps; frame rate from `sweetfb_swaplog=60` (one `SWEET FB: swaps N t us` line per second,
   `0114-...:326-345`) — two lines give fps; `ps -A -o %cpu` for load.
   Risk: none.

### Step B — governor (frequency only)

4. New `sweet_gov_tick()` on `timeout()` every 20 ms (BSD side, like `sweet_cpufreq.c`): for each
   cluster count CPUs busy since the last tick (busy = entered `cpu_idle` and left again, or a
   `cpu_idle` stamp pair) and the runnable count; map to a row:
   * A76 domains: row 0 at 0 busy / 0 runnable, one boost step above `top` when exactly one
     thread runs there and the previous tick was also busy, `top` otherwise. Never row 0 while a
     thread is bound to that CPU (`sweetbind`) and runnable.
   * A55 domain: scale over its non-boost rows.
   * L3: 2 rows down at idle, back to `top` on any tick with a busy A76 or a frame commit.
   * Boost: `sweet_hid_touch()` (`patch 0058`, `bsd/dev/sweet_hid.cpp` entry point) and
     `AppleCLCD::swap()` (`sweet_fb_bind_presenter()` call site, `0116-...:485`) set every domain
     to `top` for 100 ms, one boost per 100 ms (vendor analogue 40 ms / 150 ms,
     `cpu-boost.c:57,64`). These run on the input and present paths, so only a flag store plus
     the boost expiry work is deferred.
5. Keep the write path exactly as today (`dmb oshst; str; dsb osh` on `PERF_STATE`,
   `0115-...:127-129`); from interrupt context only raise, lower from the tick.
6. Measure: idle `counter MHz` should fall to ~650/800 and `loop MHz` to the row; fps from
   `swaplog` must not drop (scroll test); temps via lane E's readings; `kern.sweet_cpufreq_cap`
   writes must still win. Risk: none, revert with `sweetgov=0`.

### Step C — PSCI `wfi` state per CPU

7. `sweet_cpu_suspend(uint32_t state)` next to `sweet_psci_cpu_on` (`patch 0065:30-42`): same
   register-clobber list, `x0 = 0xC4000001`, `x1 = state`. Call it with DAIF masked, which is
   already the case at the idle site.
8. Insert it at both idle sites instead of the WFI *and* instead of the proximate-timer WFE loop
   (`cpu.c:528-537`, `:587-591`): compute `(rtcPop - now)` in ns and, when it is under
   `exit_latency + 1 ms`, fall through to today's WFE/WFI unchanged; otherwise `0x1`.
   `PERF_STATE`, GIC and timer are untouched by `wfi`; the only restore is that the SMC returns
   in place.
9. Measure: per-CPU idle counters must show WFI-state residency; `AFFINITY_INFO` is not needed
   because the core never leaves the OS. Failure signature to log first: SMC return value
   (`PSCI_RET_*`, `psci.c:150-166`) — anything non-zero means firmware rejected the state, and
   the code falls back. Risk: a core that does not come back; the SMC returns, so only a firmware
   bug can do that. Gate `sweetidle=0` off.

### Step D — `pc` and `rail-pc` per CPU (reset levels)

10. Add `sweet_idle_resume()`, a SWEET physical entry modelled on `sweet_secondary_entry`
    (`patch 0065:337-380`): DAIF masked, `CurrentEL` check with the same EL2 fixups
    (`VBAR_EL2`, `HCR_EL2`, `CNTVOFF_EL2`, `ICC_SRE_EL2` bits), then select `CpuDataEntries` by
    MPIDR and call `arm_init_idle_cpu()` (`arm_init.c:788`) — do not call `resume_idle_cpu`,
    it wants the monitor's x20/x21. Store its physical address in
    `cpu_data_ptr->cpu_reset_handler` (`cpu.c:1229`) and pass it as SMC `x2`.
11. On resume, before `cpu_idle_exit`, run the ICC/CNTV restore in the order of
    `gic_cpu_sys_reg_init` (`irq-gic-v3.c:686-760`): `ICC_SRE_EL1` |= 1, `ICC_PMR_EL1 = 0xFF`
    (ours, `0xA0` priorities), `ICC_BPR1_EL1 = 0`, `ICC_CTLR_EL1` EOImode clear,
    `ICC_AP1R0-3_EL1 = 0`, `ICC_IGRPEN1_EL1 = 1` — the same values `pe_init_fiq()` writes today
    (`patch 0004:167-186`), then `CNTV_CTL_EL0 = 1`, `CNTP_CTL_EL0 = IMASKED` and
    `CNTKCTL_EL1` as `fiq_context_init`/`_enable_virtual_timer` do
    (`machine_routines.c:2244-2258`). At `cx-off` and deeper also the redistributor handshake
    from `pe_fiq.c:126-141` (`GICR_WAKER.ProcessorSleep` clear, spin on `ChildrenAsleep`) and
    rewrite `GICR_ISENABLER0` for INTID 19 and SGI 1. Arm the wakeup by writing `CNTV_TVAL_EL0`
    (`ml_set_decrementer`, `machine_routines.c:2028-2043`) *before* the SMC.
12. Thresholds from the table: silver `pc` needs 901 µs of stay, `rail-pc` 4001 µs; gold 1244 /
    5555 µs. States: `0x40000003` and `0x40000004` for both clusters.
13. Measure: idle counters and `loop MHz`; a `cpuload` scroll must not change fps; a stuck core
    shows as a missing CPU in `loop MHz per cpu`. Risk: **hang** — the entry vector, the GIC
    restore order and the timer programming are each fatal if wrong. Boot with one core
    (`cpus=1`) first, then 2, then 8; keep `boot_b` untouched (it is).

### Step E — cluster collapse (only after D is stable)

14. Vote protocol mirroring `cluster_prepare`: a per-CPU vote of its current state index; the
    cluster bits (`0x10`, `0x40`, `0x2240`, `0xc240`) only when all eight votes are ≥ 2 and every
    CPU's next deadline exceeds the cluster `min-residency-us` (6118 / 8467 / 9826), and the
    entering core adds `1 << 24`. Start with `l3-wfi` (no reset, no restore), then `l3-pc`.
15. `cx-off` additionally needs the L3/GIC redistributor restore of step 11 plus
    `notify-rpm`-equivalent RPMh wake votes; `llcc-off` loses the L3 contents (`is-reset`), so it
    needs a cache-warm measurement of its own before it is default.
16. Measure: idle counters, `loop MHz` (after wake the core must be at a real clock, not 0),
    temps, fps. Risk: **hang/regression**; keep `l3-wfi` gated by `sweetidle=2`.

### Notes for the implementer

- 0115's `top` is *not* fmax: it is the top row that still allows every core. The per-core boost
  rows sit past it and are currently unreachable, so `sweetbind`-ed single-thread work is
  capped. Step B's "one boost step above `top`" recovers that; printing the rows in step A is
  what makes it safe.
- `kern.sweet_cpufreq_cap` is the contract with lane E: the governor reads it every tick, and a
  write must re-clamp the current request.
- The `wfi` boot-arg (default 1, `tooling/71-phone-image.sh:43` passes no override) disables the
  whole idle path; `sweetidle` must compose with it, not replace it.
- ADT: `powergate_latency` (per CPU, ns) makes `cpu_idle_latency` non-zero, which makes
  `SetIdlePop()` return early-armed pops and lets step C/D stop at the right distance from the
  deadline. Without it the governor's own threshold is the only guard.

## 5. Open questions only a phone run answers

1. `PSCI_VERSION` (`0x84000000`) — the value and whether `CPU_SUSPEND` is advertised in
   `PSCI_FEATURES` at all. Everything in C-E is predicated on firmware accepting it.
2. Does `CPU_SUSPEND` with bit 30 set return in place, or jump to the entry point argument? One
   read-only call with a parked core answers it (SMC return vs. resume location), and it decides
   whether step D's vector is needed or merely prudent.
3. Does `CNTV_CVAL_EL0/TVAL_EL0` survive `pc` / `rail-pc`? If not, the wake timer must come from
   a broadcast source and the min-residency thresholds have to include the rearm cost.
4. Does `GICR_ISENABLER0` survive `cx-off` on this device (DS = 0 view), and does the
   redistributor handshake work from non-secure at all? Step 11 assumes it does.
5. Do `PERF_STATE` writes take effect while a domain is fully clock-gated, or do they need one
   running core to land? That decides whether the governor can lower an idle cluster at all.
6. How much idle current does each state actually save? Lane F's gauge; until then every mW
   figure in §1 stays estimated.
7. Does LMh ever clamp below the governor's request on this unit, and does a clamp show up in
   `PERF_STATE` or only in the measured clock?
8. What does 0.6 / 1.2 / 1.8 s of idle do to UI latency before a touch is served — i.e. the real
   cost of `pc` for the presenter's core, which `sweetbind` currently pins to CPU 7.
