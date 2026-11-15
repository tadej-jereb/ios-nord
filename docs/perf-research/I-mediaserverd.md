# I — mediaserverd (and launchd) on an idle phone

Round 3, lane 4. Owns this file. No phone was touched: every number below is from a command that was
run earlier (cited to `logs/phone/…`) or from a file on the DMGs mounted read-only in
`~/.hermes/cache/scratch/lane-4/`. Anything I could not prove is marked **inferred**.

## Summary

* `mediaserverd` is **not** crash-looping: one `exec` per boot, ≤1 abort per boot (0 in the 5-boot 7 h
  ring `live-20261115-0118.txt`); 46.2 % (`h1-disable-before.txt:4`) is a **resident ≈0.46-core spin**.
* **Root cause not established; best hypothesis (H1):** the CoreAudio HAL inside it has **zero drivers**
  — the tweak moved the only HAL plugin (`VirtualAudio.plugin`) to `HAL.disabled/`
  (`tooling/33b-tweaks-idempotent.py:27-28`) — so startup never completes and it loops in a retry/pump.
  H2: its only Objective-C is a CoreMotion orientation pump nothing on this phone can satisfy.
* **One boot settles it**, never yet taken: `sweetsample=mediaserverd,launchd` (`0054:144`); no
  `SMP mediaserverd` or `IOK mediaserverd` line exists in any ring.
* Startup does fail hard in some boots: mediaserverd and `assetsd` abort at the **same unslid pc**
  (`0x1c2617198` = `libsystem_kernel+0x7198`) → an **uncaught exception escaping a dispatch block**.
* **Recommended (userland only, reversible):** `kill -STOP` to confirm, then `launchctl bootout`, then
  `launchctl disable system/com.apple.mediaserverd`. No kernel, no reboot, no audio to lose.
* `launchd`'s 77.7 % is **not** spawning: 844 execs/h measured (356/h `nanotimekitcompaniond`), 0.23/s;
  launchd has its own spin, and the next disable is `com.apple.nanotimekitcompaniond`.

## Evidence

### 1. What the two numbers actually are (and the missing "after")

* `logs/phone/h1-disable-before.txt:2` — `16:09:44 up 0:07, load average: 2.10, 2.19, 1.41`;
  `:3` `77.7 /sbin/launchd`; `:4` `46.2 /usr/sbin/mediaserverd`; `:6` `2.4 /usr/libexec/logd`.
* The metric is **not** a lifetime average. `logs/phone/cpu-scroll-20261115-0115.txt:26-28` shows
  `16:02:22` → `433.3 /usr/libexec/backboardd`: a single process at 433 % means the field is a
  **decayed recent sum over that process's threads** (XNU's `p_pctcpu`), so 46.2 % is ~0.46 core
  *right now*, and 433 % is 4.3 cores. That makes the reading trustworthy but makes a single
  snapshot a poor trend measurement.
* **The "after" file never landed:** `logs/phone/h1-disable-after.txt:1` is
  `ssh: connect to host 192.168.7.2 port 22: Connection timed out`. There is currently **no
  before/after pair for anything**, only one snapshot. Re-taking it is read-only (§11, step 0).
* The capture's kernel build is not recorded in the file; the 16:09 timestamp and 7 min uptime put
  it in the 0125/0126 era boots of 2026-11-15 (**inferred** from `logs/phone/` directory times).

### 2. mediaserverd is resident, one exec per boot

Counted over every ring in `logs/phone/` (`exec ` / `CRASH ` prefixes come from patches 0042 and
0053):

| ring | boots in ring | `exec mediaserverd` | `CRASH mediaserverd` events |
|---|---|---|---|
| `20261115-164229-usb-kernel-0126-gpu11/ring-pre.txt` | 1 | 1 (`:693`) | 0 |
| `20261115-092905-usb-kernel-0116/ring-pre.txt` | ≥1 | 2 | 1 (`:4236-4239`) |
| `live-20261115-0118.txt` | 5 (`smp --- sample 0` ×5) | 1 (`:20551`) | **0** |
| `live-20261115-0115-cpufreq.txt` | 1 | 1 | 1 (`:2077-2083`) |
| `live-20261114-0113-usb.txt` | 1 | 1 | 1 (`:3833-3842`) |
| every ring 0119…0126 | 1 each | 1 each | 0 |

