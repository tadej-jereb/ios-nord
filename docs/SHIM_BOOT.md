# Packing the avicii shim boot image (header v1)

Scope: `avicii/shim` + `avicii/tools` on an avicii (OnePlus Nord, SM7250/lito).
Nothing here touches the kernel. Status: everything below is exercised on this
host against synthetic files; **nothing has been run on a phone.**

## Why header v1

Correction to the first draft of this file: the claim "avicii's ABL drops v2/v3" is
**not** true — the stock LineageOS 21 avicii `boot.img` is header **v2** and boots on
this phone (parsed 2026-11-11, see the section at the end). v1 is still what this port
packs, because the one bit-identical ABL family we have a completed port on
(`edi194/ios-fajita`, OnePlus 6T) rejected v2 and booted only v1, and because a v1
image is the only layout that can carry the board DTB in the image itself. If an
avicii ABL revision ever rejects a v1 image, `--header_version 2` is a one-flag change
and the geometry below already matches what the stock v2 image uses.

v1 means:

* **no `dtb` section** — the board DTB rides inside the kernel section instead,
  as `Image.gz-dtb`: a complete gzip member with the flattened DTB appended
  directly after it;
* ABL gunzips the kernel, writes the decompressed image at
  `kernel_addr`, copies the DTB in right behind it, and enters the kernel with
  `x0` pointing at the live tree (which is why the shim can also find the tree
  at `_end` when `x0` is stale);
* the `recovery_dtbo_*` fields must stay zero and `header_size` must be 1648.

`shim/build.sh` refuses to run with `SHIM_HDR != 1`, and
`tools/mkbootimg_v1.sh --verify` fails an image whose `header_version`,
`page_size` or `header_size` is anything else.

## Header fields

Offsets are `struct boot_img_hdr_v1` (`system/tools/mkbootimg/include/bootimg/bootimg.h`).
Every value below is fixed; the wrapper passes them, `--verify` re-reads them.

| off | field | value | why |
|-----|-------|-------|-----|
| 0 | `magic` | `ANDROID!` | |
| 8 | `kernel_size` | actual `Image.gz-dtb` length | not page aligned; the section after it is padded |
| 12 | `kernel_addr` | `0x00008000` | base 0 + kernel_offset 0x8000, as in the stock image |
| 16 | `ramdisk_size` | actual ramdisk length | |
| 20 | `ramdisk_addr` | `0x01000000` | base 0 + ramdisk_offset 0x1000000 |
| 24 | `second_size` | `0` | avicii has no second stage |
| 28 | `second_addr` | `0` | ditto |
| 32 | `tags_addr` | `0x00000100` | base 0 + tags_offset 0x100 |
| 36 | `page_size` | `4096` | stock avicii page size |
| 40 | `header_version` | `1` | the whole point |
| 44 | `os_version` | `17.0.0`, patch `2035-06` | cosmetic; inherited from ios-sweet |
| 48 | `name[16]` | empty | |
| 64 | `cmdline[512]` | `console=null` | the shim/xnu take their arguments from the payload, not from here |
| 576 | `id[8]` | sha1 over the sections | mkbootimg computes it |
| 608 | `extra_cmdline[1024]` | empty | |
| 1632 | `recovery_dtbo_size` | `0` | v1 has no dtbo section |
| 1636 | `recovery_dtbo_offset` | `0` | ditto |
| 1644 | `header_size` | `1648` | |

Where the geometry comes from: two independent avicii board configs that boot
this phone — LineageOS `device/oneplus/avicii` (`BOARD_KERNEL_BASE 0x0`,
`BOARD_KERNEL_PAGESIZE 4096`) and `android_device_oneplus_avicii_TWRP`
(`TAGS_OFFSET 0x100`, `KERNEL_OFFSET 0x8000`, `SECOND_OFFSET 0xf00000`,
`RAMDISK_OFFSET 0x1000000`, `DTB_OFFSET 0x1f00000`) — plus `lazybrar/avicii-mainline`
`scripts/pack.sh`, which boots avicii with exactly these numbers. They are the
mkbootimg.py defaults the stock images were built with.
**Unverified against an actual stock `boot.img` header** — run the verify step
below on one and diff before flashing anything.

