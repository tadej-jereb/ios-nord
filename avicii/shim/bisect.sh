#!/bin/bash
# Build the early-boot bisect series (docs/BISECT.md) - one layer per image.
#
#   ./bisect.sh              # build + verify every rung, sha256 into SHA256SUMS
#   ./bisect.sh -s "1 2"     # only these rungs
#
# Rung 1u is the only rung that is *not* expected to pass --verify: it is rung 1
# with the AVB footer cut off again, i.e. the exact shape of every image that
# crashed before 2026-11-12 20:40. 1u then 1 is the one-variable A/B on the
# footer, so 1u's verify FAIL is reported, not counted.
#
# Every rung is a real OnePlus header-v1 image, packed exactly like build.sh
# (gzip kernel, board DTB appended after the gzip stream) and re-parsed with
# ../tools/mkbootimg_v1.sh --verify afterwards. A rung that fails to build or
# fails --verify stops the run.
#
# Output: out-diag/bisect-N/shim-boot.img. The rungs are meant to be flashed
# in order 1, 1b, 2, 3, 4, 5 and each one is expected to park in wfe forever;
# the pass/fail signature and the line the *next* image changes are in
# docs/BISECT.md.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
cd "$here"

DTB=${DTB:-$repo/src/avicii-soc.dtb}
OUTDIR=${OUTDIR:-$here/out-diag}
STAGES="1u 1 1b p1 p2 p3 2 3 4 5"

# Stock kernel section length, from the stock boot.img in docs/SHIM_BOOT.md (43,876,368 B).
STOCK_KERNEL_SIZE=43876368

while [ $# -gt 0 ]; do
	case $1 in
	-s) STAGES=${2:?}; shift 2 ;;
	-h|--help) sed -n '2,18p' "$0"; exit 0 ;;
	*) echo "error: unknown argument $1" >&2; exit 1 ;;
	esac
done

[ -f "$DTB" ] || { echo "error: no board DTB at $DTB (set DTB=)" >&2; exit 1; }
[ -f ../../tooling/env.sh ] && . ../../tooling/env.sh
CC=${CC:-clang}
case "$(basename "${CC%% *}")" in
clang*)	CC="$CC --target=aarch64-linux-gnu"
	LD=${LD_ELF:-$(command -v ld.lld || echo "")}
	[ -n "$LD" ] && export LD
	LINKFLAGS="-fuse-ld=lld -Wl,--build-id=none -Wl,-N" ;;
*)	LINKFLAGS="-Wl,--build-id=none -Wl,--no-warn-rwx-segments -Wl,-N" ;;
esac
OBJCOPY=${OBJCOPY:-$(command -v llvm-objcopy || command -v aarch64-linux-gnu-objcopy || echo objcopy)}
NM=${NM:-$(command -v llvm-nm || command -v aarch64-linux-gnu-nm || echo nm)}
READELF=${READELF:-$(command -v llvm-readelf || command -v aarch64-linux-gnu-readelf || echo readelf)}
PYTHON=${PYTHON:-python3}
CFLAGS="-O2 -ffreestanding -nostdlib -fno-pic -fno-jump-tables -mgeneral-regs-only -mstrict-align -fno-stack-protector -Wall -Wextra -I$here"

mkdir -p "$OUTDIR"
sums=$OUTDIR/SHA256SUMS.bisect
: > "$sums"

# 64 KiB prefix of the board DTB with a matching totalsize: rung 1b's tail. It
# still starts at tags_addr 0x100 and still runs into the image at 0x8000, so
# 1 vs 1b isolates "the tail overlaps the head" from "the tail is 337 KiB".
make_short_dtb() {
	head -c 65536 "$DTB" > "$OUTDIR/short.dtb"
	printf '\x00\x01\x00\x00' | dd of="$OUTDIR/short.dtb" bs=1 seek=4 conv=notrunc status=none
}

