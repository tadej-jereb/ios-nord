# Lane G — screen-off drain and the system low-power path

Scope: the system-level sleep path and the ordered screen-off sequence. CPU PSCI states are lane
B (referenced, not re-derived), current measurement is lane F, thermal lane E. Read-only research;
nothing was run on the phone. Scratch (vendor sources, greps) in `~/.hermes/cache/scratch/lane-g/`.

Sources: the live FDT (`~/.hermes/cache/scratch/perf-inputs/live.dts`, sha256 `de87b3009781a8b1…`),
`refs/lito-dts/lito-pm.dtsi`, `avicii/panel.dtsi`, `avicii/lito.dtsi`, our patches in
`xnu-avicii/patches/`, `logs/phone/`, and the vendor kernel (LineageOS
`android_kernel_oneplus_sm8250`, branch **lineage-21**; citations are `path:line` on that branch).

## 1. Summary

- **The SoC has never been asked to sleep, in either half of the protocol.** No `CPU_SUSPEND` is
  issued anywhere — `0xC4000003` (PSCI `CPU_ON`) is the only SMC in the tree (`0065:32`) — and no
  RPMh **sleep set** is ever written (`0062:115-116` states it; every log line shows only ACTIVE
  TCS traffic). Without both, the vendor's own deepest level, `llcc-off` = *"LLCC off, AOSS
  sleep"* (`refs/lito-dts/lito-pm.dtsi:48-58`), is never requested, so CX/MX collapse and XO
  shutdown cannot happen at any price.
- The second half is *what keeps the SoC from the bottom of the ladder when a request finally
  exists*: the GPU CX power switch is turned on and left on (`0119:213`, comment `:198-200`), the
  panel is faded to black but stays powered (`0079:9-12`), the framebuffer vsync timer re-arms
  every 16 667 µs forever (`0046:1057`, `0079:53`), touch keeps scanning, the UFS link never
  enters hibernate8, and the USB ECM link keeps its three PHY rails voted (`0113:47-49`).
- Screen-off today is worth **≈170-410 mW** across steps G2-G7 (**ESTIMATED**, per-step basis in
  §4, ±50 %). The sleep path (G8+G9) is what converts "awake at a few hundred mW" into the
  vendor's few mW: **≈0.5-1.2 W total** (**ESTIMATED**, dominated by 8 cores and L3 pinned at
  max — measured clocks in `logs/phone/20261115-143607-…/ring-pre.txt:160-163`).
- **Nothing here is measurable in mW yet**: no gauge, battery is a fixed 100 % (`docs/STATUS.md:47`).
  The conversion anchor for %/h is 167 mW per %/h (computed: 4320 mAh `live.dts:4211` × 3.87 V
  nominal / 100 h; nominal voltage is not in the DT — **UNVERIFIED**, the DT gives only 4.35 V max,
  `live.dts:28075`).
- Better than %/h: the platform has a **hardware sleep counter**. `qcom,rpmh-master-stats@b221200`
  (`live.dts:11207-11209`) holds per-phase arch-timer timestamps; the vendor's own reader refuses
  to update APSS stats when the valid bit is clear because *"it means APSS did not execute cx-off
  sequence"* (`rpmh_master_stat.c:319-321`). Reading it (G1) gives "did we ever collapse CX", the
  gate for every step below, with no gauge and no extra hardware.
- Order (cheapest first, each gated on G1): **G1** counter → **G2** FB timer → **G3** panel off →
  **G4** touch sleep → **G5** GPU slumber → **G6** UFS hibern8 → **G7** USB link down → **G8** CPU
  deep idle (lane B) → **G9** RPMh sleep sets + AOSS/PDC.
- Caveat that shapes the plan: writing sleep sets before G8 is inert (nothing consumes them), but
  G9's PDC wake programming is what makes G8's deepest levels survivable, so the pair must land
  together.

## 2. What the vendor does

### 2.1 The ladder has exactly one top

