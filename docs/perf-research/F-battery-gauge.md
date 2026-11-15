# Lane F — battery gauge and charger (PM7250B QG + SMB5)

Scope: `SweetBattery.cpp` (patch `0062`) reports a battery to iOS. This lane establishes what it
reads, what the PM7250B QG (fuel gauge) and SMB5 (charger) can deliver over SPMI **read-only**, and
what a real SoC / charge state / current reading costs. Nothing was run on the phone.

## 1. Summary

- **Today the gauge is not a gauge:** `sweetbattery=1` is never passed (0 hits in `tooling/ docs/
  avicii/`), so `start()` returns the fallback — every boot logs `SWEET BATTERY: static fallback,
  100% 4200mV external=1 charging=0` (**measured**, `logs/phone/20261115-ring-0118/ring-post.txt:104`).
- With the arg it would still fail: `sweet_spmi_read()` rejects every slave but 0
  (`0062…patch:564`), and 0x4804 is PPID 0x0048 = *PM8150* periph 0x48, absent (`live.dts:3885-4134`);
  the QG is on **SPMI slave 2** (`live.dts:4143-4147,4440`).
- Slave 2 reads are **already proven here**: `sweetkeys` polls PM7250B gpio3, `arb=0x50010000
  apids=512 … dn-apid=249 … dn=0x1/1` (**measured**, `…/20261114-ufsroot-0110b-touch/ring-post.txt:162`).
- Plain reads cover V_BAT (0x48C0, 0.194637 mV/LSB), I_BAT (0x48C2/0x48C6), QG status, charge state
  and USB input current limit (0x1107 × 50 mA); SoC % is software state, not a register.
- **Expected gain:** 100 % → **±5 points** at rest, **±10** under load (**ESTIMATED**; 4.7-10.9 mV
  per point, §2.4); 0 mA → `kern.sweet_battery_avg_ma`, **0.152588 mA/LSB** (vendor constant,
  `qg-util.c:126`), ~1 mA usable after averaging, ±10 mA offset floor (**ESTIMATED**) — the number
  lanes B, E and G are blocked on (`B-cpu-idle-governor.md:275`).
- Cost: one whitelist entry and ~14 SPMI byte reads per poll; no init, no writes, no partition.

## 2. What the vendor does

### 2.1 Topology (live FDT)

| Item | Value | Citation |
|---|---|---|
| PM7250B slave | SPMI slave **2**, `reg = <0x02 0x00>` | `live.dts:4143-4147` |
| QG block | `qpnp,qg` → `qgauge@4800`, `reg = <0x4800 0x100>`, `compatible = "qcom,qpnp-qg"` | `live.dts:4413-4445` |
| QG SDAM | `qg-sdam@b100`, `reg = <0xb100 0x100>` | `live.dts:4447-4450` |
| Charger | `qcom,qpnp-smb5`; children `chgr@1000`, `dcdc@1100`, `batif@1200`, `usbin@1300` | `live.dts:4160-4172` |
| QG IRQs | `qg-batt-missing`, `qg-vbat-low`, `qg-vbat-empty`, `qg-fifo-done`, `qg-good-ocv` on slave 2 / periph 0x48 | `live.dts:4442-4443` |
| Gauge is external to the charger | `qcom,external_gauge;` in the SMB5 node | `live.dts:4311` |
| DT thresholds | `vbatt-cutoff 3200 mV`, `vbatt-low 3300`, `vbatt-empty 3000`, `qg-iterm 100 mA` | `live.dts:4417-4420,4430` |
| Charger DT caps | `usb-icl-ua = 1800000` (1.8 A), `fcc-max-ua = 2000000` (2 A), `fv-max-uv = 4365000`, `batt_capacity_mah = 4320`, `iterm_ma = 230` | `live.dts:4176-4178,4209,4211` |

That `qcom,external_gauge` is why the charger has no battery ADC of its own: `qpnp-smb5.c` answers
`POWER_SUPPLY_PROP_VOLTAGE_NOW` / `CURRENT_NOW` by forwarding to the *battery* device
(`smblib_get_prop_from_bms`, `qpnp-smb5.c:1791-1806`). The QG is the only battery V/I source on
this PMIC pair.

### 2.2 Registers the vendor driver reads (branch `lineage-21`)

Map: `drivers/power/supply/qcom/qg-reg.h`, scaling: `qg-defs.h`.

