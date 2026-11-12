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

## root image (userdata) — baseline before populate, 2026-11-12

Empty 16 GiB volume, fsck -n clean, HFSX, journaled. Recorded before
`tooling/33-populate-root.sh` writes anything; the script refuses to run
against an image that does not match this while no resume marker exists.

| file | bytes | sha256 |
|---|---|---|
| ios16-root.img | 17179869184 | 21e00f47267c0f986dae16f65971f426780cb2c4eb441fc43318546f3107b5c9 |

context: host build host, tooling/31-mkiosroot.sh, `fsck.hfsplus -N` dry-run and
`-n` clean, header 4858, 114 MiB on disk. Baseline copy:
`build/ios16-root.img.sha256.pre-populate`. The populate run appends its own
block with the post-fsck hash below this one.

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

## 2026-11-12 21:0x — telemetry set (DIAG_STAGE 6/7/8 + anchors), host-built

Not flashed at write time. All host-built from `avicii/shim` with
`DTB=src/avicii-board.dtb`, `--verify` PASS except `anchor-refuse` (on purpose).
Slot for all of them: **`boot_b`** (`boot_a` has no system metadata since the
LOS flash; `boot_b` is restored from `backup/64f70df8/boot_b.img`).

| image | stage | verify | sha256 |
|---|---|---|---|
| `out-telem/stage-6/shim-boot.img` | 6 | PASS | `8429032133608bf3a3740dd5ccb0d77ab2eda8a1723001cce2e67c75f554edca` |
| `out-telem/stage-6-ro/shim-boot.img` | 6, ring off | PASS | `f65665c69a986906f0d5e37b4e2abc7a8937c18b201db47c42c518061cdb773d` |
| `out-telem/stage-7/shim-boot.img` | 7 | PASS | `22165dc07adcd2b8a657e5a46988af7b93cd6f00f7f6d1cecc097437ad5b5cc8` |
| `out-telem/stage-8/shim-boot.img` | 8 | PASS | `b0dc568409bce492e418f535614d1860c53c0bd2f1819adf33d313cfff4f9af5` |
| `out-telem/anchor-park/shim-boot.img` | park before C | PASS | `b005174a5f0f6ff7068167365fe381a8fbacb1f454fb7891672e1eccb0818f35` |
| `out-telem/anchor-refuse/shim-boot.img` | broken gzip magic | FAIL (on purpose) | `e3a5372769c395870150ed9b9f11154506ab7c4570a90cc7bdb16660da814674` |

Image header: v1, `Image.gz-dtb`, os_version 12.0.0 / 2023-09 (stock tuple,
anti-rollback), unsigned AVB hash footer, padded to the 96 MiB partition.
Protocol: `docs/TELEMETRY.md` §5; timing: `docs/TIMING.md` §3.
Result: __________ (fill after the runs; the record is readable only after the
B2 normal boot, so paste `out-telem/timing/<stamp>/runs.tsv` and the
`51-imem-read.sh` transcript).

## 2026-11-12 late - H/F hybrid set (entry convention), host-built

Not flashed at write time. Hypothesis list, kill experiments, pass criterion and the
expected/observed table: `docs/HYBRID.md`. Slot: **`boot_b`**, restore
`backup/64f70df8/boot_b.img` between runs. All 100663296 B, `--verify` PASS (v2 WARN is
expected). Corrects two earlier notes: stock `os_version` is **14.0.0 / 2024-05**
(`0x1c000185`), not 12.0.0/2023-09, and stock's `code0` branches to **+0x2480000**, not
+0x92000 (`imm26` is a word count).

| image | verify | sha256 |
|---|---|---|
| `hybrid/out/h1.img` | PASS | `1dd159a985f44a9a46e7a0253757826d851b67e6838908f016d72fb40621b616` |
| `hybrid/out/h1x.img` | PASS | `cb6fadb8ee4fa07054a2715a42c77c1c567bed5fd8aa770e94cf1858209b6e31` |
| `hybrid/out/h2.img` | PASS | `3ae325aa9e76a3fe6e54e1e53c6ec683c23b2b14e7066bcbb7d7bfa6174222ef` |
| `hybrid/out/h3.img` | PASS | `594c6109764dd3d6803687689ea4fa2ca3e1485595cbeeaa07f380803f2ca9d5` |
| `hybrid/out/h4.img` | PASS | `597175f4f36b6ffe1bfab56bdbc154541043b822c91df5a4571b3a5c9c0167f5` |
| `hybrid/out/f1.img` | PASS | `ff8cf597d1ee222a9b3df13e8da6fd18f71327955e58bab541d7cb8b144a19c4` |
| `hybrid/out/f2.img` | PASS | `4a44c043deeaf9583fd6fabbbb9ac9896f0d26e518738a970126e7a95a1a4700` |
| `hybrid/out/f3.img` | PASS | `aaae3ba4e7fad78747e978012a63ac4387de45fc5e7108382d4fbb534bac5ba7` |

Result: __________ .