## Pack chain

1. Read the stock header and confirm base/offset/pagesize/header_version:

   ```
   ../tools/mkbootimg_v1.sh --verify /path/stock-boot.img
   ```

   Expected: `header_version 1`, `page_size 4096`, `kernel_addr 0x8000`,
   `ramdisk_addr 0x1000000`, `tags_addr 0x100`, and a `board dtb` line. If any
   of those differ, change the defaults in `tools/mkbootimg_v1.sh` — not here.

2. Split the kernel section into `kernel.gz` + `board.dtb` (verifies the gzip
   CRC and the FDT `totalsize`, writes nothing on mismatch):

   ```
   ../tools/extract-dtb.py /path/stock-boot.img out --dump
   ```
   It reads the header itself, refuses v2/v3, and writes `out/kernel.gz` +
   `out/board.dtb`. (`build.sh` calls this for you when `STOCK_BOOT` is set and
   `out/board.dtb` is missing; the `kernel.gz` half is informational — the
   kernel that boots is the shim, not the stock one.)

3. Build the shim, append that DTB to the gzipped shim and pack the image:

   ```
   STOCK_BOOT=/path/stock-boot.img ./build.sh            # empty ramdisk, diagnostics only
   STOCK_BOOT=/path/stock-boot.img ./build.sh out/payload.bin   # boot an xnu payload
   ```

   `build.sh` writes `out/Image`, `out/Image.gz-dtb`, `out/shim-boot.img` and
   re-verifies the header it just produced. It also fails if any C object still
   carries an `R_AARCH64_ABS64` — the image is linked at 0 and runs wherever ABL
   loads it, so absolute data pointers would be wrong.

4. Build the ADT and the payload from the live memory map. Without a device,
   use whatever `tools/dump-live.sh` collected (`10-fdt.dtb` is
   `/sys/firmware/fdt`); the dram range is never guessed:

   ```
   ../tools/fdt-mem.py ../../logs/dumps/run-*/10-fdt.dtb > out/fdt-mem.json
   ../tools/mkadt_avicii.py out/avicii.adt --fdt-json out/fdt-mem.json --dump
   ../tools/mkpayload.py /path/kernel.development.sweet out/avicii.adt out/payload.bin
   ```

   `mkadt_avicii.py` takes the topmost usable extent of that map, carves the
   1 MiB panic log off its top, and warns if it ends up below 4 GiB or
   overlaps `/sweet-fbcon`. Then re-run step 3 with `out/payload.bin`.

5. Look at the verify output. `PASS` is required; it checks the magic, the
   version, `header_size`, the section layout, the gzip CRC and that an FDT
   follows the stream.

6. Boot it without touching flash:

   ```
   fastboot boot out/shim-boot.img
   ```

   Only after the layout is confirmed on the phone and a `boot_a` backup exists:

   ```
   fastboot flash boot_a out/shim-boot.img
   ```

## What the shim expects at runtime

* Entry at EL1, MMU off, `x0` = live FDT (ABL does this for v1 images).
* The appended DTB lands at `_end`; `fdt_locate()` prefers `x0` but scans from
  `_end` when `x0` is 0 or does not point at an `0xd00dfeed`.
* `/chosen/initrd-*` in the live tree names the ramdisk; the payload is read from
  that ramdisk, so the payload tail (`$1` → `out/ramdisk.bin`) is what actually
  boots anything.
* The console is the panel at `0xa0000000` (cont_splash_region), 1080x2400,
  stride 4800, until a payload takes over.

## Known gaps

* No hardware run. Fields are recorded, not measured on this device.
* `out/board.dtb` is only as good as the stock image it came from; the shim
  needs *the* board DTB for this unit, including its `qcom,msm-id`/
  `qcom,board-id` (avicii0/avicii1/avicii2 by SoC revision). Booting the wrong
  revision's DTB is untested.