| Reading | Addr (SID 2) | Encoding / scale | Citation |
|---|---|---|---|
| peripheral type | 0x4804 | must be `0x0D` (`QG_TYPE`) | `qg-reg.h:9,15` |
| IBAT range | 0x4805 | `3` = 5 A (`152588`), `4` = 10 A (`305176`) µA/LSB | `qg-reg.h:11-13`, `qg-util.c:123-129` |
| battery present / QG OK | 0x4808 | bit0 present, bit7 `QG_OK` | `qg-reg.h:17-21` |
| missing / good-OCV | 0x4809 | bit3 missing, bit1 `GOOD_OCV` | `qg-reg.h:22-24` |
| **V_BAT** | 0x48C0-1 (LE 16) | `194637 * raw / 1000` µV ⇒ **0.194637 mV/LSB**, `0x8000` = reset | `qg-reg.h:108`, `qg-defs.h:34-35`, `qg-util.c:465-480` |
| **I_BAT** (last ADC) | 0x48C2-3 (LE, sign-extend 15) | × 152.588 µA (5 A range) | `qg-reg.h:109`, `qg-util.c:426-457` |
| I_BAT (burst avg) | 0x48C6-7 | same scale; vendor **writes** 0x4842 bit0 (HOLD) first | `qg-reg.h:111,46-47`, `qg-util.c:426-457` |
| V_BAT (S2 average) | 0x4880-1 | same V scale | `qg-reg.h:96` |
| SoC (write-only mirror) | 0x48BF | SW writes `soc*255/100` | `qg-reg.h:106`, `qg-util.c:347-355` |
| ESR in progress | 0x480B bit4 | | `qg-reg.h:29-30` |
| IRQ real-time | 0x4810 | bit3 fifo-done, bit1 vbat-low, bit0 missing | `qg-reg.h:32-35` |
| SDAM: valid / SoC % / temp / R_bat / OCV / I_BAT | 0xB146 / 0xB147 / 0xB148-49 / 0xB14A-4B / 0xB14C-4F / 0xB150-53 | SoC 1 byte %, temp decidegC, R in mΩ, OCV µV, I µA — all **software-written** by the Linux QG | `qg-reg.h:115-132`, `qg-sdam.c:23-60,131-158` |
| SDAM PON OCV (PBS-written) | 0xB1BC-BD | written by the PMIC boot sequencer, not by Linux | `qg-reg.h:134-135` |

Charger (same slave, `smb5-reg.h:11-14`):

| Reading | Addr | Encoding | Citation |
|---|---|---|---|
| USB present | 0x1310 bit4 `USBIN_PLUGIN_RT_STS` | | `smb5-reg.h:255` |
| power path | 0x110B | bit0 valid-input, bit4 `USE_USBIN`, bit6 suspend | `smb5-reg.h:153-158` |
| charge state | 0x1006 & 7 | 0 inhibit, 1 trickle, 2 pre, 3 fullon, 4 taper, 5 terminate, 6 pause, 7 disable | `smb5-reg.h:30-40` |
| charge error | 0x1007 bit1 `BAT_OV` | | `smb5-reg.h:43-44` |
| JEITA temp status | 0x100D | bits 2/3 hard too-cold/too-hot, 4/5 soft | `smb5-reg.h:51-59` |
| **USB input current limit (settled)** | 0x1107 `ICL_STATUS` | × 50 mA | `smb5-reg.h:146`, `qpnp-smb5.c:56-61` |
| ICL max status | 0x1106 | × 50 mA | `smb5-reg.h:145`, `qpnp-smb5.c:49-55` |
| ICL configured | 0x1370 | × 50 mA | `smb5-reg.h:342` |
| input suspend | 0x1340 bit0 | | `smb5-reg.h:261-262` |
| charger type | 0x1307 `APSD_STATUS`, 0x1308 `APSD_RESULT_STATUS` | SDP/CDP/DCP/… | `smb5-reg.h:224-238` |

`smblib_get_charge_param()` is just `raw * step_u + min_u` (`smb5-lib.c:378-404`), so 0x1107 is
readable with no state machine: `mA = raw * 50`.

### 2.3 What actually needs the QG algorithm

Only three things are not a register:

1. **SoC.** `qg_get_battery_capacity()` returns the software `msoc` (a filtered, monotonicised
   estimate), not a hardware field (`qpnp-qg.c:2157`; hardware 0x48BF is only its mirror).