Five boots of `live-20261115-0118.txt` — 7 h of idle GUI, the same conditions as the 46 % reading —
produced **zero** mediaserverd aborts. So a crash loop cannot be the CPU: at 46 % of a core and
`ThrottleInterval 5`, a loop would need ~2.3 cores of abort work per second and would show
hundreds of `exec`/`CRASH` lines.

Ordering is also fixed: `exec mediaserverd` lands right after `exec amfid` and before
`exec DumpPanic`/`thermalmonitord` (`…0126-gpu11/ring-pre.txt:692-694`) — it is in the early boot
table, and `avicii/rd-root/jobs-boot.tsv:42` lists it `KeepAlive` with 87 MachServices.

### 3. What it opens, and what it does *not* loop on

* Plist (`/System/Library/LaunchDaemons/com.apple.mediaserverd.plist`, on
  `build/ipsw-x/087-86698-044.dmg`, parsed with `plistlib`): `Label com.apple.mediaserverd`,
  `ThrottleInterval 5`, `POSIXSpawnType Interactive`, `UserName mobile`, `KeepAlive = true`,
  `PublishesEvents = [com.apple.audio.piper]`, **87 MachServices** — the whole CoreAudio/CoreMedia
  server surface (`com.apple.audio.AudioSession`, `…SystemSoundServer-iOS`, `…AudioQueueServer`,
  `…AudioUnitServer`, `com.apple.coremedia.player.xpc`, `…videocompositor`, `…flashlight`,
  `com.apple.videoconference.camera`, `com.apple.mediaserverd.coremedia.watchdog`, …; 29 of them
  conditional on feature flags).
* Binary `/usr/sbin/mediaserverd` (188 416 B, thin arm64, PIE, 173 symbols, stripped of locals).
  `LC_LOAD_DYLIB` = AudioToolbox, **libAudioToolboxUtility.dylib**, CoreMotion, PhotoLibraryServicesCore,
  CoreMedia, MediaToolbox, Foundation, Security, libMobileGestalt, SoftLinking, libc++/libSystem/CF/objc.
  **No IOKit** — so nothing it does by itself is an IOKit match; the audio device side is userspace
  CoreAudio HAL, not a kernel class (this kills the "kernel stub for an IOKit class" option, §9).
* Imported: `_AudioToolboxServerInit`, `_AudioToolboxSetOrientationDetectorCallback`,
  `_audiomxd_enabled`, `_proc_disable_wakemon`, `_sl_dlopen` (soft-linked: `FigMediaServerStart`,
  `MSNMonitorStart`, Celestial.framework, MediaSafetyNet.framework), `_os_transaction_create`,
  `_shm_open`, `XPC_Service::ConnectionHandler`.
* **Its IOKit/AKS trace is startup-only and successful.** In the 0126 ring the whole mediaserverd
  footprint is `exec mediaserverd` plus one AKS group; in `live-20261115-0118.txt` each start is
  `sel 0` (kAKSOpen), `sel 7` (kAKSGetLockState) ×2, `sel 17` (kAKSGetDeviceState) — all
  `-> 0x0` (success), names from `0038-sweet-applekeystore.patch:54-67` — and then nothing for the
  rest of the boot (`:21182-21696`). **No retry on AKS.**
* No `IOK mediaserverd:` line exists anywhere in `logs/phone/` because the IOKit trace boot-arg
  defaults to `backboardd,SpringBoard` (`0054:95`). Its stderr is empty too: there is not one
  `|mediaserverd|` console line in any ring, while `backboardd` produces plenty
  (`live-20261115-0118.txt:1-13`) — consistent with a daemon that logs only via os_log.
