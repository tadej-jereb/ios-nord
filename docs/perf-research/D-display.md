# Lane D — display path: refresh rate, TE, scanout without a CPU copy

Scope: how a frame gets from iOS to glass today, what it costs, what the vendor display stack
does that we should copy, and what 90 Hz and native 1080×2400 would take. Research only, nothing
was built or flashed for this report. Sources: the live FDT
(`~/.hermes/cache/scratch/perf-inputs/live.dts`, sha256 `de87b3009781a8b1…`), the vendor dts in
`avicii/`, the vendor kernel (LineageOS `android_kernel_oneplus_sm8250`, branch `lineage-21`,
files fetched to `~/.hermes/cache/scratch/lane-d/vk/`), our patches in `xnu-avicii/patches/`,
and the captured phone logs in `logs/phone/`.

## 1. Summary

* **Path today: no scaler, no display engine.** `AppleCLCD::present` memcpys iOS's 1125×2436 BGRA surface into panel memory at `0xa0000000`, one core, 2400 rows × 4320 B = **10 368 000 B/frame**; 1125×2436→1080×2400 is a **centre crop** (offset 22/18), not a scale (`0046`, `0056`, `0061`).
* **MEASURED (phone):** backboardd SwapEnd rate median **17.3 fps** (`live-20261115-0115-cpufreq.txt`, 49 intervals) and **22.7 fps** (`live-20261115-0116-cpu.txt`, 17), best 60.1; backboardd **169 / 242 / 379 %** of one core in the three `cpu-scroll-20261115-*` samples, peak 615 %.
* **MEASURED→derived:** at the repo's only phone copy figure (~600 MB/s, `docs/anonbeat1-NOTES.md:769`) one frame costs **≈17.3 ms of one core**; 60 Hz would be 622 MB/s, i.e. the ceiling — which is why `sweetfb_hz` had to be 10 (`0056`).
* **The hardware can do it:** VIG0's QSEED3-lite scaler (live.dts:23735-23738) scales 1125×2436→1080×2400 on a fractional phase step (`sde_plane.c:877-882`), fetching via apps-SMMU SID `0xb40` (live.dts:23842); the CPU never touches pixels.
* **ESTIMATED gain, zero-copy (D3):** ≈0.35 core freed at 20 fps, ≈1 core at 60 Hz, 10–15 ms off per-frame latency — not 0, because an ~11 MB cache clean (est. 2–4 ms) replaces the 17.3 ms copy.
* **ESTIMATED gain, TE-locked pacing (D2):** up to 16.7 ms of vsync phase error plus the current tear/double-present window removed; no throughput gain on its own.
* **90 Hz (D5):** one DCS write (`0x60 = 0x10`, panel.dtsi:511-521); cannot lift fps above a 17–23 fps renderer — it cuts worst-case refresh wait 16.7→11.1 ms and needs the MDP transfer budget 12000→8000 µs (panel.dtsi:490).
* **Native 1080×2400 (D4):** 5.4 % fewer bytes and, with D3, **no scaler at all** (`SRC_SIZE == OUT_SIZE`, stride 4320); what breaks is UIKit's status-bar provider (`0061`), not the display path.
* Order: **D1** measure/probe (no behaviour change) → **D2** TE pacing → **D3** zero-copy scanout → **D4** native size → **D5** 90 Hz.
* Prior art that ran on real hardware: `refs/ry-diffusion-Bergamota/xnu/patches/0126` (the same QSEED3 registers, written from XNU) and `refs/marnov999-raphael-ios-gpu/xnu/patches/0128` (panel TE as the vsync source).

## 2. What the vendor does

### 2.1 The panel (live.dts:26443-…, `avicii/panel.dtsi`)

* Samsung **AMS644VK04**, `qcom,mdss-dsi-panel-type = "dsi_cmd_mode"` (live.dts:26449,
  panel.dtsi:19), 1080×2400, `qcom,mdss-dsi-bpp = <0x18>` (8 bit per channel), DSC compressed,
  `qcom,mdss-dsi-traffic-mode = "burst_mode"`, 4 lanes.
