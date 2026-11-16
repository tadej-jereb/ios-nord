# Perf lane G — power drain with the screen off (system low-power states)

Read `perf-shared.md` first. **Owns:** `docs/perf-research/G-idle-drain.md`.

**Question:** with the screen off the phone should drop to a few mW (vendor: RPMh sleep sets,
AOSS sleep, CX/MX collapse, XO shutdown). We never enter any of it. Map what must be off or
voted down for the SoC to reach its sleep states, and the order to do it in.

Determine:
1. The vendor system sleep path: `lito-pm.dtsi` / live dts `qcom,lpm-levels` system level,
   `rpmh-rsc` sleep/wake TCS, `drivers/soc/qcom/rpmh-rsc.c` sleep sets, `msm_pm`/`lpm-levels.c`
   system modes, and what AOP needs (`qmp` messages, e.g. `ddr`/`cx` modes).
2. What keeps the SoC awake under our kernel: clocks we enable and never release (GPU clocks from
   0119+, UFS, USB, display, touch I²C), regulators our patches vote on (`sweet_rpmh.c`), GPIOs,
   timers (XNU's tick on the arch timer), and the USB Ethernet link itself.
3. The screen-off sequence: panel off (DSI commands from `avicii/panel.dtsi`), touch suspend
   (GT9886 sleep command; see `docs/GOODIX_GT9886.md`), GPU collapse (GMU slumber — HFI
   message from the GPU track), UFS hibern8, then CPU deep idle (lane B).
4. A staged plan, cheapest first, each step with how to measure drain (needs lane F's current
   reading; until then, battery % over time with the screen off).