* AVB: the image is not signed. With an unlocked bootloader that is fine.

## Verified stock-image facts (2026-11-11)

Parsed from `src/los21-boot.img` (LineageOS 21, 20240619, archive.org mirror,
100,663,296 bytes) and `src/dtbo.img`:

| Field | Stock value | Consequence here |
|---|---|---|
| `header_version` | `2` | v2 boots; v1 kept for the fajita precedent + DTB carriage |
| `page_size` | `4096` | matches `mkbootimg_v1.sh` |
| `kernel_addr` | `0x8000` | matches (base 0) |
| `ramdisk_addr` | `0x1000000` | matches |
| `tags_addr` | `0x100` | matches |
| kernel section | raw, uncompressed `Image`, 43,876,368 B, ARM64 magic at `0x38` | we pack gzip on purpose; `--verify` reports raw instead of failing |
| appended DTB in `boot.img` | **none** | the board DTB must come from elsewhere |
| `dtbo.img` | 1-entry `dt_table`, big-endian, dtb 337,226 B at `0x40`, `board-id 8 0`, `oplus,dtsi_no 0x5141`, `pcb_range 0 0x37` | this entry is the board DTB, extracted to `src/avicii-board.dtb` and used for the build |
| boot partition | image padded to 96 MiB | 356 KiB shim has ample room; a 43 MiB kernel also fits |

`dtc` on that DTB gives `model = "Qualcomm Technologies, Inc. Lito MTP 20801"`,
`compatible = "qcom,lito-mtp", "qcom,lito", "qcom,mtp"` — the 20801 board, i.e. avicii.

Two consequences for the ladder:

* The stock DTB is a **fragment overlay** (`fragment@0`, `target = <0xffffffff>`), so it
  has no `/memory`; the live FDT in `x0` remains the only RAM source. `fdt_print_memory()`
  will report a miss on the appended copy — that is expected, not a bug.
* ABL prefers the image's own DTB when one is appended. That is what we want, but it
  means an image packed without `board.dtb` silently gets a different tree.

Rebuild after any change to these facts:

    DTB=/home/tadej/ios-nord/src/avicii-board.dtb ./build.sh
    ../tools/mkbootimg_v1.sh --verify out/shim-boot.img

## `fastboot boot` is unreliable on this ABL — verified 2026-11-12

Four attempts, four failures, so the port does not depend on it:

| Image | Result |
|---|---|
| `src/twrp_v2.img` (TWRP, FBEv2) | `Booting OKAY`, fell back to bootloader |
| `src/twrp.img` (TWRP, FBEv1) | `Booting FAILED (usb_read failed)`, device vanished from USB |
| `out/shim-boot.img` (v1, Image.gz-dtb) | `Booting OKAY`, fell back to bootloader ~20 s later |
| `out/shim-boot-v2.img` (v2, raw Image + `--dtb`) | same: boot taken, then USB dropped, then off the bus |

Neither header version helps, which rules out the v1/v2 question as the cause. The
pattern is that ABL accepts the image (`Booting` prints) and then dies or reboots
before userspace exists. So: **flash, do not boot.**

## Slot policy (observed behaviour)

- Experiments go to **`boot_a`**, then `fastboot --set-active=a` and reboot.
- `boot_b` is the working LineageOS 21 + Magisk and is never written.
- When an experiment fails, ABL **switches the active slot to `a` by itself** (observed
  once) and lands in the stock recovery with "can't load Android system". Recovery is
  therefore not evidence of a brick: check `fastboot getvar current-slot`, then
  `fastboot --set-active=b`.
- Always read `current-slot` before flashing anything. A stale assumption writes the
  working slot.
- `boot_a` holds the stock OOS kernel, backed up as `backup/64f70df8/boot_a.img`
  (md5 `e7be3c9267685382386daa17a9e820b0`), so slot a is also restorable to OOS boot.
