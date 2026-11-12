# HYBRID — localising the entry-convention fault, starting from byte-identical agreement

Status: **host-built, not flashed.** 8 images, all `--verify` PASS, all exactly
100663296 B. Build: `bash avicii/shim/hybrid/mk.sh all` (self-asserting; refuses to emit an
image that is not the bytes its recipe names). Nothing here changes the container that is
already proven good.

## 0. What is already measured, and the arithmetic error that this series fixes

Verified by earlier runs (not repeated here):

- `src/los21-boot.img` (stock) is accepted and boots: 22 s to adb.
- The **same container**, same packer, same cmdline, same ramdisk, same os_version, same
  AVB footer, with **stock's kernel**, boots. Container and packing are exonerated.
- Our shim in that same container is refused at **~6070 ms**, consistently.
- Our shim reduced to `wfe; b .` at the entry, `_head` branching to it, still refuses. So it
  dies at or before the first instruction we place.

**The correction.** Stock's `code0` is `00 00 92 14` = `0x14920000`. The `imm26` field is a
count of **words**, not bytes: `imm26 = 0x920000`, displacement `= 0x920000 << 2 =
0x2480000`. Stock does not branch to `+0x92000`; it branches **36.5 MiB into a 41.85 MiB
kernel**. 0x2480000 / 0x92000 is exactly 4 — the ratio of the two readings.

Read with `text_offset 0x80000` (kernel_addr 0x8000 ⇒ load 0x88000), stock's landing is
`0x2508000` and its declared image ends at `0x343f000`, i.e. the park/destination is inside
the declared extent. Bytes at `0x2480000` are real code (`bl +0x20`, then a call); at
`0x2508000` there is a `b .-0x34` loop. The 4× error is also why the old "park at 0x800"
builds can be internally consistent and still never sit where stock lands: they are 0x2480000
away from the landing, not 0x800.

Consequence for this brief: a literal H1 that puts the park at `0x92000` cannot be reached by
stock's own branch. Both readings are therefore built — **H1** (park on stock's real landing)
first, **H1x** (the literal reading) as the arithmetic control.

Two more measured facts used below, both byte-level:

- Our `0..0x40` differs from stock in exactly **three** fields: `code0` (`b +0x800` vs
  `b +0x2480000`), `text_offset` (0 vs 0x80000), `image_size` (0x4d000 vs 0x33b7000).
  `magic` `ARMd`, `flags` 0x0a, `res5` and every reserved byte are already identical.
- Stock's `os_version` is `0x1c000185` = **14.0.0 / 2024-05**. `mkbootimg_v1.sh` and
  `docs/IMAGE_PROVENANCE.md` both call this "12.0.0 / 2023-09"; that decode is wrong and is
  corrected here. Every image in this series carries stock's exact four bytes; the wrapper's
  12.0.0 default is a floor, not the stock tuple.

## 1. Hypotheses (entry-convention class) and the one experiment that kills each

`H` = alive unless an already-measured test killed it. Each row names the single image whose
outcome decides it, and what the outcome has to be to kill it.