2. **OCV→SoC.** `lookup_soc_ocv()` interpolates `qcom,pc-temp-v1-lut` while charging and
   `qcom,pc-temp-v2-lut` while discharging, temperature-indexed; the table's rows are SoC×100 and
   its cells are **100 µV** (`qg-battery-profile.c:40-42,395-412` — `UV_TO_DECIUV`,
   `DIV_ROUND_CLOSEST(soc,100)`).
3. **ESR correction / coulomb counting.** The vendor's `msoc` rides on OCV plus ESR compensation
   and FIFO current accumulation (`qg-soc.c`, TCSS at `:237-340`). `R_bat` comes from the profile's
   `pc-temp-z*-lut` and from `SDAM_RBAT` (`qg-sdam.c:39-43`).

Nothing in the QG needs to be *started*: `qg_hw_init()` only reads the subtype and adjusts FIFO
length/accumulator settings (`qpnp-qg.c:3461-3535`); the measurement engine runs from PMIC power-on.

### 2.4 The battery profile this phone ships

`avicii/mtp.dtsi:48-52` includes exactly two profiles, and the live FDT carries the same two
(`live.dts:28070-28301`):

| | `alium_860_89032_0000_3600mAh` | `ATL466271_3300mAh` |
|---|---|---|
| `batt-id-kohm` (15 % window, `mtp.dtsi:49`) | 107 | 24 |
| `max-voltage-uv` | 4 350 000 | 4 400 000 |
| `fastchg-current-ma` | 5400 | 8000 |
| FCC at 25 °C (`fcc1-temp-lut`) | **3581 mAh** | **3320 mAh** |

(`qg-batterydata-alium-3600mah.dtsi:3-6,32-36`, `qg-batterydata-atl466271_3300mAh.dtsi` same lines,
lineage-21.) 25 °C OCV, discharging table (`pc-temp-v2-lut`, alium, from the same file):

| SoC % | 100 | 90 | 80 | 70 | 60 | 50 | 40 | 30 | 20 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| mV | 4336.0 | 4214.6 | 4107.9 | 3989.3 | 3903.9 | 3838.7 | 3799.1 | 3766.6 | 3731.2 | 3687.5 |

Slope: **10.9 mV per point at 90 %**, **4.7 mV per point at 50 %**, 6.6 mV at 20 %. Three different
capacity numbers live in the vendor DT (4320 from SMB5, 3581 alium, 3320 ATL) and none is the
marketed 4115 mAh — the profile the gauge actually uses is chosen at runtime by `batt-id`
(`qg-battery-profile.c` profile load), which is a phone-run question (§5.4).

## 3. What we do today

Patch `0062-sweet-touch-power-battery.patch`. `SweetBattery` subclasses `IOPMPowerSource` and
implements exactly the contract Apple's header documents: setters, then `updateStatus()` to flush
to powerd (`IOPMPowerSource.h:226-235,269-284`; keys in `IOPM.h:579-591`).

- **`publish()` (`:720-784`)** sets `BatteryInstalled=true`, `CurrentCapacity = 5020*pct/100`,
  `MaxCapacity = 5020`, `Voltage = mv`, `Amperage = ma`, `ExternalConnected`,
  `ExternalChargeCapable`, `IsCharging`, `TimeRemaining = -1`, `CycleCount = 0`,
  `Temperature = 2500` (fixed 25.00 °C, `:745`), `AtWarnLevel=false`, `AtCriticalLevel=false`, plus
  `FullyCharged` and the `AppleRaw*`/`DesignCapacity` mirrors, and a legacy `IOBatteryInfo`
  dictionary. It then calls `updateStatus()` and logs one line per mode change (`:772-779`).
- **5020 mAh is sweet's number**, not avicii's (`:724,727,742`) — the DT here says 4320
  (`live.dts:4211`) and the active profile says 3581 or 3320 (§2.4).
- **`estimatePercent()` (`:806-824`)** is a generic 10-point single-cell curve
  (3400→1 %, 3700→20 %, 3800→40 %, 4000→75 %, 4350→100 %), explicitly not the profile's OCV table.