`qcom,lpm-levels` (`live.dts:11050`, source `refs/lito-dts/lito-pm.dtsi`) declares one cluster, L3,
with four levels. µs figures are entry / exit / min-residency:

| node | label | psci mode | shift/mask | entry | exit | min resid | flags |
|---|---|---|---|---|---|---|---|
| `pm-cluster-level@0` | `l3-wfi` | 0x1 | 4 / 0xfff | 660 | 600 | 1260 | — |
| `pm-cluster-level@1` | `l3-pc` | 0x4 | | 2752 | 3048 | 6118 | `is-reset`, `min-child-idx 2` |
| `pm-cluster-level@2` | `cx-off` | 0x224 | | 3638 | 4562 | 8467 | `is-reset`, `min-child-idx 2`, **`notify-rpm`** |
| `pm-cluster-level@3` | `llcc-off` | 0xC24 | | 3263 | 6562 | 9826 | `is-reset`, `min-child-idx 2`, **`notify-rpm`** |

(`live.dts:11057-11112` decimal, `refs/lito-dts/lito-pm.dtsi:7-58`; the vendor's own comment on
level 3 is *"LLCC off, AOSS sleep"*, `lito-pm.dtsi:48`). Per-CPU levels are C1 `wfi` 0x1, C3 `pc`
0x3, C4 `rail-pc` 0x4, all C3/C4 `use-broadcast-timer` (`lito-pm.dtsi:73-142`). Lane B has the
encoding and the per-CPU plan; this lane only needs the fact that **every level that collapses CX
is `notify-rpm`** — i.e. it is gated on the RPMh sleep path, not on the CPU state alone.

### 2.2 `notify-rpm` wires the level to three things

`lpm_cpu_select()` refuses such a level unless `sys_pm_ops->sleep_allowed()` says yes
(`lpm-levels.c:1070-1072`), and `cluster_configure()` calls `sys_pm_ops->enter(&cpumask)` before
the PSCI call (`lpm-levels.c:1128-1129`). The provider is `system_pm.c` (compatible
`qcom,system-pm`, bound under our own RSC, `live.dts:5502-5504`):

- `system_sleep_allowed()` = `rpmh_ctrlr_idle()` = every ACTIVE TCS free (`system_pm.c:45-48`,
  `rpmh-rsc.c:591-604`) — a busy client TCS blocks system sleep outright;
- `system_sleep_enter()` = `rpmh_flush()` (`system_pm.c:56-58`), which invalidates and then writes
  the cached **sleep** values into SLEEP_TCS and the wake values into WAKE_TCS as *control* writes
  (`rpmh.c:556-602`, `rpmh-rsc.c:532-551` `tcs_ctrl_write` → `rpmh_rsc_write_ctrl_data`
  `rpmh-rsc.c:612-625`);
- **the wake source must be armed by hand**: `system_sleep_update_wakeup()` reads
  `arch_timer_mem_get_cval()` (the *physical* timer) and writes two words — `hi | valid<<31`,
  `lo` — into `RSC_PDC_DRV_DATA` (`system_pm.c:21-39`), which is DRV offset `0x38`, next word
  `0x08` later (`rpmh-rsc.c:67-70`, `:627-648`). Without that, nothing wakes the SoC once XO is
  off.

Geometry of the RSC we own: DRV2 base `0x18220000`, `qcom,tcs-offset = 0xd00`
(`live.dts:5480-5490`, confirmed in our own map `0111:19-21`), `qcom,tcs-config = <2 2 0 3 1 3 3 1>`
= 2 ACTIVE / 3 SLEEP / 3 WAKE / 1 CONTROL TCS (`live.dts:5496`, ordering
`dt-bindings/soc/qcom,rpmh-rsc.h:8-11`). PDC data therefore sits at `0x18220038` and `0x18220040`.

### 2.3 The AOP gets no message; it consumes the handshake

