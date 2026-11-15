# Lane H — userland daemons that spin, crash or wake the CPU

Research only. No phone was touched; every command below is for the main agent to run. Written
2026-11-15. Inputs: `logs/phone/live-*.txt`, `logs/phone/cpu-scroll-*.txt`, every
`logs/phone/*/ring-pre.txt`, the LaunchDaemons/LaunchAgents/LaunchAngels trees of
`build/ipsw-x/087-86698-044.dmg` (mounted read-only through `tooling/opt/apfs-fuse`),
`avicii/rd-root/jobs-boot.tsv`, and the AKS/touch/sampler patches in `xnu-avicii/patches/`.

## 0. Method, and why the rates are trustworthy

* Spawn counts come from the kernel's own `exec <name>` line (patch `0042`). Exit lines do not
  exist, so a repeated `exec` of the same name is the only signal we have; crash **events** come
  from `CRASH <name>[pid] sig …` (patches `0043`/`0044`, always 4 lines per event; the tables below
  count events, not lines).
* Wall time per log comes from the process sampler (`SMP --- sample N`, patch `0054`/`0055`:
  first sample 90 s after start, then every 120 s). Every line is mapped onto that axis and rates
  are per covered second, ×3600.
* Two independent checks that the axis is right: (a) the spacing between respawns of the
  looping daemons below (10.2 s) is exactly launchd's default `ThrottleInterval` — neither plist sets the key; (b)
  `SWEET TOUCH: report err` prints once per 100 failed polls of a 10 ms loop (`0060:756,766`),
  i.e. ~18/s, and the logs measure 17.1/s (`live-20261114-0113-usb.txt`, 48359 lines / 2821 s).
* Covered time per file: 0113 2821 s, 0114 1817 s, 0115 954 s, 0116 4438 s, 0118 25007 s
  (three boots).
* `ESTIMATED` marks anything I could not measure.

## 1. Summary (ranked by measured cost)

| # | offender | measured cost | status |
|---|---|---|---|
| 1 | `assetsd` (+ its `ReportCrash` escort) | 68 crashes+spawns in 100 s → **257/h**; `ReportCrash` at **50.4–192.4 %** of one core while it runs; loop starts ~1 s after `photoanalysisd` is exec'd and never stops before the log ends | **live**, fires whenever the Photos path runs |
| 2 | `bluetoothd` **+** `fairplayd.H2` | **704 spawns/h** together (352+353 … 314+314), i.e. 47 % of every exec in `0113`; each lives ~0.35 s and is respawned every 10.2 s | **disabled** (0 spawns in the newest 7 h and in `0123`/`0125`); must stay disabled |
| 3 | `nanotimekitcompaniond` | **956 spawns in 7 h of `0118`** (33 % of every exec in that log), 337/h in its last boot, **31 in the 277 s tail of `0125` ≈ 400/h**, restart every **4.1 s** median | **live**, newest kernel |
| 4 | `ReportCrash` | 50.4–192.4 % of one core for every crash burst (8 positive `ps` samples) | **live**; was disabled once by the owner (`docs/anonbeat1-NOTES.md:656`) |
| 5 | `mediaserverd` | 1.3 and 3.8 SIGABRT crashes/h in the two runs that show it, at `assetsd`'s exact pc | **live** |
| 6 | `PosterBoard` | 0.4–2 SIGTRAP crashes/h, same pc every time, right after `SWEET AKS: PosterBoard sel 0/7` | **live** |
| 7 | `driverkitd` | exactly **1 jetsam kill per boot, in 20+ consecutive runs** | **live** |
| 8 | SpringBoard AKS selector-17 storm | bursts at 0.05 s spacing (**20/s**), **416 calls in the worst minute**, 1 kernel log line per call | **live** |
| 9 | `securityd` sel 10 / SpringBoard sel 8+32 | **203** sel-10 calls in `0118` alone, **96** sel-8 across all logs — every one returns `0xe00002c7` (unsupported) | **live**, kernel-side fix |
| 10 | `chronod`, `searchd`, `cloudd`, `nsurlsessiond` | single-sample peaks 24.8 / **206.5** / 19.1 / 21.9 % | live, secondary |

