# Lane 1 — JOBMAP (offline, no QEMU, start immediately)

Find out which 68 jobs launchd spawned, and what each one needs.

* Read `build/rd-root.stage/System/Library/xpc/launchd.plist` and the LaunchDaemons plists
  (`plistlib`, `python3 -I`). List the jobs that start at boot without a client: `RunAtLoad`,
  `KeepAlive` true or with conditions satisfied at boot, `LaunchEvents` that fire at boot.
  Check that the count comes out at, or explains, 68.
* For each job: label, Program (or `ProgramArguments[0]`), whether it is in the stage,
  `UserName`, `MachServices`, and whether it is `_PanicOnCrasX`.
* For every Program that is missing, list what it loads that is **not** in the dyld cache:
  `LC_LOAD_DYLINKER`, non-cache `LC_LOAD_DYLIB`s, the enclosing bundle's `Info.plist` and
  resources. Use the OS DMG through `tooling/opt/apfs-fuse` (read-only), as `61` does.
* `.jobs-raw.json` (repo root, untracked, 13 Nov) is an earlier dump of the same data. Regenerate
  it, don't trust it.
* **Owns:** `avicii/rd-root/jobs-boot.tsv` (new), `avicii/rd-root/tier1.txt` (new).
  `tier1.txt` is one absolute path per line, the input for lane 2. Put first the daemons
  everything else waits on: `logd`, `notifyd`, `configd`, `UserEventAgent`, `securityd`,
  `lockdownd`, `mDNSResponder`, `syslogd`/`diagnosticd`. Keep the list ordered and give the bytes
  it adds.
* **Report:** the job table, how the 68 were counted, `tier1.txt` with its byte total.
