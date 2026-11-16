# Shared brief for all five lanes — read me first, then your lane file

Repo: `/home/tadej/ios-nord`. You are one of five parallel sub-agents on one task, coordinated by
Hermes. Read in this order: `AGENTS.md`, `docs/STATUS.md` (first entry), `docs/RAMDISK_ROOT.md`
(the set table and the divergence table), `docs/LAUNCHD_BOOTSTRAP.md` §5, then
`HANDOFF-HERMES-DAEMONS.md`. Your lane's section of that handoff is reproduced word for word in
your own lane file in this directory.

Rules that hold for every lane:

* You own the files named in your lane section and **nothing else**. Two lanes never write the
  same file. If you need a change in a file you do not own, say so in your report instead of
  making it.
* Do not `git commit`, `git add`, `git checkout`, `git stash` or switch branches. Leave your
  changes in the working tree; the coordinator commits. Do not touch `.hermes-lanes/`.
* Do not read or write anything under `build/` or `logs/` except as your lane says, and never
  modify `build/ios16-root.img`, `build/rd-root.img`, `build/rd-root.stage`.
* The reports are the deliverable. Be concrete: exact paths, byte counts, sha256, run dirs,
  command lines, and the log lines you are quoting. If you are blocked, say so and say why —
  a smaller honest result beats a padded one.
* Do not invent output. Every number in your report must come from a command you actually ran.

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
