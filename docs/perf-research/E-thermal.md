# Lane E — thermal sensors, vendor trips, and a minimal in-kernel throttle

Scope: thermal sensors, the vendor's trips, and the smallest kernel change that makes sustained
load safe. The governor itself is lane B (`docs/perf-research/B-cpu-idle-governor.md`), current
measurement is lane F, idle drain is lane G. Everything here is a plan; nothing was run on the
phone.

## 1. Summary

- Nothing throttles: 0115/0116 pin every domain at its top max-core row and never revisit it (**measured**,
  `logs/phone/20261115-092905-usb-kernel-0116`, gold 652→2208, prime 806→2400, A55 1516→1804, L3 1209→1516);
  0118 reads tsens into `kern.sweet_cpufreq` and nothing consumes it (`0118:21-62`).
- The vendor's policy runs on **PMIC thermistors**, not on the junctions: skin 46/48/50/52 °C,
  msm-skin 55/57 °C, each with an explicit target frequency (`avicii/avicii.dtsi:6-159`); the
  junction trips are far out (110/115/125 °C). Our 41-53 °C is junction (`live.dts:978-1290`),
  so applying skin numbers to it would over-throttle by roughly 25-35 °C.
- The only fail-safe is hardware: PMIC temp alarm stage 3 = 145 °C shutdown with software
  override cleared (`qcom-spmi-temp-alarm.c:57-61,252-263`). No `critical` trip exists anywhere
  in the DT (0 hits) and the tsens critical IRQ is never requested (`tsens.c:113-185`).
- Plan: a 1 Hz junction monitor writing `kern.sweet_cpufreq_cap` (`0116:315-346`) at
  75/85/95/105/110 °C with the vendor's own target MHz, then the skin thermistor over SPMI.
- **Estimated**: −35-45 % A76 dynamic power at J1-J3, a plateau 5-10 °C lower, ≤10 % fps. **Measured**:
  nothing about temperature — no log line in `logs/phone/` carries one; the 41-53 °C figure is only
  in the lane brief.

## 2. What the vendor does

**Sensors.** Two tsens blocks, `tsens0` = `/soc/tsens@c222000` (SROT 0xc222000, TM 0xc263000) and
`tsens1` = `/soc/tsens@c223000` (SROT 0xc223000, TM 0xc265000), `compatible = "qcom,tsens26xx"`,
16 channels each (`live.dts:3580-3604`; the alias table `live.dts:28592-28593` names them). Channel
map from the zone names that reference them: ch 0 `aoss0`, ch 1-6 `cpu-0-0..5`, ch 7-8 `cpuss-0/1`,
ch 9-12 `cpu-1-0..3`, ch 13-14 `gpuss-0/1` (`live.dts:955,978,1001,1024,1047,1070,1093,1116,1139,1162,1185,1208,1231,1254,1277`).
Read protocol: TM + 0xa0 + 4·ch, `[11:0]` signed 0.1 °C, valid bit 21 (`tsens-v2.c:11-13,23-27,59`).
The modem's own sensors are QMI (`qmi-ts-sensors`, `live.dts:14672`) and unreachable without the modem.

The policy sensors are PMIC thermistors on the PM8150L ADC5: `skin_therm` ch 0x54 and
`msm_skin_therm` ch 0x4e (ratiometric, `qcom,hw-settle-time = <0xc8>`, `live.dts:4969-4983`,
vadc at 0x3100 with `qcom,adc-vdd-reference = <0x753>`, `live.dts:4926-4934`), wired to
`adc-tm5` threshold monitors (`live.dts:5003-5043`) so a crossing raises an interrupt
(`adc-tm5.c:579-594`) — the zones have `polling-delay = <0>` and are event-driven.

**Policy — skin** (`avicii/avicii.dtsi`, `step_wise`, hysteresis 2 °C):

| trip | °C | action |
|---|---|---|
| `skin-trip0` | 46 | cpu7 → 1766400 kHz, cpu6 → 1728000 kHz (`:6,33-44`) |
| `skin-trip1` | 48 | cpu7 → 1401600, cpu6 → 1478400, GPU `MAX_LIMIT-2` (`:12,49-66`) |
| `skin-trip2` | 50 | A55 → 864000, isolate cpu4/5/6/7 (`:18,70-98`) |
| `skin-trip3` | 52 | A55 → 614400 (`:24,102-105`) |

**Policy — msm-skin** (`:113-159`): 55 °C cpu7 → 2304000 (its comment — barely under fmax), cpu6 → 1900800; 57 °C
A55 → 1728000 and GPU `MAX_LIMIT-1`. Note the DT bug: both 57 °C CPU maps point at `&CPU0`
(`:145,152`), so cpu6/cpu7 get no cap from that trip.

**Policy — junction/PMIC** (`live.dts`): every tsens zone carries 125 °C passive and 115 °C
`reset-mon-config` (`cpu-0-0-usr` `:993-997`); `cpu-N-step` zones isolate the CPU at 110 °C
(`:1692-1930`); `cpu-0/1-max-step` are sensorless 120 °C (`:1660,1676`); the three PMIC die zones
step at 95/115/145 °C (`:2283-2310,2368,2638-2655`). `soc` (bcl-soc) isolates cpu6/7 at 5 % SOC (`:2599-2620`).