- **`poll()` (`:826-867`)** reads, all as `sweet_spmi_read(0, …)`:
  `0x4804` type==0x0d, `0x4805` subtype∈{3,4}, `0x4808` present, `0x48c0` V (×194637/1e6),
  `0x48c2` I (×152588/1e6, negated), `0x1310`, `0x110b`, `0x1006`, `0x1007`, `0x100d`. The
  **charger decode is correct** (state 1-4 charging, 5 full, `POWER_PATH` bits match
  `smb5-reg.h:153-158`, `USBIN_PLUGIN` bit4 matches `:255`) and the **sign convention is correct**:
  the QG reports negative while charging (`qg-soc.c:507`), so `-raw` is positive-while-charging,
  which is what IOPM's `Amperage` wants.
- **The blocker is the slave:** `sweet_spmi_read()` returns −1 unless `sid == 0` and the peripheral
  is 0x10-0x13 or 0x48 (`:564-566`). The QG is PPID **0x0248** and SDAM **0x02b1**. Today's
  `0x4804` therefore looks up PPID 0x0048 (PM8150, absent) → `SP_NO_APID` → `poll()` invalid →
  fallback (`:836-841`). That whitelist is itself a sweet leftover: on sweet the charger sat on
  PM6150 (slave 0), and the `PM6150` in the log text (`:778`) came with it. On avicii slave 0 is
  PM8150, whose peripherals are 0x08 (PON), 0x24 (temp-alarm), 0x31 (VADC), 0x35 (adc_tm),
  0x5b (clkdiv), 0x61 (RTC), 0xb1 (SDAM), 0xc0 (GPIO) (`live.dts:3885-4134`) — none of 0x10-0x13
  or 0x48.
- `sweetbattery=1` is not on any cmdline, so `fReal` is false at `:885` and the SPMI block never
  even initialises — consistent with there being no `SWEET BATTERY: SPMI arb=…` line anywhere in
  `logs/` and only the fallback line in every ring.
- `readWord()` (`:786-804`) reads two adjacent bytes 4× until two consecutive reads agree, with no
  HOLD write — a reasonable torn-read guard we should keep.
- Timer cadence is 30 s (`:874,895`), and `TimeRemaining` is permanently −1, so iOS shows no
  estimate even when a real current is available.

## 4. Plan

### 4.1 Step 1 — reach the right slave (one-line fix, no risk)

In `sweet_spmi.c` replace the `sid != 0` guard with a PPID whitelist: `(sid==0, periph 0x08/0x0c/0x10-0x16)`,
`(sid==2, periph 0x48)` for QG and `(sid==2, periph 0xb1)` for SDAM — mirroring `sweetkeys`, which
already computes a 16-bit PPID and reads slave 2 successfully (`0109…patch:15-18`). Also reduce the
1000×`delay(1)` timeout to ~50 iterations for QG reads so a dead APID costs 50 ms, not 1 s, inside
`sp_lock`.

First boot after this change should log the map probe (`arb=0x50010000 apids=512`, as keys does) and
then `QG type=0x0d subtype=? present=?`. If PPID 0x0248 is missing from the APID table, stop — see
§5.1; there is no read-only way around a missing APID.

### 4.2 Step 2 — read V/I/state, keep the charger decode

Per poll (5 s): `0x4804` type, `0x4805` subtype, `0x4808` (present + QG_OK), `0x4809` (missing,
good-OCV), `0x48C0-1` V, `0x48C2-3` I; charger `0x1310`, `0x110B`, `0x1006`, `0x1007`, `0x100D`,
`0x1107`. All plain reads; no HOLD, no writes, no IRQ enable. Store `last_*` under an
`IOCommandGate`/`IOLock` for the sysctl side.

### 4.3 Step 3 — honest SoC: ESR-corrected OCV against the profile table

Do **not** port the QG. Do this, in the poll thread:

```
v_ocv_uv = v_bat_uv + (i_bat_ua * r_bat_mohm) / 1000     /* i>0 = discharging */
```
`r_bat_mohm`: prefer SDAM `0xB14A` (mΩ, defined units, `qg-sdam.c:39-43`) when `valid && 50..500`;
else the profile's `pc-temp-z1-lut` at (SoC, 25 °C) = **12 041** at 100 % / **12 116** at 50 %
(scale not stated in the file; 0.01 mΩ/count ⇒ ~120 mΩ, **UNVERIFIED scale**); else a flat 120 mΩ.
Then piecewise-linear interpolation of the 25 °C column of `pc-temp-v2-lut` (discharging) /
`v1-lut` (charging), clamped to [1,100], with:
* `state == 5` (terminate) and V > 4.2 V ⇒ 100 %, and hold (vendor: `qcom,hold-soc-while-full`);
* slew limit 1 point/poll unless the jump is > 5 points (no flicker);
* publish `SweetBatterySOCEstimated=1` and keep the generic curve only as the `invalid` fallback.