* **The HAL has no driver.** `/Library/Audio/Plug-Ins/HAL/` on the OS DMG contains exactly one
  bundle, `VirtualAudio.plugin` (`CFBundleIdentifier com.apple.audio.CoreAudio.VirtualAudio`,
  `CFBundlePackageType BNDL`), and the bring-up tweak moves it away on every populate
  (`tooling/33b-tweaks-idempotent.py:27-28`; enforced in `tooling/35-verify-root-image.sh:586,624-625`).
  No ring mentions `VirtualAudio`/`vdef` at all, i.e. it was not loaded in the boots we have
  (**inferred** from absence). The kernel side has no audio driver either: `xnu-avicii/patches/`
  matches `IOAudio|AppleHDA` only inside the HID usage tables of `0058`.

### 4. The abort is an uncaught exception escaping a dispatch block

`CRASH` lines give pc/lr/sp/fp and 10 backtrace words. Normalising by each boot's slide makes them
comparable, and they are identical across two different ASLR slides:

| boot | slide | pc | pc − slide |
|---|---|---|---|
| 0113 (`live-20261114-0113-usb.txt:3834`) | `0x5e0000` | `0x1c2bf7198` | `0x1c2617198` |
| 0115/0116 (`20261115-092905-usb-kernel-0116/ring-pre.txt:4237`) | `0xb894000` | `0x1cdeab198` | `0x1c2617198` |

