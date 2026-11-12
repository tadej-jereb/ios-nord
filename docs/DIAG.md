# DIAG: the first images that are safe to run on avicii

A five-rung ladder. Each rung announces itself **once on the panel and once in
the UFS ring before it touches the block it probes**, so a hang, a watchdog
reset or a panic names its own last step: on the panel while the phone is up
(`D1`..`D5` + text), and in `userdata` afterwards.

Rungs 1 and 2 only read controller registers. Rung 3 only writes inside
`cont_splash_region`. Rung 4 brings secondary cores up and lets them go again.
Rung 5 compares the live `/memory` node against the table
`avicii/tools/mkdiag_memtab.py` generates out of `avicii/tools/mkadt_avicii.py`
and prints every mismatch instead of panicking.

Nothing here flashes, formats, or regenerates a partition. `boot_a` is the
experiment slot, `boot_b` keeps bootable LineageOS + Magisk and stays untouched.
Read `docs/SHIM_BOOT.md` first; the header rules there are what the images obey.
The rung order is the ladder `docs/fajita-PORTING.md` worked out on the 6T port
of this same tree - GIC, then UFS, then the panel, then cores, then memory - so
the walls are hit in the order that already has answers.

## 0. Claim status

| claim | status |
|---|---|
| all seven images build and pass `mkbootimg_v1.sh --verify` | **verified** (see §2 output, `out-diag/SHA256SUMS`) |
| GICD 0x17a00000, PIDR2 0xfe8, TYPER 0x004 as read by rung 1 | verified: `avicii/CONSTANTS.md:49` (base from `lito.dtsi:599,605`), PIDs at Arm's GICD offsets; expected TYPER shape from a sibling lito unit, `docs/anonbeat1-NOTES.md:1054` (`0x007B041D`, 30 groups) |
| UFSHCI 0x1d84000 / PHY PCS 0x1d87008 as read by rung 2 | registers from JESD223 + dts node `ufshc@1d84000`; **PCS offset 0x08 is UNVERIFIED** for lito's PHY |
| `cont_splash_region` = 0xa0000000 + 0x2300000, framebuffer 1080x2400x4 inside it, row = 1080*4 B, unpadded | region **verified** from the live DTB (`10-fdt.dtb`, decoded with `dtc`), re-checked by rung 3 at boot; geometry is the panel's own `qcom,mdss-dsi-panel-width` 0x438 x 0x960 in that tree - no node states a stride, and nothing pads an ABL row |
| FDT `/memory` decoding of the ladder's walker | **verified** on the live DTB: 3 extents, 0x80000000+0x3bb00000, 0xc0000000+0xc0000000, 0x180000000+0x100000000 |
| expected stage-5 result on this unit = exactly 1 mismatch (mkadt fallback window) | **verified** by replaying the checks on the dumped values; see §6 |
| `fastboot boot` works on avicii | **UNVERIFIED on this unit** (claimed by twrp.me/PitchBlack threads) - §3 covers the fallback |
| ring survives a warm reset | UNVERIFIED; each line is written with WRITE(10) + SYNCHRONIZE CACHE, which is the strongest thing a non-mounted writer can do |

## 1. Build

From the repository root, with the toolchain sourced.

```sh
. tooling/env.sh
```

```sh
cd avicii/shim
```

```sh
./build-diag.sh
```

Back to the repository root, everything below is root-relative:

```sh
cd ../..
```

That builds rungs 1..5 plus the two write-nothing variants `ro1`/`ro2`
(`DIAG_LOG=0`), verifies every one of them, and writes `out-diag/SHA256SUMS`.
Stage 1 and 2 are "read-only probes" - but the ring writes 4 MiB of `userdata`
tail, so **if you want literally zero writes today, use `ro1`/`ro2`** and accept
panel-only output.

One rung at a time, if you prefer:

```sh
DIAG_STAGE=1 ./build-diag.sh -s 1
```