The state encoding is `THERMAL_MAX_LIMIT-k`, which the core normalises to `max_state-k`
(`thermal_core.c:755-768`) and `cpu_cooling` turns into `freq_table[max_level-state]`
(`cpu_cooling.c:335-345`, bounds-checked `:408`); `max_state` is the floor, so `k` counts up from
the floor and the vendor writes the resulting frequency as a comment. Use those MHz, not the state.

**thermal-engine.** `/vendor/etc/thermal-engine.conf` is empty — 2 lines, sha256
`c32b39af7a19759a7db7f8b2d92d069a0534848aa7a195ca2cec24aa6c317cb3` ("File empty by default",
`TheMuppets/proprietary_vendor_oneplus_avicii` `lineage-21`, the tree this zip is built from — the
OTA payload ops are zucchini-compressed and undecodable here). The thresholds are compiled into
`/vendor/bin/thermal-engine`; `strings` shows sections `SS-CPU0-1-2-3`, `SS-GPU`, `SS-POPMEM`,
zone names `skin-msm-therm-usr`, `socd-usr` and a reset action, but the numbers are in binary
tables. It only replaces the in-kernel step_wise if it runs, and it is a user-space daemon we have
no way to run yet.

**Hardware that fails safe on its own**

- PMIC temp alarm, gen2 map, threshold set 1 (our DT: `live.dts:3939`): stage1 95 °C, stage2
  115 °C, stage3 145 °C (`drivers/thermal/qcom-spmi-temp-alarm.c:57-61`). Stages 2 and 3 act in
  the PMIC itself — the driver explicitly leaves their override cleared (`:252-259`) and
  force-enables the alarm (`:263`), so the rails are cut with no HLOS in the loop (**inferred**:
  the stage actions are PMIC-internal, only the thresholds are in the source).
- LMh DCVS-HW: a per-cluster frequency cap asserted by the limits engine, configured through
  `SCM_SVC_LMH` with ARM/HI/MAX trips, default working point 75 °C, 120 °C ceiling, 10 ms poll
  (`msm_lmh_dcvs.c:57-63,135-160,249-276,660-700`). It clamps on its own once armed, but arming
  is an SCM call from the (Linux) driver — **inferred**: with XNU nothing re-arms it, so it is at
  whatever ABL left, possibly nothing. 0115:32 and 0118:14 both assert "LMh clamps the domain on
  its own" without evidence.
- Not protection: tsens thresholds raise an IRQ only (`tsens.c` has no IRQ handler and no
  `set_trips`), BCL levels are only acted on by their drivers, and there is no `critical` trip.

## 3. What we do today

- Boot pins everything up once and walks away: `0115:90-132` (per-domain top max-core row),
  `0116:236-345` (L3, `kern.sweet_cpufreq`, rw caps), never revisited — no timer in either patch,
  `delay()` is used only inside the report (`0116:275,413`).
- 0118 adds a read-only tsens dump to that report: both TM blocks, all 16 channels, `hottest`
  (`0118:16-53`), consumed by nothing (`0118:62`). It is the only thermal code in the tree.
- `kern.sweet_cpufreq_cap` (int, rw) and `kern.sweet_l3_cap` re-request a row on write
  (`0116:315-346`); `osm_request()` only ever lowers — a value at or above the boot `top` leaves the
  row alone and a negative value means "back to `top`" (`0116:141-160`) — and it is the contract
  lane B's governor reads each tick (`B-cpu-idle-governor.md:254`).
- Evidence: only 0118+ kernels print temperatures and none was captured; junction 41-53 °C comes
  from the brief. Under 0116+ every core is at max, so that reading is the max-clock steady state.
- iOS side: `thermalmonitord` is exec'd on every boot (`logs/phone/20261114-184748-0110d-touch-norails/ring-post.txt`)
  and does nothing but one unknown FB selector (`SWEET FB: thermalmonitord sel 78 in 2/1788 out 0/0`)
  — there is no `AppleSMC` in the tree, so it has no sensor to read. The kernel-side API it would
  use is there: `IOPMrootDomain::setThermalState(OSObject *)` (`iokit/IOKit/pwr_mgt/RootDomain.h:965`),
  levels `kIOPMThermalLevelNormal/Danger/Critical = 0/5/10` (`IOPM.h:764-771`), published as
  `kIOPMThermalLevelWarningKey` under `kIOPMRootDomainPowerStatusKey` and fanned out by
  `messageClients(kIOPMMessageSystemPowerEventOccurred)` (`IOPMrootDomain.cpp:8152-8188`); the
  state gates system sleep and full-wake (`:7478-7498,7514`). Nothing calls it on avicii.

## 4. Plan

Design rule: the throttle never *raises* a domain above the row 0115/0116 chose; it only lowers the
cap and restores it. Targets are MHz from the vendor table above, converted to a row once at init
from the same LUT 0115 already reads (highest row whose MHz ≤ target, clamped) — no hardcoded rows.