build_one() {
	local name=$1; shift
	local out=$OUTDIR/bisect-$name
	mkdir -p "$out"
	echo "=== rung $name"
	local srcs=() objs=() ld="" dtb="$DTB" defs=() ABS64="" raw="" pad="" hdr=${HDR:-1}
	while [ $# -gt 0 ]; do
		case $1 in
		--ld) ld=$2; shift 2 ;;
		--no-dtb) dtb=""; shift ;;
		--short-dtb) dtb="$OUTDIR/short.dtb"; shift ;;
		--raw) raw=1; shift ;;			# kernel section = raw Image, no gzip
		--pad-kernel) pad=$STOCK_KERNEL_SIZE; shift ;;	# zero-pad to the stock kernel length
		--hdr) hdr=$2; shift 2 ;;
		--abs64-check) ABS64=1; shift ;;
		-D*) defs+=("$1"); shift ;;
		*) srcs+=("$1"); shift ;;
		esac
	done
	local cobjs=()
	for s in "${srcs[@]}"; do
		local o=$out/$(basename "${s%.*}").o
		$CC $CFLAGS "${defs[@]}" -c "$s" -o "$o"
		objs+=("$o")
		case $s in *.c) cobjs+=("$o") ;; esac
	done
	if [ -n "${ABS64:-}" ]; then
		# Only C objects: start.o legitimately carries one ABS64 (image_size).
		local abs=0
		for o in "${cobjs[@]}"; do
			abs=$((abs + $($READELF -r "$o" | grep -c ABS64 || true)))
		done
		[ "$abs" = 0 ] || { echo "error: $abs absolute relocations (rung $name)" >&2; return 1; }
	fi
	$CC $CFLAGS -static -T "$ld" $LINKFLAGS "${objs[@]}" -o "$out/shim.elf"
	$OBJCOPY -O binary "$out/shim.elf" "$out/Image"
	local size_hex; size_hex=$($NM "$out/shim.elf" | awk '$3=="_end"{print $1}')
	[ -n "$size_hex" ] || { echo "error: no _end in rung $name" >&2; return 1; }
	truncate -s "$((0x$size_hex))" "$out/Image"
	if [ -n "$raw" ]; then cp "$out/Image" "$out/section"
	else gzip -9 -n -c "$out/Image" > "$out/section"; fi
	[ -z "$pad" ] || truncate -s "$pad" "$out/section"
	if [ -n "$dtb" ]; then cat "$out/section" "$dtb" > "$out/section+tail"
	else cp "$out/section" "$out/section+tail"; fi
	(cd "$out" && rm -rf rd && mkdir rd && cd rd && find . | cpio -o -H newc --quiet | gzip -9 > ../ramdisk.bin)
	HDR=$hdr ../tools/mkbootimg_v1.sh --kernel "$out/section+tail" --ramdisk "$out/ramdisk.bin" \
		--os_version 17.0.0 --os_patch_level 2035-06 \
		--cmdline "console=null" -o "$out/shim-boot.img" > "$out.pack" 2>&1 || {
			echo "--- pack FAILED, tail of $out.pack:" >&2; tail -8 "$out.pack" >&2; return 1; }
	if ! ../tools/mkbootimg_v1.sh --verify "$out/shim-boot.img" | tee "$out.verify" | tail -1 | grep -q '^PASS'; then
		echo "--- verify FAILED for rung $name:" >&2; cat "$out.verify" >&2; return 1
	fi
	( cd "$out" && sha256sum shim-boot.img ) | sed "s|shim-boot.img|bisect-$name/shim-boot.img|" >> "$sums"
	echo "--- rung $name PASS, $(stat -c%s "$out/shim-boot.img") B, sha256 recorded"
	rm -f "$out/host_test"
}

# Rung 1u: rung 1 with the AVB footer truncated back off (the pre-20:40 shape).
# original_image_size lives at footer offset 12; the sections end there.
build_unfooted() {
	local out=$OUTDIR/bisect-1u
	rm -rf "$out"; cp -a "$OUTDIR/bisect-1" "$out"
	local f=$out/shim-boot.img
	local orig
	orig=$($PYTHON - "$f" <<'EOF'
import struct, sys
d = open(sys.argv[1], 'rb').read()
print(struct.unpack_from('>Q', d, len(d) - 64 + 12)[0])   # AVB structures are big-endian
EOF
)
	truncate -s "$orig" "$f"
	( cd "$out" && sha256sum shim-boot.img ) | sed "s|shim-boot.img|bisect-1u/shim-boot.img|" >> "$sums"
	echo "--- rung 1u built, $orig B, footer cut off (verify FAIL is expected):"
	../tools/mkbootimg_v1.sh --verify "$f" | grep -E '^  - |^FAIL' || true
	rm -f "$out/host_test"
}

make_short_dtb
fails=0
for s in $STAGES; do
	case $s in
	1u) build_one 1 --ld bisect/n1.ld bisect/n1.S && build_unfooted ;;
	1)  build_one 1 --ld bisect/n1.ld bisect/n1.S ;;
	1b) build_one 1b --ld bisect/n1.ld --short-dtb bisect/n1.S ;;
	2)  build_one 2 --ld shim.ld start.S bisect/stubs.S -DPARK_AFTER_ENTRY ;;
	# p1-p3: same N1 code, only the carriage differs. See docs/BISECT.md §5.
	p1) build_one p1 --ld bisect/n1.ld --raw bisect/n1.S ;;
	p2) build_one p2 --ld bisect/n1.ld --raw --no-dtb --hdr 2 bisect/n1.S ;;
	p3) build_one p3 --ld bisect/n1.ld --raw --no-dtb --pad-kernel --hdr 2 bisect/n1.S ;;
	3)  build_one 3 --ld shim.ld --abs64-check start.S bisect/stubs.S bisect/park.c mmu.c -DBISECT_N=3 -DBISECT_NO_FB ;;
	4)  build_one 4 --ld shim.ld --abs64-check start.S bisect/stubs.S bisect/park.c mmu.c -DBISECT_N=4 ;;
	5)  build_one 5 --ld shim.ld --abs64-check start.S bisect/stubs.S bisect/park.c mmu.c console.c -DBISECT_N=5 ;;
	*)  echo "error: unknown rung $s" >&2; fails=$((fails + 1)) ;;
	esac || fails=$((fails + 1))
done
# avbtool salts the vbmeta it hashes, so two runs of one rung differ byte for
# byte: a recorded sha256 names this exact artifact, it is not a rebuild target.
# Rung 1u rebuilds rung 1 internally, so keep the last line per path.
tac "$sums" | awk '!seen[$2]++' | tac > "$sums.tmp" && mv "$sums.tmp" "$sums"

echo
echo "images under $OUTDIR (bisect-<n>/shim-boot.img), sha256 in $sums"
echo "order: 1u (control), 1, 1b, p1, p2, p3, 2, 3, 4, 5."
[ "$fails" = 0 ] || { echo "$fails rung(s) failed" >&2; exit 1; }