* **TE is used**: `qcom,mdss-dsi-te-pin-select = <0x01>`, `-te-dcs-command = <0x01>`,
  `-te-check-enable`, `-te-using-te-pin` (live.dts:26469-26477), and the DSI display node maps the
  pin: `qcom,platform-te-gpio = <0x19 0x0a 0x00>` = GPIO 10 on phandle `0x19`
  (live.dts:27886), `qcom,panel-te-source = <0x00>`.
* Two timings, **both at the same DSI clock** `qcom,mdss-dsi-panel-clockrate = <832000000>`
  (panel.dtsi:81 and :493):

  | | 60 Hz (timing@0) | 90 Hz (timing@1) |
  |---|---|---|
  | panel.dtsi lines | 77-99 | 489-511 |
  | v-back / v-pulse / v-front | 8 / 4 / **1208** | 8 / 4 / **4** |
  | h-front/back/pulse | 52 / 24 / 24 | 52 / 24 / 24 |
  | `qcom,mdss-mdp-transfer-time-us` | 12000 | **8000** |

  Arithmetic on those numbers (mine): vtotal 3620 lines @ 60 Hz and 2416 @ 90 Hz, htotal 1180 both
  → pixel clock **256.3 MHz** and **256.6 MHz**. The mode is the same transfer rate with the
  vertical blanking taken out; that is why the DSI PLL coefficient does not change.
* Vendor kernel: `bit_rate = bit_clk_rate_hz * num_of_lanes; pclk_rate = bit_rate / bpp`
  (`dsi_display.c:4423-4427`) → 832 Mb/s per lane × 4 = **3.328 Gb/s** aggregate, byte clock
  104 MHz per lane. Both modes keep it.
* **The 60↔90 switch is one DCS register**: unlock `F0 5A 5A`, write `0x60 = 0x10` (90 Hz) or
  `0x00` (60 Hz), lock `F0 A5 A5`; 60 Hz also sets `E6 02` and `B0 69/E6 02, B0 77/E6 B3`,
  90 Hz sets `E6 00` (panel.dtsi:99-116 and 511-521). The driver applies it per-timing
  (`qcom,mdss-dsi-timing-switch-command`), with `qcom,dynamic-mode-switch-enabled` and
  `-type = "dynamic-switch-immediate"` (panel.dtsi:60-61).

### 2.2 The pipeline

* MDSS/DPU register block at **`0xae00000`** (`mdp_phys` 0xae00000 +0x84208, vbif at 0xaeb0000,
  live.dts:23671-23672). Inside: 4 CTLs `0x2000/0x2200/0x2400/0x2600` (23683), mixer/LM
  `0x45000-0x48000` (23686), INTF `0x6b000/0x6b800/0x6c000/0x6c800` with types
  `"dp dsi dsi dp"` (23703-23704) → **DSI0's interface is INTF1 at `0x6b800`**, ping-pong blocks
  `0x71000-0x72800` (23706), SSPPs `0x5000` (VIG0), `0x7000` (VIG1), `0x25000/0x27000/0x29000`
  (DMA0-2) (23722), DSC `0x81000/0x81400` (23715).
* Clocks: DISPCC only. `disp_cc_mdss_mdp_clk_src` max **460 MHz** (`dispcc-lito.c:456-461`), dts
  `clock-rate` `0x1b6b0b00` = 460 000 000 for `core_clk` and `lut_clk`, `0x124f800` = 19.2 MHz for
  `vsync_clk`, `0xbebc200` = 200 MHz `rot_clk` (live.dts:23675). The dts carries the *same* 460 MHz
  as `clock-max-rate` — the MDP is provisioned at its ceiling from boot.
* Command mode with TE: the vendor encoder arms the panel's tear check and uses the TE-derived
  read-pointer interrupt as the frame signal — `_sde_encoder_phys_cmd_config_autorefresh`
  (`sde_encoder_phys_cmd.c:101-137`, `setup_autorefresh` on the INTF when `has_intf_te`) and
  `sde_encoder_phys_cmd_te_rd_ptr_irq` (`:272-320`, stamps `wr_ptr_line_count`/`intf_frame_count`).
  A new frame is one CTL flush latch; the panel pulls it on its own TE, so the display never waits
  for the host.

