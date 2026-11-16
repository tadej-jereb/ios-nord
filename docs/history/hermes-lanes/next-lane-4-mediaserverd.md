# Round 3, lane 4 — why mediaserverd (and launchd) burn CPU on an idle phone

Read `next-shared.md` first. **Owns:** `docs/perf-research/I-mediaserverd.md`.

**Observation (phone, 2026-11-15, kernel 0126, 5–7 min after boot, idle on the lock screen):**
`/sbin/launchd` 77–81 % CPU, `/usr/sbin/mediaserverd` 46–47 %, `logd` 2 %
(`logs/phone/h1-disable-before.txt`). `ReportCrash` and `assetsd` were then disabled (perf lane H,
change #1); `logs/phone/h1-disable-after.txt` has the numbers two minutes later. Lane H did not rank
mediaserverd. Find out what it is doing and the safest fix.

Determine:
1. **What mediaserverd waits on or retries:** from `logs/phone/live-*.txt` and other rings (its log
   lines, IOKit matching failures, `SWEET AKS`/IOKit user-client calls it makes, repeated
   `exec`/exit), and from its binary and plist on the OS DMG (which audio / camera / video services
   it opens: `AppleAudio*`, `IOAudio*`, `AppleH*VideoEncoder`, `AppleCamera*`, `AppleAVE`, …).
   Separate what it loops on from what it merely fails once.
2. **What depends on mediaserverd:** SpringBoard, backboardd (sounds, haptics), media playback,
   keyboard clicks — which would break or hang if it were disabled (from plists' `MachServices`
   and clients' imports; mark inferred where so).
3. **Options**, cheapest first, each with risk: disable (`launchctl disable system/<label>` — exact
   label from the plist), a launchd plist tweak (e.g. throttle interval), a kernel stub that makes the
   missing service exist and answer "no device" (which IOKit class/properties it matches), or a stub
   audio device.
4. **launchd's own CPU:** after the disable, is launchd still high? From the logs, which jobs it is
   still respawning (count execs per label per hour as lane H did), and which of those are safe to
   disable next.
5. The **read-only** commands the main agent should run on the phone to confirm (e.g.
   `ps -M -p <pid>`, `launchctl print system/<label>`, `log show --predicate ... --last 5m` if
   available, `sample`-like tools present under `/var/jb`). Do not run them yourself.

Report: the root cause (or the best-supported hypothesis, marked as such), the recommended change
with the exact commands, and what to measure before/after.