`DIAG_STAGE` is 1..5, `MAX` (default) = 5, `0` = the old milestone shim. The
value is compiled in, so a stage-3 image contains rungs 1, 2 and 3 and cannot be
talked into rung 4.

Stages **6, 7 and 8** are a different kind of build and live in
`docs/TELEMETRY.md`: the cheap side effects (IMEM record, TLMM/SPMI, haptic) are
laid down *before* the ring and the console, because neither of those has ever
produced a byte. A stage-6 image therefore writes the IMEM record first and only
then enters the code below. While the question is still "does anything execute",
use `docs/TELEMETRY.md` and `docs/TIMING.md` rather than rungs 1-5.

## 2. Verify (gate: do not boot an image that has not printed this)

```sh
avicii/tools/mkbootimg_v1.sh --verify avicii/shim/out-diag/stage-1/shim-boot.img
```

The last line must read `PASS: header v1, stock avicii geometry, gzip+DTB kernel`
and `board dtb : totalsize 337226`. Record the sha256 in
`docs/IMAGE_PROVENANCE.md` before the flash in §3.

```sh
cd avicii/shim/out-diag && sha256sum -c SHA256SUMS
```

## 3. Boot rung 1

```sh
fastboot devices
```

```sh
fastboot getvar current-slot
```

Expect `_b`. If it says `_a`, LineageOS is on the other slot - still fine, but
swap the words `boot_a`/`boot_b` in §7.

```sh
fastboot boot avicii/shim/out-diag/ro1/shim-boot.img
```

`fastboot boot` downloads the image into RAM and jumps to it. Nothing on the
phone changes, no slot changes, and a power cycle returns to LineageOS.
**This is the normal path for every rung.**

If the ABL refuses `boot` (`FAILED (remote: unknown command)` or a silent
reboot back to Android), use the flash path - one rung, on `boot_a` only:

```sh
fastboot flash boot_a avicii/shim/out-diag/ro1/shim-boot.img
```

```sh
fastboot reboot
```

`flash boot_a` does **not** change the active slot. ABL still boots `boot_b`
until the slot flips, so a plain reboot after flashing runs the old kernel -
that is why the ladder is built around `fastboot boot`, and why a flash needs
either the slot switch in §7 or `fastboot boot` from `boot_a` afterwards:

```sh
fastboot boot avicii/shim/out-diag/ro1/shim-boot.img
```

Never `fastboot flash boot` (unslotted) on this unit: it defaults to the active
slot, which is the fallback.

## 4. What each rung must print

Format: `D<rung> <text>`. The `begin` line is the marker; everything after it is
result. A hang **between two lines** names the rung and step above it.

### Panel console (every rung)

- Geometry: 1080x2400 `a8r8g8b8` at `0xa0000000`, one row is exactly `FB_W * 4` = 4320 B, glyphs 8x16 at 3x from `24,24` (`avicii/shim/console.h:7`).
- Garbled blobs that still sit in the right order and colour are a stride fault, not a font or bpp one: check `FB_STRIDE` against the panel width first.

### Rung 1 - GIC read-only

Good:

```
SHIM avicii DIAG stage 1 of 5
LOG on: last 1024 blocks of userdata
D1 gic probe read-only begin
D1 read gicd_pidr2
D1 pidr2=0x0000000000000033
D1 typer=0x00000000007b041d
D1 gicv3 ok, arch nibble 3
D1 itlines sane for an SoC
```

`pidr2` low nibble is the product id (3 = Arm GIC), arch nibble (`>>4 & 15`)
must be 3 = GICv3. `typer` bits [4:0] are `ITLinesNumber`; the rung prints it as
`groups` and the derived `max_intid`. A sibling lito unit answers
`typer=0x007b041d` (29 -> 30 groups, 960 INTIDs), so good is roughly 8..31
groups.

Bad, and what it means:

| print | meaning |
|---|---|
| `pidr2=0x0000000000000000` | GICD not answering: wrong base, or the block is unclocked/gated |
| `pidr2=0x00000000ffffffff` | same, bus returning all-ones: no device at 0x17a00000 |
| `not gicv3: arch nibble 3` missing, chip replies with nibble 2 | GICv2 view - the DT would be wrong, XNU's gicv3 driver would not attach |
| `groups=32` | ITLinesNumber all-ones: plausible-looking all-ones answer, treat as suspicious |

### Rung 2 - UFS registers read-only

Good: `version` in `0x00010000..0x0003ffff` (UFSHCI 1.x..3.x), `cap` with the
DP (device present) bit set, `pcs` neither 0 nor all-ones, and `phy pcs not
stuck`.

Bad: `version=0x00000000` or `0xffffffff` (host not enabled - ABL left it off,
or the base is wrong), `hcs DP clear` (host up but sees no device), `hci version
implausible`. Any of these with rung 1 good points at the UFS block, not at the
interconnect. UFSHCI puts **CAP at 0x00 and VER at 0x08** (the reverse of what
looks natural) and VER packs major in [15:8], so `0x300` is HCI 3.0, not an
implausible `0x300`. `pcs=0` at `0x1d87008` is *not* a PHY fault when `DP` is
set - the rung scans PHY offsets `0x0/0x8/0x160/0x16c/0x1c0/0x1d4` and a live
PHY answers on `0x160`/`0x16c`.

### Rung 3 - splash buffer

Prints first, paints second, so the marker line is already in the ring:

```
D3 splash fill magenta begin
D3 splash base=0x00000000a0000000
D3 splash size=0x0000000002300000
D3 region matches, painting pattern MAGENTA
D3 painted, ms=...
D3 no MDP/DSI writes: ABL scan-out still showing
```

Good: the whole screen turns magenta with the text on it. The lines printed
before the fill (`begin`, `base`, `size`, `region matches`) are erased by it -
that is the point of the rung - so on screen you will only see the two lines
after it; the ring keeps all of them:

```
D3 painted, ms=...
D3 no MDP/DSI writes: ABL scan-out still showing
D4 psci cpu_on 0x100-0x700 begin
...
```

`ms` is the fill time (roughly 100-400 ms; a hang inside the fill leaves the
marker in the ring and a half-painted screen).

Bad: `no cont_splash_region in live fdt` or `region != 0xa0000000/0x2300000, no
paint` - the live tree disagrees with the dump, the rung refuses to paint and
keeps the ABL splash intact. Rung 3 arms no MDP/DSI: the command-mode panel
keeps being scanned out by ABL, which is why the fill is visible at all.

### Rung 4 - PSCI CPU_ON

One line per attempted core, then a mask:

```
D4 mpidr=0x00000100 ret=0x0000000000000000
...
D4 released=7 ackmask=0x000000fe
D4 spin 1=... 2=... 3=... 4=...
D4 all 7 secondaries acked
```

Good: `ret=0` for all seven, `ackmask=0x000000fe`, non-zero spin counts from
every core.

Bad and the PSCI code that produced it:

| ret | meaning |
|---|---|
| `0xffffffffffffffff` | NOT_SUPPORTED: TZ does not expose CPU_ON |
| `0xfffffffffffffffe` | INVALID_PARAMETERS: entry point/context rejected |
| `0xfffffffffffffffd` | DENIED: core is held by another security state |
| `0xfffffffffffffffc` | ALREADY_ON |
| `0xfffffffffffffffb` | ON_PENDING (stuck) |

An `ackmask` below `0xfe` with `ret=0` means the core was released but never
reached our entry (stack, vector or CPU bring-up problem, not PSCI).

### Rung 5 - memory map self-check

```
D5 mem base=0x0000000080000000
D5 mem size=0x000000003bb00000
...
D5 RESULT mismatch=00
```

Good on this unit: three extents exactly as dumped, `dram reaches above 4 GiB`,
`splash carve inside dram, expected`, and a final `RESULT mismatch=00`.

