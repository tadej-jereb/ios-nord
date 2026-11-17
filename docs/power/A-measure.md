# A — measurement and battery reporting (static, kern-0150)

## Evidence and confidence

Only vendor DTS facts below have vendor-configuration evidence; no hardware behavior was verified by this audit, and there were **no live reads**. **UNVERIFIED** applies to every driver-derived register interpretation, software behavior, prediction, policy value and proposed interface below. A source citation establishes what source says, not what this handset does. This appendix proposes work; it changes no driver and runs no phone command.

Repository paths are relative to kern-0150 (`0b457c4`); `XNU:` means `/home/tadej/xnu-8796.141.3/`. `LOS:` means a pinned primary source in [LineageOS android_kernel_oneplus_sm7250, commit 9ea68e4dee77be15d37a9044ecae6754fb2ca454](https://github.com/LineageOS/android_kernel_oneplus_sm7250/tree/9ea68e4dee77be15d37a9044ecae6754fb2ca454). In `LOS:` citations, driver filenames expand to `drivers/power/supply/qcom/<filename>`; `pm7250b.dtsi` expands to `arch/arm64/boot/dts/vendor/qcom/pm7250b.dtsi`. Sources were downloaded read-only to `/tmp/power-m-*`, not added to the repository. The pinned source URL and exact lines remain reproducible without those temporary files. Hardware constants added below must first be incorporated into `avicii/CONSTANTS.md` with these citations before implementation (`AGENTS.md:23-25`).

## Corrected current state

**UNVERIFIED — important discrepancy with the task brief:** 0062 is not merely a fixed battery stub. It already adds a read-only observer SPMI helper, a `SweetBattery : IOPMPowerSource`, and optional `sweetbattery=1` polling. Default `real=0` still publishes the static fallback; the enabled path is PM6150-specific, hardcodes SID 0, nominal capacity 5020, and estimates SOC from a generic voltage curve. Therefore “there is no avicii fuel-gauge readout” is an appropriate deployment description, but “there is no implementation to adapt” is false. Sources: `xnu-avicii/patches/0062-sweet-touch-power-battery.patch:475-479,560-578,638,723-751,806-822,830-865,884-902`.

The board DTS enables **PM7250B**, not PM8150B, for charger and QG: `avicii/mtp.dtsi:287-319,321-335`. Its PMIC parent uses SID **2**, QG is **0x4800**, QG SDAM **0xb100**, and charger subperipherals include CHGR **0x1000**, DCDC **0x1100**, BATIF **0x1200**, USBIN **0x1300**: `LOS:pm7250b.dtsi:11-19,27-39,60,81,100,222-254`. These are vendor DTS facts; selecting them over the inherited SID0 helper follows the board overlay. Actual APID ownership, QG state after ABL, and availability of calibrated ADC samples remain **UNVERIFIED** until live reads.

**UNVERIFIED:** the current helper rejects every SID except 0; simply enabling `sweetbattery=1` cannot constitute an avicii port. Its observer map/APID logic, lane timeout poisoning and serial lock are useful templates, but must be checked against the live arbiter and SID2 lanes; do not broaden access to arbitrary SPMI addresses. Source: `xnu-avicii/patches/0062-sweet-touch-power-battery.patch:490-500,510-525,538-550,560-595`. The SPMI MMIO bases themselves are DTS-backed in `avicii/lito.dtsi:1804-1815` / `avicii/CONSTANTS.md:79` (use the DTS anchor if table line moves).

## Read-only register shortlist

Everything in the interpretation column is **UNVERIFIED** until matched to live PM7250B revision/subtype and Lineage readings. Offsets and bit fields below are Linux-driver-derived, not DTS constants; they must stay explicitly UNVERIFIED in any new constants entry. Bases/SID are separately DTS-backed above.

| Read | Interpretation and source |
|---|---|
| SID2 QG base +0x04/+0x05 | Type should be QG type 0x0d; subtype3 = 5A conversion, subtype4 = 10A conversion. `LOS:qg-reg.h:9-15`; reject any other subtype, do not assume a default conversion. |
| QG +0x08 | Battery-present bit0, QG_OK bit7. `LOS:qg-reg.h:17-20`; publish raw byte and validity separately. |
| QG +0xc0/+0xc1 | Last ADC voltage, little-endian16. `LOS:qg-reg.h:108`; Linux reads it in `LOS:qg-util.c:466-485`, scaling `raw*194637/1000` microvolts from `LOS:qg-defs.h:34`. |
| QG +0xc2/+0xc3 | Last ADC current, signed little-endian16. `LOS:qg-reg.h:109`; candidate instantaneous current, conversion `signed_raw*152588/1000` µA for subtype3, `*305176/1000` µA for subtype4 (`LOS:qg-util.c:123-128`). This is not automatically equivalent to Linux's `current_now`. |
| QG +0xc6/+0xc7 | Last burst-average current. Linux `qg_get_battery_current` writes a HOLD bit before reading and releases it after; a strict read-only port must not copy that procedure. `LOS:qg-reg.h:46-47,111`; `LOS:qg-util.c:426-463`. An unlatched repeated read may still tear or be stale; record that limitation. |
| USBIN +0x10 | USB plugin bit4. `LOS:smb5-reg.h:24,251-258`; actual Linux present getter `LOS:smb5-lib.c:3259-3272`. Plugin alone does not mean charging. |
| DCDC +0x0b | USE_USBIN bit4, VALID_INPUT bit0, suspend bit6. `LOS:smb5-reg.h:153-158`. Separate physical cable presence from selected valid source. |
| CHGR +0x06/+0x07/+0x0d | Charge state bits2:0; 1..4 indicate trickle/pre/full-on/taper, 5 terminate, 6 pause, 7 disable; error OV bit1 and temperature-hard-limit bits3:2. `LOS:smb5-reg.h:30-59`; Linux status has additional policy/workarounds (`LOS:smb5-lib.c:2068-2118`), so report raw state alongside conservative derived charging. |
| QG +0xbf and SDAM | A saved monotonic SOC is not fresh calibrated charge. `LOS:qg-reg.h:106,115-128`; Linux capacity is software `msoc`, conditional on profile-loaded/full/missing (`LOS:qpnp-qg.c:1761-1796`). Do not publish this byte as a new measurement. |

**UNVERIFIED — charge limitation:** Linux `CHARGE_COUNTER` is computed from learned/nominal capacity and software `cc_soc`, while shadow charge is supplied through algorithm userspace data. It is not a standalone read-only hardware coulomb register. Evidence: `LOS:qpnp-qg.c:1223-1224,1664-1681,1799-1819,2213-2217`. A minimum read-only driver can expose voltage/current and estimate **delta charge by integration**; it cannot honestly expose absolute charge or a calibrated SOC merely by reading 0xbf. Preserve `charge_valid=0`, `soc_valid=0` until the profile/algorithm/temperature design is ported and validated. Do not port the generic PM6150 voltage-to-percent table or 5020mAh capacity as avicii facts (`xnu-avicii/patches/0062-sweet-touch-power-battery.patch:723-745,806-822`).

## Minimal sweet_fg design and patch sketch

**UNVERIFIED proposal:** adapt the existing helper and class rather than register a second competing power source. New `bsd/dev/sweet_fg.c/.h` owns one cached sample, one serial lock and read-only sysctl handlers; `SweetBattery` consumes the cache. Default disabled; opt in with `sweetfg=1`. No charger policy, no PMIC writes, no IRQ acknowledgment, no HOLD/FIFO clear, no SDAM write, no ADC configuration, no RPMh vote. Existing helper already issues observer read commands and poisons timed-out lanes (`xnu-avicii/patches/0062-sweet-touch-power-battery.patch:475-479,575-595`). Do not call Linux `qg_read()` verbatim: its special handling writes sticky STATUS2 back to clear it (`LOS:qg-util.c:21-45`).

Pseudo-diff against the classes introduced by 0062; not compilable or applied:

```diff
--- a/bsd/dev/sweet_spmi.c
+++ b/bsd/dev/sweet_spmi.c
- reject sid != 0; permit broad PM6150 battery peripheral ranges
+ accept only board-configured SID2 and explicit approved read addresses
+ discover APIDs from live arbiter mapping; validate access/timeout as before
+ expose no PMIC-write primitive; fail closed on unexpected arbiter/revision
--- /dev/null
+++ b/bsd/dev/sweet_fg.c
+ /* proposed API: all hardware-dependent interpretation UNVERIFIED */
+ sample_once():
+   verify QG type/subtype; record raw present byte
+   read two matching complete little-endian voltage/current words
+   bound retries; reset sentinel 0x8000 => invalid, never 0% / 0mA success
+   read USB present, power path, charger state/errors
+   convert to signed microamps and microvolts using checked wide arithmetic
+   publish sample atomically with sequence, monotonic timestamp, valid mask
+   mark coherence/freshness unknown until observed conversion cadence is known
+   charge_uah_valid = soc_valid = 0
+ /* cached reads do not trigger fresh SPMI operations from sysctl callers */
+ SYSCTL_RD kern.sweet_fg.sample     // one consistent text record
+ SYSCTL_RD kern.sweet_fg.errors     // count + latest transport/subtype error
+ SYSCTL_RD kern.sweet_fg.info       // SID, bases, subtype, source and validity
--- a/iokit/Kernel/arm/SweetBattery.cpp
+++ b/iokit/Kernel/arm/SweetBattery.cpp
- directly poll hardcoded SID0 PM6150; use 5020mAh and generic SOC table
+ consume validated sweet_fg sample; report raw measurement validity explicitly
+ publish measured voltage/current/source/charging independently of SOC validity
+ do not invent capacity, temperature, full, cycle count or time-to-empty
+ keep compatibility fallback visibly labelled until calibrated capacity exists
+ updateStatus() after one complete coherent batch; no duplicate battery service
```

**UNVERIFIED proposed sample contract:** `seq=<n> mono_ns=<t> voltage_uv=<v> current_ua=<i> current_sign=discharge_positive usb_present=<0|1> charging=<0|1> valid=<mask> age_ns=<a> charge_valid=0 soc_valid=0`. Record raw bytes/subtype in `info`. `valid=0`/errno is an unsuccessful measurement; do not average it as zero power. Poll cadence is a policy to choose after measuring conversion freshness, not a fabricated PMIC capability. Start with one cached acquisition per second for diagnostics (UNVERIFIED design value), then reduce periodic wakes; source cadence comes from observing the device, not a guaranteed datasheet rate (`LOS:qg-util.c:426-485`; existing retry concept `xnu-avicii/patches/0062-sweet-touch-power-battery.patch:782-802`). Repeated matching reads mitigate tearing but prove neither simultaneous V/I capture nor a newly converted sample.

## iOS battery UI contract

**UNVERIFIED:** XNU's supported path is an `IOPMPowerSource` subclass, populated at startup and updated using setters plus `updateStatus()`. Capacity/max must share mAh units, current mA and voltage mV. Evidence: `XNU:iokit/IOKit/pwr_mgt/IOPMPowerSource.h:44-60,95-115,226-235,266-285`. Existing `SweetBattery` already supplies that class and legacy dictionary, so first test its registry publication and notifications; do not initially spoof AppleSmartBattery identity or add a second provider (`xnu-avicii/patches/0062-sweet-touch-power-battery.patch:638,720-772,887-902`). Keep signed current conversion explicit; the inherited class flips Linux discharge-positive current for its compatibility output (`xnu-avicii/patches/0062-sweet-touch-power-battery.patch:859-862`), which still needs validation against the consumer.

**UNVERIFIED proposed minimum properties:** BatteryInstalled, ExternalConnected, ExternalChargeCapable, IsCharging, Voltage, Amperage, and coherent CurrentCapacity/MaxCapacity only when supported. Optional AppleRaw* properties are compatibility hypotheses present in the inherited implementation, not proof of iOS16.7 consumer requirements (`xnu-avicii/patches/0062-sweet-touch-power-battery.patch:725-751`). Once SOC exists, choose measured/profile-calibrated capacity and real temperature; publish no zero remaining-time on transport error. Compare IORegistry and visible SpringBoard state on cable attach/detach; an accurate registry does not prove the UI uses it. The task's requested exact private SpringBoard/powerd consumer ABI remains **UNVERIFIED**; this audit did not infer it from binary names.

**UNVERIFIED static root evidence, reproducible extraction:** 7z successfully returned plist bytes but also returned status2 / `Headers Error`; both plist payloads parsed. Treat completeness of the image as unproven. No mount or image write occurred. Decoded `iOSRoot/System/Library/LaunchDaemons/com.apple.powerd.plist` has KeepAlive=true, Label=com.apple.powerd, Program=/System/Library/CoreServices/powerd.bundle/powerd, and MachServices for PowerManagement.control / iokit.powerdxpc / lowpowermode / smartpowernap. The SpringBoard preferences examined contain watchdog/setup keys only, not a battery percentage override. Root evidence is recorded below by a text capture with line numbers, because binary plists have no meaningful source line numbering:

```text
A-root-capture:1 image=/home/tadej/ios-nord/build/ios16-root.img (read-only 7z -so)
A-root-capture:2 member=iOSRoot/System/Library/LaunchDaemons/com.apple.powerd.plist
A-root-capture:3 bytes_sha256=99bd1283703e2f58cc41f5d601fa6534ae904d7b646d0c0ca45542d7d9c21886
A-root-capture:4 KeepAlive=true Label=com.apple.powerd
A-root-capture:5 Program=/System/Library/CoreServices/powerd.bundle/powerd
A-root-capture:6 MachServices=com.apple.PowerManagement.control,com.apple.iokit.powerdxpc,com.apple.powerd.coresmartpowernap,com.apple.powerd.lowpowermode,com.apple.powerd.smartpowernap
A-root-capture:7 member=iOSRoot/private/var/mobile/Library/Preferences/com.apple.springboard.plist
A-root-capture:8 bytes_sha256=e80395c626cc633e4998428d4c85bba17f55a36b00fd2d74e3b479450b037856
A-root-capture:9 BKNoWatchdogs=true FBLaunchWatchdogExceptions={com.apple.purplebuddy:100.0} MCForceShowCloudConfigurationUI=false
A-root-capture:10 both 7z extractions returned exit2/Headers Error; plistlib.loads accepted returned bytes
```

Keep powerd enabled while validating notifications; its published services and restart policy are evidence of expected consumers, not proof of idle CPU cost (`A-root-capture:4-6`, **UNVERIFIED**).

## Measurement procedure for Claude (future commands; not run here)

All durations, repetitions and thresholds below are **UNVERIFIED experimental design choices**, not hardware constants. No flash/reboot/build command is included. Any separately prepared kernel deployment needs its own owner gate and provenance hash before a destructive operation (`AGENTS.md:29-31`). Use the already authorized SSH setup; if direct SSH is not configured, use its existing key/preset wrapper, never change phone state to make this transcript work.

1. **First measurement on current iOS kernel:** record the actually published power source and the kernel log. These are current interfaces/class definitions, not invented new fg sysctls (`xnu-avicii/patches/0062-sweet-touch-power-battery.patch:638,746-751,775-777,902`; log interface evidence `xnu-avicii/patches/0142-avicii-log-over-ssh-and-flush-at-reset.patch:19-20,85-99`). Command availability on userland is UNVERIFIED; missing ioreg is a tooling gap, not proof no source exists.

```sh
ssh root@192.168.7.2 'ioreg -r -c SweetBattery -l'
ssh root@192.168.7.2 'sysctl -b kern.sweetlog'
```

Expected inherited default: SweetBatteryFallback=true and SweetBatteryHardwareSampleValid=false, nominal/static values; enabling the wrong SID0 path should not be interpreted as PM7250B telemetry (`xnu-avicii/patches/0062-sweet-touch-power-battery.patch:843-844,884-888`, **UNVERIFIED** expected output). Do **not** use the shown Voltage/Amperage for power before those validity flags and board identity are fixed.

2. After a separately reviewed read-only instrumentation kernel exists, check the **proposed**, currently absent interface before starting any run. A missing sysctl on kern-0150 is expected; no claimed measurement has been made (`sample_once` sketch above, **UNVERIFIED**).

```sh
ssh root@192.168.7.2 'sysctl kern.sweet_fg.info kern.sweet_fg.sample kern.sweet_fg.errors'
```

Require SID2/QG4800, supported subtype, valid voltage/current, sequence progression, no growing errors and known source/charging status. First compare magnitude/sign with Lineage `voltage_now`, `current_now`, `capacity`, `charge_counter` on a separate owner-driven Lineage run; never silently assume Linux average equals last ADC. A first Lineage read-only snapshot, only when Claude already has that OS booted and adb available:

```sh
adb shell 'for p in /sys/class/power_supply/bms /sys/class/power_supply/battery; do for n in voltage_now current_now capacity charge_counter status; do echo "$p/$n"; cat "$p/$n"; done; done'
```

Those sysfs paths/property presence are **UNVERIFIED** until read; Linux exports corresponding QG properties at `LOS:qpnp-qg.c:2158-2170,2213-2217,2321-2322`. Do not boot/switch a slot merely to execute this static plan.

3. Use fixed brightness/content, identical render path, thermal settling and similar SOC/temperature for every pair. Proposed baseline windows: 60s settling, 120s capture, three A/B/A pairs. Manually place the phone in each state before running the next capture: screen-on static idle; screen off; reproducible lock-screen animation; GLES compositor; later equivalent Metal compositor once independently available. Compare the same scene, resolution, animation duration and frame pacing. Screen-off vs screen-on differences also include panel energy, and Metal/GLES comparison is invalid if one omits layers (`/home/tadej/ios-nord/docs/METAL_PLAN.md:3-4,43-50` in primary checkout is the external planning input; renderer completeness must be established independently, **UNVERIFIED**).

```sh
ssh root@192.168.7.2 'i=0; while [ "$i" -lt 120 ]; do sysctl -n kern.sweet_fg.sample; sleep 1; i=$((i+1)); done' > power-screen-on-idle.txt
ssh root@192.168.7.2 'i=0; while [ "$i" -lt 120 ]; do sysctl -n kern.sweet_fg.sample; sleep 1; i=$((i+1)); done' > power-screen-off.txt
ssh root@192.168.7.2 'i=0; while [ "$i" -lt 120 ]; do sysctl -n kern.sweet_fg.sample; sleep 1; i=$((i+1)); done' > power-lock-animation.txt
ssh root@192.168.7.2 'i=0; while [ "$i" -lt 120 ]; do sysctl -n kern.sweet_fg.sample; sleep 1; i=$((i+1)); done' > power-gles.txt
ssh root@192.168.7.2 'i=0; while [ "$i" -lt 120 ]; do sysctl -n kern.sweet_fg.sample; sleep 1; i=$((i+1)); done' > power-metal.txt
```

**UNVERIFIED measurement limitations:** USB Ethernet sampling wakes CPUs and often supplies charging power. Above files measure the **battery net terminal power**, not total handset consumption, while USB supplies energy. Keep identical cable/charger state and mark those runs “USB attached, net battery”; do not report their difference as battery-life improvement without independent input-power measurement. Add a bounded in-kernel sample ring (fixed duration, no network stream or per-sample disk writes) and retrieve after an unplugged window to measure discharge. Sampling itself adds wakes, so quantify instrumentation-on vs off; keep watchdog safety enabled. Any USB input meter measures handset+charging/conversion losses, not automatically battery energy. These are proposed experimental controls, with the transport and charging ambiguity grounded in `AGENTS.md:34-36` and `LOS:smb5-reg.h:153-158,251-258`.

**UNVERIFIED analysis rule:** for validated, timestamped discharge-positive samples, `P_mW=voltage_uv*current_ua/1e9`; integrate trapezoidally over monotonic seconds: `E_mWh=sum(P_avg*dt)/3600`, `delta_charge_uAh=sum(I_avg*dt)/3600`. These are arithmetic definitions, not handset measurements. Reject stale/invalid samples; preserve the sign during charging. Report mean/median, range across repeats, energy per identical animation and p95/p99 frame time/dropped frames. `gain=(baseline_energy-candidate_energy)/baseline_energy`; no percent gain is justified before this experiment. Add kernel CPU runtime/wakeup/interrupt/OSM sample counters from tracks B/C so an energy change can be separated from reduced work or slower UI.

## Top items (gain / risk / effort / exact check)

1. **Port PM7250B read-only telemetry first.** Gain: **UNVERIFIED, no direct battery saving claimed**; enables comparable current/energy measurements. Risk: wrong SPMI lane/revision and stale ADC; fail closed and never change charger configuration. Effort: medium, reusing the observer and existing service. Check: step2 `sysctl kern.sweet_fg.info kern.sweet_fg.sample kern.sweet_fg.errors`; expected SID2, supported type/subtype, valid fresh timestamps and zero error growth. Evidence: `avicii/mtp.dtsi:287,321`; `LOS:pm7250b.dtsi:11-13,236-254`; `xnu-avicii/patches/0062-sweet-touch-power-battery.patch:560-595`.
2. **Keep battery UI honest before advertising capacity.** Gain: **UNVERIFIED, correctness/observability, no saving claimed**. Risk: false SOC/critical state can trigger userland policy; do not turn a generic voltage curve into real charge. Effort: medium for V/I/source, high for calibrated SOC/temperature/model. Check: step1 `ioreg -r -c SweetBattery -l`, then the same command on each owner-driven cable state; expected ExternalConnected/IsCharging agree with raw hardware status while SOC validity stays false until implemented. Evidence: `xnu-avicii/patches/0062-sweet-touch-power-battery.patch:720-772,806-822`; `LOS:qpnp-qg.c:1761-1819`; XNU header `:44-60,95-115`.
3. **Establish unplugged paired energy capture before tuning.** Gain: **UNVERIFIED, experimental validity, no direct saving claimed**. Risk: USB/charging and thermal drift confound runs; sampling perturbs idle. Effort: low for attached diagnostic snapshots, medium for a cached timed ring. Check: the five step3 capture commands after each controlled state, plus matching sequence/valid masks; unplugged ring retrieval must show an interval with `usb_present=0`, known discharge sign and no invalid/stale samples. Proposed ring interface is not yet implemented; do not claim attached SSH runs prove battery life (`LOS:smb5-lib.c:3259-3272`; sample contract above).