Resolving those unslid addresses against the image table of the SystemOS dyld shared cache
(`087-86593-047.dmg`, `dyld_shared_cache_arm64`, uuid `8f970452c9e33e88b114feb1864bc9e0`, 2031
images parsed from the header's image table):

```
pc  0x1c2617198 -> libsystem_kernel.dylib  + 0x7198   (abort path)
lr  0x1d1ba65f8 -> libsystem_pthread.dylib + 0xd5f8   (pthread_kill)
bt0 0x18dc5c4b8 -> libsystem_c.dylib       + 0x1c4b8   (abort)
bt1 0x1d1adef54 -> libc++abi.dylib         + 0x13f54
bt2 0x1d1acfa4c -> libc++abi.dylib         + 0x4a4c
bt3 0x1800d2afc -> libobjc.A.dylib         + 0x1aafc
bt4/bt5          -> libc++abi.dylib        + 0x13424 / 0x133d4
bt6 0x18db98794 -> libdispatch.dylib       + 0x64794
bt9 0x18db7cc68 -> libdispatch.dylib       + 0x48c68
```

`assetsd` (pids 317, 707) aborts at the **same pc/lr and the same bt[0..6]**, differing only at
bt[7]/bt[8] — `libdispatch+0x3f6fc`/`+0x401e4` for mediaserverd vs `+0x3bd48`/`+0x3b480` for
`assetsd` (`20261115-092905-usb-kernel-0116/ring-pre.txt:4236-4239` vs `:8477-8493`). Two unrelated
daemons, one shared failure: a libc++ exception raised inside a block dispatched onto a queue, with
no handler → `std::terminate` → `abort()`. **Inferred** (frames only, no symbols): it is the classic
"uncaught exception in a dispatch block" abort, and its common cause is a failing shared service
both daemons call at startup, not code in either daemon.

This is a real bug worth its own lane, but it is **not** the CPU: it fires once (`sig 6 code 0x0
sub 0x0`, `reason ns 2 code 0x6`, `:4239`).

### 5. The one thing mediaserverd itself loops on

`__objc_methname` in the binary is **193 bytes and holds exactly eight selectors** — the daemon's
entire Objective-C vocabulary:

```
currentRunLoop, deviceOrientationBlocking, initWithTimeIntervalSinceNow:, mainQueue,
orientation, runMode:beforeDate:, startDeviceOrientationUpdatesToQueue:withHandler:,
stopDeviceOrientationUpdates
```

with `_CMDeviceOrientationManager` and `_AudioToolboxSetOrientationDetectorCallback` imported, and
`NSRunLoop`/`NSDate`/`NSOperationQueue`/`NSDefaultRunLoopMode` loaded. In the disassembly (scratch)
the corresponding code starts updates on `mainQueue`, records `orientation`, and waits in a run-loop
pump (`runMode:beforeDate:` with a date from `initWithTimeIntervalSinceNow:`) while
`deviceOrientationBlocking` is set. On an iPhone X the first CoreMotion orientation arrives in
milliseconds; here there is no accelerometer/AOP source in the port, so the wait has nothing to
end it. **Inferred:** if that loop's timeout is small (sub-10 ms) the pump alone accounts for a
sustained ~half core; a run-loop wait with a large timeout would cost ~0, so the timeout constant is
exactly what the sample in §11 step 2 will show.

### 6. launchd: 844 execs/h measured, and that is not 0.77 core

Newest coherent ring (`20261115-164229-usb-kernel-0126-gpu11/ring-pre.txt`): starts at boot
(`:1` `# --- shim ring (loader / diag) ---`), first sample at `:3288` after 455 execs, last (sample
7) at `:3868` after 652 execs. Samples are 120 s apart (`0054:144`: first at +90 s, then every
120 s), so the window is 7 × 120 = 840 s and contains **197 execs = 0.235/s = 844/h**:

| label | in window | per hour |
|---|---|---|
| `xpcproxy` | 98 | 420 |
| `nanotimekitcompaniond` | 83 | **356** |
| everything else | 16 | 69 |

At 0.23 spawns/s launchd would need ~3.3 s of its own CPU per spawn to reach 77 % — implausible
(measured on the same phone: a `assetsd` respawn cycle takes 4.1 s *including* the child's work, lane
H). **Conclusion: launchd has its own spin, independent of the respawn rate**, and the respawn rate
is a second, smaller tax. `nanotimekitcompaniond` at 356/h with a thrash interval is the next
cheapest disable (`com.apple.nanotimekitcompaniond`), as lane H already ordered it.

### 7. What depends on mediaserverd (inferred from the plist, not from a test)

Every client of the 87 MachServices. Practically, on this phone (GUI up, no audio hardware):

* **SpringBoard / UIKit** — `AudioServicesPlaySystemSound`, `AVAudioSession` category/interruption
  setup, media remote. Any of these is a synchronous XPC to mediaserverd; with the job unloaded the
  lookup fails fast in launchd (no kernel hang), so the client gets an error, not a stall.
* **backboardd** — keyboard clicks and UI sounds, and haptics *through* the audio server for some
  paths; it does not link AudioToolbox in its own binary (0 occurrences of `Audio`/`CoreAudio` in
  `LC_LOAD_DYLIB` and strings), so it reaches the server through UIKit/CoreAudio dylibs.
* **Media playback** (any `CoreMedia`/`FigPlayer` path) — nothing plays today: no audio device, and
  the video side is lane A/D work.
* Nothing that is currently *working* on this port needs it: with an empty HAL there is no audio
  output to lose. The risk is client retry storms and os_log noise, which the exec/h count in §6
  will show.

## Options, cheapest first

| # | Option | Exact action | Risk | Cost |
|---|---|---|---|---|
| 1 | **Freeze** (measurement, not a change) | `kill -STOP <pid>`, measure, `kill -CONT <pid>` | a client's synchronous XPC blocks until it times out while frozen; fully reversible in one command | 2 commands |
| 2 | **Unload** (A/B test) | `launchctl bootout system/com.apple.mediaserverd` | clients lose the 87 services; restore with `bootstrap` | 2 commands |
| 3 | **Disable** (the change) | `launchctl disable system/com.apple.mediaserverd` + `bootout` | survives reboot; same client risk; one command to undo | 2 commands |
| 4 | **Restore the HAL plugin** (alternate fix, tests H1) | `mv /Library/Audio/Plug-Ins/HAL.disabled/VirtualAudio.plugin /Library/Audio/Plug-Ins/HAL/` | the old port's `vdef` SIGSEGV loop can come back (that is why it was moved); needs a remount rw | 1 `mv` + reboot |
| 5 | Plist tweak (`ThrottleInterval`) | — | **inert**: nothing is crash-looping (§2). Do not bother. | — |
| 6 | Kernel stub answering "no device" | — | **wrong layer**: mediaserverd loads no IOKit (§3); the missing object is a userspace HAL plugin, not an IOKit class | large |
| 7 | Stub audio device (a HAL plugin that answers "no streams") | new plugin bundle in `/Library/Audio/Plug-Ins/HAL` | needs the AudioServerPlugIn ABI implemented correctly or the exception in §4 becomes a loop | large |

**Recommended: 1 → 3.** Freeze first (zero-risk confirmation that the 46 % is mediaserverd's own
threads), then disable. Option 4 is the thing to try *later* if we want audio, and it is also the
test that separates H1 from H2.

## Plan

0. **(read-only, main agent)** Re-take the snapshot that `h1-disable-after.txt` lost, 3× 10 s apart,
   plus per-thread `ps -M -p <pid>` — commands in §11. Record the exec/label counts.
1. **Freeze.** `kill -STOP <mediaserverd pid>` (or `launchctl kill SIGSTOP
   system/com.apple.mediaserverd`), wait 20 s, take the same `ps` series. Verify: mediaserverd's
   `%cpu` → 0.0 and stays; launchd's `%cpu` and the load average record whatever they do — that
   number alone tells whether launchd's spin is coupled to mediaserverd. Then `kill -CONT <pid>`.
2. **Sample the live process (no reboot).** `ps -M -p <pid>` gives per-thread `%cpu`, state and CPU
   time but **no pc** — record which thread carries the load and in what state (R vs S); it splits
   "one thread spinning" from "several threads taking turns". The pc/bt needs step 3.
3. **One boot with the sampler** (main agent's `74-kernel-loop.sh`, its usual phone run):
   `tooling/74-kernel-loop.sh <RUN_ID> mediaserverd --preset usb --extra "sweetsample=mediaserverd,launchd sweetiolog=mediaserverd"`
   (`tooling/74-kernel-loop.sh:58` passes `--extra` to `71-phone-image.sh`). Verify in the next ring:
   `SMP mediaserverd[pid] tN pc …` lines appear at +90 s and every 120 s, and `IOK mediaserverd:`
   lines appear if it does any registry lookup. Attribute the spin:
   * pc/caller in `libsystem_kernel` (read/kevent/mach_msg) → it is *waiting*, and the 46 % is
     elsewhere (re-run the freeze test);
   * pc in `__CFRunLoopRun` and the caller in mediaserverd's own `__text` → **H2** (orientation pump);
   * pc/bt inside AudioToolbox / libAudioToolboxUtility / Celestial → **H1** (HAL with no driver);
   * pc in `libdispatch` (`_dispatch_*`) → a queue is being drained in a loop, look at the block's
     caller for `AudioToolboxServerInit` vs `MSNMonitorStart`.
4. **Disable and measure.** `launchctl disable system/com.apple.mediaserverd` then `launchctl bootout
   system/com.apple.mediaserverd`; verify `launchctl print-disabled system | grep mediaserverd` says
   `disabled`, `ps` has no `mediaserverd`, and after 10 min idle `launchd`'s `%cpu` and the exec/h
   count (§6 method) are recorded. Undo: `launchctl enable system/com.apple.mediaserverd &&
   launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.mediaserverd.plist`.
5. **Next disable (independent of this lane).** `com.apple.nanotimekitcompaniond` — 356 execs/h
   measured, same 2-command pattern, same revert.
6. Feed the abort (§4) to whoever owns userland crashes: it is one shared, reproducible frame set
   with a slide-independent pc, so it is symbolicate-able with `tools/sweet-crash.py` if the cache
   `.symbols` are staged. It costs a crash per boot, not a core.

## Read-only commands for the main agent (phone, ssh root@192.168.7.2)

```sh
# 0 — rebuild the missing "after" snapshot; 3 samples, 10 s apart, same shape as h1-disable-before
for i in 1 2 3; do date '+%H:%M:%S'; uptime; ps -Ao %cpu,comm | sort -rn | head -6; sleep 10; done
# 0b — monotonic CPU time, so the delta is honest regardless of how %cpu is computed
ps -Ao pid,etime,time,%cpu,comm | grep -E 'mediaserverd|launchd|nanotimekit'
# 0c — per-thread view (this is the shape logs/phone/bbd-threads-20261115.txt has); pid from 0b
ps -M -p <mediaserverd-pid>
# 0d — the job as launchd sees it: pid, last exit status, run count, state
launchctl print system/com.apple.mediaserverd | head -40
launchctl print-disabled system | grep -E 'mediaserverd|nanotimekit'
# 0e — is the HAL really empty, and did anything log an audio failure?
ls -la /Library/Audio/Plug-Ins/HAL/ /Library/Audio/Plug-Ins/HAL.disabled/
# 0f — tools actually present on the phone before trusting any of the above
ls /bin /usr/bin /usr/sbin /usr/libexec /var/jb/usr/bin 2>/dev/null | sort -u | tr '\n' ' '
# 0g — unified log, if logd has anything for it (may print nothing; do not treat empty as proof)
log show --last 5m --predicate 'process == "mediaserverd"' 2>&1 | tail -40
# 0h — launchd alone, same shape, so the freeze test has a baseline to compare against
ps -Ao pid,%cpu,time,comm | grep launchd
```

Freeze test (step 1) and the disable (step 4) are in §Plan; both are 2 commands and reverse with
one. **I ran none of these.**

## What to measure before/after

| metric | how | what "fixed" looks like |
|---|---|---|
| mediaserverd CPU | `ps -o %cpu,time` series, Δtime/Δt | 46.2 % → 0; process gone after disable |
| launchd CPU | same series | 77.7 % → the freeze test says whether it moves at all |
| spawn rate | `grep -c '^exec '` in the next ring ÷ sampled window (sample0→sample7 = 840 s, §6) | 844/h baseline; expect no change from a mediaserverd disable |
| load average | `uptime` | 2.10/2.19/1.41 baseline (`h1-disable-before.txt:2`) |
| client damage | one GUI action per service after the disable: lock/unlock, a key click (no audio expected anyway), open Photos (assetimagegenerator lives here) | no hang; errors only |
| thermal side-effect | `sysctl` tsens readings that lane E uses | unchanged, or the point is moot |

## Open questions

1. **Which thread?** Unanswerable offline; one sample (§Plan step 3) names it. Everything in §5 and
   the H1/H2 split rests on that.
2. **Is 46 % one thread or several?** `ps -M -p` answers it without a reboot — if it is 4 threads at
   11 %, the story changes (IO fan-out), not just the culprit.
3. **Why does an uncaught exception escape a dispatch block in two daemons?** Shares a cause with
   lane H's crash work; the frame set in §4 is slide-independent, so it is worth one symbolication
   pass with the cache `.symbols`.
4. **Was the 46 % reading taken with the same kernel as the rings we have?** The file records no
   version (`h1-disable-before.txt` has only a time); inferred 0125/0126.
5. **Does the GUI survive a mediaserverd disable?** Predicted yes (no audio hardware, fast lookup
   failure), but no one has tried it; the freeze test in §Plan step 1 is the cheap falsifier.

## Scratch

`~/.hermes/cache/scratch/lane-4/` — both DMGs mounted read-only (`mnt/os`, `mnt/sysos`), `macho.py`
/ `syms.py` (Mach-O + symbol readers), `text.asm` (mediaserverd disassembly, 17 660 lines),
`hits` logic inline. DMG versions: OS `087-86698-044.dmg` (mediaserverd, plists),
SystemOS `087-86593-047.dmg` (dyld shared cache, uuid `8f970452c9e33e88b114feb1864bc9e0`). Neither
DMG content nor any Apple binary is copied into the repo.