### 2.3 Can MDP scale 1125×2436 → 1080×2400?

Yes, and it is the SSPP's normal mode of operation:

* Scaling is expressed as a **phase step**, not a fixed-ratio filter:
  `phase_step_x[C0] = mult_frac(1 << PHASE_STEP_SHIFT, src_w, dst_w)` and the same for y
  (`sde_plane.c:877-882`), with the chroma components derived from it (887-896). Any ratio,
  fractional included, is representable.
* QSEED3 / QSEED3-lite is selected by dts and dispatched in `_sde_plane_setup_scaler`
  (`sde_plane.c:1288-1310`), programmed by `_sde_hw_sspp_setup_scaler3` →
  `sde_hw_setup_scaler3` (`sde_hw_sspp.c:595-608`). Defaults for an RGB layer with no explicit
  request are bilinear (`sde_plane.c:938-943`: `y_rgb_filter_cfg = SDE_SCALE_BIL`,
  `blend_cfg = 1`, `enable = 1`).
* This board's scaler is the **lite** flavour: `qcom,sde-qseed-type = "qseedv3lite"`
  (live.dts:23735) → `SDE_SSPP_SCALER_QSEED3LITE` (`sde_hw_catalog.c:3539-3540`, features set at
  `:1145-1147`). The lite filter takes our ratio comfortably; the numbers that actually bound us
  are the line widths, and both fit:

  | limit | dts value | our frame |
  |---|---|---|
  | `qcom,sde-sspp-linewidth` | 0xb40 = 2880 (live.dts:23738) | src 1125 ✓ |
  | `qcom,sde-vig-sspp-linewidth` | 0x1000 = 4096 (23739) | src 1125 ✓ |
  | `qcom,sde-mixer-linewidth` | 0xa00 = 2560 (23737) | dst 1080 ✓ |
  | QSEED3 downscale | < 4× (driver/hardware practice, `0126` guard) | 1.04× ✓ |
* Source address is a **32-bit** register (`SSPP_SRC0_ADDR 0x14`, written 32-bit,
  `sde_hw_sspp.c:26,778-781`), so whatever the MDP fetches must be below 4 GiB — either physical
  low memory or a low IOVA. Our DRAM starts at `0x1_8000_0000` (above 4 GiB, `0112` header
  comment), the splash carve-out `0xa0000000` is below it.

### 2.4 Zero-copy, the vendor way

The MDP fetches the layer straight out of an ION buffer whose IOVA comes from the apps-SMMU. The
stream for the display engine is `smmu_sde_unsec_cb → iommus = <&apps_smmu 0xb40 0x402>`
(live.dts:23842; secure `0xb41` and `0xf41`, :23851). apps-SMMU is `@15000000` (live.dts:28998).
So the MDP needs (a) a translation for SID `0xb40` covering the buffer, or (b) bypass. Nothing in
this path is CPU-visible; there is no copy anywhere in Vendor's present.

## 3. What we do today

### 3.1 The path, in code

* `AppleCLCD::start` takes the boot framebuffer that ABL left scanning out —
  `PE_current_console()` → `fPhys = 0xa0000000`, 1080×2400, stride 4320
  (`0046-sweet-iosurface-iomfb.patch:1127-1142`; constants in `avicii/CONSTANTS.md:66`,
  `docs/DIAG.md:28`) — wraps it as a `SweetSurface` and publishes an `IOSurface` for it.
* iOS is told the display is **1125×2436** (`kSweetFBGetDisplaySize` returns `fLogicalW/H`,
  `0061-sweet-iphone-x-display-size.patch:82-88`), because UIKit only has status-bar/layout data
  for real iPhone screens (`0061:9-16`). `sweetfb_native=1` reports the real panel size instead.
* `swap()` does no pixel work: it copies the 0x46c-byte swap record into `fPending` and sets
  `fDirty` (`0056-sweet-fb-throttled-present.patch:60-73`).
