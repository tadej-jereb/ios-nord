# ABL forensics: why our packer's images are not executed

Scope: host-side byte analysis of the boot images named in the task, plus the device's own
pstore/`misc`/`ro.boot.*` channels. Nothing flashed here; the orchestrator flashes.
Written 2026-11-12. Every number below comes from a tool run pasted in this file, or from a
command whose output is quoted; anything reasoned from those numbers is labelled
**HYPOTHESIS**. Host scratch tooling: `logs/forensics/` (`parse.py`, `digest2.py`,
`check_bootimg.py`, `build/`).

Images under analysis (sha256, all 100663296 B = the 96 MiB boot partition):

| id | file | sha256 | behaviour |
|---|---|---|---|
| stock | `src/los21-boot.img` | `183795b7a887d4f4c69e5b29cf65f3345ae6cea634ebdb2db49edc9cbaa45239` | **boots** (18 s to system) — control |
| magisk | `backup/64f70df8/boot_b.img` | `39ed8eeaf9053a9a53028b3b2ba03f45ab288df38e8f9430ca0a6fda545b1ef0` | **boots** — control |
| repack7 | `/tmp/repack7.img` | `f5271cdfba61e691005b04b03fe2f1e8bd64c74189c6444f9ec399e403863434` | refused ~6 s |
| v1stock | `/tmp/v1stock.img` | `eee2f7ada9e5d908b629c417dffbc9f8f9f96774b1c5f2986600f1110e3cbc08` | refused ~6 s |
| p0f | `avicii/shim/out-diag/p0f/shim-boot.img` | `fdb6061b087b90ea8d9f0dbbdaf9e6b316bccc6425f2024f9e8d29230f58f85c` | refused ~6 s |
| p0c | `avicii/shim/out-diag/p0c/v2.img` | `29160d8e92754aec5e5b20b6af1479dc4bad5403b18f8e1f794eecb14a511396` | refused ~6 s |

---

## 0. Verdict, ranked

`repack7` and stock share a byte-identical kernel and ramdisk and differ in **five header
bytes only** inside the region they share (§4); the entire difference between them is the
406620-byte dtb section that stock has and repack7 does not. Both controls and *every* image
this phone has ever accepted carry a `dtb` section; all four refusals do not. That is the finding; the rest of this section is the ranking of
everything else that differs, and §5 is the list of candidates the bytes already exclude.

