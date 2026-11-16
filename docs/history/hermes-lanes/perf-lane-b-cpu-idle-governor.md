# Perf lane B — CPU idle states and a frequency governor

Read `perf-shared.md` first. **Owns:** `docs/perf-research/B-cpu-idle-governor.md`.

**Question:** today all 8 cores and the L3 run at max clock all the time (patches 0115/0116,
`kern.sweet_cpufreq_cap`, `kern.sweet_l3_cap`) and idle with plain WFI. That buys speed but
costs heat and battery. Plan a governor and deep idle that keep the UI fast.

Determine:
1. **Idle states:** the PSCI `cpu_suspend` states for Silver/Gold cores and the cluster from
   `refs/lito-dts/lito-pm.dtsi` / live dts (`qcom,lpm-levels`, `idle-states`, `arm,psci-suspend-param`,
   entry/exit latencies, residency), and the vendor `drivers/cpuidle/lpm-levels*.c` sequence. What
   XNU's idle path (`machine_idle`, `cpu_idle` in `osfmk/arm64/`) needs to issue PSCI
   CPU_SUSPEND safely (timer, GIC wake-up, per-CPU state restore). PSCI conduit: the same SMC as
   CPU_ON in patch 0065.
2. **Frequency:** the OSM / EPSS (cpufreq-hw) interface we already drive in `sweet_cpufreq.c`
   (patch 0116): the LUT, the per-domain perf-state register, and how the vendor `schedutil` +
   `cpu-boost` (input boost on touch) pick levels. Propose a governor that fits XNU: e.g. load from
   `processor` idle time, boost on touch events (`sweet_touch.c`) and on frame commits.
3. **XNU side:** how XNU's scheduler/CLPC sees this SoC (we fake `cpufamily` via 0117), whether
   `perfcontrol` callouts (`sched_perfcontrol_*`, `machine_perfcontrol_*`) can drive the governor,
   and how to keep backboardd's render thread on a Gold core (we bind it to CPU 7 today).
4. **Thermal interplay:** coordinate with lane E (do not duplicate it): which limit the governor
   must respect.
5. Measurement plan: idle current (needs lane F's gauge), temperatures (tsens via
   `kern.sweet_cpufreq`), frame time (backboardd thread timing as in `logs/phone/bbd-threads-*`).
