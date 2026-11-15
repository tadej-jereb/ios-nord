# Performance / battery research — the eight lanes, ranked

iOS 16.7.16 runs on the Nord (`avicii`, SM7250) but is slow and hot for four structural reasons that
the lanes below each pin to a citation: **every core and the L3 are pinned at max clock and never
revised** (0115/0116), **nothing ever idles deeply** (no `CPU_SUSPEND`, no RPMh sleep set), **DDR/LLCC
bandwidth is never voted** (no BCM vote in the tree at all), and **the framebuffer is a 10.4 MB CPU
memcpy per frame** with no display engine involved. On top of that sit two measurement holes — no
battery gauge (fixed 100 %) and no thermal consumer of the tsens values we already read — and a
userland crash loop that costs a full core.

Each lane owns one file here. Read the lane file before acting on its row; every number in it is
traceable to a command or a cited line.

## Ranked by expected gain ÷ (risk × effort)

| # | Change | Lane | Expected gain | M / E | Effort | Risk |
|---|---|---|---|---|---|---|
| 1 | Disable `ReportCrash` + `assetsd` (then `nanotimekitcompaniond`) | H | ~1 core of crash reporting, ~600 spawns/h | **measured** (68 crashes/100 s; 50–192 % CPU; 4.1 s respawn) | 2 `launchctl` lines | none — userland only, no kernel |
| 2 | Vote DDR/LLCC over RPMh BCM (`SH0=16265`, `MC0=7980`, `ACV=8`) | A | 5–25 ms off a frame → 10 Hz → 10.5–13 Hz | **estimated** (−25 % bound is `inferred`) | ~30 lines in `sweet_rpmh.c` | low — no hang path, boot-arg gated |
| 3 | Gauge: allow SPMI slave 2 (QG 0x48, SDAM 0xb1), ESR-corrected OCV | F | 100 % → ±5 pts SoC; **unblocks B/E/G's mA** | **estimated** (0.152588 mA/LSB is vendor) | small, one whitelist + LUT read | low — read-only SPMI, already proven by `sweetkeys` |
| 4 | UFS: drop the pre-read bounce clean; read gear/clocks first | C | 1.5–3× on ≥1 MiB reads, ~4 s of boot | **estimated**; measured only that reads pin one core at 99–100 % | small (one edit) | correctness, not bricking — cache ops must stay ordered |
| 5 | `kern.sweet_cxoff` from `rpmh-master-stats@b221200` | G | no gain itself: the gate for G2–G9 and proof any sleep step worked | **measured** bit (vendor's own reader treats it so) | tiny | none — a read |
| 6 | 1 Hz governor: drop idle A76 domains to row 0, restore on load | B | A76/L3 idle rail power down ~4–7×, a few °C, 0 fps lost | **estimated**; clocks measured | medium (timer + hooks) | low — PERF_STATE only, no idle-state entry |
| 7 | 5-stage junction throttle at 75/85/95/105/110 °C via `osm_request()` | E | −35–45 % A76 dynamic power at J1–J3, plateau 5–10 °C cooler, ≤10 % fps | **estimated** | medium | low — cap only lowers, fails open |
| 8 | Zero-copy scanout: MDP VIG0 + QSEED3-lite instead of the memcpy | D | ~0.35 core at 20 fps, ~1 core at 60 Hz, 10–15 ms latency | **estimated**; 17.3 ms copy derived from a measured 17.3 fps | large (MDP/DSI/SMMU plumbing) | highest — a bad flush wedges the display, not the GPT |
| 9 | Screen-off sequence G2–G7 (FB timer, panel, touch, GPU, UFS, USB) | G | ≈170–410 mW screen-off; + G8/G9 → ≈0.5–1.2 W total | **estimated** ±50 %; nothing measurable in mW until lane F | staged, each small | low, one step at a time |
| 10 | 90 Hz + native 1080×2400 | D | 90 Hz cannot lift a 17–23 fps renderer; cuts worst-case refresh wait 16.7→11.1 ms | **estimated** | small after D3 | none once D3 lands |

The ordering is deliberately *not* by headline gain. #8 frees the most CPU but needs #5's gate, #7's
safety and the largest piece of new code; #1 costs two commands and is already measured.

## Dependencies between lanes

* **F → B, E, G.** `kern.sweet_battery_ma` / `_avg_ma` is the only way any of them reports mW. F
  defines the contract (`F-battery-gauge.md` §4); until it exists, B/E/G measure in °C, %/h and the
  G1 counter. G's 167 mW per %/h anchor is a computed conversion, not a measurement.
* **E → B, not the reverse.** E throttles by writing the same shared cap B's governor honours
  (`osm_request()` only lowers, `0116:141-160`), so the governor and the thermal ladder
  compose only if the cap wins. Land B first; E's stages then simply lower B's ceiling.
* **E must not copy the vendor's numbers literally.** The vendor's 46/48/50/52 °C trips are *PMIC
  skin* temperatures; our 41–53 °C readings are *junction* (`tsens`). Using skin values on junctions
  over-throttles by 25–35 °C. E's ladder starts at 75 °C for that reason.
* **B ↔ G9.** Writing RPMh sleep sets before B's `CPU_SUSPEND` exists is inert (nothing consumes
  them), but G9's PDC wake programming is what makes B's C3/C4 survivable. The pair must land
  together; G's own summary says so.
