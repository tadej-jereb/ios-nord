# Image provenance log — avicii

One block per boot attempt, appended, never rewritten. The point is that after
three days of "which build was that" every image on the phone can be traced to a
commit, a cmdline and a result, and that slot a can be abandoned in one command.

Generate the hash block with `tooling/43-hash-images.sh <build-dir>`; paste its
output here and fill the blank rows by hand. Commit this file.

## Invariants

- `boot_b` holds the last known-good Android+Magisk boot and is never flashed
  during iOS work. Only the rollback procedure below writes it.
- `persist`, `modemst1`, `modemst2`, `fsg`, `fsc`, `xbl*`, `abl*`, `tz*` are
  never written by iOS work at all.
- Every flash names its slot. A bare `fastboot flash boot` targets the active
  slot, so `fastboot getvar current-slot` first, always.
- The iOS root lives in `userdata` and is the only thing expected to destroy
  data.

## Template — copy for every boot

```markdown
## boot NN — YYYY-MM-DD HH:MMZ

| field | value |
|---|---|
| slot | a |
| build dir | /home/tadej/ios-nord/…/out |
| kernel commit / CI run | `0123456789ab` / run 1234567890 |
| shim commit | `0123456789ab` |
| cmdline (exact) | `keepsyms=1 cpus=1 …` |
| vbmeta flags | 3 (hashtree off, verification off), from <package> |
| result | clean to SpringBoard / panic after 34 s `…` / black, no console / no USB |
| log | `logs/boot-NN.txt` (pulled via 42-log-pull.sh) |
| notes | |

| file | bytes | sha256 |
|---|---|---|
| shim-boot.img | 41943040 | … |
| boot_a.img | 100663296 | … |
| dtbo_a.img | 25165824 | … |
| vbmeta_a.img | 8192 | … |
```

Rules for filling it:

- `sha256` from `tooling/43-hash-images.sh`, not from memory. Hash the bytes that
  get flashed, not the archive they came out of.
- The cmdline is copied from the built boot image header
  (`unpack_bootimg --boot_img X --out . && cat ./boot_args`), not from the source
  file you meant to use.
- A boot with no log and no screen still gets a block: "black, no USB" is a
  result and it is the one that matters most.
- If the same image is flashed twice, the block is duplicated with the new
  timestamp — the counter, not the hash, distinguishes them.

## Restore rules for the step-3 backup

| partition(s) | restore onto this handset | restore onto another avicii |
|---|---|---|
| `persist`, `modemst1`, `modemst2`, `fsg`, `fsc` | yes, and it is the whole point of the backup | only if you accept the calibration of the donor, `fsc`/`modemst*` mismatch breaks IMEI/radio |
| `boot_a/b`, `dtbo_a/b`, `vbmeta_a/b`, `recovery_a/b` | yes, whole-partition, slot by slot | yes, they are ROM-side and signed-or-not as they came |
| `xbl*`, `abl*`, `tz*`, `hyp*`, `aop*`, `qupfw*`, `uefisecapp*`, `keymaster*` | yes — but a wrong one bricks boot before fastboot, so take the MSM route if two or more of these fail at once | only as a set with the matching firmware |
| `userdata`, `super` | recorded size only | not dumped; reformat instead |

Restore one image at a time and read fastboot's reply. `fastboot flash` to a
`by-name` partition is sparse-unaware; use the raw `.img`, and add `-S 512M` for
anything above roughly 100 MiB.

## Rollback to the fallback slot

Use when slot a will not boot, or boots but is useless (no USB, panic loop,
garbage on screen). Median time matters here — do it in this order, do not
improvise.

1. Power + Volume Down into fastboot (or `adb reboot bootloader` if adb still
   answers).
2. Confirm you are on the right phone and it is still the same handset:
   `fastboot getvar product` → `avicii`, `fastboot getvar serialno` → matches
   `backup/<serial>/VERIFIED`.
3. Look before you leap: `fastboot getvar current-slot` should say `a`. If it
   already says `b`, ABL has rolled back by itself and you only need step 5.
4. `fastboot --set-active=b`
5. `fastboot reboot`
6. Confirm the fallback: Android boots, `adb shell su -c id` returns uid 0,
   `adb shell getprop ro.boot.slot_suffix` returns `_b`. Only then pull the log
   of the failed boot (`42-log-pull.sh`) before touching slot a again.
7. If the phone will not reach fastboot at all, or fastboot flashes land but
   nothing boots: MSM DownloadTool with the OOS 12 package. That reflashes the
   protected set too and is the outer boundary of this procedure — the step-3
   backup is what you restore *after* it to get calibration back.
8. Only once a new shim build is staged: `fastboot --set-active=a`, flash
   `boot_a`, and log a new provenance block. Never re-flash `boot_b` to "try
   something"; if `boot_b` itself is suspect, the Magisk root procedure in
   `docs/RECOVERY.md` §5 is how it gets rebuilt.

Between steps 4 and 6 do not "clean up" slot a — while it is the suspect it is
the only copy of the evidence, and TWRP flashing there changes what you are
about to stare at.

If `userdata` was reformatted for the iOS root, the Android fallback boots to a
clean first-run wizard. That is expected, not a second failure: `fastboot -w`
(or TWRP's format data) before judging it.