| # | difference | stock (works) | ours (fails) | confidence |
|---|---|---|---|---|
| 1 | `dtb` section present | `dtb_size` = **406620**, `dtb_addr` = **0x1f00000**, 406620-byte FDT at 0x2bab000 | `dtb_size` = **0**, `dtb_addr` = **0x0**, no dtb section (repack7, p0c); v1 images: no dtb section and no dtb fields at all (v1stock, p0f) | **VERIFIED difference**; gate status HYPOTHESIS (see §4, §10) |
| 2 | header version | **2** | 1 (v1stock, p0f) | HYPOTHESIS (secondary). Every image that boots on this phone is v2 — boot, recovery, TWRP all carry a dtb section (v2 magic at 40 = 2 for all three). `docs/SHIM_BOOT.md:9-16` already records that the "avicii drops v2" claim is false |
| 3 | `dtb_addr` used as the `x0` FDT pointer | 0x1f00000 → a real FDT | **0** | HYPOTHESIS, sub-case of 1: with `dtb_size`=0 our header hands ABL nowhere to load a tree and `x0`=0 is the natural outcome (`avicii/shim/start.S:3` "x0 = DTB pointer") |
| 4 | `os_version` | 0x1c000185 (= `14.0.0` / `2024-05`, the tool's own round-trip) | 0x0 (v1stock, p0c); 0x22000236 (p0f); stock's value (repack7) | weak as a gate: `mkbootimg_v1.sh` now hard-fails `os_version` 0 on an anti-rollback claim, but repack7 and p0f carry non-zero values and are refused too, so 0 is not sufficient to be refused and not necessary |
| 5 | embedded-vbmeta size / contents | 704 B, hash descriptor + 2 property descriptors | 512 B, hash descriptor only | weak: shape is legal, `avbtool info_image` parses it, and property descriptors are informational |
| — | **footer digest freshness** | matches | also matches on all four failures | **excluded** (§5) |
| — | footer presence, magic, version, partition size, page size, magic `ANDROID!`, load addresses, `header_size`, all padding | — | identical | **excluded** (§5) |

Consequence: a footer that merely *parses* is provably not enough — our four refusals all
carry a structurally perfect, self-consistent footer whose `SHA256` over
`image[0:original_image_size]` recomputes correctly (§5).

---

## 1. Method

1. Parse every header field (named and unnamed) of all six images; the parser is
   `logs/forensics/parse.py`, run output quoted in §2 and §3. All offsets are byte-exact.
2. Hash every section and diff section-by-section against the controls (§4).
3. `avbtool info_image` on each image and on `backup/64f70df8/vbmeta_b.img`; recompute each
   embedded `boot` hash descriptor digest as `sha256(salt ‖ image[0:image_size])` and compare
   (§5).
4. `cmp`-style full-file diff of stock against a rebuild by our own tooling (§8).
5. Read the device's pstore, `misc` and `ro.boot.*` to size the log channel that can settle
   the remaining HYPOTHESIS (§9).

The footer is big-endian: `struct "!4sIIQQQ28s"` (`avbtool.py:1999` `FORMAT_STRING`;
`RESERVED`=28 so the footer is 64 B in the last 64 B of the partition). Reading it
little-endian yields nonsense — a trap worth restating; `mkbootimg_v1.sh --verify` did
exactly that until the uncommitted `'>Q'` fix now in the tree (`docs/BISECT.md:40`).

---

## 2. Header, field by field

Empty cells = zero. `id` is 32 B (20 B SHA-1 + 12 B zero). `cmdline` is byte-identical to
stock in stock, magisk, repack7, v1stock and p0c
(`androidboot.hardware=qcom … reboot=panic_warm … swiotlb=2048`); p0f differs.

| off | field | stock | magisk | repack7 | v1stock |
|---|---|---|---|---|---|
| 0 | `magic[8]` | `ANDROID!` | `ANDROID!` | `ANDROID!` | `ANDROID!` |
| 8 | `kernel_size` | 43876368 | 43876368 | 43876368 | 20344704 (gzip) |
| 12 | `kernel_addr` | 0x8000 | 0x8000 | 0x8000 | 0x8000 |
| 16 | `ramdisk_size` | 1900641 | 1439638 | 1900641 | 1900641 |
| 20 | `ramdisk_addr` | 0x1000000 | 0x1000000 | 0x1000000 | 0x1000000 |
| 24 | `second_size` | 0 | 0 | 0 | 0 |
| 28 | `second_addr` | 0 | 0 | 0 | 0 |
| 32 | `tags_addr` | 0x100 | 0x100 | 0x100 | 0x100 |
| 36 | `page_size` | 4096 | 4096 | 4096 | 4096 |
| 40 | `header_version` | **2** | **2** | **2** | **1** |
| 44 | `os_version` | 0x1c000185 | 0x1c000185 | 0x1c000185 | **0x0** |
| 48 | `name[16]` (unnamed in AOSP) | empty | empty | empty | empty |
| 64 | `cmdline[512]` | stock | stock | stock | stock |
| 576 | `id[32]` | `9e8527a0…e9be38ab`+0 | `f8ea2675…ca36cf23`+0 | `9e8527a0…e9be38ab`+0 | `2365cc37…8f927b80`+0 |
| 608 | `extra_cmdline[1024]` | empty | empty | empty | empty |
| 1632 | `recovery_dtbo_size` | 0 | 0 | 0 | 0 |
| 1636 | `recovery_dtbo_offset` | 0 | 0 | 0 | 0 |
| 1644 | `header_size` | 1660 | 1660 | 1660 | 1648 |
| 1648 | **`dtb_size`** | **406620** | **406620** | **0** | *(no such field in v1)* |
| 1652 | **`dtb_addr`** | **0x1f00000** | **0x1f00000** | **0x0** | *(no such field in v1)* |
| 1660-4095 | header page padding (bytes past the struct) | all 0 | all 0 | all 0 | all 0 |

For the two shim images: p0f is header **v1**, kernel 354519 (`Image.gz-dtb`), ramdisk 98,
`os_version` 0x22000236, `header_size` 1648, bytes 1648-1659 (the v2 `dtb_*` area) unused/0.
p0c is header v2, kernel 315392 (uncompressed Image), ramdisk 99, `os_version` 0x0,
`header_size` 1660, **`dtb_size` 0 / `dtb_addr` 0x0**.

Stock's bytes at 1648-1659 are `5c 34 06 00 | 00 00 f0 01 00 00 00 00` — the only five
bytes of the whole stock image that are non-zero here and zero in repack7 (`1648, 1649,
1650, 1654, 1655`).

---

## 3. Layout: sections, padding, vbmeta, footer

All padding is zero-filled. Every image in this set puts the vbmeta block immediately after
the page-aligned end of the last section (`gap` = 0) and the footer in the last 64 bytes;
there is no trailing byte after the footer. Total size 100663296 in all six.

| region | stock | magisk | repack7 | v1stock |
|---|---|---|---|---|
| header block | 0 + 4096 | 0 + 4096 | 0 + 4096 | 0 + 4096 |
| kernel | 4096 + 43876368 | 4096 + 43876368 | 4096 + 43876368 | 4096 + 20344704 |
| pad to page | 4080 | 4080 | 4080 | 128 |
| ramdisk | 43884544 + 1900641 | 43884544 + 1439638 | 43884544 + 1900641 | 20348928 + 1900641 |
| pad to page | 3999 | 2154 | 3999 | 3999 |
| second / recovery_dtbo | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| **dtb** | **45789184 + 406620** | **45326336 + 406620** | **— none —** | **— none —** |
| pad to page | 2980 | 2980 | — | — |
| end of sections = `original_image_size` = `vbmeta_offset` | 46198784 | 45735936 | 45789184 | 22253568 |
| vbmeta block | 46198784 + 704 | 45735936 + 704 | 45789184 + 512 | 22253568 + 512 |
| gap vbmeta→footer (all zero) | 54463744 | 54926592 | 54873536 | 78409152 |
| AVB footer | 100663232 + 64 | 100663232 + 64 | 100663232 + 64 | 100663232 + 64 |
| file size | 100663296 | 100663296 | 100663296 | 100663296 |

Footer, all fields:

| footer field | stock | magisk | repack7 | v1stock |
|---|---|---|---|---|
| magic | `AVBf` | `AVBf` | `AVBf` | `AVBf` |
| version | 1.0 | 1.0 | 1.0 | 1.0 |
| `original_image_size` | 46198784 | 45735936 | 45789184 | 22253568 |
| `vbmeta_offset` | 46198784 | 45735936 | 45789184 | 22253568 |
| `vbmeta_size` | 704 | 704 | 512 | 512 |
| reserved[28] | all 0 | all 0 | all 0 | all 0 |

There is no rollback index or rollback-index location in the footer; both live in the
embedded vbmeta *header*, and are 0 in every image here (as in stock): `avbtool info_image`
on the embedded blob reports `Rollback Index: 0`, `Rollback Index Location: 0`,
`Release String: 'avbtool 1.3.0'`, `Minimum libavb version: 1.0` for all six.

The vbmeta block itself, field by field, is uniform across the set apart from size and
descriptors — which is why the digest is the only graded difference:

| vbmeta field | stock | magisk | repack7 | v1stock |
|---|---|---|---|---|
| magic | `AVB0` | `AVB0` | `AVB0` | `AVB0` |
| header version | 1.0 | 1.0 | 1.0 | 1.0 |
| header block | 256 | 256 | 256 | 256 |
| authentication block | 0 (unsigned) | 0 | 0 | 0 |
| auxiliary block | 448 | 448 | 256 | 256 |
| algorithm | NONE | NONE | NONE | NONE |
| public key (sha1) | — | — | — | — |
| minimum libavb version | 1.0 | 1.0 | 1.0 | 1.0 |
| rollback index / location | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| header flags | 0 | 0 | 0 | 0 |
| release string | `avbtool 1.3.0` | `avbtool 1.3.0` | `avbtool 1.3.0` | `avbtool 1.3.0` |
| descriptors | hash `boot` (image_size 46198784, salt 0e53b366…, digest 23bf8963…) + prop `boot.os_version` + prop `boot.fingerprint` | **same three, same bytes** | hash `boot` (image_size 45789184, fresh salt/digest), no props | hash `boot` (image_size 22253568, fresh salt/digest), no props |
| descriptor `Flags` | 0 | 0 | 0 | 0 |

Embedded vbmeta header (256 B) of stock and magisk are **byte-identical**, sha256
`030d9f565ed5983f4e3c51d42e00403f8f21f9e3c5220902b436d47a6cb8202b`, and the two images'
footers differ in exactly four bytes — `17, 18, 25, 26`, i.e. only the two relocated size
fields. Ours (repack7) is a different blob (512 B, `d0e2daee…`), carrying the same shape of
descriptor but a freshly generated salt and a digest that recomputes correctly.

---

## 4. The A/B that isolates the dtb section

`repack7` is our packer fed the stock kernel and the stock ramdisk. Its payload is not
"similar" to stock, it is **the same bytes**:

```
kernel stock   sha256 0e53b3664a2212d2d592cb6ad004ec4a…
kernel repack7 sha256 0e53b3664a2212d2d592cb6ad004ec4a…
ramdisk stock  sha256 5d5a792b3d85c016032443504bec1d74…
ramdisk repack7 sha256 5d5a792b3d85c016032443504bec1d74…
cmdline equal: True      id equal: True (both 9e8527a0…)
```

Full-file compare of stock vs repack7 over `0 … 0x2bab000` (everything up to where stock's
dtb begins) yields **5 differing bytes: offsets 1648, 1649, 1650, 1654, 1655** — exactly
`dtb_size` and `dtb_addr` going to zero. From where stock's dtb starts, repack7 already has
the vbmeta (`AVB0` at 0x2bab000 where stock has `d00dfeed`).

So the single image pair that differs only in packaging is: same kernel, same ramdisk, same
cmdline, same header, same footer shape, same partition fill — **one boots and one does
not, and the only payload difference is the 406620-byte dtb section.**

Device-side corroboration that a dtb section is not optional here: every image known to be
accepted on this phone carries one —

```
src/los21-boot.img      hdrver 2  page 4096  dtb (406620,   0x1f00000)
src/recovery.img        hdrver 2  page 4096  dtb (406620,   0x1f00000)
src/twrp.img            hdrver 2  page 4096  dtb (1096921,  0x1f00000)
src/twrp_v2.img         hdrver 2  page 4096  dtb (1096921,  0x1f00000)
```

and the LOS `recovery.img` reuses stock's identical 406620-byte tree.

HYPOTHESIS on mechanism, two branches, both consistent with a constant ~6 s with no
watchdog (bark is 15 s, `docs/BISECT.md:47`):

* **A — ABL refuses before hand-off.** For a v2 image ABL loads `dtb_size` bytes at
  `dtb_addr`; with both zero there is nothing to load and it bails back to fastboot. Best
  fit for the parked-shim evidence: a `wfe` park cannot return on its own, yet it returns in
  the same 6 s as the 30 s-spin variant, so the shim was never executed.
* **B — ABL hands off and the payload dies at once.** `x0` = 0 into
  `fdt_check_header()`/`setup_arch` faults, `reboot=panic_warm` (in the cmdline) warm-resets.
  Explains the real kernel; does not explain a parked shim.

§9's procedure decides between them: a panic writes `dmesg-ramoops-*`, a refusal writes
nothing.

---

## 5. Candidates the bytes exclude

* **Footer digest freshness.** `sha256(salt ‖ image[0:image_size])` recomputes to the stored
  digest on stock, repack7, v1stock, p0f, p0c — and **fails on the boots-fine magisk image**
  (stored digest and `image_size` = stock's 46198784/`23bf8963…`, while the file's own
  `original_image_size` is 45735936). A verifier that enforced this would reject our
  controls. Not a gate.
* **Footer presence / shape.** `AVBf`, version 1.0, 28 zero reserved bytes, footer last 64 B,
  vbmeta page-aligned at `original_image_size`, nothing after the footer: identical in all
  six.
* **Partition fill.** 100663296 B in all six.
* **Header magic, `page_size`, load addresses, `header_size`, header-page padding.**
  Identical where the field exists; `header_size` is 1660 for v2 and 1648 for v1, correct in
  both cases.
* **`id`.** Stock and repack7 are equal; magisk's differs and boots. Informational only
  (note: our tool's formula does not reproduce stock's id — `sha1(k‖len‖ramdisk‖len‖0‖0‖dtb‖len)`
  gives `0e68c45f…`, stock has `9e8527a0…` — so the stock id came from a different
  build-time tool. Harmless, but do not expect id equality).
* **vbmeta aux block 448 vs 256, missing `com.android.build.boot.{os_version,fingerprint}`.**
  Both parse; props are informational.
* **Signature.** Every image here is unsigned (`Authentication Block: 0 bytes`,
  `Algorithm: NONE`); the controls are too.

---

## 6. What Magisk's patcher actually does to the footer and the padding

Source: `topjohnwu/Magisk`, `native/src/boot/bootimg.cpp` (master; the on-disk APK is
v31.1). Registration of the footer, in the `boot_img` constructor:

```cpp
        // Find AVB footer
        const void *footer = tail.data() + tail.size() - sizeof(AvbFooter);
        if (BUFFER_MATCH(footer, AVB_FOOTER_MAGIC)) {
            avb_footer = static_cast<const AvbFooter*>(footer);
            // Double check if meta header exists
            const void *meta = addr + __builtin_bswap64(avb_footer->vbmeta_offset);
            if (BUFFER_MATCH(meta, AVB_MAGIC)) {
                fprintf(stderr, "VBMETA\n");
                flags[AVB_FLAG] = true;
```

Repack, three steps, in this order:

1. **The vbmeta blob is copied verbatim**, `vbmeta_size` bytes taken from the *old* footer,
   at a fresh 4096-aligned offset after the new sections:

```cpp
    if (boot.flags[AVB_FLAG]) {
        // According to avbtool.py, if the input is not an Android sparse image
        // (which boot images are not), the default block size is 4096
        file_align_with(4096);
        off.vbmeta = lseek(fd, 0, SEEK_CUR);
        uint64_t vbmeta_size = __builtin_bswap64(boot.avb_footer->vbmeta_size);
        xwrite(fd, boot.vbmeta, vbmeta_size);
    }
```

2. **Two footer fields are rewritten** after the image is complete, and the footer is
   written at `out.size() - sizeof(AvbFooter)` (last 64 B); the file is zero-padded back to
   its original size first:

```cpp
        auto footer = reinterpret_cast<AvbFooter*>(out.data() + out.size() - sizeof(AvbFooter));
        memcpy(footer, boot.avb_footer, sizeof(AvbFooter));
        footer->original_image_size = __builtin_bswap64(orig_img_size);
        footer->vbmeta_offset = __builtin_bswap64(off.vbmeta);
        if (check_env("PATCHVBMETAFLAG")) {
            auto vbmeta = reinterpret_cast<AvbVBMetaImageHeader*>(out.data() + off.vbmeta);
            vbmeta->flags = __builtin_bswap32(3);
        }
```

3. **Nothing is re-signed and no digest is recomputed.** The hash descriptor keeps the old
   `image_size`, salt and digest — which is why the working backup's descriptor is stale.

`PATCHVBMETAFLAG` defaults to false in `scripts/boot_patch.sh` (`[ -z $PATCHVBMETAFLAG ] &&
PATCHVBMETAFLAG=false`), so the copied header keeps its original `Flags: 0` — confirmed in
the backup: both its descriptor flags and its vbmeta-header flags read 0.

What Magisk does **not** do: it does not drop the dtb section. The backing files for
kernel/ramdisk/second/recovery_dtbo/**dtb** are restored if present, so a patched image is
stock's layout with a new ramdisk. Verified in `boot_b.img`: `dtb_size` 406620, `dtb_addr`
0x1f00000, and the dtb bytes at 0x2b3a000 are **byte-identical to stock's**
(sha256 `48b0902a99c10a11ff52680bf81e9fec2574ad687c58ea35a00fdbf7aefe40ce`, 0 differing
bytes).

Net: Magisk's footprint on the AVB structures is exactly "relocate the blob, fix the two
size fields, keep everything else". That is enough for this ABL — because verification is
off (§7) — but it is **not** enough by itself: the working image also kept a dtb section
that ours drop.

---

## 7. Does the footer have to match the `vbmeta_b` chain?

No — and the controls prove it. Measurement:

```
$ python3 avicii/tools/avbtool.py info_image --image backup/64f70df8/vbmeta_b.img
Flags:                    3                     <- VERIFICATION_DISABLED | HASHTREE_DISABLED
Algorithm:                SHA256_RSA4096
Public key (sha1):        2597c218aae470a130f61162feaae70afd97f011
    Hash descriptor: Partition Name: boot, Image Size: 46198784,
      Salt: 0e53b366…9391, Digest: 23bf8963…ba78
```

* `vbmeta_b` is signed with a real key and disabled for verification by build flags
  (3). `src/vbmeta.img` (slot a) is the same blob, same flags.
* Its `boot` hash descriptor is **byte-identical** to the descriptor embedded in the stock
  boot image — stock's footer *is* the chained descriptor, so for stock the two agree
  exactly (and stock's recomputed digest matches, §5).
* But the boots-fine magisk image carries the same stale descriptor over a different image
  and boots anyway. Therefore the descriptor digest is not consulted on this unit
  (verification off, `verifiedbootstate=orange`, `flash.locked=0`).
* Ours are self-consistent but describe a *different* vbmeta than `vbmeta_b`'s (fresh salt
  and digest, 512 B aux block). With verification off that costs nothing — but if
  verification is ever turned back on, ours would fail first.

Practical rule: a self-consistent footer is required (ABL reads it to find the vbmeta at
all); agreement with `vbmeta_b` is not. Cheap way to get both: sign with the stock salt and
byte-identical `original_image_size`, which makes the descriptor identical to the chain's
(§8 does exactly that for a stock payload).

---

## 8. Minimal recipe for an image ABL will run

Requirements it satisfies, in order of what actually gated us: header v2, `dtb_size` > 0,
`dtb_addr` = 0x1f00000, section order kernel→ramdisk→dtb, page-aligned sections, vbmeta at
the page-aligned end of sections, footer last 64 B, partition 100663296 B. Payload-agnostic:
works for the stock kernel and for a shim Image.

Recover the stock sections **and the stock dtb** (the DTB in the image is 406620 B and is
*not* `src/avicii-board.dtb`, which is 337226 B with sha256 `8d3818a2…`):

```sh
mkdir -p /tmp/fix && cd /tmp/fix
dd if=/home/tadej/ios-nord/src/los21-boot.img of=kernel.img bs=4096 skip=1 count=43876368 iflag=count_bytes
dd if=/home/tadej/ios-nord/src/los21-boot.img of=ramdisk.img bs=4096 skip=10714 count=1900641 iflag=count_bytes
dd if=/home/tadej/ios-nord/src/los21-boot.img of=dtb.img bs=4096 skip=11179 count=406620 iflag=count_bytes
dd if=/home/tadej/ios-nord/src/los21-boot.img of=cmdline.txt bs=1 skip=64 count=512
```

(`iflag=count_bytes` lets `count` be a byte count; `skip` stays in `bs` units and the values
above are exactly `off/4096` from §3: 4096/4096=1, 43884544/4096=10714, 45789184/4096=11179.
For a shim payload use `avicii/shim/out-diag/p0X/Image` as `--kernel` and its `ramdisk.bin`
as `--ramdisk`, and keep the stock `dtb.img`.)

Build the header with v2 and the stock geometry:

```sh
python3 /home/tadej/ios-nord/avicii/tools/mkbootimg.py \
  --header_version 2 \
  --kernel kernel.img \
  --ramdisk ramdisk.img \
  --dtb dtb.img \
  --cmdline "$(tr -d '\000' < cmdline.txt)" \
  --base 0x0 --kernel_offset 0x8000 --ramdisk_offset 0x1000000 \
  --second_offset 0xf00000 --dtb_offset 0x1f00000 --tags_offset 0x100 \
  --pagesize 4096 \
  --os_version 14.0.0 --os_patch_level 2024-05 \
  -o boot.img
```

Note the wrapper's new `OS_VERSION` default (`12.0.0` / `2023-09` → raw `0x180000F9`) is
**not** what stock carries: stock is `14.0.0` / `2024-05` → `0x1c000185`. Pass
`OS_VERSION=14.0.0 OS_PATCH_LEVEL=2024-05` if you drive the wrapper instead of
`mkbootimg.py` directly.

Append the footer over the whole 96 MiB partition, unsigned, verification-0, with stock's
salt and stock's property descriptors so the descriptor is the chain's:

```sh
python3 /home/tadej/ios-nord/avicii/tools/avbtool.py add_hash_footer \
  --image boot.img \
  --partition_size 100663296 \
  --partition_name boot \
  --algorithm NONE \
  --flags 0 \
  --salt 0e53b3664a2212d2d592cb6ad004ec4a31e8d6be86a8d91259b9810635869391 \
  --prop com.android.build.boot.os_version:14 \
  --prop com.android.build.boot.fingerprint:OnePlus/Nord/Nord:12/RKQ1.211119.001/Q.202212051830:user/release-keys
```

PASS test (`logs/forensics/check_bootimg.py`) — structural gates ABL applies, the three
footer invariants the task names, and the digest recomputation:

```sh
python3 /home/tadej/ios-nord/logs/forensics/check_bootimg.py boot.img
```

Expected `RESULT PASS`, with `original_image_size covers every section`,
`dtb_size > 0`, `file size == partition size 100663296`, `avbtool info_image parses
footer/vbmeta` all PASS. Then `sha256sum boot.img` and record it in
`docs/IMAGE_PROVENANCE.md` before flashing.

**This recipe is byte-proven against stock.** Run exactly as above on stock's own payload
it produces `logs/forensics/build/raw.img` (sha256 `5689a0ac86d0d917d35883a1b8f29f7d20f9852849174d7c21740f8ef6006cf8`),
which differs from `src/los21-boot.img` in 50 bytes only — the `id` field (576-595) and the
32-byte digest that field feeds (46199208-46199239); every other byte, the whole vbmeta
header and descriptor block included, is identical:

```
$ diff <(python3 avicii/tools/avbtool.py info_image --image src/los21-boot.img) \
       <(python3 avicii/tools/avbtool.py info_image --image logs/forensics/build/raw.img)
22c22
<       Digest:                23bf896366e129302547fca403c733dffcd5c2fdeead85f630efcba3baacba78
---
>       Digest:                75bf6cde08d5245de04bafd587f0f3f19cc6e44374f130f8b3a6a2a35c8fa39d
```

Refusals against it:
`repack7`, `v1stock`, `p0c` all FAIL the dtb gate; a shim image built this way
(`logs/forensics/build/shimfix.img`, sha256 `4245202e…`) PASSes everything.

Cross-check, independent line, same conclusion: the six-image series another agent left in
`avicii/build/out/` (S1…S6) also carries a dtb section in every image and all six PASS this
same test — `S1.img` is byte-identical to `src/los21-boot.img` (`sha256 183795b7…`, 0 bytes
differing, i.e. it carries stock's footer and vbmeta forward verbatim rather than
re-signing). The two recipes agree on every gate; the difference is only whether the vbmeta
is rebuilt (§8 above, fresh salt, digest recomputed) or copied (their S1).

---

## 9. Log collection for a refused boot

Validated device facts first, because they dictate the procedure:

| fact | evidence |
|---|---|
| `console-ramoops-0` is 262144 B and is a **live printk console** | `dmesg`: `console [pstore0] enabled` @0.163385, `pstore: Registered ramoops as persistent store backend`; `/sys/module/ramoops/parameters/console_size` = `record_size` = 262144, `mem_size` 4194304, `ecc` 0, `dump_oops` 1, `pstore: Using compression: deflate` |
| a full record **stops accepting output**; it is not a ring | the record ends at 74.676 s of one old boot and nothing later was captured, over many reboots |
| `rm` frees the record and it is **not re-created until the next boot** | `rm -f /sys/fs/pstore/console-ramoops-0` → file gone; `echo x > /dev/kmsg`, `sleep 1` → still absent |
| records survive a boot (not erased at boot) | a record from a previous boot was readable as-is |
| both records are **bit-corrupted (~1 char in 9)**, stably | `md5sum` on device == md5 of the pulled file, so not transport; keep raw bytes and match fuzzily |
| `device-info-ramoops-0` (2036 B) carries project/PCB/RF/soc/SoC version, serial, kernel version and the **full ABL boot cmdline** | pulled file |
| `misc` 0x0 carries the ABL-written `bootloader_message.command` = `bootonce-bootloader` | `dd if=/dev/block/by-name/misc bs=4096 count=1` |
| `ro.boot.bootreason` = `bootloader` is **not** refusal-specific | it reads `bootloader` on the current healthy boot too, because the last reset was `reboot bootloader` |
| `su` is absent from `$PATH` in `adb shell`, `adb root` works (uid=0) | `ls /system/bin/su` → missing; `adb root` → `uid=0(root) … context=u:r:su:s0` |

Numbered transcript. Gate: `boot_b` is bootable and `backup/64f70df8/boot_b.img` is on the
host (sha256 `39ed8eea…`). `adb kill-server` before every reboot: pstore is overwritten by
the next boot, so a stale adb server that survives the transition makes the whole run
ambiguous.

**(a) baseline** — capture both records, hash them, and keep them:

```sh
adb root
adb kill-server
adb start-server
adb exec-out cat /sys/fs/pstore/console-ramoops-0 2>/dev/null > logs/forensics/base-console.bin
adb exec-out cat /sys/fs/pstore/device-info-ramoops-0 2>/dev/null > logs/forensics/base-devinfo.txt
adb exec-out dd if=/dev/block/by-name/misc bs=4096 count=1 2>/dev/null > logs/forensics/base-misc.bin
adb shell cat /proc/cmdline > logs/forensics/base-cmdline.txt
sha256sum logs/forensics/base-*.bin logs/forensics/base-*.txt
```

Baselines already pulled on 2026-11-12 are kept as `logs/forensics/baseline-console-raw.bin`
(sha256 `29f21b406b7c8791363f3dd886ef979aedf5f41cfe577906fd09591c56262135`, 262132 B) and
`logs/forensics/baseline-device-info.txt` (sha256 `571ca2d9a7b08b136ed1715c6af4c9aaa1f13128b08e9f2de0e1d56852c36003`);
note that this run erased the device's console record, so a fresh (a) is required for any
new attempt. Gate: `base-console.bin` is a *full* record — 262132 B, which is the whole exposed record
(`console_size` is 262144; the 12-byte difference is pstore bookkeeping) — and
`base-devinfo.txt` is ~2036 B and non-empty. If not, stop: you are not looking at the channel
you think you are.

**(b) arm** — free the console record (it will be re-created, empty, by the next boot), then
go to fastboot and flash the candidate to `boot_a` with slot a active. Order matters: arm
before leaving Android.

```sh
adb shell rm -f /sys/fs/pstore/console-ramoops-0
adb shell rm -f /sys/fs/pstore/device-info-ramoops-0
adb shell sync
adb kill-server
adb reboot bootloader
fastboot devices
fastboot flash boot_a /tmp/fix/boot.img
fastboot --set-active=a
fastboot reboot
```

Observe and time it. A refusal is: back in fastboot in ~6 s, `fastboot devices` answers
again, panel unchanged. Record the seconds.

**(c) restore** — `boot_b` content back and slot b active, from fastboot:

```sh
fastboot devices
fastboot flash boot_b /home/tadej/ios-nord/backup/64f70df8/boot_b.img
fastboot --set-active=b
fastboot reboot
```

**(d) capture immediately after** — first thing once adb answers, before anything else:

```sh
adb root
adb kill-server
adb start-server
adb exec-out cat /sys/fs/pstore/console-ramoops-0 2>/dev/null > logs/forensics/post-console.bin
adb exec-out cat /sys/fs/pstore/device-info-ramoops-0 2>/dev/null > logs/forensics/post-devinfo.txt
adb exec-out dd if=/dev/block/by-name/misc bs=4096 count=1 2>/dev/null > logs/forensics/post-misc.bin
adb shell getprop ro.boot.bootreason > logs/forensics/post-bootreason.txt
adb shell cat /proc/cmdline > logs/forensics/post-cmdline.txt
sha256sum logs/forensics/post-*.bin logs/forensics/post-*.txt
```

**(e) diff and read** — never open the log with `xxd | less`; it is corrupted, so diff the
hashes first and only then match on distinctive substrings:

```sh
cmp logs/forensics/base-console.bin logs/forensics/post-console.bin && echo "console UNCHANGED"
cmp logs/forensics/base-misc.bin logs/forensics/post-misc.bin && echo "misc UNCHANGED"
diff logs/forensics/base-devinfo.txt logs/forensics/post-devinfo.txt
grep -a -m3 -E 'Linux version|Booting Linux|panic|wfe|shim|Restarting system|bootloader' logs/forensics/post-console.bin
```

Reading the result:

* **nothing ran → ABL refused before hand-off (HYPOTHESIS A, §4).** The record you find
  belongs entirely to the restore boot, which created it: it starts at time 0.0 s with a
  banner, and the kernel version / project version in `post-devinfo.txt` are *the same* as in
  `base-devinfo.txt` (`Linux version 4.19.300-perf…`, project version 20001). `post-misc.bin`
  equals `base-misc.bin` except for ABL's own `bootonce-bootloader` churn, and no
  `dmesg-ramoops-*` record exists.
* **the image was entered and died (HYPOTHESIS B, §4):** `post-devinfo.txt` names a different
  kernel/version than the baseline, or a `dmesg-ramoops-*` record exists next to the console
  one, or the restore boot's console log carries our payload's markers (`wfe`, `shim`, a
  `Kernel panic` from a kernel that is not `4.19.300-perf`).
* **`misc` differing beyond the existing `bootonce-bootloader`** → ABL wrote its own boot
  decision; quote the bytes.
* After the restore boot the fresh record belongs to *that* boot, so always state which boot
  a quoted line came from: the banner/version in `post-devinfo.txt` is the discriminator, not
  the timestamps (the RTC is wrong — a Nov-12 boot logs `20261110_…`).

---

## 10. What would still falsify this

1. A `dtb`-section-bearing image that is refused anyway → the gate is not the dtb but
   something correlated with it (rank 3's `x0`=0, or rank 2's v2 requirement being about
   something else). The recipe in §8 exists to be falsified this way.
2. A refusal that nonetheless leaves a panic dump naming our payload → ABL did hand off and
   the missing DTB killed it in `setup_arch`, i.e. rank 1 is a *payload* bug, not an ABL
   gate, and the shim's park should have survived — which would then point hard at the park
   shims not being reached for a different reason (load address / Image header), worth its
   own bisect rung.
3. `docs/SHIM_BOOT.md` needs a correction either way: the port packs v1 with no dtb section
   (`build.sh` refuses `SHIM_HDR != 1`), and neither of the two working controls looks like
   that.