* The **IOTimerEventSource vsync** (`SWEET_FB_VSYNC_US 16667`, `0046:1057,1148-1153`) fires at a
  free-running 60 Hz, notifies clients (`SWEET_FB_NOTIFY_VSYNC`), and every `fFlushTicks` ticks
  (`60 / sweetfb_hz`, `0056:23-25`) calls `present(rec)`.
* `present()` walks up to 4 layers, and for each one clips the logical dest rect into panel space
  by subtracting `fOffX/fOffY` (`0061:63-75`) and then does, per row,
  `memcpy(fPixels + (dy+y)*fRowBytes + dx*4, src + s->offset + (sy+y)*s->bytesPerRow + sx*4, w*4)`
  (`0046:1284-1290`). **No scaling, no format conversion, no display engine.** `fPixels` is a
  write-combined kernel mapping (`0046:220`), the source is backboardd's own cacheable memory
  (wrapped client memory, `0108-sweet-sweetsurface-client-memory.patch:46-48,150`).
* Which CPU: whichever runs the AppleCLCD work-loop thread; the copy is not parallelised and
  holds `fLock` only in `swap()`, not during the copy itself.

### 3.2 Measured numbers (phone)

* The layer is 1125×2436 BGRA, **stride 4608**, 2 surfaces ping-ponging, dest rect `0,0 1125x2436`:
  `SWEET SURF: backboardd create id 2 1125x2436 fmt 0x42475241 bpe 4 bpr 4608 planes 0 size 11239424`
  at `logs/phone/20261114-202115-0112-usb/ring-post.txt:1552`,
  `SWEET FB: swap 2 layer 0 surface 2 1125x2436 fmt 0x42475241 bpr 4608 a 0,0 1125x2436 b 0,0 1125x2436`
  at the same file's `:1578` (and `logs/phone/live-20261115-0118.txt:199`).
  After `0061` clipping the copy reads from (22, 18) of a 4608-byte row and writes 1080×2400.
* SwapEnd cadence, computed from the `SWEET FB: swaps N t X us` lines (60 swaps per line):
  `live-20261115-0115-cpufreq.txt` (50 lines → 49 intervals) median **17.3 fps**, min 2.9, max 60.1;
  `live-20261115-0116-cpu.txt` (18 lines → 17 intervals) median **22.7 fps**, min 5.4, max 33.5. The
  0.2 and 0.0 fps readings are 347 s and 3494 s suspend gaps, not frame times. Bursts at
  exactly 60.0/60.1 fps (five consecutive intervals in 0115) are CA running at the display link.
* CPU: `ps`-style samples in `logs/phone/cpu-scroll-20261115-*.txt` — backboardd median
  **169 %** (0115), **242 %** (0115-reduce), **379 %** (novmd), max **615 %**; SpringBoard adds
  158–170 % during scroll.
* Copy cost: the only measured figure in the repo is `docs/anonbeat1-NOTES.md:769` — a 10 MB
  frame copy per swap "≈600 MB/s memcpy on the single CPU" at `cpus=1`, which starved everything.
  That is **≈17.3 ms per frame**. Everything downstream is ESTIMATED from it.
* Bandwidth implied by that: 20 fps × 10.368 MB = **207 MB/s**; 60 Hz → **622 MB/s** (at the
  measured ceiling); 90 Hz → **933 MB/s**.
* Boot args in use: `sweetfb_hz=10` or `60`, `sweetfb_noconsole=1`, `sweetecon=1`
  (`build/phone/ufsroot.*.cmdline` — the newest GUI builds run `sweetfb_hz=60`).

### 3.3 What it costs, stated plainly

1. One core spends ~17 ms per presented frame in the kernel, at exactly the moment CA wants to
   render the next one; with a median of 20 presented fps that is ~0.35 core-seconds per second.
2. The frame reaches glass at `next tick + copy`, i.e. up to 16.7 + 17.3 = **34 ms** after the
   swap (ESTIMATED). Nothing is synchronised to the panel's TE, so the tick and the panel drift.
3. 1125×2436 on a 1080×2400 panel is presented by **cropping**, not scaling: 22–23 columns are
   dropped on each side and 18–19 rows top and bottom (`(1125-1080)/2`, `(2436-2400)/2`).
