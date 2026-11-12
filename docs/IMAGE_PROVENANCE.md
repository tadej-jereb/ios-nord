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

## dtb-section fix: the park and everything behind it

The dtb section carried `src/avicii-board.dtb` (the dtbo *overlay*, 620 fragments, no
`qcom,msm-id`) instead of the SoC base tree, which is the plausible cause of the ~6 s
refusal of every earlier image. `mkbootimg_v1.sh` now defaults to `src/avicii-soc.dtb`
(406620 B, `48b0902a...`, extracted from the dtb section of `src/los21-boot.img` at
`0x2bab000`) and `--verify` fails on a missing `qcom,msm-id` or any `__overlay__`.
`--verify` PASSes the park and FAILs the overlay control; both kept as the gate's own
regression pair.

T1 vs stock `los21-boot.img`: every header field identical (incl. `dtb_addr`, `tags_addr`,
`cmdline`, `os_version 0x1c000185`, `code0 b+0x2480000`) **except** `kernel_size` and
`ramdisk_size`. Not flashed at write time; path is `fastboot boot` (writes nothing), so
`boot_b` is the fallback by default and needs no restore.

| image | what | verify | sha256 |
|---|---|---|---|
| `out-diag/dtbfix-park` | T1: bare park at 0x80000, soc dtb | PASS | `69cdca532998f06f965855fd6a84018a2e12a6f88ee7d1476923f32cb121f6dc` |
| `out-diag/dtbfix-neg` | T2: overlay dtb control (must be refused) | FAIL by design | `2b1a18098230734f4065513811bdb6aeed9eb820107f09a1458559dc5e09327e` |
| `out-diag/l0` | park inside `shim_main` (no 60 s reset) | PASS | `6f7b1bc71e6c8184c4b63380fbc76463daddb3a2e79d05ec410b72a77ac4ad41` |
| `out-diag/l1` | stage 1, LOG=0 | PASS | `94cffac8f27e4a0459d2f74c63cb7eeb75d51bf01878b3550b0594f7e31c2bea` |
| `out-diag/l2` | stage 1, LOG=1 | PASS | `5866e9c7fc95eff3f3c64febaf056842e846c22def2715e065c30500530498e5` |
| `out-diag/l3` | stage 2, LOG=1 | PASS | `0bb629f9c953fd52443e109e5b35c5cd9bb47314ab9f04fa1d65cd260c84a4a4` |
| `out-diag/c1` | park as first insn of `_start` (`-DPARK_C1`) | PASS | `f76d4d96cba2c6c663d67ecbb52fd296bde5e135c70ddc88e06c62da5d97ca16` |
| `out-diag/c2` | park after `mov sp,x1`, sans `spsel` (`-DPARK_C2`) | PASS | `c83d9c3b7f7ea09784db6c93850d6a4a426e19a660ffaab64ec9b3e8a45e80f5` |
| `out-diag/c3` | park after `vbar_el1`+`isb` (`-DPARK_C3`) | PASS | `3a18f3370ea64c304c1c341f551e9cbd4f8ff8f43dfbefae8c94dd4d0d46d642` |

Every dtb section above re-hashed at its own header-derived offset:
`48b0902a99c10a11ff52680bf81e9fec2574ad687c58ea35a00fdbf7aefe40ce`, all of them.
Packed-image hashes are not run-reproducible (empty-cpio ramdisk mtime); the `Image`
bytes are.

Result: **T1 PASS (2026-11-12 22:13:13).** `fastboot boot` sent 98304 KB in 2.241 s, `Booting
OKAY` in 0.084 s, then ≥200 s of silence: screen kept the fastboot UI unre-drawn, no
re-enumeration on USB at all (`lsusb` has no 05c6/18d1 node, `fastboot devices` and
`adb devices` both empty at 22:16:44). A refusal would have re-entered fastboot and put
the 05c6 gadget back within ~6 s. ABL therefore decoded `code0`, honoured
`base+text_offset` and executed at least `wfe` at 0x80000 — the SoC-dtb section is
accepted. T1 never self-resets; left with Power+VolDown.

