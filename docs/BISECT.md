# BISECT: the early-boot crash (shim dies before its first line of C)

Scope: `avicii/shim` only. No flashing, no `adb`, no `fastboot` here — every image below
is built, `mkbootimg_v1.sh --verify`-PASSed (except the 1u control, see §5) and
sha256-recorded on the host, and the parent flashes. Written 2026-11-12 after the bisect result that a `for(;;) wfe` diag body
**still** dies before it parks.

Trust the bisect result: the fault is upstream of `diag.c`. The panel has never shown a
character and no ring line has ever appeared, so neither the console nor `dlog_init` can
be used as evidence yet — and both are kept *out* of rungs 1-4 so they cannot be the
thing that kills a rung.

## 0. How to read a rung

* **Pass** = the phone stays off USB for a full **90 s** after the boot. A parked core
  never re-enumerates; a bare +90 s with no USB device is the only positive signal
  available before the panel is proven.
* **Fail** = ABL is back in fastboot **within ~10 s**. Record the measured seconds and
  whether the screen changed at all; both go in the report.
* A fail is information, not a setback. **Stop at the first failing rung** — every later
  rung re-tests the same broken layer plus more, which only blurs it.
* Order is fixed: **1u, 1**, 1b, **p1, p2, p3**, 2, 3, 4, 5. `boot_a` only; `boot_b`
  untouched. The `p` rungs come third because the device evidence (§1) says the packaging
  is the first thing to settle; the code-layer rungs (2-5) are pointless until an image
  parks at all.
* 1u is rung 1 with the AVB footer cut off and is the only rung whose `--verify` FAILs
  on purpose. 1u then 1 is one variable: the footer.
* Every fail is reported with the sha256 of the exact image that failed (`out-diag/SHA256SUMS.bisect`)
  and the seconds to fastboot. A rebuild does not reproduce a sha256, so name the file.

## 1. Facts the search is restricted to