4. The display engine (460 MHz core clock, running since ABL) is doing nothing but pushing the
   frame we memcpy into it.

## 4. Plan, cheapest first

Every step is a `xnu-avicii/patches/` change to `SweetFramebuffer.cpp` (plus a new small file
where noted), gated by a boot-arg so a bad guess boots to the copy path. Nothing here touches
`persist`, `modemst`, `xbl`, `abl`, `tz` or the GPT.

### D1 — Measure before changing anything (no behaviour change)

* Instrumentation inside `SweetFramebuffer.cpp`: `copy_us` (start/end
  `mach_absolute_time` around the row loop), presented/skipped counters, and a once-a-second
  `SWEET FPS: %u swaps, %u shown, %u late, in %llu ms` line (same shape as `raphael 0128`).
* One read-only probe at boot, `sweetfb_probe=1`: map `0xae00000` (`ml_io_map`, 0x120000) and
  `IOLog` VIG0 `SRC0_ADDR` (`+0x14`), `YSTRIDE0` (`+0x24`), `SRC_FORMAT` (`+0x30`), QSEED3
  version/op-mode (`+0xa00`, `+0xa04`), CTL0 layer/flush (`+0x2000`, `+0x2018`), INTF1
  (`+0x6b800`) config and the tear block `+0x6b800+0x288/0x294/0x298`. **No writes.**