**A. Report first.** `sweet_cpufreq.c` already has the domain table; add
`sweet_thermal_hottest()` (max over tsens0 ch 1-6, 9-12 for CPU, 13-14 for GPU) and a
`kern.sweet_thermal` text sysctl with per-sensor and per-domain state. Boot-arg
`sweetthermal=0` off / `1` log only / `2` act (default 1 until the numbers exist).

**B. Throttle.** One `timeout()` at 1 Hz (BSD side, `sweet_ufs_init()`-style hook like 0115:141-151),
5 °C hysteresis, 10 s minimum dwell, one log line per transition:

| stage | trigger (junction) | action | source |
|---|---|---|---|
| J1 | 75 °C | gold ≤ 1766400, prime ≤ 1766400 | LMh default working point `msm_lmh_dcvs.c:57`; freq from `avicii.dtsi:33` |
| J2 | 85 °C | gold ≤ 1478400, prime ≤ 1401600 | `avicii.dtsi:49,56` |
| J3 | 95 °C | A55 ≤ 864000, gold ≤ 1113600 (extrapolated) | `avicii.dtsi:70`; PMIC die trip 95 `live.dts:2638-2655` |
| J4 | 105 °C | A55 ≤ 614400, gold floor | `avicii.dtsi:102` |
| J5 | 110 °C | every CPU domain row 0, L3 ≤ 1209 | vendor isolate trip `live.dts:1692-1930`; isolation itself is lane B |
| J6 | 115 °C | hold J5, publish `kIOPMThermalLevelCritical` | `reset-mon-config` `live.dts:993-997`; API above |

Write the shared `cpu_cap` (and `l3_cap`) variable and call `osm_request()`, i.e. the same path
`sysctl_sweet_cap` uses (`0116:315-346`), not `PERF_STATE` directly, so lane B composes instead of
fighting. Recover one stage per 10 s while `hottest < trip-5`, and write -1 (back to the boot `top`
row) once below J1. J1 sits above every idle reading we have (41-53 °C), so idle behaviour does not
change; only load does.

**C. Skin sensors.** Read PM8150L ADC5 over SPMI (USID 5, vadc 0x3100, ch 0x54/0x4e, ratiometric,
200 µs settle — `live.dts:4926-4983`) and move the ladder to the vendor's 46/48/50/52/55/57 °C with
its exact frequencies. This needs the first PMIC *writes* in the tree (ADC `CONV_REQ`,
`adc-tm5.c:168-176`); `sweet_spmi.c` is read-only today (`0062:472-477`), and its lane-poisoning
already covers a timeout. Until then the 75-110 °C junction ladder is the approximation — **inferred**
offset from the vendor bands.

**D. Apple side.** A small nub that calls `setThermalState` from J6 so the hot-phone UI and app
throttling exist at all. Full thermalmonitord cooperation needs an `AppleSMC` key provider (out of
scope).

**Risk — can it hang?**

- No partitions, no clock or regulator changes: only OSM `PERF_STATE`/cap values already written at
  boot by 0115/0116, and (phase C) PMIC ADC writes. A wrong cap is a slow phone, not a dead one.
- The written row is always ≤ the boot row (`0116:141-160`), so neither an out-of-range target nor
  a bad MHz→row conversion can fault. Oscillation is bounded by the 5 °C hysteresis and 10 s dwell.
- A stuck tick leaves today's behaviour (no throttle) — fail-open; `sweetthermal=0` is the escape
  hatch on the cmdline.
- Real hazards: the ADC read path (SPMI timeout → poison, retry next tick, never block the timeout
  thread) and any future attempt to isolate cores, which is lane B's resume work.
- LMh may already be capping; if it is, our steps show less than estimated. Measure before tuning.

**Measure on the phone** (SSH is up, patches 0072-0077):

1. `sweetthermal=0` control, 10 min: `for i in 1 2 3 4 5 6 7 8; do (while :; do :; done) & done`, and
   every 5 s `sysctl kern.sweet_cpufreq | grep -A2 'temp C'` (hottest + per-domain rows).
   Record slope and plateau — that plateau is the headroom number nobody has yet.
2. Same run with `sweetthermal=2`. Success: plateau ≥5 °C lower, `SWEET THERMAL` transitions
   monotone and <20/min, scroll fps within 10 %, no `req row` above the chosen cap.
3. Odd cases: cap write while a domain is collapsed (does the counter move on wake?), and J5 hit
   under load.

## 5. Open questions only a phone run answers

- What is the real skin↔junction offset at sustained load? All our numbers hinge on it, and both
  sensors can only be read once phase C exists.
- Is LMh armed at all under XNU? A cap write that does not move the measured domain counter proves
  the OSM is not the effective limiter.
- Does a `PERF_STATE` write land while that domain is power-collapsed, or is it lost?
- How hot does the phone actually get with no throttle, and how fast — is 110 °C reachable in
  minutes (needs J1-J4) or hours?
- Does anything in the iOS userland react to `kIOPMThermalLevelWarningKey` with no SMC
  (hot UI, backboardd slow-down), or is it inert?
- Does the PMIC BCL isolate a core by itself mid-load, and does XNU's PSCI path survive it?