AOP is reachable only through one mailbox (`qcom,qmp-aop@c300000`, `qcom,qmp-mbox`, msgram
`0xc300000`, mailbox `0x00`, `live.dts:6938-6951`) plus a debugfs client (`live.dts:6954-6957`);
message framing is 96-byte QMP packets (`msm_qmp.c:373`, `qmp-debugfs-client.c:14`). No sleep
driver in the tree sends a QMP/`ddr`/`cx` message — the only QMP consumers are the AOP clock
controller (`qcom,aopclk`, `live.dts:3629-3630`) and the debugfs client. So the AOP's part in
cx-off/llcc-off/AOSS sleep is driven by the PSCI power-state handshake the RSC and AOSS firmware
perform, not by HLOS messages (**inferred** from the absence of any sender plus the vendor's
`notify-rpm`-only design).

### 2.4 The ordered screen-off sequence is ordinary driver code

Everything the SoC needs off *before* a collapse request, the vendor does in its own drivers, and
the values are in the vendor tree and dts:

- **panel**: two DCS writes with waits, `05 01 00 00 0A 00 01 28` (display off, 10 ms) then
  `05 01 00 00 78 00 01 10` (sleep in, 120 ms), `dsi_lp_mode` (`avicii/panel.dtsi:193-196,431`);
- **touch**: command register `0x6F68`, `GTP_CMD_SLEEP` = **0x05**, payload is
  `{cmd, data, -(cmd+data)}` = `05 00 FB`, written as a 3-byte block, 8 ms, then poll the register
  until it no longer reads back 0x05 (`goodix_drivers_gt9886.c:919`, `goodix_drivers_gt9886.h:86`, `:203-252`); wake is
  a reset-pin toggle only — low 2 ms, high, 10 + 20 ms — and the vendor's mode switch states
  *"after reset, it's already normal"*, no config re-upload (`:816-828`, `:2712-2723`);
- **GPU**: `H2F_MSG_PREPARE_SLUMBER` over HFI, then the GX/CX switches (`kgsl_hfi.h:174`, the
  command struct `:402`) — GPU track;
- **UFS**: hibernate8 over UIC (`ufshcd.c:5623` `ufshcd_uic_hibern8_enter`), auto-hibern8 armed by
  `ufs_qcom_init` (`ufs-qcom.c:716`), clock gating only *after* hibernate8
  (`ufs-qcom.c:1584-1587`);
- **system**: only then `psci_enter_sleep()` with the level's state id (`lpm-levels.c:1353-1384`).

Note the boot capture in `live.dts:628` carries `lpm_levels.sleep_disabled=1` — the vendor itself
boots *dc_charger* mode with idle LPM off, and suspend (`lpm_suspend_enter`, `lpm-levels.c:1724`)
is not gated by it. So the vendor's day-to-day drain reduction lives in the suspend path, not in
cpuidle, and a mirror of it must not depend on G8 being finished (**observed** for that boot;
whether normal boots carry the flag is an open question).

## 3. What we do today

Measured, from the phone: all eight cores and L3 pinned at max — A55 row 8 (1804 MHz), A76 row 7
(2208 / 2400 MHz), L3 row 11 (1516 MHz) (`logs/phone/20261115-143607-usb-kernel-0122-gpu8/ring-pre.txt:160-163`).

Then, by construction:

| what | evidence |
|---|---|
| No `CPU_SUSPEND`, no system suspend; idle is bare `dsb; wfi`, skipped for a WFE poll when a timer is armed | only PSCI function id `0xC4000003` exists (`0065:32`); lane B report §1 |
| No sleep/wake programming at all: the RSC client is active-only, "called from thread context with deep idle disabled" | `0062:114-116`; log shows only `ACTIVE TCS` enable/trigger/complete (`ring-pre.txt:183-186,199-200`) |
| Dropping into a gated block during a transaction quarantines the client for the boot | `0062:452-455`, `:379-380` |
| Touch rails voted on and never released: `ldo13` at 3008 mV, 1.8 V enable via PM8150L GPIO 1 over SPMI | `0095:264-267`, `0110:806-808`, `docs/STATUS.md:35` |
| USB PHY rails voted on and never released: `ldoa5` 880 mV, `ldoa12` 1800 mV, `ldoa2` 3075 mV | `0113:47-49` |
| GPU CX switch collapse bit cleared and left cleared — "up as long as the SoC runs" — plus GCC GPU PLL/`memnoc`/`snoc_dvm`/`ddrss_gpu_axi` clocks left enabled | `0119:198-200,213,230-234` |
| GMU firmware loaded and running, `HFI_CORE_FW_START` sent; no slumber message is ever sent (`grep -c slumber 0122` = 0) | `0122:786` |
| Display "off" halves every pixel for seven vsyncs and then idles, **panel stays powered**; the vsync timer is re-armed on every pass at `SWEET_FB_VSYNC_US` 16 667 µs (60 Hz) | `0079:9-12,38-55,53`; `0046:1057` |
| No DSI register access anywhere in the series (grep `dsi` over `xnu-avicii/patches/` hits only unrelated identifiers): the panel is driven purely by what ABL left configured | grep result; DSI ctrl is `0xae94000` (`live.dts:27378`) |
| Touch stays in normal scan; suspend/resume listed as a gap | `docs/GOODIX_GT9886.md:254-255` |
| UFS: one polled command in slot 0, no UIC, so no hibernate8 and no clock gating | lane C report §1 (`0028:200-226`) |
| USB: ECM link up, ABL's dwc3 + QUSB2 left powered; the driver only reads GCC and adds the rails | `0072:37-42,109` |
| No platform sleep hook: no PMGR/PMU driver, no `setSleepWake` in the series (grep: nothing) | grep over `xnu-avicii/patches/` |
| iOS *does* ask: `powerd` drives display off and `IOPMrootDomain` opens successfully, and nothing below answers | `logs/phone/20261114-184748-0110d-touch-norails/ring-pre.txt:1506-1509` (display off, IOPMrootDomain open) |

## 4. Plan, cheapest first

Every step is gated on G1: if the cx-off timestamps do not move, the step did not buy a sleep
state, whatever else it changed. **Risk column is about hangs on the one phone** — none of these
touches `persist`, `modemst`, `xbl`, `abl`, `tz` or the GPT.

### G1 — instrument the sleep counter first (0 mW, no risk)

Read the four APSS profile units at `0xb221200`, stride `0x14`, each with valid at `+0`, lo at `+4`,
hi at `+8` (`rpmh_master_stat.c:23-28`); units are `POWER_DOWN_START`, `POWER_UP_END`,
`POWER_DOWN_END`, `POWER_UP_START` (`:50-55`), values in 19.2 MHz arch-timer ticks (`:105`). One
`sysctl kern.sweet_cxoff` printing `valid, down_end, up_start` and their delta; a boot-arg to also
print it once a minute. Same block also carries the *real* vendor check — valid clear means APSS
never executed cx-off (`:319-321`). **Measure:** the pair must stay 0/0 today (expected) and start
moving after G9. This is the only phone-side sleep evidence that exists before lane F.

### G2 — stop the 60 Hz vsync timer while the display is off (≈5-20 mW, ESTIMATED)

`SWEET_FB_VSYNC_US` is 16 667 (`0046:1057`) and is re-armed on both the fade path and the idle path
(`0079:53`, `0046:1153,1183`). When `fPowerOff` and the fade is finished, re-arm at 1 s instead of
16.7 ms; restore 16 667 µs (or `sweetfb_hz`) in the same block that clears `fPowerOff`. 60 wakeups/s
at high OPP is the cheapest thing to delete, and only one file changes.
**Risk:** SpringBoard animation on wake starts late; bounded by the on-path being immediate.
**Measure:** count wakeups over 10 min now vs. after (a `kern.sweet_idlecount` is more than this
step deserves — use the G1 delta and CPU-time from `top` on the ring).

### G3 — real panel off: `28h`/`10h` plus DSI clocks (≈30-60 mW, ESTIMATED)