| fact | source |
|---|---|
| a diag body of nothing but `for(;;) wfe` still dies ~6 s in, before the park | bisect result (trusted) |
| **the death is a constant ~6 s whatever the image does** — even a body that deliberately self-resets after a 30 s counter spin dies at 6 s, i.e. the CPU never reaches the code and the 6 s is a host-side refusal/timeout, not a shim crash | `PROGRESS.txt:36-43` |
| an **untouched stock `boot.img` boots** (18 s to the ABL's next stage), while the **same stock kernel re-packed by our packer does not** → the slot, the partition, the flash path and the ABL hand-off all work; what differs is *our packaging* | `PROGRESS.txt:46-58` |
| header v1 vs v2 and the cmdline change nothing on our images; an AVB footer alone is not sufficient | `PROGRESS.txt:48-50` |
| the stock boot image carries an **unsigned AVB hash footer** (`AVBf`, algorithm NONE) and `mkbootimg_v1.sh` now pads to the 96 MiB partition and appends one; until 2026-11-12 20:40 it did not, so **every image that has crashed so far had no footer** | `avicii/tools/mkbootimg_v1.sh` (`add_hash_footer --algorithm NONE`), `out-diag/bisect-1u` vs `bisect-1` |
| the AVB footer is big-endian (`original_image_size` = BE u64 at footer offset 12); the `--verify` code reads that field little-endian and so always compares a huge number (harmless, but say `'>Q'` if that check is ever tightened) | observed footer bytes of any built image |
| no console text ever, no ring line ever → console and UFS log are unproven | every image so far |
| load geometry: base 0, `kernel_addr` `0x8000`, `page_size` 4096, header v1, kernel section = gzip + board DTB | `docs/SHIM_BOOT.md`, re-parsed by `mkbootimg_v1.sh --verify` (`kernel load addr: 0x8000`) |
| image is linked at vaddr 0 with an ARM64 Image header stub, `text_offset` 0, flags 0xa (LE, 4K, place-anywhere) | `start.S`, `shim.ld` |
| the ABL of this family loads where it likes and **varies per boot** (0xA0080000 / 0xA00B0000 on a sibling lito unit) | `docs/anonbeat1-NOTES.md:44,51` |
| board DTB totalsize **337,226 B**, `tags_addr` **0x100** → a merged FDT written there reaches 0x5260a, i.e. 0x4a60a bytes past the entry at 0x8000 | `docs/DIAG.md:79`, header |
| `start.S` and `shim.ld` are **byte-identical** to both reference ports (sweet and the completed fajita port) | `diff` against `refs/` |
| watchdog bark is 15 s on this unit (`qcom,bark-time` = 0x3a98), so ~6 s is *faster* than any watchdog | `src/avicii-board.dtb`, `fragment@80` |

The last two matter: the entry code is not novel, and the death is quicker than a
watchdog, so it is an immediate trap/handoff failure, not a slow timeout.

## 2. Ranked hypotheses, with the code evidence for each

Ranked by how well they explain "nothing printed, nothing logged, dead in 6 s, at the
very first instructions, regardless of body". The device evidence in §1 forces the order:
because an image that *is* executed (the stock one) boots and our packaging of the same
stock kernel does not, the whole "packaging and hand-off" class sits above every
image-internal layer. Each hypothesis names the rung that kills it.

**H0a — our packaging is refused before any of our code runs, and the AVB footer is the
known instance of that.** ABL validates
boot images by the AVB footer at the end of the partition; `fastboot` accepts a footer-less
image happily, and then the bootloader declines to run it. Every crashing image so far
was built before the footer was added to the packer, i.e. it was ~350 KB in a 96 MiB
partition with nothing at the tail. This explains all four observations exactly: nothing
prints, nothing logs, the failure is body-independent, and it is quicker than any
watchdog. Rung **1u** (rung 1 with the footer cut off) is the deliberate reproduction and
**N1** (identical code, footer present) the single-variable swap. Note the parent's
result that a footer alone is *not* sufficient (`PROGRESS.txt:50`) — H0a is a necessary
piece, not the whole answer, which is exactly why 1u/1 are run before anything else.

**H0b — the gzip carriage.** Our kernel section is a gzip member; the stock section is a
raw `Image` and boots. If ABL hands the *compressed* bytes to the entry, the first
instruction is `0x1f 0x8b ...` and nothing ever prints. Rung **P1** (rung 1 with the
identical `Image`, raw instead of gzipped, DTB tail kept).

**H0c — the v1 carriage itself: `tags_addr` 0x100 and the appended DTB.** Stock is v2
with `dtb_size 0`; ours is v1 with a 337 KB tree appended to the kernel section.
Rung **P2** (v2, raw `Image`, no dtb section — the stock shape at shim size).

**H0d — the kernel section size.** The stock section is 43,876,368 B and the ABL may size
something (a gunzip buffer, a memcpy, a copy-to-fit) from `kernel_size`. Rung **P3** (P2
with the section zero-padded to exactly the stock length).

**H1 — the first instruction never runs: the handoff traps (EL, MMU state, entry
address, decompression).** Nothing exists to print with: a synchronous exception at
`_start` is taken before `vbar_el1` is written, so it vectors through whatever ABL left
there and the screen stays as ABL left it. Evidence: identical code is proven on
sweet/fajita; the death is uniform and body-independent; 6 s < the 15 s bark, so the
reboot is ABL/fastboot coming back, not a watchdog. Rungs **N1** (only `b` + `wfe`) and
**N1b** decide it — if N1 dies, no shim code is involved at all.
Sub-cases worth naming when reading a fail: entry at EL2 (then `msr vbar_el1`,
`msr sctlr_el1` are inert and the MMU never comes on), the kernel section not being
decompressed (the stock section is a **raw** `Image`, see `docs/SHIM_BOOT.md`), or the
entry address not being 0x8000.

**H2 — the appended DTB lands on the image head.** `tags_addr` is 0x100 and the board
tree is 337 KB, so anything ABL writes at `tags_addr` covers 0x100..0x5260a and
overwrites the first 0x4a60a bytes of the image, entry included. Evidence: the numbers
above; the stock kernel is 43 MB and raw, so an overlap of its first 300 KB would be
just as fatal there — i.e. this hypothesis predicts the whole v1 `Image.gz-dtb` shape is
wrong for this ABL. Rungs **N1 vs N1b** separate "a tail at 0x100" from "a 337 KB tail"
with byte-identical code (N1b's tail is a 64 KiB prefix with a patched totalsize).

**H3 — the section is not gunzipped (or gunzipped to the wrong length).** `--verify`
proves the stream is a valid single-member gzip with an FDT right after it, but nothing
proves avicii's ABL gunzips a v1 section at all. Evidence: the stock image needs no
gunzip (raw `Image`), so this path has never been exercised on this device. N1 catches it
(a 128-byte image executing gzip bytes traps at once). The clean control is **P1**, the
same `Image` delivered raw; H0b is its packaging-side twin and P1 serves both.

**H4 — the prologue itself: stack or BSS clear over live code.** `_stack_top` is
`_bss_end + 0x8000` and the clear runs 0x7d10..0x3d000 (**176,880 B** of 8-byte stores)
before any C; a wrong `_stack_top`/`_bss_*` would destroy the image or the stack while
executing from it. Evidence: `shim.ld` is byte-identical to the working ports, so this is
a low-probability but cheap-to-test layer. Killed by **N2**.

**H5 — MMU table content.** 16K granule, TCR `T0SZ`=28 (36-bit VA, walk starts at level
2, 2048 x 32 MB blocks = 64 GB), MAIR `0x44ff00`, `tlbi vmalle1` before `SCTLR.M`,
`ic iallu` before the enable, L3 only over the image, everything else Device with
PXN|UXN. A wrong block size vs granularity, or a table/L3 placement that lands off the
16K grid, turns the first fetch after `SCTLR.M` into a prefetch abort at an address whose
vector is also unmapped → recursive abort with no output. Killed by **N3** (identity map,
no fb).

**H6 — the splash mapping / `con_clear`.** FB block mapped `NC` (`0x44`, outer
shareable, PXN|UXN) at block `0xa0000000` — the number comes from the live FDT and is
re-derived by rung 3, and the write covers 2400 x 4800 = 11,520,000 B inside a 35 MiB
carve-out. Killed by **N4** (mapped only) and **N5** (paint).

**H7 — UFS / `dlog_init` before the console.** `ufs_takeover()` writes `UTRLRSR`, checks
`HCE`/`HCS`, then wipes 4 MiB of ring. It is the only writer in the ladder. Deliberately
absent from N1-N4; the `ro1`/`ro2` stage images (DIAG_LOG=0) exist for it.

## 3. Retarget audit: every avicii file against its sweet and fajita original

Nothing in the retarget broke the entry: `start.S` and `shim.ld` are byte-identical to
both references, and `mmu.c` is byte-identical to the anonbeat1/sweet copy apart from one
inlined line. The table lists every diff and its verdict; the retarget's real risk was
numeric substitution inside a mask, and the address-derived indices are the only numbers
that end up in a mask.

| file | diff vs original | verdict |
|---|---|---|
| `start.S` | none (both refs) | sound. Checked line by line: every address goes through `adr` (pc-relative, so position independent at any load address), `msr daifset,#0xf` first, `vbar_el1` before any C, BSS cleared before any C, stack 32 KB at `_bss_end+0x8000`, 8 x 4 KB secondary stacks adjacent above the main stack, no absolute value anywhere |
| `shim.ld` | none (both refs) | sound. `. = 0`; `.bss`/stacks sit inside the file because `build.sh` pads to `_end`; `_end` doubles as `image_size` |
| `mmu.c` | identical to sweet; fajita had the fb block derived into a local | **fixed**: the derivation was substituted away to `l2[FB_PHYS >> BLK_SHIFT] = (FB_PHYS & ~(BLK_SIZE-1)) ...`. Equivalent for an aligned FB_PHYS, and 0xa0000000 *is* 32 MB aligned, so no behaviour change — the explicit form is restored so the "FB_PHYS need not be aligned" invariant survives the next retarget |
| `mmu.h` | `FB_PHYS` 0x9c000000 (sweet) / 0x9d400000 (fajita) → **0xa0000000** | correct, dts-cited (`CONSTANTS.md:64`). The index the substitution feeds is `FB_PHYS >> 25` = **0x50**, and the built store is `str x14, [x9, #0x280]` = entry 80 x 8 B, so the new base did **not** land inside a mask or collide with the table slot — checked in the disassembly, not assumed |
| `console.h` | `FB_BASE` → 0xa0000000; `FB_H` 2340/2400 → 2400; `FB_STRIDE` `(FB_W*4)` = 4320 → **4800** | frame 2400 x 4800 = 11,520,000 B **< 0x2300000** carve-out, and every row write (`1080*4` = 4320 B) stays inside the 4800 stride — verified by arithmetic only, **not on hardware**. This is the one substantive retarget delta and it is unverified |
| `console.c` | freestanding `strcmp` added | sound (`ufs.c` needs the symbol when built with clang) |
| `shim.c` | strings; `IMEM_RESTART_REASON` 0x146aa65c (sweet) → **0x146ab65c** (lito msm-imem@146ab000+0x65c); diag hooks | consistent with `CONSTANTS.md`; not reached by any rung |
| `ufs.c`, `diag.c`, `diaglog.c`, `fdt.c`, `loader.c` | not retargeted from the refs by substitution | out of scope for rungs 1-5 |

Table/table-count invariants re-checked because they scale with the addresses:
`pt_pool` is 4 x 2048 entries (1 L2 + 2 L3 + one page of slack) and the guard
`(img_hi-1)>>25 - img_lo>>25 > 1` still returns -1 rather than overrunning for anything
wider than two blocks. A 315 KB image needs one block.

## 4. What was changed, and what is verified

1. **Load base is published.** `start.S` stores the runtime address of `_head` into
   `kimg_base`; the panic screen prints `BASE` and the diag banner prints `load base=`.
   Why: this ABL family loads where it likes and varies per boot, the header asks for
   0x8000, and nothing checked it — a crash report without that number is blind.
   **Verified** in QEMU: `kimg_base` read back as the actual load address 0x40200000.
   Unverified on the device (the value has never been read there).
2. **`mmu.c` symbol→address path audited and left as `(uintptr_t)sym`.** The audit
   conclusion, which cost a QEMU round trip to establish: `(uintptr_t)sym` is *already*
   the runtime address, because clang emits `adrp`/`adr` (both pc-relative) and
   `build.sh` refuses ABS64 relocations in C objects. Verified: with the untouched
   expression the built map used `img_lo == 0x40200000` (the real load address) in QEMU.
   An intermediate `kimg_base + sym` version doubled it to 0x80400000 and faulted
   296,317 times — recorded here so nobody re-introduces it.
3. **`#ifndef BISECT_NO_FB`** around the splash block, so rung 3 can be built without it.
4. **`#ifdef PARK_AFTER_ENTRY`** in `start.S`, so rung 2 parks instead of entering C.
5. **`bisect.sh` + `bisect/{n1.S,n1.ld,stubs.S,park.c,dbg.c}`** and the series below.
6. `docs/BISECT.md` (this file).

Rebuild side effect: because `shim.c`/`diag.c` changed, the diag ladder was rebuilt and
its hashes moved. Current ones are in `out-diag/SHA256SUMS`; `docs/DIAG.md`'s printed
table is stale by that rebuild.

## 5. The series

All rungs build clean and every rung **except 1u** passes `mkbootimg_v1.sh --verify`
(1u is the footer-less control and fails exactly that one check on purpose). All ten
were executed to a park at EL1 under QEMU before handover (§7). Everything lands in
`out-diag/bisect-N/shim-boot.img`, hashes in `out-diag/SHA256SUMS.bisect`;
`./bisect.sh` rebuilds the series, `./bisect.sh -s "1 2"` a subset.

Parking images are padded to the 96 MiB partition and carry the AVB footer, so each file
is 96 MiB (1u excepted) — that is expected, not a mistake. `avbtool` salts the vbmeta it
hashes, so **a rebuild does not reproduce a sha256**: the value below names this exact
artifact only.

| rung | isolates | file | size | sha256 |
|---|---|---|---|---|
| **1u** | **control**: N1 with the AVB footer truncated back off — the shape of every previously crashing image. `--verify` FAILs on the footer by design | `bisect-1u/shim-boot.img` | 348160 | `67dc5468a9d9c74291fd1dc71ae29589238b53c4683b8f161205062f3a5816d7` |
| **N1** | same code as 1u + footer + partition padding: header, `b`, `wfe`. MMU off, no stack, no vectors, no BSS, no C | `bisect-1/shim-boot.img` | 100663296 | `b7cf2d250d49808115767982c530172b3175c562e6b5055dd8372d930fe89fda` |
| **N1b** | N1 with a 64 KiB DTB tail instead of 337 KB — same image, only the append differs | `bisect-1b/shim-boot.img` | 100663296 | `6f5c690228db2fbaade52ab5b91f3de40f2433182af3b31d08544c240779368b` |
| **P1** | N1's exact `Image` (sha256 `cc83c139…`) delivered **raw** instead of gzipped, DTB tail kept, header v1 | `bisect-p1/shim-boot.img` | 100663296 | `857b589aca59aa4329002cd6aafe58444fccb93c81036631aabd5601d7f79aad` |
| **P2** | P1 without the DTB tail and as **header v2** — the stock shape (raw `Image`, `dtb_size` 0) at shim size | `bisect-p2/shim-boot.img` | 100663296 | `6821c6e49f2f5e963be3c00eb159ed6a62126ffdb1379744ca796bb46e85c884` |
| **P3** | P2 with the kernel section zero-padded to the stock 43,876,368 B | `bisect-p3/shim-boot.img` | 100663296 | `02cf807c5e395dc0486beda8a13f680853c258135dfcacfdee414915c54a5ed0` |
| **N2** | N1 + the real prologue: vectors, `vbar_el1`, BSS clear, stack — parks before C | `bisect-2/shim-boot.img` | 100663296 | `b49a27d5baf63655115c36999b5bf30476962623cffadcbea9f2ce2ab2ed8b78` |
| **N3** | N2 + MMU on, identity map over the image only, no fb block, no console | `bisect-3/shim-boot.img` | 100663296 | `e0b0e04b78d81f7f9235783ce82aafeee7a943c8441fcdc6ef91c5d5cfe1a580` |
| **N4** | N3 + the splash block mapped NC (never touched), no console | `bisect-4/shim-boot.img` | 100663296 | `c420b4c205fb36d733fabac17c82d939db6ec4666a0e2924b85bf36c5efa27b4` |
| **N5** | N4 + `con_clear(MAGENTA)` over the whole panel, then park | `bisect-5/shim-boot.img` | 100663296 | `4ff2973623fb15b77fd3d8db160687977a3a980bcbac0c778e236bffbb9ff5f9` |

P1-P3 carry the **same `Image` bytes as N1** (`cc83c139046157da3051d2463bf48ff5dbb0b08c2363f307d744211f52903a37`)
and differ only in the container, so a pass/fail difference between them is packaging and
nothing else. P2 and P3 print a `WARN` for header v2 — expected, they are the stock shape.

Every rung is expected to **park** (pass = off USB ≥ 90 s), including 1u. Screen
expectations are *not* pass criteria for N1-N4 — the panel is what N5 alone tests.

| rung | pass | fail signature | if it fails: the next image |
|---|---|---|---|
| 1u | parks, screen unchanged — and reproduces the historical crash | back in fastboot ≤ 10 s, i.e. the pre-20:40 behaviour | **N1**, same code, footer restored. 1u dies and N1 passes → the missing AVB footer was the whole fault (H0a): stop here and rebuild every candidate with `mkbootimg_v1.sh` as it is now. 1u **parks** → the footer was never the problem, continue to N1 |
| N1 | parks, screen unchanged | back in fastboot ≤ 10 s | **N1b**, byte-identical image, only the append changes (`bisect.sh`, `head -c 65536` → the full `$DTB`). N1b passes and N1 fails → the 337 KB tail at `tags_addr` is the killer (H2): next control is N1 with `text_offset` 0x80000 + `kernel_addr` 0 (`../tools/mkbootimg_v1.sh`), so the entry lands beyond the tags window |
| N1b | parks as N1 | as N1 | N1 and N1b both fail → the 337 KB tail is not the variable. Next image: **P1**, the same `Image` delivered raw — that separates "ABL does not gunzip" (H0b) from "the entry never runs" (H1) |
| P1 | parks | back in fastboot ≤ 10 s while N1 passed | the gzip carriage (H0b). Next image: **P2**, which drops gzip and the DTB and switches to v2 in one step; if P2 also fails, bisect gzip vs v2 by building P1 with `--hdr 2` (`bisect.sh`, the `--hdr 2` argument) |
| P2 | parks | back in fastboot ≤ 10 s while P1 passed | the v1/DTB carriage (H0c). Next image: **P3**, same shape with the stock kernel length — if P3 parks, the section size (H0d) is the lever and the packer must always pad to the stock length |
| P3 | parks | back in fastboot ≤ 10 s while P2 passed | the section size (H0d): pad to the stock length unconditionally in `build.sh`/`bisect.sh` (`STOCK_KERNEL_SIZE`) and re-run the ladder from 1u |
| N2 | parks, screen unchanged | back in fastboot ≤ 10 s while N1 passed | the prologue (H4). Next image: N2 with the BSS clear removed — delete the three lines `adr x1, _bss_start` / `adr x2, _bss_end` / the `1:`..`b 1b` loop in `start.S` |
| N3 | parks, screen unchanged | back in fastboot ≤ 10 s while N2 passed | the table content (H5). Next image: `#define DEV_FLAGS` in `mmu.c` without `D_PXN \| D_UXN` — if that parks, the block attributes, not the walk, were wrong |
| N4 | parks, screen unchanged | back in fastboot ≤ 10 s while N3 passed | the fb mapping (H6). Next image: the `l2[fb_block >> BLK_SHIFT]` line with `DEV_FLAGS` instead of `NC_FLAGS`, mapping the block but not as Normal non-cacheable |
| N5 | parks **and the panel turns magenta** | back in fastboot ≤ 10 s, or a park with no colour change, while N4 passed | the write pattern (H6). Next image: `con_clear` reduced to one row — `for (int y = 0; y < FB_H; y++)` → `y < 1` in `console.c` |

Reading the end state: 1u parks → a footer alone is not the fix (expected, the parent already
showed that) and the ladder proceeds on its own merits. A rung passes and the *next* one
dies → the layer between them is the fault and the table above names the single line to
change.

N1-N5 all pass and N5 paints → CPU, prologue, MMU and console are
all sound and the fault is in the layer the ladder skipped (UFS/`dlog_init`, then the
FDT walkers): go to `out-diag/ro1` (stage 1, DIAG_LOG=0, writes nothing) and only then
`stage-1`. N5 parks with no colour → the console path is the fault and the ring must
carry everything from there.

## 6. Reproduce

```sh
. tooling/env.sh
```

```sh
cd avicii/shim
```

```sh
DTB=/home/tadej/ios-nord/src/avicii-board.dtb ./bisect.sh
```

```sh
DTB=/home/tadej/ios-nord/src/avicii-board.dtb ./bisect.sh -s "1u 1"
```

Each rung prints `PASS` (1u prints its expected footer FAIL instead), writes
`out-diag/bisect-N/shim-boot.img` and appends its sha256 to
`out-diag/SHA256SUMS.bisect`. `bisect/` is only built by `bisect.sh`; the normal
`./build.sh` / `./build-diag.sh` are unaffected.

## 7. What the host-side execution proves, and what it does not

Each rung was run before handover: raw `Image`, `-M virt,virtualization=off` (without it
QEMU enters at EL2, `msr sctlr_el1` is inert and nothing is exercised), `-cpu cortex-a76`,
`-m 4G`, `-d int`, 5 s each.

```
qemu-system-aarch64 -M virt,virtualization=off -cpu cortex-a76 -m 4G -nographic \
    -kernel out-diag/bisect-N/Image -d int -D /tmp/e.log   # the raw Image, not the boot.img
```

Result: all seven rungs park at EL1 with **zero exceptions**, at a load address QEMU picks
itself (0x40200000) — i.e. at a base that is neither 0 nor 0x8000. An instrumented build
(`bisect/dbg.c`, same recipe) confirmed `img_lo` = 0x40200000, `SCTLR_EL1.M` set, one L3
table, and that `con_clear` really writes magenta (0xffff00ff at 0xa0000000 and
0xa0100000, 11 MB in) before parking. A deliberate read of unmapped 0x300000000 faults,
so the harness does surface aborts.

Proves: the header/`b` entry, the prologue, the identity map, the fb mapping and the
paint all execute without a trap at a foreign load base, at EL1, with the MMU off at
entry.
Does **not** prove: avicii's ABL behaviour, gunzip, the DSC command-mode panel actually
scanning out what we write, UFS at 0x1d84000, GIC, or any TZ/XPU restriction. QEMU virt
also returns 0 for unassigned Device reads, so `ufs_takeover()` does not fault there and
stage-1's ring result under QEMU means nothing.