Measured bottom line: disabling #2 took the process-start load from **1568 execs/h** (`0116`) to
**417/h** (`0118`), −73 %. If 4.1–4.7 all land, the **ESTIMATED** extra gain is ~1 core of crash
reporting plus ~600 spawns/h; #1 is the one that costs a whole core when anything touches Photos.

## 2. What Apple ships, and why it does not fit this phone

The plists are readable in the mounted DMG; the job table already flags these jobs
(`avicii/rd-root/jobs-boot.tsv` says of bluetoothd, fairplayd.H2 and vmd: "program not in OS
DMG").

* **`com.apple.bluetoothd`** (`…/LaunchDaemons/com.apple.bluetoothd.plist`): `RunAtLoad true`,
  `KeepAlive {"SuccessfulExit": false}`, `SuccessfulExit false`, 13 Mach services
  (`com.apple.server.bluetooth*`, `com.apple.bluetooth.xpc`, `…wirelessproxd`), `PublishesEvents
  com.apple.bluetooth.connections/discovery`. A non-zero exit therefore means *respawn forever*.
  The live DT still names `/soc/bt_wcn3990` (`perf-inputs/live.dts:28539`, node at `:662`) but
  nothing in the kernel owns it, so every start fails init and exits.
* **`com.apple.fairplayd.H2`**: `KeepAlive true` **unconditionally** — even a clean exit is
  restarted; `HostSpecialPort 17` for `com.apple.unfreed`, 3 Mach services. No AKS call is ever
  made by it (`SWEET AKS: fairplayd` = 0 lines in `0113`): it dies before it needs the keybag, so
  our keystore stub is not the cause.
* **`com.apple.assetsd`**: `KeepAlive {"Crashed": true}`, no `ThrottleInterval`, 5 Mach services
  incl. `com.apple.assetsd.keepDaemonAlive`, `com.apple.photos.service`,
  `com.apple.corespotlight.receiver.photos*`, plus notifyd/xpc-activity/distnoted launch events
  and a `Crashed`-only keepalive. Any abort is an instant relaunch; observed spacing is 1.3–1.5 s,
  i.e. faster than the 10 s default.
* **`com.apple.nanotimekitcompaniond`**: **no `KeepAlive` at all** — launchd only starts it when a
  client asks for one of its 8 Mach services (`com.apple.nanotimekit.facesupportserver`,
  `…facesnapshotserver`, `…collectionserver`, `…devicelibraryserver`, `…clockface.sync-idswake`,
  `com.apple.clockface.pairedsync`). `LaunchEvents`: xpc activity
  `com.apple.nanotimekitcompanion.snapshots.prewarm` (`ShouldWakeDevice`, `CPUIntensive`,
  `RequiresClassC`, `GracePeriod 60`, `ExpectedDuration 300`, `PostInstall`) and notifyd matching
  `com.apple.LaunchServices.ApplicationsChanged`, `…LanguageChange`, `…LocaleChange`,
  `NanoPhotosLibraryChanged`, `LibraryCollectionTargetMapDataChange`.
* **`com.apple.PosterBoard`** is an **Angel** (`LaunchAngels/com.apple.PosterBoard.plist`):
  `KeepAlive false`, `RunAtLoad false`, `ProcessType/ POSIXSpawnType App`,
  `com.apple.posterboardservices.services` marked `_ExperimentalNonLaunching`, managed by
  RunningBoard — launchd's own keepalive is not in the path.
* **`com.apple.ReportCrash`**: `MachServices com.apple.ReportCrash {ExceptionServer}`,
  `EfficiencyMode Efficient`, no keepalive — one spawn per crash, cannot be reached by
  `launchctl kickstart` alone.
* **`com.apple.mediaserverd`**: `KeepAlive true`, `ThrottleInterval 5`, `PublishesEvents
  com.apple.audio.piper`.
* **`com.apple.driverkitd`**: `RunAtLoad true`, `EnablePressuredExit false`, distnoted events on
  `com.apple.LaunchServices.applicationRegistered/Unregistered`, `HostSpecialPort 15`.
* Do **not** consider `securityd` (`MinimalBootProfile true`, 7 Mach services incl. `octagon`,
  `ckks`, `general`), `watchdogd` (`_PanicOnCrash {PanicOnConsecutiveCrash: true}`), `logd`
  (`KeepAlive true`, BSD syslog socket), `launchd`, `SpringBoard`, `backboardd`.

Structural finding: `driverkitd`, `chronod` and `nanotimekitcompaniond` **all** subscribe to
LaunchServices application registration (`com.apple.LaunchServices.applicationRegistered` /
`…ApplicationsChanged`). `com.apple.datamigrator` re-registers apps repeatedly (6 execs in `0115`, 17 in `0118`), so one registration storm re-arms three daemons.

## 3. What we actually see

### 3.1 The loops that are gone (keep them gone)

`live-20261114-0113-usb.txt` starts the pattern at `:236` (`exec fairplayd.H2`) / `:362`
(`exec bluetoothd`) and repeats it to the end: 277 / 276 execs in 2821 s = **353 / 352 per hour**.
Same in `0114` (180/180 in 1817 s = 357/h, e.g. `:266,:267`), `0115` (95/94 in 954 s = 358/355),
`0116` (387/387 in 4438 s = 314/h). Each pair is ~350 log lines ≈ 10.2 s apart — launchd's
default throttle, both plists leave `ThrottleInterval` unset. Neither prints a `CRASH` line:
they exit on their own after ~0.35 s (7 touch lines), bluetoothd with a non-zero status
(`SuccessfulExit false`), fairplayd with any status (`KeepAlive true`).
In `live-20261115-0118.txt` (7 h) there is **not one** `exec bluetoothd` / `exec fairplayd.H2`,
and none in `…/20261115-153011-usb-kernel-0125-gpu10/ring-pre.txt`. The disable is real and
persistent (state lives in `/private/var/db/com.apple.xpc.launchd/disabled.system.plist`, which
is on `userdata`, not in the rebuilt root — `tooling/` has no disabled-list handling).
Total exec load: `0116` 1568/h → `0118` 417/h.

### 3.2 `assetsd` — the expensive one that is still live

`live-20261115-0115-cpufreq.txt:6315-6318`: `exec com.apple.datamigrator`, `exec photoanalysisd`,
then `CRASH assetsd[317] sig 6` — and from there to the end of the file (2170 lines, ~100 s) it
never stops: 68 `CRASH assetsd` events, each preceded by `SWEET AKS: assetsd sel 0` +
`sel 7` both returning `0x0` (`:6312-6313`, `:6329-6330`). 68 spawns in 954 s = **257/h**.
Every crash is SIGABRT at the identical `pc 0x1cdeab198 lr 0x1dd43a5f8`
(`:6319`, `:6331`, …): a deterministic abort ~1.3 s after start, in a shared library — `mediaserverd`
aborts at the *same* pc/lr (`:2078`), so it is one shared assertion path, not photo-library logic
(**inferred**; the frames are unsymbolised because neither log carries a `STR` heap string).
While the loop runs, `ReportCrash` is up: `cpu-scroll-20261115-0115.txt:228,258` (**192.4 %**,
100.0 %), `cpu-scroll-20261115-0115-reduce.txt:139,149,199` (50.4, 85.9, 99.6),
`cpu-scroll-20261115-novmd.txt:108,113,128` (99.3, 99.3, 100.0) — three different runs, so it is
not one bad capture. Outside the storm assetsd is cheap: 4 spawns / 1 crash in `0114`, 2 / 1 in
`0118`.

### 3.3 `nanotimekitcompaniond` — a 4-second respawn, newest kernel included

`live-20261115-0118.txt:16998,17001,17012,17048,17050,17055,17059` are a 60-line slice; the pairs
`exec xpcproxy` + `exec nanotimekitcompaniond` repeat for the whole last boot. Counts: 956 execs in
25007 s (**138/h**), 337/h in the final 929 s boot; median interval between restarts **4.1 s**
(first intervals of the last boot: 8.2, 5.5, 4.1, 2.7, 8.2, 4.1, 4.1, 24.5, 4.1, 4.1, 10.9, 9.5).
It is 950 of 1406 `xpcproxy` spawns in `0118` (**68 %**) and 31 of 249 in the `0125` ring. No
`CRASH nanotimekitcompaniond` line anywhere, so it exits on its own (SIGKILL would also be silent);
with no `KeepAlive` in its plist, something re-asks for its Mach services every few seconds
(**inferred**: a SpringBoard face/clock client, re-armed by the LaunchServices events above).

### 3.4 Crashes at startup, AKS-adjacent

`PosterBoard` dies **immediately after** our keystore answers it, at one fixed address:
`live-20261115-0118.txt:1949-1954` — `SWEET AKS: PosterBoard sel 0`, `sel 7` (both `0x0`), then
`CRASH PosterBoard[222] sig 5 code 0x600000001 … pc 0x1e1250268 lr 0x1e1250268` (SIGTRAP,
pc == lr, i.e. a trap/assert, not a call). Identical shape at `0114:16403-16409`
(pc `0x1db718268`) and `0116:73854-73855` (pc `0x20a74c268`): same instruction inside
PosterBoard every time, after the same two keystore calls. It is the wallpaper process of an iPhone X-class SpringBoard.

`SWEET AKS: SpringBoard sel 17` is **not** a failing call — sel 17 is `kAKSGetDeviceState`
(`0038-…applekeystore.patch:67`) and every one returns `0x0`. It is a *notification* storm:
SpringBoard registers an `IOServiceNotificationUser` on `AppleKeyStore`
(`live-20261115-0115-cpufreq.txt:745` `IOK SpringBoard: matching1 … AppleKeyStore … ->
AppleKeyStore`) and then re-reads the state in bursts of 25–35 calls at 0.05 s spacing (measured
deltas: 0.05, 0.05, … then 1.6–30 s pause): 1320 calls in 673 s in `0115` — 118/min on average
over the storm and **416 calls in one single minute**, i.e. ~7/s sustained, 20/s inside a burst;
558 in 4438 s in `0116`, 280 in 7 h in `0118`, 94 in the `0125` ring (≈2.6/min). The 20/s bursts
coincide with `IOPMPowerSource -> SweetBattery` re-matches, i.e. our own battery driver's
notification churn. Answering the call is already done; the load is the retry itself.

Failing selectors (all `0xe00002c7` = unsupported): `securityd sel 10` = `kAKSWrapKey`
(**203** in `0118`, 23 in `0114`, 12 in `0116`), `SpringBoard sel 8` (96 total), `SpringBoard sel
32` (20), `profiled sel 31`, `sharingd sel 57`. Every key *wrap* in the system fails; that is the
best candidate for why keystore-adjacent processes abort (**inferred**, kernel lane owns the fix).

### 3.5 Smaller, still worth stopping

* `mediaserverd` SIGABRT 1.3–3.8/h (`0115:2077`), no audio device exists; `ThrottleInterval 5`
  bounds it, but each one still buys a `ReportCrash`.
* `driverkitd`: `CRASH driverkitd sig 9 … reason ns 1 code 0x7` (ns 1 = jetsam) in **every** run
  dir from `20261114-194619-0110f-touch` to `20261115-153011-…-0125-gpu10` — 1 event per boot,
  20+ runs, after a single `exec driverkitd`. Nothing on this phone is a DriverKit extension.
* `Preferences` SIGSEGV twice in `0114` (operator-driven), `searchd` 206.5 % once
  (`cpu-scroll-20261115-0115-reduce.txt:54`), `chronod` 19.8–24.8 % for four consecutive samples
  (`0115:160,169,180` + `:98`), `cloudd` 19.1 % and `nsurlsessiond` 21.9 % in `novmd`.
* Not an offender, for the record: `SWEET Sandbox: … denied` is 3–13 lines per run
  (`dasd` 10001, `accountsd`/`aggregated`/`cloudd` 1002) — noise level.

## 4. Plan

Order is by measured gain. Run one step per boot and check the next ring dump before the next;
`launchctl disable` is persistent, `bootout` only kills the running instance. Undo is the same
line with `enable` everywhere.

Measurement for every step, on the next `ring-pre.txt`: `grep -c 'exec <name>'` normalised per
1000 ring lines, `grep -c 'CRASH <name>'`, `ps -Ao %cpu,comm | sort -rn | head -5` twice 10 s
apart, and `launchctl print-disabled system | grep <label>`. Regression guard for SpringBoard:
`grep -c 'SWEET FB: swap'` must stay non-zero and the panel must keep updating.

### 4.1 `com.apple.ReportCrash` — do this first (≈1 core of bursts, zero functional loss)

```
launchctl disable system/com.apple.ReportCrash
launchctl bootout system/com.apple.ReportCrash
```
Already validated on this port: `docs/anonbeat1-NOTES.md:656` records it disabled by owner OK, and
`:643` notes crashes still show as kernel `CRASH` lines with no `.ips` files. It is safe by
construction: the Mach service is an exception server only; nothing in SpringBoard, touch,
`backboardd`, `sshd` or `ue0` looks it up by name. Risk: we lose symbolication over time (we are
not reading the `.ips` anyway) and crash counts stay visible only as `CRASH` lines. Nothing
depends on it.

### 4.2 `com.apple.assetsd` (≈257 spawns/h + the 1-core escort when triggered)

```
launchctl disable system/com.apple.assetsd
launchctl bootout system/com.apple.assetsd
```
The loop is fatal on its own (68 crashes with no external trigger), so the respawn buys nothing.
Dependents: `com.apple.assetsd.keepDaemonAlive`, `com.apple.photos.service`,
`com.apple.corespotlight.receiver.photos{,.search}` → Photos.app, the photo picker, Spotlight
photo results. **Safe** for SpringBoard boot, home screen, touch, USB-ECM and SSH (assetsd is
demanded lazily, well after SpringBoard is up — its first exec is at line 2056 (`0115`), 3803 (`0113`), 31153 (`0114`) — i.e. long after
SpringBoard is up and its Mach services are not in SpringBoard's 33). Risk: Photos and the picker fail while
disabled, `assetsd.keepDaemonAlive` lookups return `MIG_SERVER_DIED`-class errors to whoever
asks; SpringBoard survives that (it already does today, since assetsd is dead most of the time).
The proper fix is the abort itself (§3.2) — re-enable if the shared abort pc gets solved.

### 4.3 `com.apple.nanotimekitcompaniond` (138–400 spawns/h, 33–68 % of all execs)

```
launchctl disable system/com.apple.nanotimekitcompaniond
launchctl bootout system/com.apple.nanotimekitcompaniond
```
Gain: **ESTIMATED** 2–5 % of a core (an exec + dyld of a framework-backed daemon every 4 s) plus
the largest single block of `launchd` time; it will not show as a `ps` line because it never lives
long enough to be sampled. Dependents are all watch/Nano surfaces (`facesnapshotserver`,
`devicelibraryserver`, `clockface.pairedsync`, `collectionserver`) plus
`clockface.sync-idswake` (IDS is dead anyway). There is no watch paired and no Wi-Fi/BT/modem, so
the faces cannot be produced meaningfully. **Safe** for SpringBoard/touch/USB/SSH; risk is visual
only — face/complication snapshots and the Clock app's face list may come up empty. If the lock
screen clock stops ticking, re-enable and treat the respawn as the price.

### 4.4 `com.apple.mediaserverd` (1.3–3.8 crashes/h, no audio device)

```
launchctl disable system/com.apple.mediaserverd
launchctl bootout system/com.apple.mediaserverd
```
`KeepAlive true` respawns it into the same abort forever; there is no codec and no audio device
behind it (`STATUS.md:47` "no … audio"). Risk: anything that touches CoreMedia at *startup* —
`SpringBoard` plays UI sounds, some apps (MobileSafari, MobileSlideShow) block on it — will log
failures; a hang is unlikely because the XPC lookups just fail. Measured but small (1.3–3.8/h):
do it after 4.1–4.3, and drop it first if SpringBoard starts stalling.

### 4.5 `com.apple.PosterBoard` (0.4–2 SIGTRAP/h, wallpapers)

```
launchctl disable system/com.apple.PosterBoard
launchctl bootout system/com.apple.PosterBoard
```
Every launch is an abort, so it never gets to draw; SpringBoard keeps the icon grid and falls back
to a plain background. **Because it is an Angel** (`KeepAlive false`, `_ExperimentalNonLaunching`)
`disable` may not stick — check `launchctl print-disabled`. Risk: a plain/black wallpaper and a
SpringBoard that has to redraw more on wake (it re-asks
`com.apple.posterboardservices.services` and gets a failure instead of a slow success). Watch
`SWEET FB: swap` after this step; if the frame rate drops instead of rising, revert.

### 4.6 `com.apple.driverkitd` (1 jetsam kill per boot, every boot)

```
launchctl disable system/com.apple.driverkitd
launchctl bootout system/com.apple.driverkitd
```
One spawn plus one `ReportCrash` plus its resident pages per boot, for a subsystem with no
extensions. `RunAtLoad true`, `EnablePressuredExit false` (so it sits in memory until jetsam takes
it). Dependents: `com.apple.DriverKitExtensionServer`,
`com.apple.KernelManagementPingServer` (`HostSpecialPort 15`) — both unused here. Safe.

### 4.7 `com.apple.searchd` (206 % peak, Spotlight)

```
launchctl disable system/com.apple.searchd
launchctl bootout system/com.apple.searchd
```
Cost: **ESTIMATED** 2–10 % of a core while it indexes, plus 266 `sel 35` AKS calls in `0118`. It
already has `_ExponentialThrottling` and `EnablePressuredExit`, so the loop self-limits. Risk:
Spotlight/pulldown search returns nothing, and `com.apple.spotlight.IndexAgent` lookups fail
(SpringBoard handles that — search is on demand). Safe for touch/USB/SSH.

### 4.8 Leave alone

`securityd` (`MinimalBootProfile`, keybag), `watchdogd` (`PanicOnConsecutiveCrash`), `logd`,
`cfprefsd`, `launchd`, `SpringBoard`, `backboardd`, `sshd`, and the ue0 stack. `contextstored`,
`duetexpertd`, `searchpartyd`, `ospredictiond`, `peopled`, `privacyaccountingd` are cheap
(1.6 % and below each, 2–3 AKS `sel 17` per minute) — disabling them is optional, and each costs
its Mach services.

## 5. Open questions only a phone run answers

1. Does `assetsd` still crash-loop when `photoanalysisd`/`com.apple.datamigrator` are also
   disabled? If the *trigger* is gone, the crash path may never be entered and 4.2 becomes free.
2. What actually re-asks for `nanotimekitcompaniond` every 4 s — a `launchctl print
   system/com.apple.nanotimekitcompaniond` instance log plus `log show --predicate
   'subsystem == "com.apple.nanotimekit"'` during a respawn would name the client; then a
   narrower fix (e.g. a distnoted throttle) may beat a disable.
3. Does disabling `PosterBoard` stick through a SpringBoard relaunch, or does RunningBoard
   resurrect it? (Angels are not launchd's decision.)
4. Is the shared abort at `pc 0x1cdeab198` / `lr 0x1dd43a5f8` removed by implementing
   `kAKSWrapKey` (sel 10) or by supplying a real keybag? That decides whether §4.2/§4.4 are
   temporary.
5. Does the `sel 17` storm stop if `SweetBattery` stops re-publishing at 20/s, and what is that
   rate's actual CPU cost (`pidstat`-style delta on SpringBoard with and without the storm)?
6. Nothing here was measured with the GPU path up: `backboardd` at 314 % median may absorb the
   savings differently once QuartzCore has an accelerator.