* **A ↔ D.** A raises the DDR/LLCC OPP that D3's SMMU fetches need, and D3 removes the CPU copy that
  makes A's gain visible in the first place. Do A first — it is cheap and makes D3's headroom real.
  D3 also lowers the value of B's governor (less CPU to idle), never the reverse.
* **C is on its own axis** (boot/app-launch latency), except that its `dd` baseline is the same one
  F's poll thread must not disturb.
* **H is independent of all of it** and is the only lane whose gain is already measured.

## First three changes

1. **Disable the crash loop (H).** `launchctl disable system/com.apple.ReportCrash` +
   `bootout`, then `com.apple.assetsd`; keep `bluetoothd`/`fairplayd.H2` disabled (removing them
   already took 1568 → 417 execs/h). Measure: execs/h in the next ring, `ps` for ReportCrash.
2. **Vote DDR and LLCC (A).** Relax `rh_lookup()` to accept cmd-db slave 5, send three
   single-command ACTIVE-TCS writes on DRV2 (`0x50004=16265`, `0x50000=7980`, `0x5007c=8`) behind
   `sweetddr=`/`sweetllcc=`, and settle the estimate in one boot with `kern.sweet_bwtest`.
3. **Turn the gauge on (F).** Whitelist SPMI slave 2 for the QG and SDAM, publish
   `kern.sweet_battery_avg_ma`, then correct `MaxCapacity` (4320 mAh from `live.dts:4211`, not
   sweet's 5020). Every lane after this one can finally report mW.

Not committed — `docs/perf-research/` is untracked; the coordinator commits.

## Round 3 — the mediaserverd verdict (`I-mediaserverd.md`)

Lane I went after the two processes at the top of the idle-time `ps` and **moved both of lane H's
conclusions**. `mediaserverd` is *not* crash-looping: one `exec` per boot, at most one abort per
boot, zero aborts across the five-boot / seven-hour ring — its 46.2 % (`h1-disable-before.txt:4`)
is a **resident ≈0.46-core spin**, which is exactly why a respawn model could not find it
(`I:7-23`, `I:41-63`). And `launchd`'s 77.7 % is **not** spawning: 844 execs/h measured (356/h of
them `nanotimekitcompaniond`) is 0.23/s, nowhere near a core, so launchd has a spin of its own
(`I:158-176`).

**Root cause is not established, and the report says so.** Best hypothesis H1: the CoreAudio HAL
*inside* the daemon has zero drivers, because the tweak moved the only HAL plugin,
`VirtualAudio.plugin`, to `HAL.disabled/` (`tooling/33b-tweaks-idempotent.py:27-28`) — so startup
never completes and it loops in a retry/pump. H2: its only Objective-C is a CoreMotion orientation
pump nothing on this phone can satisfy. Nothing offline can separate them: **one boot settles it**
— `sweetsample=mediaserverd,launchd` (`0054:144`) — and no `SMP mediaserverd` or `IOK
mediaserverd` line exists in any ring yet (`I:7-23`). Separate finding, worth keeping: in some
boots mediaserverd and `assetsd` abort at the **same unslid pc** (`0x1c2617198` =
`libsystem_kernel+0x7198`), i.e. an uncaught exception escaping a dispatch block (`I:100-136`) —
one symbolication pass with the cache `.symbols` would pay for itself.

Recommended change is userland-only and reversible, in tiers: `kill -STOP` to confirm the CPU is
its own threads, then `launchctl bootout`, then `launchctl disable
system/com.apple.mediaserverd` — no kernel, no reboot, no audio to lose (there is no audio
hardware anyway), one command to undo (`I:193-208`). Do **not** bother with a `ThrottleInterval`
plist tweak (nothing is crash-looping, so it is inert) or a kernel "no device" stub (mediaserverd
loads no IOKit; the missing object is a userspace plugin). The earlier `h1-disable-after.txt`
"after" snapshot is missing, so step 0 is to re-take the baseline before touching anything
(`I:242-266`); the before/after table is at `I:267-277`. Next disable after that, independently,
is `com.apple.nanotimekitcompaniond` at 356 execs/h.
