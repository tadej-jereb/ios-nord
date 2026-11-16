# Perf lane E — thermal limits and throttling

Read `perf-shared.md` first. **Owns:** `docs/perf-research/E-thermal.md`.

**Question:** we read tsens temperatures (patch 0118, `kern.sweet_cpufreq`: 41–53 °C seen) but
nothing limits anything while every core runs at max. What are the vendor's trip points and
mitigations, and what must our kernel do so sustained load stays safe?

Determine:
1. Sensors: every tsens channel on lito (live dts `tsens0`/`tsens1`, `thermal-zones`: names like
   `cpu-0-0-usr`, `gpuss-*`, `skin-therm` / `xo-therm` ADC thermistors on the PMIC) and which of
   them we already read (0118: TM bases 0xc263000/0xc265000).
2. Vendor policy: `thermal-zones` trips (passive/hot/critical), cooling maps (cpufreq caps per
   cluster, GPU levels, `qcom,cpu-isolate`), and the OnePlus thermal engine config if it is in the
   vendor image (`/vendor/etc/thermal-engine*.conf`, from the LOS zip already in
   `src/lineage-21.0-20240619-nightly-avicii-signed.zip` → payload → vendor; extract into
   `~/.hermes/cache/scratch/perf-e/` only).
3. Hardware protection that exists regardless of software (tsens critical reset, LMh/OSM limits) —
   so we know what fails safe and what does not.
4. iOS side: what `thermalmonitord` expects from the kernel (IOKit thermal sensors / `IOPMrootDomain`
   thermal notifications) so that iOS itself throttles apps and shows the hot-phone UI.
5. Plan: a minimal in-kernel throttle (caps via `kern.sweet_cpufreq_cap` mechanism) with trip
   values cited from the vendor, and the measurement (sustained load test over SSH, temperature log).
