# Handoff — launchd spawns 68 jobs, 66 have no binary (QEMU)

For Hermes. Written 2026-11-14 by Claude Code. QEMU only; the phone is not touched in this task.
Read in this order: `AGENTS.md`, `docs/STATUS.md` (first entry), `docs/RAMDISK_ROOT.md` (the set
table and the divergence table), `docs/LAUNCHD_BOOTSTRAP.md` §5, then this.

**Run this with five parallel sub-agents.** `delegation.max_concurrent_children` is now `5` in
`~/.hermes/config.yaml` (was the default 3). Send all five lanes below in **one** `delegate_task`
batch so none of them is truncated. You stay the coordinator: you do not run QEMU or edit
tooling yourself, you hand out the lanes, merge their reports and write `docs/STATUS.md`.

## Where it stands

The jobs handoff is closed. `tooling/61-mkrd-root.sh` now stages launchd's job table and the
job plists:

* `System/Library/xpc/launchd.plist`, tweaked like the phone image (7 `_PanicOnCrash` ->
  `_PanicOnCrasX`, 2 CommCenter jobs removed, 528 jobs, 795 217 B);
* 491 `System/Library/LaunchDaemons/*.plist` + 1 `Library/LaunchDaemons/*.plist`, byte copies;
* empty `NanoLaunchDaemons`, `NanoLaunchDaemonsAltAccount`, `DeveloperModeLaunchDaemons`.

`build/rd-root.img` sha256 `0e247ac47216a7c21167e00d66ad388351676163aeecc3c2489c190e8aec725a`,
612 files, `34` absent 0 / mismatch 0, `fsck_hfs` clean.

Run `logs/qemu/20261114-094151` (`msgbuf.txt`, 300 s):

    [31.700] [Event: boot] Early boot complete. Continuing system boot.
    [31.977] tcp listen :::49152, :::62078, 0.0.0.0:62078   (launchd:1)
    [32.18 - 33.32] 68 x "exec xpcproxy"   pids 3-70
    [34.516] exec keybagd
    [34.548] exec usermanagerd
    [34.872] SWEET AKS: keybagd sel 0 arg0 0 in 0/0 out 0/0 -> 0x0
    ... nothing to 300 s, no panic

## One-line problem

launchd spawns `xpcproxy` for 68 jobs, but only `keybagd` and `usermanagerd` get as far as an
`exec` line. My reading, **not yet proven per job**: the other 66 Programs are not on this root,
which carries only the 21 boot-table binaries, and a failed exec in `xpcproxy` prints nothing to
the kernel log. Prove or disprove that, then put the first tier of daemons on the root.

## The five lanes

Each lane owns the files named in it and **nothing else**. Two lanes never write the same file.
If a lane needs a change in a file it does not own, it says so in its report instead of making it.

### Lane 1 — JOBMAP (offline, no QEMU, start immediately)

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

### Lane 2 — RDPROGS (build, depends on lane 1's list, start the plumbing now)

Put the tier-1 daemons on the RAMDisk root.

* Add `--programs FILE` to `tooling/61-mkrd-root.sh`: it stages every path in FILE from the OS
  DMG (Program files plus the bundle files lane 1 names), at mode 0755 for Mach-O and 0644
  otherwise, and fails on a path the DMG does not have. Sizing already follows `add_bytes`.
* Start with a seed list of `logd notifyd configd` until lane 1 delivers `tier1.txt`, then
  rebuild with the real one.
* Build to **its own** paths so lanes 4 and 5 can keep reading the baseline:
  `--out build/rd-root.progs.img --staging build/rd-root.progs.stage`.
* The image must stay QEMU-bootable at `QEMU_MEM=6G` (2.9 GiB today). If tier 1 pushes it past
  ~3.3 GiB, cut tier 1 rather than raising RAM, and say what you cut.
* Gates before handing the image over: `34` absent 0 / mismatch 0, `fsck_hfs` clean, the probe
  block passes, sha256 recorded in the report.
* **Owns:** `tooling/61-mkrd-root.sh`, `build/rd-root.progs.*`.
* **Report:** the diff, the sha256, size, and one boot (see "How to run") with lane 4's summary.

### Lane 3 — EXECLOG (make failed spawns visible)

Today a job whose Program is missing fails silently. Make the kernel say so.

* Find where an exec failure can be logged with the path and errno for every process, not only
  launchd: `exec_activate_image`/`__mac_execve`/`posix_spawn` return paths in the xnu tree. Check
  first whether an existing boot-arg already prints it (`debug=` bits, `launchd_log_serial`,
  `-v` paths). If one does, use it and skip the patch.
* Otherwise write `xnu-avicii/patches/0105-sweet-exec-fail-log.patch`: one `printf` (`SWEET
  EXEC: <path> failed errno N`) behind a boot-arg (`sweetexeclog=1`), default off. Add it to
  `xnu-avicii/series`. Dry-apply with the pre-flight in `docs/KERNEL_CI.md` and stop there:
  **do not dispatch the macOS workflow** until you, the coordinator, have read the patch. Then
  dispatch once.
* **Owns:** `xnu-avicii/patches/0105-*`, `xnu-avicii/series`, the kernel artifact it produces.
* **Report:** the patch or the existing flag, the CI run id, the kernel sha256.

### Lane 4 — HARNESS (test infrastructure, start immediately)

Make each run judge itself, and make parallel runs safe.

* New `tooling/62-msgbuf-summary.sh RUN_DIR [BASELINE_DIR]`. It prints the last timestamp, the
  `Early boot complete` time, the count of `exec xpcproxy`, every other `exec <name>` with its
  time, `SWEET` lines after early boot, any panic string, and with a baseline a diff of exec
  names. Exit 0 if no panic. Baseline for this rung: `logs/qemu/20261114-094151`.