Why the ESR term is not optional: at 120 mΩ and 500 mA the sag is 60 mV = **12.8 points** at 50 %,
and 1 A is 120 mV = **25 points**. Without it a voltage-only gauge is worse than useless while the
CPU is pinned at max clock, which is exactly today's state (`E-thermal`, `B-*`).

Second-order caveat, worth one line of code: if the *wrong* profile is selected the table itself is
off by ~55 mV at the top (alium 4336 mV vs ATL 4391 mV at 100 %), which is 5-11 points mid-curve —
so log the selected `battery-type` string next to the first SoC reading (§5.4).

Optional Step 3b (only if 3 is not accurate enough): read SDAM `0xB147` SoC and `0xB14C` OCV as an
anchor at boot, then coulomb-count `soc -= i_avg*dt/(fcc_mAh*3.6)` and re-anchor to the OCV value
whenever |I| < 50 mA for 2 min. That is 20 lines and gets us to true-gauge behaviour without
touching the QG.

### 4.4 Step 4 — the sysctl contract for lanes B, E and G

Expose a cached, lock-protected snapshot; SPMI stays on the `SweetBattery` timer thread only
(`sweet_spmi.h` says thread context only). New file `bsd/kern/sweet_batstats.c` with the same
`SYSCTL_PROC(_kern, OID_AUTO, …)` shape as `0116…patch:311-313`:

| Sysctl | Type | Meaning |
|---|---|---|
| **`kern.sweet_battery_ma`** | int, RO | **battery current in mA; positive = charging into the battery, negative = discharge. This is the number lanes B/E/G use.** Instantaneous (last poll). |
| **`kern.sweet_battery_avg_ma`** | int, RO | 60 s trailing mean of the same quantity — the steady-state drain figure; signed the same way. |
| `kern.sweet_battery_mv` | int, RO | V_BAT in mV (terminal voltage, **not** OCV). |
| `kern.sweet_battery_ocv_mv` | int, RO | ESR-corrected OCV in mV, or −1 when unavailable. |
| `kern.sweet_battery_soc` | int, RO | 0-100 as published to iOS. |
| `kern.sweet_battery_valid` | int, RO | 1 = fresh QG sample (type/OK/present/range all good), 0 = fallback. |
| `kern.sweet_battery_poll_ms` | int, RW | poll period, default 5000, clamped 500-60000. |

Semantics the other lanes must rely on: 1 mA resolution after the 60 s mean, `0` is a real reading
(QG reports ±0.15 mA steps), and a stale/absent sample is signalled by `valid=0` — never by 0 mA.
Rule for consumers: only compare two `avg_ma` values taken with `valid=1` at the same brightness,
same charger state, ≥3 min apart.

Also fix in `publish()`: `MaxCapacity`/`DesignCapacity` from the **active profile's** FCC
(3581 or 3320 mAh, §2.4) instead of sweet's 5020; `TimeRemaining = capacity*60/|ma|` when
|ma| ≥ 20 mA else −1; `AtWarnLevel` at ≤ 20 % and `AtCriticalLevel` at ≤ 5 % so iOS can warn and
shut down instead of dying at 0 %.

### 4.5 Risk

| Risk | Assessment |
|---|---|
| Reading an unmapped APID | 1 ms × N timeout, then the APID is poisoned (`:594-598`); no PMIC effect. Lower N (§4.1). |
| Two drivers on one observer block | APIDs are per (slave, peripheral) and `sweetkeys` uses different PPIDs; only same-APID access is unserialised. Keys and QG do not overlap. Safe. |
| Torn 16-bit read | Existing 4× double-read guard; keep it. Worst case one wrong sample per poll. |
| Writing the QG by mistake (HOLD 0x4842, master hold 0x4841, mode 0x4844) | Avoidable: read 0x48C2/0x48C6 and accept ±1 LSB noise. Any write to 0x4844 `VI_MODE` or 0x4842 could stall the engine until PMIC reset — do not write. |
| Charger registers | Read-only. `CHARGING_ENABLE_CMD` (0x1042) must never be written — that is the one register that can leave the phone not charging until a full power cycle. |
| Bricking | None: nothing here touches `persist`, `modemst`, `xbl`, `abl`, `tz`, the GPT or a partition. Worst case is a wrong battery percentage and a fallback log line. |