**L0 PASS (22:18:01).** Same signature: sent 98304 KB in 2.239 s, `Booting OKAY` 0.084 s,
60 s of silence with no USB at all (`fb=0 usb05c6=0 adb=0` at every poll to 22:19:04). The
park sits in `shim_main`, so `daifset`, `spsel`, `mov sp`, `vbar_el1`, `isb`, the bss clear
and the `bl shim_main` all completed. The entry prologue is not the problem and the C1/C2/C3
contingency is not needed yet. L0 does not self-reset (bare `wfe` in C, not `diag.park()`).

**L1 RAN (22:20:06)** — first rung that executes `diag_run`. Sent 98304 KB in 2.242 s. The
screen carried **multiple lines of white and yellow glyphs, unreadable** — the console draws,
the font table is fine, but the glyph raster does not land where it should. Values are
therefore only obtainable from the ring, not from the panel. Also: the 60 s `park()` expired
and the `smc` PSCI_SYSTEM_RESET did not reset (no re-enumeration at 105 s, 22:21:51); the
power button stays the way out of a `park()`. L2 (`DIAG_LOG=1`) is the rung that puts the
same lines in the userdata ring for `tooling/42-log-pull.sh`.

**Ring works, rung 1 and 2 green (22:29-22:44).** Four probe/infra bugs found by the
ladder and fixed, each proven by the next run: (a) `dlog_init` returned 5 on the header
read-back, which is a lie on this medium - Linux reads the same block fine - so the gate
became a warning (`dlog_warn()`, panel line `LOG warn rc=`); (b) `GICD_PIDR2` was 0xfe8,
a 4 KiB-frame offset, while the GICD frame is 64 KiB and RAZ there - now 0xffe8;
(c) `HCI_VERSION`/`HCI_CAP` were swapped vs the UFSHCI layout (CAP 0x00, VER 0x08 - what
`ufs.c` uses) and the version test compared a major/minor-packed VER against 0x10000;
(d) the park deadline used `60 * freq` with `freq` in ticks/ms, so every "60 s" park
was 58 ms - now `60000 * freq`, measured 60 s. Also: `smc` PSCI reset never fires at
EL2, `hvc` does, so the reset is HVC-then-SMC and a parked image now recovers by itself.

| run | result |
|---|---|
| `l2` (stage 1, LOG=1, pre-fix) | header written, ring wiped, `total 0` - nothing logged |
| `l2b` | ring live, rc=5 reported, D1 pidr2=0 (offset bug), typer 0x7b041d |
| `l2c` | **D1 PASS**: pidr2=0x3b, arch nibble 3, gicv3 ok, itlines sane; HVC reset works |
| `l3b` (stage 2, pre-fix) | version/cap read from swapped offsets, park 58 ms |
| `l3c` | version=0x300, cap=0x1587031f, hcs DP set, park 60 s |
| `l3d` | **D2 PASS**: hci 3.0 plausible, DP set, PHY window answering (+0x160=0x80) |

Load base every run: `0xa7e80000` (ABL ignores the header's 0x8000, harmless - the code
is position independent). Console `FB_STRIDE` was 4800 B for a 1080-px row (4320 B), which
sheared every scanline 120 px right; fixed to `FB_W * 4`.

**Ladder walked 1-5 (22:45-23:03).** Ring reads only, `fastboot boot`, nothing flashed.

| rung | image | sha256 | result |
|---|---|---|---|
| 3 | `out-diag/l4`, `l7(ruler)` | `2821a59b…`, `991ba4ed…` | PASS: base 0xa0000000 size 0x2300000, `region matches`, painted 97 ms; ruler bars straight at `stride=0x10e0` - 4320 is the panel's real row pitch |
| 4 | `out-diag/l5` | `0fc147dd…` | FINDING: `CPU_ON` accepted for 0x100-0x700 (ret=0) but `ack mask=0`, each spin slot a different value - cores released, none acked |
| 5 | `out-diag/l6` | `0b305f26…` | PASS: three extents as tabled, `dram reaches above 4 GiB`, `RESULT mismatch=00` (docs' expected 01 is stale - the live map matches the generator now) |

Console: `FB_STRIDE` 4800 -> `FB_W*4` (4320) confirmed on hardware; glyphs resolve at 1:1 and
the ruler bars are straight. LineageOS drops to **recovery** (not Android) after a ring write,
which is where adb lands; recovery adbd is root but has no `su`, so ring pulls there go through
`adb exec-out dd` of `/dev/block/sda16` skip `size/4096-1025`, not `42-log-pull.sh`.