We have no DSI driver, so first map DSI0 (ctrl `0xae94000`, `disp_cc_base 0xaf08000`, supplies
`vdda-1p2` + `refgen`, `live.dts:27373-27385,27592`) without touching what ABL set, then send the
two vendor DCS commands (`05 01 00 00 0A 00 01 28`, `05 01 00 00 78 00 01 10`,
`avicii/panel.dtsi:193-196`) in LP mode, then gate `byte_clk`/`pixel_clk` and drop `vdda-1p2`.
Gain is the DDIC, the DSI PHY/PLL and the 1.2 V LDO.
**Risk:** a wrong DSI write leaves a black panel with no way back short of reboot (acceptable — the
phone boots from RAM); do not touch the PHY PLL until the command path is proven.
**Measure:** the vendor's own visible tell is that `10h` blanks the panel *hard* rather than fading;
then G1, and ΔT from lane E's tsens.

### G4 — GT9886 sleep (`05 00 FB` to `0x6F68`), rails down (≈15-30 mW, ESTIMATED)

Write the 3-byte block to register `0x6F68` on the existing GPI-DMA transport (`goodix_drivers_gt9886.c:210-228`),
wait 8 ms, poll the register until it stops reading 0x05, mark the chip halted and mask its IRQ.
Wake = TLMM GPIO 8 low 2 ms, high, 10 + 20 ms (`:816-828`), then re-enable the IRQ; the vendor
needs no config re-upload after that reset (`:2712-2723`). Optionally drop the `ldo13` vote after
the chip is halted.
**Risk:** touch dead until the wake path is exercised — keep it behind a boot-arg; the reset pin is
TLMM 8 and the IRQ GPIO 9 (`avicii/lito.dtsi:4004,3995`), both already driven by 0109/0110.
**Measure:** G1; plus "first touch after wake works" as a pass/fail.

### G5 — GPU: HFI slumber, then the switches (≈60-150 mW, ESTIMATED)

Send `H2F_MSG_PREPARE_SLUMBER` (`kgsl_hfi.h:174`), then set `GDSC_SW_COLLAPSE` in `gpu_cx_gdscr` (`0x3d9106c`,
`0119:83`) and clear the GCC GPU PLL vote / gate `memnoc`, `snoc_dvm`, `ddrss_gpu_axi`
(`0119:70-74,230-234`). Currently the CX half is explicitly left powered (`0119:198-200`), so this
is the difference between "CX usable" and "CX collapsible".
**Risk:** highest so far — the GPU track's own evidence is that the GX core does not always come
back (HackiOS raphael hung once switching it off, `0119:200-201`); slumber alone first, switches
second. Boot-arg it.
**Measure:** G1, and a GPU command from userland after wake.

### G6 — UFS hibernate8 (≈10-30 mW, ESTIMATED)

UIC `DME_HIBER_ENTER` (or arm the auto-hibernate timer register) before the ref clock is gated;
the vendor only gates after hibernate8 confirmed (`ufs-qcom.c:1584-1587`). Lane C owns the UIC
bring-up; this step needs it.
**Risk:** a failed hibernate exit wedges the root device — test with `/` on a RAM overlay first.
**Measure:** G1; then a `dd` read after wake.

### G7 — USB link down, PHY rails released (≈50-120 mW, ESTIMATED)

Screen-off with no host traffic should park dwc3: `GUSB2PHYCFG` suspend bit, `DCTL` run-stop, then
release `ldoa5`/`ldoa12`/`ldoa2` and the `usb30_prim` GDSC. Since the stopgap connector is the only
log channel, this step competes with diagnosis — gate it off by default in the first boots.
**Risk:** losing the console exactly when the phone misbehaves; USB re-enumeration after wake is
not proven on this port.
**Measure:** G1 first, `SWEET USB` re-probe lines after wake second.

### G8 — CPU deep idle (lane B) (≈0.4-0.9 W, ESTIMATED)

