# Perf lane D — display path: refresh rate, TE, scanout without a CPU copy

Read `perf-shared.md` first. **Owns:** `docs/perf-research/D-display.md`.

**Question:** iOS renders 1125×2436 into a buffer that `SweetFramebuffer.cpp` (in the series) hands
to the panel (1080×2400 AMOLED, 90 Hz capable). How does a frame get from iOS to glass today, what
does it cost, and what does the vendor display stack do that we should copy — including 90 Hz?

Determine:
1. Today: read `SweetFramebuffer.cpp` / `SweetSurface.cpp` and the `sweetfb_*` boot-args in
   the series: who copies/scales the 1125×2436 image to the 1080×2400 panel, on which CPU, how
   long it takes (`logs/phone/` timings), how pacing works (`sweetfb_hz`).
2. Panel: `avicii/panel.dtsi` and live dts `qcom,mdss_dsi_*` for this panel: video vs command
   mode, supported refresh rates (60/90), TE GPIO / `qcom,mdss-dsi-te-*`, the DSI and MDP clock
   needs per mode, and the commands that switch 60↔90 Hz.
3. MDP/DPU: the vendor `drivers/gpu/drm/msm/sde/` pipes (SSPP) and the hardware scaler: can MDP
   scale 1125×2436 → 1080×2400 and composite planes, so the CPU never touches pixels? Registers and
   the SMMU stream for MDP (needed for zero-copy; see `docs/gpu-research/README.md` scanout notes).
4. Alternative: render at native 1080×2400 (iOS display zoom / a different `product` in the ADT)
   — what breaks, what it saves.
5. Plan in order (cheapest first) with risk and how to measure (frame time, vsync jitter).