* Also call `sweet_smmu` *read-only* for SID `0xb40`: does an SMR exist, is the S2CR bypass or a
  stage-1 bank (`0112` already has the walk; raphael's `0120:160-172` shows the same probe).
* Risk: none (reads). Measurement: the numbers in §3.2 become measured instead of derived; the
  probe answers open questions 1 and 2 below.

### D2 — TE-locked pacing (real panel TE instead of the free-running timer)

* On each tick, read INTF1's tear counter — `TEAR_SYNC_CONFIG_VSYNC` +0x288,
  `TEAR_VSYNC_INIT_VAL` +0x294, `TEAR_INT_COUNT_VAL` +0x298 (raphael `0128:32-36`, same INTF
  index; the read pointer advances at the configured lines/s from `VSYNC_CLK_HZ = 19200000`
  = our dts `vsync_clk` live.dts:23675) — and re-arm the timer to `last_TE + period/2` instead of
  a blind 16667 µs. `sweetfb_telock=1`, `sweetfb_telead=<µs>` guards.
* Registers: read-only on the tear block; the only write is the timer itself. No clock change.
* Risk: low. A wrong offset reads a plausible-but-wrong counter; it cannot hang the pipeline.
  Keep a `sweetfb_telock=0` fallback and log the measured TE period.
* Measurement: `SWEET FPS: … TE period %llu.%03llu ms` — expect 16.66 ms ±0.1 at 60 Hz; vsync
  jitter = stddev of (TE timestamp − tick timestamp), which today is unmeasured and unbounded.
  Frame-time p95 should stop jumping by a full tick.

### D3 — MDP zero-copy scanout: point VIG0 at the iOS surface (the real win)

* Pool: two canvases of 1125×2436 BGRA, stride 4608 (4608×2436 = 11 225 088 B of rows each; backboardd's
  own allocation of the same geometry is 11 239 424 B, log line below), inside `cont_splash_region`
  `0xa0000000 + 0x2300000` (35 MiB, live.dts / `CONSTANTS.md:66`) after the console frame — frees
  us from both the SMMU and the 32-bit `SRC0_ADDR` limit, and keeps the buffers inside whatever
  mapping ABL left for the MDP. 10.37 + 2×11.23 = **32.8 MB < 35 MiB** (fits, no third buffer).
* Program VIG0 (`0xae00000 + 0x5000`) exactly as `refs/ry-diffusion-Bergamota/…0126` does, which
  is the vendor's own sequence reimplemented: `SRC_SIZE`/`SRC_IMG_SIZE` (`0x00`/`0x04`) =
  1125×2436, `SRC_XY` `0x08` = 0, `OUT_SIZE` `0x0c` = 1080×2400, `OUT_XY` `0x10` = 0, pixel
  extension rects `0x100-0x128` zeroed with `REQ = src` (QSEED3 needs them), `SRC0_ADDR` `0x14`,
  `YSTRIDE0` `0x24` = 4608, and QSEED3 at `+0xa00`: phase init 0, `PHASE_STEP_Y_H/V` =
  `src<<21 / dst` = `1125<<21/1080` = **0x215555** and `2436<<21/2400` = **0x207AE1**
  (computed here; 2^21 = 1.0 fixed point, `sde_plane.c:877-882`), preload
  `4|3<<8|4<<16|3<<24`, `SRC_SIZE_Y_RGB_A`/`UV`, `DST_SIZE`, `OP_MODE` = enable | bilinear |
  blend_cfg (bit 16, 31; alpha bit 10 + 29/30 if the format has alpha).
* Latch with a **CTL0 flush** (`0xae00000 + 0x2000 + 0x18`, bit for VIG0 and CTL) and let the
  panel's TE pick it up; store the boot values first and restore them on panic so the console
  still appears (`0126`'s `sweet_mdp_restore` pattern).
* SMMU: only needed if the canvas is not below 4 GiB. Our `bsd/dev/sweet_smmu.c` (`0112`) creates
  one stage-1 bank identity-mapping `0x180000000…` for "thread context only" — that IOVA is above
  4 GiB, so for a high buffer it needs a **second bank with a low IOVA** (raphael `0120:74-78`:
  `IOVA_SLOT0 0x10000000`, 16 MB slots) and SID `0xb40` added to that bank; the splash-region
  pool avoids all of it.
* Cache: the MDP reads DRAM, so the scanned canvas must be cleaned after CA paints it —
  `flush_dcache64` / `dc cvac` over ~11 MB (≈86 k lines). **ESTIMATED 2–4 ms**, vs the 17.3 ms
  memcpy it replaces. Do not skip this: skipping it is the "garbage blocks / stale rows" failure
  mode beryllium documents (`DISPLAY_HW.md` §5.4).
* Boot-args: `sweetfb_mdp=1` (use the engine), `sweetfb_pool=splash` (buffer placement),
  `sweetfb_scale=1` (scale to fit rather than crop — this is what makes the 22-pixel crop go
  away), `sweetfb_mdp=0` to fall back.
* Risk: **medium**. Failure modes are all visible, none are bricking: wrong phase step → soft or
  aliased image; no cache clean → stale bands; wrong flush bit → frozen panel; wrong address →
  underrun/black. Keep the copy path one boot-arg away and never write DSC/INTF while the panel is
  the only console.
* Measurement: `SWEET FPS` shows `shown` == `swaps` with `copy_us` 0; backboardd %CPU drop from
  the `ps` samples; frame time p50/p95; visually the 45/36 cropped columns/rows come back
  (`sweetfb_scale=1`). This is the step that decides whether 60 Hz and 90 Hz are reachable at all.

### D4 — Native 1080×2400 (alternative, and the cheapest zero-copy of all)

* Today `sweetfb_native=1` already exists (`0061:35-44`); it reports 1080×2400 to userland and
  the crop/deskew offsets become 0 (`SweetHID` too, `0061:104-109`).
* What it saves: 5.4 % of the bytes per frame (10 368 000 vs 10 962 000), the two integer
  divisions of the clip, and — with D3 — **the scaler itself**: `SRC_SIZE == OUT_SIZE` and
  stride 4320 == the panel's row pitch, so QSEED3 can stay off and the register change is two
  writes (`SRC0_ADDR`, `YSTRIDE0`) plus a flush. Also no phase-step rounding, so no resampling
  softness at all, and the touch mapping becomes 1:1 (no 22/18 offset error at the edges).
* What breaks: UIKit has no per-device layout for 360×800 pt — that is exactly the reason `0061`
  exists ("No status bar visual provider for screen", red status bar, `0061:10-14`), plus every
  iPhone X-specific chrome decision (notch inset, safe areas, 3× assets sized for 375×812 pt).
* Risk: cosmetic, and it is a boot-arg test, not a code change. Measurement: same `SWEET FPS`
  frame times plus a screenshot of the status bar; compare iOS's own `backboardd` %CPU to see
  whether the smaller canvas helps the renderer at all.

### D5 — 90 Hz

* Kernel side is one DCS long write on the panel: unlock `F0 5A 5A`, `60 10`, lock `F0 A5 A5`,
  plus `E6 00` (panel.dtsi:511-521). We have no DSI driver; the cheapest carrier is the DSI
  controller's command DMA at `0xae94000` (`dsi_ctrl` reg, live.dts:27378) — the same mechanism
  raphael's `0128` uses to send a DCS long write from XNU (`:99`). Byte clock stays 104 MHz,
  DSI bit clock stays 832 Mb/s per lane, so **no DISPCC or PLL change**.
* What must change with it, or the panel will tear/underrun: the MDP's transfer budget —
  `qcom,mdss-mdp-transfer-time-us` 12000 → **8000** (panel.dtsi:490) — which on our side means
  the INTF1/DSI "spread" configuration and the tear check lines-per-second must be re-derived for
  a 11.1 ms frame, and `SWEET_FB_VSYNC_US` 16667 → **11111**.
* Boot-arg `sweetfb_hz=90` (and `sweetfb_refresh=90` to also do the DCS write); `sweetfb_refresh=60`
  is the reverse command set (panel.dtsi:99-116).
* Risk: **medium-high** for the panel, none for the device: a wrong DCS write while the panel is
  the only console can leave a black screen until reboot. Do it only after D3, with the log on
  USB (`sweetusb=2`) so a failed write is visible without a recovery pull.
* Measurement: TE period in the `SWEET FPS` line must be 11.1 ms (not 16.7); `shown`/second should
  rise if the renderer has headroom. **Expect no fps gain at today's 17–23 fps** — the gain is
  latency (−5.6 ms worst case) and smoothness once the renderer is faster.

## 5. Open questions only a phone run answers

1. **Is SID `0xb40` in bypass, and what does ABL's translation cover?** If it bypasses, only
   physical addresses below 4 GiB work (`SRC0_ADDR` is 32-bit) — the splash-region pool is then
   the only option. If it has a stage-1 bank, does it cover the whole `cont_splash_region` or just
   the first frame? (beryllium saw both. `DISPLAY_HW.md` §5.3.)
2. **What did ABL leave INTF1 in?** Command mode with autorefresh, or a continuous fetch? Every
   write we make to `0xa0000000` appears on glass with no commit from us, which only an
   autorefresh/per-TE refetch explains (**inferred**); the tear-block and `AUTOREFRESH_CTRL` reads
   in D1 settle it, and it decides whether D3 needs a CTL flush per frame or just an address write.
3. **Does the lite scaler at 1.04× look right?** Bilinear on a fractional phase step is the
   vendor default, but nobody has looked at 1125→1080 text on this panel. Arithmetic says yes;
   only a photo says whether it is acceptable versus the current crop.
4. **Cache-clean cost on real surfaces.** Is CA's canvas actually cacheable (`0108` says wrapped
   client memory is) and does cleaning ~11 MB per frame really cost 2–4 ms, or does it cost like
   the memcpy and make D3 pointless for the CPU renderer?
5. **Does anything break when the panel's refresh rate changes under a running iOS?** CA's display
   link is told 60 Hz by the vsync timer; a 90 Hz panel behind an unchanged 60 Hz timer may just
   show every frame twice — measurable only by flipping it on.
6. **Does the MDP accept `SRC_SIZE` 1125 with `OUT_SIZE` 1080 at the same time as DSC is active**
   on the DSI side, at 11.1 ms budget? Underrun shows up as a tear line or a frozen band; only a
   run distinguishes "works" from "works most of the time".
7. **Is the vsync timer's actual period 16.667 ms?** `IOTimerEventSource::setTimeoutUS` re-arms
   after the callback returns, so the true period is 16667 µs + the callback + the copy — that is,
   the display link we present to iOS is already a few ms slow, and D2's measured TE period is the
   only way to know by how much.
