# Perf lane H — userland daemons: what still spins, crashes or wakes the CPU

Read `perf-shared.md` first. **Owns:** `docs/perf-research/H-daemons.md`.

**Question:** iOS starts dozens of launchd jobs built for an iPhone X with hardware we do not
have. Some crash-loop (bluetoothd and fairplayd.H2 did ~386 times/hour before they were disabled;
vmd was disabled earlier) and burn CPU and battery. Find the rest, cheaply, from evidence we
already have.

Determine:
1. From `logs/phone/live-*.txt` and other captured logs: every process that is spawned repeatedly
   (count `exec`/exit lines per name per hour), every `exec DumpPanic`/crash line, and processes
   with high CPU in the thread dumps (`bbd-threads-*`, any `ps` captures). Rank by cost.
2. For each offender: its launchd plist (from the OS DMG `build/ipsw-x/087-86698-044.dmg`, mounted
   read-only with `tooling/opt/apfs-fuse` as `tooling/61-mkrd-root.sh` does), why it fails
   (missing hardware, entitlement, service it waits on — from our logs, not guesses), what depends
   on it, and whether disabling is safe for SpringBoard, touch, USB networking and SSH.
3. The exact disable commands (`launchctl disable system/<label>` + `bootout`) for the main agent
   to run — **do not run them yourself; you have no phone access.**
4. Anything polling: timers, `notifyd` storms, log spam (`SWEET AKS: SpringBoard sel 17` repeats in
   the logs — what keybag call is SpringBoard retrying and would answering it stop the loop?).
5. Expected gain per item (measured from the logs where possible).
