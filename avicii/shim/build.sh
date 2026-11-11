#!/bin/bash
# Build the avicii shim and pack it into an OnePlus header-v1 boot image.
#
# avicii (OnePlus Nord, SM7250/lito) ABL parses header v2/v3 and then drops back
# to fastboot. It accepts exactly one shape: header v1 whose kernel section is
# `Image.gz-dtb` - a complete gzip stream with the board DTB appended right
# after it - so SHIM_HDR is fixed at 1 here. ABL gunzips the kernel, writes the
# DTB directly behind the decompressed image and jumps to the kernel entry with
# x0 pointing at the live tree; the shim's fdt_locate() uses x0 when it is real
# and otherwise scans from _end, where the appended DTB lands.
#
# The DTB is taken out of the stock boot image, not from a build tree:
#   STOCK_BOOT=/path/to/stock/boot.img ./build.sh [payload.bin]
# or drop a board.dtb into out/ yourself (DTB=...).
#
# Ramdisk handling and the payload layout are unchanged from ios-sweet: $1 is an
# xnu payload from tools/mkpayload.py, otherwise an empty newc cpio is used so
# ABL still gets a non-empty ramdisk.
#
# Not verified on hardware: the header geometry below is the one the stock OTA
# images were built with (see ../tools/mkbootimg_v1.sh), and mkbootimg_v1.sh
# re-parses the header after packing.
set -euo pipefail
cd "$(dirname "$0")"

if [ -f ../../tooling/env.sh ]; then . ../../tooling/env.sh; fi

SHIM_HDR=${SHIM_HDR:-1}
[ "$SHIM_HDR" = 1 ] || { echo "error: this ABL only takes header v1 (SHIM_HDR=$SHIM_HDR)" >&2; exit 1; }

# Toolchain: $CC wins (the workspace LLVM wrapper exports it), else the distro
# aarch64 gcc. clang needs an explicit target or it emits x86-64.
CC=${CC:-}
if [ -z "$CC" ] && command -v aarch64-linux-gnu-gcc >/dev/null; then
	CC=aarch64-linux-gnu-gcc
fi
CC=${CC:-clang}
LINKFLAGS=""
case "$(basename "${CC%% *}")" in
clang*)
	# ELF lld, not the env's ld64.lld (Mach-O), and no binutils-only flags.
	CC="$CC --target=aarch64-linux-gnu"
	LD=${LD_ELF:-$(command -v ld.lld || echo "")}
	[ -n "$LD" ] && export LD
	LINKFLAGS="-fuse-ld=lld -Wl,--build-id=none -Wl,-N"
	;;
*)
	LINKFLAGS="-Wl,--build-id=none -Wl,--no-warn-rwx-segments -Wl,-N"
	;;
esac
OBJCOPY=${OBJCOPY:-$(command -v llvm-objcopy || command -v aarch64-linux-gnu-objcopy || echo objcopy)}
NM=${NM:-$(command -v llvm-nm || command -v aarch64-linux-gnu-nm || echo nm)}
READELF=${READELF:-$(command -v llvm-readelf || command -v aarch64-linux-gnu-readelf || echo readelf)}
PYTHON=${PYTHON:-python3}

# avicii cont_splash_region: whatever the panel showed when we jumped in.
DTB=${DTB:-out/board.dtb}
if [ ! -f "$DTB" ]; then
	[ -n "${STOCK_BOOT:-}" ] || {
		echo "error: no $DTB and no STOCK_BOOT=<stock boot.img> to extract it from" >&2
		exit 1
	}
	"$PYTHON" ../tools/extract-dtb.py "$STOCK_BOOT" out --dump
fi

# -fno-jump-tables: clang turns dense switches into tables of absolute string
# pointers in .rodata (R_AARCH64_ABS64). Those are only correct if the image is
# loaded at its link address (0); the shim is loaded wherever ABL likes, so keep
# the switches as compare-and-branch. The ABS64 check below enforces it.
CFLAGS="-O2 -ffreestanding -nostdlib -fno-pic -fno-jump-tables -mgeneral-regs-only -mstrict-align -fno-stack-protector -Wall -Wextra"
mkdir -p out
for f in start.S shim.c console.c mmu.c fdt.c loader.c ufs.c; do
	$CC $CFLAGS -c "$f" -o "out/${f%.*}.o"
done
# The image runs wherever ABL puts it with no relocation pass: only the
# header's image_size (start.o, linked at 0) may be an absolute address.
abs=$($READELF -r out/shim.o out/console.o out/mmu.o out/fdt.o out/loader.o out/ufs.o | grep -c ABS64 || true)
[ "$abs" = 0 ] || { echo "error: $abs absolute relocations in C objects" >&2; exit 1; }
$CC $CFLAGS -static -T shim.ld $LINKFLAGS \
	out/start.o out/shim.o out/console.o out/mmu.o out/fdt.o out/loader.o out/ufs.o -o out/shim.elf
$OBJCOPY -O binary out/shim.elf out/Image
# ABL copies the file; pad to image_size so .bss/stacks exist as zeroed bytes.
# mawk has no strtonum, so let bash do the hex conversion.
size_hex=$($NM out/shim.elf | awk '$3=="_end"{print $1}')
[ -n "$size_hex" ] || { echo "error: no _end symbol in out/shim.elf" >&2; exit 1; }
size=$((0x$size_hex))
truncate -s "$size" out/Image
# gzip -n: no name/mtime, so the image is reproducible.
gzip -9 -n -c out/Image > out/Image.gz
cat out/Image.gz "$DTB" > out/Image.gz-dtb

# Ramdisk: an xnu payload (tools/mkpayload.py) if given as $1, else an empty
# newc cpio (ABL dislikes a zero-size ramdisk on some builds) -> diagnostics.
if [ -n "${1:-}" ]; then
	cp "$1" out/ramdisk.bin
else
	(cd out && rm -rf rd && mkdir rd && cd rd && find . | cpio -o -H newc --quiet | gzip -9 > ../ramdisk.bin)
fi

../tools/mkbootimg_v1.sh --kernel out/Image.gz-dtb --ramdisk out/ramdisk.bin \
	--os_version 17.0.0 --os_patch_level 2035-06 \
	--cmdline "console=null" -o out/shim-boot.img

# Host render of the console layout (x86 gcc, host_test only).
if command -v gcc >/dev/null; then
	gcc -O1 -Wall -o out/host_test console.c host_test.c && ./out/host_test
fi
ls -l out/Image out/Image.gz-dtb out/shim-boot.img
echo "flash: fastboot boot out/shim-boot.img   (or flash boot_a once the layout is confirmed)"
