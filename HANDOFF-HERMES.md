# Handoff for Hermes — test the dtb-section fix, then climb the diag ladder

Written 2026-11-12 by Claude Code in answer to `HANDOFF-CLAUDE.md`. You are the
orchestrator: you own the phone and the sub-agents. Read §1–§3, then start §4 and §5 at
the same time.

## 1. Finding (answers `HANDOFF-CLAUDE.md` §5)

The compiled shim is not what ABL refuses. The refused images carry the wrong DTB in the
boot image's dtb section.

| dtb section | images | recorded outcome |
|---|---|---|
| 406620 B, sha256 `48b0902a…` (stock's) | `h1`, `S6`, stock control | park / boot |
| 337226 B, sha256 `8d3818a2…` (`src/avicii-board.dtb`) | `off3`, `psm`, `s0`, `n2`, `n2c`, `v2s1` | refused ~6 s |
| none (header v1, or `dtb_size 0`) | every earlier build | refused ~6 s |

- VERIFIED (`dtc -I dtb -O dts src/avicii-board.dtb | grep -c fragment@` = 620):
  `src/avicii-board.dtb` is the **overlay** from `dtbo.img`. It has no `qcom,msm-id`.
- VERIFIED (`fdtget -t x avicii/shim/hybrid/sections/dtb-stock / qcom,msm-id` =
  `190 10000 1b8 10000`): stock's section is the **SoC base tree**, zero fragments.
- VERIFIED: `avicii/tools/mkbootimg_v1.sh:195` defaults `DTB_FILE` to the overlay, so
  every `build.sh` image got it. `hybrid/mk.sh` and `avicii/build/mk.sh` use stock's.
- VERIFIED: `S6` already contains compiled shim code behind its park and it parks.
- HYPOTHESIS: ABL finds no `qcom,msm-id` match in an overlay-only section and returns
  to fastboot before jumping. Not yet tested on hardware — that is T1/T2 below.
- CORRECTION: `h4` has no `.result` file. Only `h1` and `S6` have recorded parks.

## 2. Images already built (do not rebuild)

Both are the compiled shim, `off3` layout (code0 `b +0x80000`, `text_offset 0x80000`),
full `_start` prologue, then `wfe; b .` before `shim_main` (`-DPARK_AFTER_ENTRY`).
Their kernel sections are byte-identical (`cmp` = 0 differences). The dtb section is the
only variable. Both `--verify` PASS.

| id | image | dtb section | sha256 | expected |
|---|---|---|---|---|
| T1 | `avicii/shim/out-diag/dtbfix-park/shim-boot.img` | stock base | `69cdca532998f06f965855fd6a84018a2e12a6f88ee7d1476923f32cb121f6dc` | PARK |
| T2 | `avicii/shim/out-diag/dtbfix-neg/shim-boot.img` | overlay | `2b1a18098230734f4065513811bdb6aeed9eb820107f09a1458559dc5e09327e` | REFUSED ~6 s |

Restore image: `backup/64f70df8/boot_b.img`,
sha256 `39ed8eeaf9053a9a53028b3b2ba03f45ab288df38e8f9430ca0a6fda545b1ef0`.

## 3. Agent plan — one device lane, everything else in parallel

The phone is a single serial resource. Exactly **one** agent touches USB; a second
agent issuing `adb`/`fastboot` corrupts the timing and can flash over a parked run.
Every other agent is host-only and starts immediately, without waiting for T1.

| agent | starts | touches device | job | deliverable |
|---|---|---|---|---|
| **Flasher** | t=0 | YES, sole owner | run §4 queue in order, one image at a time | one result line per image (§6) |
| **Packer** | t=0 | no | §5.1 packer fix + verify gate | patch, `--verify` proof on T1/T2 |
| **Ladder** | t=0 | no | §5.2 build rungs with the stock dtb | images + sha256 list handed to Flasher |
| **Contingency** | t=0 | no | §5.3 prepare the T1-refused branch | 3 images, ready but not queued |
| **Scribe** | on first result | no | §5.4 docs | commits to `PROGRESS.txt`, `docs/` |

Rules that keep it cheap:

- Spawn all four host agents in one message. Give each only its own section of this
  file plus §1, §2, §7. Do not paste the long docs; give paths.
- Agents return a result table and file paths, never file dumps or disassembly.
- No agent re-tests anything listed in `HANDOFF-CLAUDE.md` §3 or re-derives §1.
- The Flasher never builds. Builders never flash. The Flasher takes images only from a
  list with a sha256 per line and re-hashes before flashing.
- Cancel **Contingency** the moment T1 parks. Cancel **Ladder** the moment T1 is
  refused. Do not let a dead branch keep spending.
- One flash per question. Do not repeat a run unless its result contradicts §2.

## 4. Flasher queue (device lane)

Gate before every flash: `sha256sum` of the image equals the listed value, and the
device answers `fastboot devices`.

T1 — the decisive run:

```
1. cd /home/tadej/ios-nord
2. source tooling/env.sh
3. sha256sum avicii/shim/out-diag/dtbfix-park/shim-boot.img
4. adb kill-server
5. tooling/50-boot-timing.sh --image avicii/shim/out-diag/dtbfix-park/shim-boot.img --runs 1
```

T1 has no self-reset. After a park, hold **Power 30 s**, then enter fastboot.

Restore, after every run, always:

```
6. fastboot flash boot_b backup/64f70df8/boot_b.img
7. fastboot reboot
8. adb kill-server
9. adb wait-for-device
```

If ABL flipped the slot: `fastboot --set-active=b` before step 7.

T2 — the negative control, only if T1 parked (it turns a correlation into a
one-variable proof; skip it if T1 was refused):

```
10. sha256sum avicii/shim/out-diag/dtbfix-neg/shim-boot.img
11. adb kill-server
12. tooling/50-boot-timing.sh --image avicii/shim/out-diag/dtbfix-neg/shim-boot.img --runs 1
13. fastboot flash boot_b backup/64f70df8/boot_b.img
14. fastboot reboot
```

Decision:

| T1 | T2 | meaning | next |
|---|---|---|---|
| PARK | REFUSED | dtb section was the gate, proven | flash the Ladder list, lowest rung first |
| PARK | PARK | first run of the pair lied; repeat T1 once | then decide |
| REFUSED | — | dtb theory dead, prologue suspect | flash the Contingency list (§5.3) |

Ladder runs (after T1 PARK + T2 REFUSED): flash in the order Ladder hands over. Stop at
the first rung that does not park and report it; do not skip ahead. After each rung with
`DIAG_LOG=1`, restore, boot LineageOS, then `tooling/42-log-pull.sh` and attach the ring.

## 5. Host-side work (all parallel, no device)

### 5.1 Packer

- Extract stock's dtb section to `src/avicii-soc.dtb` from `src/los21-boot.img`
  (406620 B, must hash to `48b0902a99c10a11ff52680bf81e9fec2574ad687c58ea35a00fdbf7aefe40ce`).
- Change the `DTB_FILE` default at `avicii/tools/mkbootimg_v1.sh:195` to it.
- Make `--verify` FAIL when the dtb section has no `qcom,msm-id` or contains
  `__overlay__`. Proof required: T1 image PASS, T2 image FAIL.
- Fix the same default in `avicii/shim/build-diag.sh` only for the section; the
  `DTB=` variable in `build.sh` is the gzip-appended copy and is unused by the v2 path.
- Do not touch `shim/*.c`, `start.S`, `shim.ld`.

### 5.2 Ladder

Build with `DTB_FILE=/home/tadej/ios-nord/avicii/shim/hybrid/sections/dtb-stock` until
5.1 lands. Order, one variable per step:

| rung | build | why |
|---|---|---|
| L0 | `DIAG_STAGE=0 DIAG_LOG=0`, park planted at top of `shim_main` (the `psm` shape) | first C frame, stack and bss proven |
| L1 | `DIAG_STAGE=1 DIAG_LOG=0` (`ro1` shape) | rung 1, writes nothing |
| L2 | `DIAG_STAGE=1 DIAG_LOG=1` (`v2s1` shape) | first UFS ring write |
| L3 | `DIAG_STAGE=2 DIAG_LOG=1` | next rung |

Each: `avicii/tools/mkbootimg_v1.sh --verify` PASS, dtb section sha `48b0902a…`,
`sha256sum` recorded. Hand the Flasher a four-line list, nothing else. `park()` in
`diag.c` self-resets after 60 s, so L1+ need no power button; L0 does if its park is a
bare `wfe; b .`.

### 5.3 Contingency (only used if T1 is refused)

All with the stock dtb section, park as the last instruction before the point named:

| id | change vs T1 | names |
|---|---|---|
| C1 | park as the first instruction of `_start` at `0x80000` | entry reached at all |
| C2 | park after `mov sp, x1`, `msr spsel, #1` removed | `spsel` |
| C3 | park after `msr vbar_el1` + `isb`, before the bss loop | bss clear / image extent |

Build and verify all three now; queue none unless T1 is refused.

### 5.4 Scribe

After each Flasher result: one row in `docs/HYBRID.md`, the sha256 + outcome in
`docs/IMAGE_PROVENANCE.md`, a dated entry in `PROGRESS.txt`. On T1 PARK + T2 REFUSED also
correct `docs/SHIM_BOOT.md:168`, `docs/STAGED.md:17` and `docs/STATUS.md:66`:
`avicii-board.dtb` is the dtbo overlay and must never be the boot image's dtb section.
Record `h4` as untested. Commit docs only; never commit under `refs/`.

## 6. Result line format (Flasher → orchestrator)

```
<id> <sha256[:16]> <PARK|REFUSED|BOOT> first-USB=<ms or none/90s> kind=<fastboot|adb|none> restore=<ok|FAIL>
```

PARK = no USB for 90 s. REFUSED = fastboot within ~10 s. BOOT = adb present.
`restore=FAIL` stops the whole queue until a human looks.

## 7. Hard rules (unchanged)

- Flash `boot_b` only. Never `boot_a`, never unslotted `boot`, never `fastboot boot`.
- Never write `persist`, `modemst1/2`, `fsg`, `xbl`, `abl`, `tz`, or the GPT.
- `adb kill-server` before every reboot check.
- Restore `backup/64f70df8/boot_b.img` after every run, pass or fail.
- Mark every claim VERIFIED (with the command) or HYPOTHESIS. Do not soften a failure.