### 4.6 Measurement (what a boot proves)

1. **SPMI reach:** boot with `sweetbattery=1`; expect `SWEET BATTERY: SPMI arb=0x50010000 APIDs=512`
   then `SWEET BATTERY: QG type=0xd subtype=? present=1 qg_ok=1` — pass/fail on one log line.
2. **SoC agreement with Android, same charge.** Three points: charge to full on LineageOS, note
   `capacity`, `voltage_now`, `temp` from `/sys/class/power_supply/battery/*` (QG psy props,
   `qpnp-qg.c:2318-2350`); boot the iOS image within a minute; compare. Repeat at ~50 % and ~20 %.
   Pass: |Δ%| ≤ 5 points and |ΔV| ≤ 30 mV every time.
3. **Current.** Unplugged, fixed brightness, SpringBoard idle 5 min: `sysctl kern.sweet_battery_avg_ma`
   must be (a) negative, (b) stable within ±15 mA over 3 min, (c) consistent with Android's
   `current_now` in the same condition (expect the same sign and magnitude class). That single
   number is what B/E/G use; record it in `docs/STATUS.md` as the first measured drain figure.
4. **Charger.** Plug a 5 V charger: `ExternalConnected=1`, `IsCharging=1`, the iOS bolt appears,
   and `0x1107 × 50` equals the DT ceiling (1800 mA ⇒ raw 36) or the SDP 500 mA limit. Unplug:
   `ExternalConnected=0` within one poll (≤ 5 s).
5. **Drain integration.** One hour of discharge at fixed brightness: `avg_ma` × 1 h must match the
   Android `charge_counter` delta (µAh) within 10 %; that is the calibration that makes §4.4 usable
   for overnight runs (lane G).

## 5. Open questions only a phone run answers

1. **Is PPID 0x0248 (QG) — and 0x02b1 (SDAM) — in the EE0 APID table at all?** The keys run proves
   slave 2 / periph 0xc2 exists; the QG's presence is inference from Android needing it. If absent,
   the read-only plan dies and the fallback is a PMIC arbitration/owner write we have not done before.
2. **Is the QG measurement engine converting after a cold PMIC power-on with no Linux?** Corollary:
   are 0x48C0/0x48C2 live, or frozen at the last Android value? Test: read twice, apply a load, read
   again; and check `0x4808 bit7 QG_OK` / `0x4810 bit3 FIFO_UPDATE_DONE`.
3. **IBAT range:** subtype 3 (5 A, 152.588 µA/LSB) or 4 (10 A, 305.176) — decides the mA scale by 2×.
4. **Which profile is selected?** `batt-id-kohm` 24 (ATL, 3320 mAh, 4.40 V) vs 107 (alium, 3581 mAh,
   4.35 V) — decides both the OCV table and `MaxCapacity`. One SDAM/VADC batt-id read, or compare
   the OCV table's 100 % voltage (4336 vs 4391 mV) against a freshly-charged pack.
5. **Sign of IBAT on this PMIC in practice** — `qg-soc.c:507` implies negative while charging; confirm
   with the charger plugged in before trusting `kern.sweet_battery_ma` in lanes B/E/G.
6. **Does SDAM hold a plausible SoC/OCV after a cold boot** (`0xB147`, `0xB14C`, and the PBS-written
   `0xB1BC`)? If yes, Step 3b gets a free anchor; if no, the gauge must always start from OCV.
7. **Does iOS's powerd accept the corrected `MaxCapacity`** (3581/3320 instead of 5020) without
   refusing the source, and does the status bar then show a sane percentage? Our `publish()` already
   ships a legacy `IOBatteryInfo` dictionary, so a mismatch here would be visible in one boot.
8. **QG vs Android accuracy on the same discharge curve** — the 3-point comparison in §4.6.2 either
   validates the 0.194637 mV/LSB and the table's 100 µV cells, or shows a scale bug like the one
   that made `sweet_spmi` read the wrong slave.