* Make two QEMU runs at once safe: always pass `--out logs/qemu/<stamp>-<lane>` (`60` mints the
  dir name from the second, so two runs started in the same second collide). Check `60` for any
  other shared path (payload, ADT, temp files under `avicii/shim/out/`) and give each run its
  own if one exists.
* Document the no-sudo memory scope in `docs/QEMU_AVICII.md` (see "How to run").
* **Owns:** `tooling/62-msgbuf-summary.sh` (new), `tooling/60-qemu-boot.sh`,
  `docs/QEMU_AVICII.md`.
* **Report:** the script, its output on `20261114-092833` and `20261114-094151`, and the
  parallel-run fix.

### Lane 5 — GATE (read-only analysis, no phone)

`docs/IMAGE_PROVENANCE.md` "Gate: write the 16 GiB root over userdata" requires that **the same
root has booted in QEMU**. `build/ios16-root.img` is 16 GiB; QEMU guest DRAM here is ~3.7 GiB, so
it cannot be an `md0` ramdisk. Work out what can satisfy the gate, and present the options.
**Do not choose one yourself.**

* Options to weigh, with evidence: a QEMU block device the kernel can root on (does the `sweet`
  config carry any virtio/AHCI/NVMe storage driver?); a RAMDisk built from the *same files* as
  `ios16-root.img` minus the bulk (a provable subset); or rewording the gate.
* Diff the RAMDisk set against `ios16-root.img` for the paths launchd touches up to now: the
  launchd table (byte-equal after the tweak?), the 492 plists, `/private/etc`, the root links,
  owners (`0:80` cache on the phone vs `0:0` here). Open the image **read-only** only
  (`fstool` read path or `apfs-fuse`-style read-only mount, never `rw`), and sha256 it before
  and after: it must stay `8654ec2b…70a0`.
* **Owns:** nothing in the tree. The report is the output.
* **Report:** the options, each with what it proves and what it costs; the diff.

## Order and merge

1. Send lanes 1, 2, 3, 4 and 5 in one batch.
2. Lane 2 rebuilds as soon as lane 1's `tier1.txt` lands, and boots with lane 4's `--out` rule.
3. If lane 3 delivers a kernel, lane 2's image is booted a second time on that kernel with
   `sweetexeclog=1`. That boot is what proves or disproves "missing Programs".
4. You write the new `docs/STATUS.md` entry from the reports: what was staged, the sha256s, the
   run dirs, the first line after `34.87 s`, and which kernel produced it.

Success for this rung: a message after `34.87 s` that names a daemon from tier 1 (an `exec`
line, a crash or a panic that names it), **or** proof from the exec log that the silent jobs
fail for a reason other than a missing binary. Silence with tier 1 staged is a separate
finding: report it with the kernel and the image that produced it.

## How to run (memory scope, no sudo needed)

A 3 GiB payload plus guest RAM is OOM-killed around 4.1 GiB anon in the tool session's cgroup.
A **user** scope works, needs no sudo, and leaves the artifacts owned by `tadej`:

    systemd-run --user --scope -p MemoryMax=12G -q -- /bin/sh -c 'cd /home/tadej/ios-nord && DISPLAY= QEMU_MEM=6G ./tooling/60-qemu-boot.sh --ramdisk build/rd-root.progs.img --out logs/qemu/<stamp>-<lane> --cmdline "rd=md0 sweettouch=0 sweetkeys=0 sweetfb_console=1 sweetecon=1 keepsyms=1 launchd_log_serial=1 launchd_disable_all_timeouts=1 -v debug=0x144 cpu-factor=10" --secs 300'
    ./tooling/62-msgbuf-summary.sh logs/qemu/<stamp>-<lane> logs/qemu/20261114-094151

Budget: the host has 62 GiB, ~50 free. **At most three QEMU runs at once** (12 GiB cap each).
Lanes 1, 3 and 5 do not boot. `61` takes ~15 s with a warm page cache and ~4 min cold. Read
`msgbuf.txt`, never `screen.txt` (blank in this layout).

## Do not

* Do not touch the phone, `boot_a`/`boot_b`, `persist`, `modemst1/2`, `fsg`, `xbl`, `abl`, `tz`,
  the GPT, or write `build/ios16-root.img` (sha256 `8654ec2b…70a0`, read-only use only).
* Do not run the `userdata` `dd`. The gate is the user's decision, not a lane's.
* Do not undo the `fakeroot` create, the `0:0` cache, the `/etc` `/var` `/tmp` links, the
  cryptex roots, the tweaked `launchd.plist`, `lp-sip0=0x6f`/`lp-sip1=1`, AMFI or `0104`.
* Do not overwrite `build/rd-root.img` or `build/rd-root.stage`: they are the baseline.
* Do not dispatch the macOS kernel workflow before the coordinator has read the patch.
* Do not run QEMU outside a memory scope. Do not commit `build/*`, `logs/*`.

## Working tree

Uncommitted, from Claude Code's session today: the `61` job-table step, the `docs/STATUS.md`
and `docs/RAMDISK_ROOT.md` updates, and a docs cleanup (closed `HANDOFF-*.md` files,
`docs/CLEANUP.md`, `docs/STAGED.md`, `docs/POPULATE-ROUTE-RUST.md` removed; references in
`README.md`, `AGENTS.md`, `docs/IMAGE_PROVENANCE.md`, `docs/POPULATE-ROUTE-FUSE.md` and
`avicii/tools/loader_opts.py` repointed). Commit that as one change before the lanes start, so
each lane's diff stands on its own.
