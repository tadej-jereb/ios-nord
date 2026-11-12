# Payload / shape series — controlled images to separate packer shape from payload

Every image here is a test of exactly **one** variable against the untouched stock
`src/los21-boot.img`. Stock is also S1, the positive control: if a series cannot boot stock,
nothing in it means anything.

Nothing is flashed from this directory. `docs/PAYLOAD_ORDER.md` is the flashing order and the
gate/restore rules that go with it.

## Correction to the brief, measured

The hand-over said `dtb_size=0` and that the stock image carries "no dtb". It does not. Reading
the stock header directly:

| field | offset | value |
|---|---|---|
| `header_size` | 1644 | `0x67c` = 1660 (v2) |
| `dtb_size` | 1648 | `0x6345c` = 406620 |
| `dtb_addr` | 1652 | `0x1f00000` |

That 406620-byte FDT (`d00dfeed`, total size `0x6345c`, "Qualcomm Technologies, Inc. Lito SoC",
`qcom,lito`, `memory`, `mem-offline`) sits at file offset `0x2bab000`, on the page boundary
directly behind the ramdisk, and is exactly `dtb_size` long. So stock is a **v2 image with a real
dtb section**, not `dtb_size=0`. The earlier `dtb_size=0` reading came from unpacking the
`recovery_dtbo`/`dtb` offsets at the wrong field boundaries.

Consequence: every image in this series carries the stock dtb section at the stock offset with the
stock `dtb_addr`. Dropping it would have been an unmentioned second variable.

Second measured fact: our `mkbootimg.py` reproduces the stock image **byte for byte** up to
`original_image_size` (`46198784`), with one exception — the 20-byte sha1 `id` at `0x240`. Nothing
else in the 1660-byte header, the kernel, the ramdisk, the dtb or the trailing zeros differs. So
the packer's *geometry* is already exact; this series does not re-test geometry, it tests the
remaining shape variables one at a time.

## The series

Order is fixed. The v1 path is dead (a stock kernel packed as v1 + appended DTB was refused the
same way), so every image here is **v2** and no step spends a boot on v1. S1 and S2 are the gates;
stop the series at the first unexpected result instead of running on.

| # | payload | variable under test | delta to stock (complete) | expected | what the result means |
|---|---|---|---|---|---|
| **S1** | stock | none — byte-identical copy | none (sha256 must equal stock's) | boots | control. Stock still boots on this ABL/unit, the flash procedure itself is clean, and later refusals are attributable to the image. |
| **S2** | stock | **the AVB footer/vbmeta region only**, rebuilt by our `avbtool.py` at the stock offset | bytes `46198784..100663296` (vbmeta + padding) | boots → footer is not the fault. refused → the fault is entirely in our footer/vbmeta, payload questions are moot | **highest-value step.** The footer is the last thing the ABL reads before it hands over, and it is the one thing every failing image of ours has in common with the stock image it is otherwise identical to. 20 bytes of `id` also differ (see below). |
| **S3** | stock kernel/ramdisk/dtb, packed by us | **our packer as the producer** — same bytes, 10-byte lighter kernel section | `kernel_size` `0x8..0xc` (43876358 vs 43876368) + `id` `0x240..0x254` | boots | our packer can produce a stock-shaped image. Refused while S2 booted → the refusal is in the *produced* image, not the footer; the only produced difference is `kernel_size` and `id`. |
| **S4** | stock kernel/ramdisk/dtb, packed by us | **kernel section padded to the stock length** (`43876368`, last 10 bytes are stock's zeros) | `id` `0x240..0x254` only; every section offset and size is the stock value | boots; byte-identical to S2 except the 20-byte `id` | with S3: is a section size off by 10 bytes enough to be refused? A pass at S4 after a fail at S3 says any size/weight deviation is fatal; both pass → the ABL does not care and later weight results are clean. |
| **S5** | park shim (`wfe`) | **payload = shim, weight = stock** — kernel section zero-padded from 354519 to 43876368, sub-stock 98-byte ramdisk, stock dtb and header | kernel bytes, ramdisk bytes, `kernel_size`, `ramdisk_size`, `id`; ~1.96 MB lighter overall | boots (parks) | the shim's own code runs from a stock-weight image. Gzip + appended-DTB kernel with trailing zero padding is the risky part here: a refusal at S5 but not S4 points at trailing-zero tolerance in the kernel decompressor. |
| **S6** | park shim (`wfe`) | **weight = natural small** — unpadded 354519-byte kernel section, 98-byte ramdisk, stock dtb and header, 446464-byte image | as S5 minus the padding; `kernel_size` 354519 | boots (parks) | the shim runs from a small image. S5 refused + S6 boots = the ABL has an image-weight/size dependence; both refused = it is our packer or the payload, not the weight. S6 is the cheapest image to keep iterating on afterwards. |

Every image ends at exactly `100663296` bytes, carries `header_version 2`, `page_size 4096`,
`os_version 0x1c000185`, the 235-byte stock cmdline, `dtb_size 0x6345c` at `0x1f00000`, the stock
addresses, a zero `id`-padding field and an `AVBf` footer at the stock offset with
`Algorithm: NONE`.

## The `id` field

`0x240..0x254` is the sha1 `id`. Ours is not identical to stock's for identical sections: stock's
`9e8527a0…` is not reproducible from any of kernel/ramdisk/dtb/size/os_version/cmdline
combinations tried, so it is a derived, opaque field. It is the *only* header delta in S4 and the
only delta at all between S4 and S2. If S2 boots and S4 is refused, `id` is the prime suspect and
the next step is to copy stock's 20 bytes over ours.

## What the weight axis actually is

The stock kernel section is already exactly the stock length (`43876368`), with only its last 10
bytes zero. So S3 against S4 is a 10-byte, same-page difference: it tests whether *any* section
size deviation is fatal, not whether the image is heavy. The real weight axis is S5/S6 against
S4 — 44 MB of body versus 0.77 MB — and it is only worth reading if S4 already boots.

Measured, not asserted: S4 differs from S2 in 20 bytes of body — all of them inside the `id` —
plus its own footer bytes, and S3 differs from S4 only in `kernel_size` and `id`. Any difference
outside those ranges or the footer is a builder bug and the build fails on it.

## Determinism

The footer salt is derived (`sha256(target name + stock sha256)`) rather than random, so the
builds are byte-reproducible; two full rebuilds produced identical sha256s and an identical
`MATRIX.txt`. The hashes in `docs/PAYLOAD_ORDER.md` therefore stay valid until an image is
rebuilt on purpose.

## Build

    bash avicii/build/mk.sh all      # s1 s2 s3 s4 s5 s6, in order, each verified + sha256'd
    bash avicii/build/mk.sh s2       # one target
    bash avicii/build/mk.sh matrix   # section-by-section diff of every built image against stock

`mk.sh` refuses to leave an image behind that fails any of: exact partition size, header field
match against stock, section content match, zero fill outside sections, footer parse via
`avbtool info_image`, `original_image_size` covering every section, or
`avicii/tools/mkbootimg_v1.sh --verify`. Output plus `.sha256` land in `avicii/build/out/`; the
matrix lands in `avicii/build/MATRIX.txt`.

Only `avicii/build/` is written. `avicii/shim/` is read (the park `Image.gz-dtb` and its 98-byte
ramdisk are copied out, never rebuilt here).