That `00` is newer than the doc's first draft: the earlier expectation of
`mismatch=01` came from `mkadt_avicii.py`'s fallback window `0xb0000000 +
0x4d000000` spanning the `0xbbb00000..0xc0000000` hole. The tabled window now
sits entirely inside the map (third extent `0xc0000000 + 0xc0000000`, total
`0x1fbb00000`), so the check is clean and a non-zero mismatch is again a real
finding. Anything
else - an extent below `0x80000000`, an extent under `MIN_MEM_SIZE`, an overlap
with the GIC or UFS carve-out, or `no /memory in x0` - is a genuine finding and
the log keeps it.

## 5. Reading the log back

Only if you built without `DIAG_LOG=0`. The ring is the last 1024 blocks of
`userdata` behind a `SWEETLOG` header, which is exactly what
`tooling/42-log-pull.sh` decodes. Pulling needs root, so boot TWRP:

```sh
fastboot boot src/twrp_v2.img
```

```sh
sh tooling/42-log-pull.sh -o logs/diag-01.txt
```

```sh
tr -d '\000' < logs/diag-01.txt
```

Every line carries `[ms] <kind> <rung> <text>`, kinds `B` (marker), `K` (ok),
`X` (bad), `-` (note). The NUL padding `tr` strips comes from the zeroed ring
ahead of a short log; the newest lines are always last.

A ring write makes LineageOS drop into **recovery** afterwards, not Android, and
recovery adbd is already root but has no `su` binary - so `42-log-pull.sh`'s
root check fails there. Pull by hand instead (read-only, same offsets):

```sh
adb exec-out "dd if=/dev/block/sda16 bs=4096 skip=$(( $(adb shell blockdev --getsize64 /dev/block/sda16)/4096 - 1025 )) count=1025 2>/dev/null" > logs/ring.bin
```

`skip=0,count=0` after the 4096-byte header is the log; cut at the first NUL.

Costs: writing the ring overwrites 4 MiB at the end of `userdata`. LineageOS may
report `/data` corruption afterwards. Recovery is in §8.

## 6. Building and booting a rung

```sh
(cd avicii/shim && DIAG_STAGE=3 ./build-diag.sh -s 3)
```

```sh
avicii/tools/mkbootimg_v1.sh --verify avicii/shim/out-diag/stage-3/shim-boot.img
```

```sh
fastboot boot avicii/shim/out-diag/stage-3/shim-boot.img
```

Same for 4 and 5. Each carries every rung below it, so only ever go forward one
number at a time and read the whole screen before the next.

## 7. Going back to Android

Nothing was flashed: hold power ~10 s, or

```sh
fastboot reboot
```

The phone boots LineageOS from `boot_b` on its own. If you took the flash path
in §3, `boot_a` now holds a diag image - still irrelevant to a plain reboot
because the slot is `_b`; restore the slot to stock-photo state whenever you
want with

```sh
fastboot flash boot_a src/los21-boot.img
```

Only if you deliberately switched slots (`fastboot --set-active=a`) do you have
to switch back:

```sh
fastboot --set-active=b
```

## 8. If the tail of userdata got clobbered by the ring

Symptom: LineageOS boots and `/data` needs repair. In TWRP:

```sh
adb shell fsck.f2fs -f /dev/block/bootdevice/by-name/userdata
```

An encrypted `/data` that still refuses is recoverable only by formatting -
`userdata` is the throwaway partition by design (the iOS root will live there).
`persist`, `modemst1/2`, `fsg`, `xbl`, `abl`, `tz` are never touched by any of
this.

## 9. Files

| path | what |
|---|---|
| `avicii/shim/diag.c` | the five rungs, `DIAG_STAGE`/`DIAG_LOG` gated |
| `avicii/shim/diaglog.c` | the UFS ring: `SWEETLOG` header + text, one WRITE(10)+SYNC per line |
| `avicii/shim/memtab.h` | generated by `avicii/tools/mkdiag_memtab.py` from `mkadt_avicii.py` |
| `avicii/shim/build-diag.sh` | builds + verifies the whole ladder, records sha256 |
| `avicii/shim/out-diag/SHA256SUMS` | what was actually built |