Lane B's C1/C3/C4 plan plus a governor below the max rows. Prerequisite for everything the ladder
can do, and the largest single term because 8 cores + L3 sit at max today. C3/C4 are
`use-broadcast-timer` (`lito-pm.dtsi:85-142`), so the tick and the always-on timer must be lined up
before XO can be trusted.
**Risk:** resume needs a SWEET entry vector and per-CPU GIC restore (lane B §4).
**Measure:** G1 (cx-off must still be 0 here — C3/C4 are CPU-level only), plus idle CPU %.

### G9 — RPMh sleep sets, PDC wake, AOSS (≈0.1-0.3 W on top; the only path to a few mW)

Two halves, and they land together:

1. **sleep sets**: for every rail we keep voted, a SLEEP value that is either the same (rails a
   sleeping consumer still needs) or "off" (touch/USB rails once G4/G7 exist). Writes go through
   `rpmh_rsc_write_ctrl_data` semantics — a *control* write into SLEEP_TCS, no AMC trigger
   (`rpmh-rsc.c:532-551,612-625`), and a matching WAKE value, which the RSC replays on wake.
   Extend `sweet_rpmh.c` past its current "active only" contract (`0062:115-116`).
2. **PDC wake**: the arch timer's compare value into `0x18220038`/`0x18220040` exactly as
   `system_pm.c:21-39` does — but from **CNTV_CVAL, not CNTP_CVAL**, because XNU drives the virtual
   timer (`0017:41-53`, `0065:363-364` sets `CNTVOFF_EL2 = 0`). The vendor reads the physical
   timer; copying it blindly arms a wake source XNU never uses.

Then the deepest cluster levels become reachable from the `notify-rpm` path with the state id lane B
computes (`lpm-levels.c:1335-1337` shift/mask from `lito-pm.dtsi:13-14`).
**Risk:** the real hang risk of the whole project — sleep with no armed wake is a dead phone
(no serial, no watchdog surviving XO). Do it with the charger attached, one level at a time
(`cx-off` 0x224 before `llcc-off` 0xC24), and keep a boot-arg that limits to the previous level.
**Measure:** G1 timestamps and the `SWEET` line from `msm_rpmh_master_stats_update`-equivalent;
only then %/h at 167 mW per %, and lane F's current when it exists.

## 5. Open questions only a phone run answers

1. Does the PDC actually fire and wake the APSS when armed with CNTV (virtual) rather than the
   vendor's CNTP value? Nothing on paper proves the PDC compares against the virtual comparator.
2. With the GMU slumbered, does `gpu_cx_gdscr` hardware still hold `cx.lvl`, or does the sibling
   switch collapse CX and make `cx-off` a no-op?
3. Does a reset-only wake bring the GT9886 back with its flash config intact, or does it need the
   vendor's ESD/subsystem re-flash path?
4. Which rails survive a sleep set at all: does AOSS accept a SLEEP "off" for `ldo13`/`ldoa2` while
   the ACTIVE vote is still there, or must the active vote be dropped first?
5. Does the device tolerate hibernate8 without our driver re-issuing UIC link startup?
6. Do our SMMU stage-1 TBU votes (`0110`) and the `hlos1_vote_*` GDSCs hold MMNOC up and block
   `cx-off` even with everything else off?
7. Is `lpm_levels.sleep_disabled=1` on the vendor's normal boot too, i.e. does the intended product
   behaviour need G8 at all or only the suspend path?
8. How much of the tick survives: with the arch timer as a PPI on a powered-down CPU, does the
   broadcast timer alone keep SpringBoard's 60 Hz expectations, or does G2 have to be undone on
   wake for userland timers?

## 6. Blocked / not blocked

Not blocked on anything except the phone: every step above is code plus one boot. The one thing
that cannot be produced here is a **mW** number — `docs/STATUS.md:47` has no gauge and a fixed
100 % battery, so §4 uses the G1 counter and %/h; lane F's current reading replaces both when it
lands.