| # | hypothesis | kill experiment | killed if |
|---|---|---|---|
| **E1** | ABL does not enter at `Image+0` at all: it enters at `kernel_addr` (0x8000, i.e. the boot header's page) or at some other fixed address, so our first instruction is never reached while stock's happens to be harmless there | **H4** — park placed exactly at `base+text_offset` (0x80000), code0 branching there | H4 parks ⇒ entry is `base+text_offset`, E1 as stated dies |
| **E2** | ABL enters at the image base but at a *fixed near* offset (its own stub convention), and a branch is not followed that far | **H3** — same payload, park 0x92000 away with a truthful `image_size` | H3 parks ⇒ distance is followed |
| **E3** | `text_offset` is semantic: the loader adds it to `kernel_addr`, so `text_offset 0` relocates everything by 0x80000 into a region the ABL reserves or the DTB/tags collide with | **F1** — H1 with the single field `text_offset` set to 0, park unmoved (branch is PC-relative) | F1 parks ⇒ text_offset 0 is harmless |
| **E4** | The first page is sanity-checked against something: the branch must be a branch (`opcode == b`), `image_size >= header`, `image_size <= section`, magic at 0x38, or the caller compares the page against the stock stub | **H1** (whole page stock) then **H2** (our header, stock stub) then **F2**/**F3** (one field each) | H1 parks ⇒ nothing in page 0 is checked; H2 refused while H1 parks ⇒ the check is on our header fields, and F2/F3 name which |
| **E5** | `image_size` is an extent the loader trusts: it copies `image_size` bytes, so anything past `image_size` is absent in RAM even when `kernel_size` is larger (our 0x4d000 vs a body that is 0x92008 B) | **H3** — the pre-edit `image_size` (0x4d000) is smaller than the park offset, and H3 raises it to the real extent; if the reader instead honours the small one, this is killed by F2 alone | H3 parks ⇒ the declared extent is honoured and upwards-corrected |
| **E6** | Our stub bytes `0x40..0x1000` clobber something the ABL or its loader uses (its own scratch at the image base, a signature, a magic it writes) | **H1** / **H2** — stock stub bytes in that range | H1 or H2 parks ⇒ stub bytes are not the fault |
| **E7** | The 8-byte `wfe; b .` itself is the problem (e.g. entered at EL1 with an unmasked event; `wfe` with no `daifset` behaves differently than assumed) | **H3/H4/F*** — the same 8 bytes at a different offset; also compare a `b .`-only park | park succeeds at any single offset while failing at another ⇒ position, not bytes |
| **E8** | Weight/shape coupling: a small kernel (315 KiB vs 41.85 MiB) trips a size threshold in the ABL (`image_size`/`kernel_size` band, or minimum size) | **H1/H2** are 36.6 MiB, near stock; **H3/H4** are ~0.5 MiB | H1/H2 park while H3/H4 refuse ⇒ weight is load-bearing and a size floor exists |

E7 is deliberately not given its own image: every image differs from its neighbours only in
position, so E7 is decided by the *set* (a park anywhere with the same 8 bytes exonerates them).

## 2. The series, in flash order

All images keep, byte for byte: stock cmdline (235 B incl. NUL), stock ramdisk (1 900 641 B),
stock dtb section (406 620 B at `dtb_addr 0x1f00000`), header v2, page 4096, `kernel_addr`
0x8000, `ramdisk_addr 0x1000000`, `tags_addr 0x100`, `os_version 0x1c000185`, unsigned AVB
hash footer, 100663296 B. Kernel sections are page-padded with zeros; the compose step also
asserts the landing byte is the park and `code0` branches at it.

| img | kernel | differs from stock in | expected signature |
|---|---|---|---|
| **H1** | stock `0x0..0x1000` verbatim, zeros to `0x2480000`, `wfe; b .` there, end `0x2480008` | nothing in page 0; body zeros | **park** |
| **H1x** | same but park at `0x92000` | nothing in page 0 | refused, or `udf`-die; **never a park** |
| **H2** | our `0..0x40`, stock `0x40..0x800`, park at `0x800`, stock `0x808..0x1000`, park also at `0x2480000`, end `0x2480008` | page 0 `0..0x40` and `0x800..0x808` | park, or refused |
| **H3** | our image verbatim, zeros to `0x92000`, park, `code0 b +0x92000`, `text_offset 0x80000`, `image_size 0x93000` | `code0`, `text_offset`, `image_size` | park |
| **H4** | our image verbatim, zeros to `0x80000`, park, `code0 b +0x80000`, `text_offset 0x80000`, `image_size 0x81000` | `code0`, `text_offset`, `image_size` | park |

Single line that changes next if the image is refused — per image:

- **H1 refused** → page-0 identity is not sufficient. The fault is in the body/layout or in
  weight, not the entry bytes: run **H3**, then **H4** (small, far-entry), and read E8 the
  other way round.
- **H1x refused while H1 parks** → nothing new; H1x is the arithmetic control.
- **H2 refused while H1 parks** → the fault is inside our `0..0x40`. Go straight to **F1**.
- **H3 refused** → the far entry or `text_offset` handling is the variable: run **H4**, then
  **F1** with H4's shape.
- **H4 refused while H3 parks** → the ABL does not accept `text_offset 0x80000` as an entry
  contract: **F1** (H1 shape, `text_offset` 0 only) isolates the field.

### Sign-off criterion (one line)

A **pass = the phone stays off fastboot and off adb for ≥ 90 s** after the flash-triggered
reboot (no re-enumeration; measured by `tooling/50-boot-timing.sh`, t0 = USB node gone, t1 =
first sighting, 90 s cap — `docs/TIMING.md` §1-2). A first sighting in **< 2500 ms** in
fastboot is a refusal; a sighting in **2500-10000 ms** in fastboot, reproducible, is
ran-and-died. Restore `backup/64f70df8/boot_b.img` between runs; slot is `boot_b`.

## 3. The fine series — only if H1 or H2 parks

Baseline for all three is H1 (stock page 0, 36.6 MiB, park on stock's landing). Each carries
**exactly one** of our header's differing fields; nothing else changes.

| img | introduced field | expected | what a refusal names |
|---|---|---|---|
| **F1** | `text_offset` = 0 (stock 0x80000) | park | `text_offset` is the offending field → pack 0x80000 and only that |
| **F2** | `image_size` = 0x4d000 (stock 0x33b7000) | park | `image_size` is sanity-checked against the load extent → always declare the real extent |
| **F3** | `code0` = `b +0x800`, park moved to it, `text_offset`/`image_size` stock | park | the entry distance itself is checked → always land where stock lands |

If all three park, the residual explanation is the (very) small weight of our own payload
(E8) or bytes below `0x800`, and the next artefact is a shim build with the park *and* the
real `text_offset`/`image_size`/landing contract baked into `start.S`, i.e. our code at
`0x2480000` rather than a hybrid.

## 4. Results

Verify column is the literal `PASS`/`WARN` state of `mkbootimg_v1.sh --verify` (the v2 WARN is
expected: v2 is stock-accepted, the port's own pack is v1). Observed is `-` until flashed.

| img | size | verify | sha256 | expected | observed |
|---|---|---|---|---|---|
| H1 | 100663296 | PASS (WARN v2) | `1dd159a985f44a9a46e7a0253757826d851b67e6838908f016d72fb40621b616` | park ≥ 90 s | - |
| H1x | 100663296 | PASS (WARN v2) | `cb6fadb8ee4fa07054a2715a42c77c1c567bed5fd8aa770e94cf1858209b6e31` | refused / die | - |
| H2 | 100663296 | PASS (WARN v2) | `3ae325aa9e76a3fe6e54e1e53c6ec683c23b2b14e7066bcbb7d7bfa6174222ef` | park, or refused | - |
| H3 | 100663296 | PASS (WARN v2) | `594c6109764dd3d6803687689ea4fa2ca3e1485595cbeeaa07f380803f2ca9d5` | park | - |
| H4 | 100663296 | PASS (WARN v2) | `597175f4f36b6ffe1bfab56bdbc154541043b822c91df5a4571b3a5c9c0167f5` | park | - |
| F1 | 100663296 | PASS (WARN v2) | `ff8cf597d1ee222a9b3df13e8da6fd18f71327955e58bab541d7cb8b144a19c4` | park | - |
| F2 | 100663296 | PASS (WARN v2) | `4a44c043deeaf9583fd6fabbbb9ac9896f0d26e518738a970126e7a95a1a4700` | park | - |
| F3 | 100663296 | PASS (WARN v2) | `aaae3ba4e7fad78747e978012a63ac4387de45fc5e7108382d4fbb534bac5ba7` | park | - |

Record an observation with `python3 avicii/shim/hybrid/table.py set h1 "parked, 94 s"`; the
table then prints from `out/*.result` instead of this one.

## 5. Independent checks already done on the host (all measured)

- Every image is exactly 100663296 B and ends in a 64-byte `AVBf` footer whose
  `original_image_size` equals the computed end of the last section.
- Every non-payload boot-header byte equals stock's; only `kernel_size`, `ramdisk_size` and the
  sha1 `id` differ (`check.py` asserts this field by field, not by restating it).
- The kernel section equals the composed kernel byte for byte, the ramdisk and dtb sections
  equal stock's, and every inter-section gap is zero.
- `code0` is a `b` with the documented displacement and the park bytes `5f2003d5ffffff17`
  (`wfe; b .`) sit exactly at that displacement.
- Rebuilds are byte-identical (H1 rebuilt: same sha256).

## 6. Known limits

- H1/H2 are 36.6 MiB, H3/H4 ~0.5 MiB, so weight is not held constant across the two pairs;
  §1 E8 exists because of it.
- H1 and H2 execute our 8 bytes only; a park proves entry, nothing about ABL env (MMU, vectors,
  DTB pointer). Those are the subject of the next series after a park.
- No console on this panel: the only observers are USB timing, the IMEM/ring records and the
  motor (`docs/TELEMETRY.md`).
