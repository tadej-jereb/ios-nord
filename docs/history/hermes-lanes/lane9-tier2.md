# Lane 9 — TIER2 (QEMU, bigger guest RAM): turn the 64 ENOENT names into executed daemons

Repo: /home/tadej/ios-nord. Read `.hermes-lanes/shared.md` first (rules, How to run, Do not), then
the QEMU results in `docs/STATUS.md` (first entry) and `avicii/rd-root/jobs-boot.tsv`.

## Why this lane exists

We now have the exact list of what launchd cannot start: 64 `SWEET EXEC: <path> failed errno 2`
lines from `logs/qemu/20261114-103445-kern0105/msgbuf.txt`, i.e. the Programs the tier-1 ramdisk
does not carry. The ramdisk budget was the blocker (3.10 GiB of a ~3.3 GiB DRAM window), not the
kernel. QEMU can be given more DRAM than the phone, so it can run ahead of the handset and tell us
which wall comes next — the boot jobs (`mount-phase-1/2`, `keybagd`, `fips`, `fsck`, `tzinit`,
`data-protection`, `recovery-mode` are all `RequireSuccess`), `devfs`, or something new.

## What to do

1. **Raise the guest.** Confirm `QEMU_MEM=8G` actually yields a bigger dram window: build one probe
   payload and read the ADT / `result.json` (`dram base … size …`). Report the measured dram bytes.
   If 8G does not fit the 12 GB scope budget, use 7G. Do not exceed one QEMU run at a time.
2. **Build a tier-2 root** to its own paths — `build/rd-root.tier2.img` / `build/rd-root.tier2.stage`
   — from `61-mkrd-root.sh --programs <file>`, where the file is: every one of the 64 ENOENT paths
   from that msgbuf, plus the Programs that are on-demand and whose absence can hang a Mach lookup
   (`notifyd`, `securityd`, `mDNSResponder`, `diagnosticd` are already in), plus, for each Program
   that lives inside a framework/bundle, the bundle's `Info.plist` (lane 1's `jobs-boot.tsv` names
   which 26). Skip `syslogd`/`sntpd`/`dhcp6d` binaries being pointless is NOT true — stage them
   anyway, they are small; they simply may not run (`Disabled:true`).
3. **Sizing:** keep the image under the measured dram window minus 0.6 GiB. If it does not fit, cut
   in this order and say what you cut: `SpringBoard` and other UI apps first, then
   `CoreTelephony/CommCenter`, then the AppleInternal paths. Do not cut a daemon that has no
   substitute.
4. **Boot it once** with the 0105 kernel (`avicii/shim/out/kernel/kernel.development.sweet`, sha256
   `534248682bbc5cbb29e38033be872b3edfbbb84d45476f6cb12ad8e31779cf1e`) and the usual cmdline plus
   `sweetexeclog=1`, `--secs 300`, `--out logs/qemu/<stamp>-lane9`, inside
   `systemd-run --user --scope -p MemoryMax=12G`.
5. **Judge it** with `tooling/62-msgbuf-summary.sh <run> logs/qemu/20261114-094151` and answer:
   which new Programs exec (name + time), whether `SWEET EXEC` lines drop (and to what), whether
   any boot job reports, and where it stops now. Quote the last 5 lines verbatim.

## Hard limits

- You own `build/rd-root.tier2.img`, `build/rd-root.tier2.stage`, `avicii/rd-root/tier2.txt`, and
  `logs/qemu/<stamp>-lane9`. **Do not** modify `build/rd-root.progs.*` (lane 2 is rebasing it),
  `build/rd-root.cachetrial.*` (lane 8), `build/rd-root.img`, `build/rd-root.stage`,
  `build/ios16-root.img`, `build/phone/*`, or any `tooling/*` script. No phone, no fastboot/adb, no
  `dd`, no git commit, no `.hermes-lanes/`.
- One boot. If the image is wrong, fix and boot once more — at most two QEMU runs total, and never
  more than three QEMU processes on the host at once.

## Report

Measured dram; image path/size/sha256 and what you staged or cut; the gate output; the run dir; the
new execs and the remaining `SWEET EXEC` list; the stop line; and one sentence on what the next wall
is. Real output only.
