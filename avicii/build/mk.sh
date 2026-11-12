#!/bin/bash
# Build the controlled shape/payload series S1..S6 for avicii boot_b.
#
#   bash avicii/build/mk.sh all      # s1 s2 s3 s4 s5 s6 in order
#   bash avicii/build/mk.sh s2       # one target
#   bash avicii/build/mk.sh matrix   # section-by-section diff of everything built, vs stock
#
# Stock is the reference AND target S1. Every image keeps stock's non-payload header fields
# verbatim (os_version, cmdline, dtb_size/dtb_addr, addresses, pagesize, header v2) and ends at
# exactly the partition size. Each target's only permitted delta is documented in README.md and
# enforced by check_image.py; a build that drifts anywhere else fails instead of producing an
# unattributable image.
#
# Writes only avicii/build/. Reads (never modifies) src/los21-boot.img and avicii/shim/out-diag/p0f.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
stock=$root/src/los21-boot.img
sec=$here/sections
out=$here/out
part=100663296
py=${PYTHON:-python3}
mkbootimg=$root/avicii/tools/mkbootimg.py
avbtool=$root/avicii/tools/avbtool.py
check=$here/check_image.py
verify=$root/avicii/tools/mkbootimg_v1.sh
shimdir=$root/avicii/shim/out-diag/p0f

die() { echo "error: $*" >&2; exit 1; }
note() { echo "  $*"; }

# ---------------------------------------------------------------------------
# Sections are lifted from stock once; the geometry they imply is asserted against the header
# values before anything is packed, so a re-extracted stock image cannot silently shift them.
# ---------------------------------------------------------------------------
sections() {
	[ -f "$stock" ] || die "stock image missing: $stock"
	mkdir -p "$sec" "$out"
	if [ -f "$sec/.stamp" ] && [ "$(cat "$sec/.stamp")" = "$(sha256sum "$stock" | cut -d' ' -f1)" ]; then
		return
	fi
	"$py" - "$stock" "$sec" <<'PY'
import struct, sys
src, dst = sys.argv[1], sys.argv[2]
d = open(src, 'rb').read()
v = dict(kernel_size=struct.unpack_from('<I', d, 8)[0],
         ramdisk_size=struct.unpack_from('<I', d, 16)[0],
         dtb_size=struct.unpack_from('<I', d, 1648)[0],
         page=struct.unpack_from('<I', d, 36)[0],
         hdr_size=struct.unpack_from('<I', d, 1644)[0])
if d[:8] != b'ANDROID!':
    sys.exit('stock: bad magic')
if v['page'] != 4096 or v['hdr_size'] != 1660:
    sys.exit(f'stock: unexpected geometry page={v["page"]} header_size={v["hdr_size"]}')
k = 4096
r = k + -(-v['kernel_size'] // 4096) * 4096
t = r + -(-v['ramdisk_size'] // 4096) * 4096
if d[t:t + 4] != b'\xd0\x0d\xfe\xed':
    sys.exit(f'stock: no FDT magic at the expected dtb offset {t:#x}')
if struct.unpack_from('>I', d, t + 4)[0] != v['dtb_size']:
    sys.exit('stock: dtb totalsize does not match dtb_size')
if len(d) - 64 < t + v['dtb_size']:
    sys.exit('stock: footer cuts into the dtb section')
open(f'{dst}/kernel-stock', 'wb').write(d[k:k + v['kernel_size']])
open(f'{dst}/ramdisk-stock', 'wb').write(d[r:r + v['ramdisk_size']])
open(f'{dst}/dtb-stock', 'wb').write(d[t:t + v['dtb_size']])
open(f'{dst}/cmdline', 'wb').write(d[64:64 + 235])
open(f'{dst}/gsize', 'w').write(str(v['kernel_size']))
open(f'{dst}/rsize', 'w').write(str(v['ramdisk_size']))
open(f'{dst}/tsize', 'w').write(str(v['dtb_size']))
print(f'  sections: kernel {v["kernel_size"]} @{k:#x}, ramdisk {v["ramdisk_size"]} @{r:#x}, '
      f'dtb {v["dtb_size"]} @{t:#x}')
PY
	[ "$(wc -c < "$sec/cmdline")" = 235 ] || die 'cmdline is not the 235 stock bytes'
	[ "$(head -c 25 "$sec/cmdline")" = 'androidboot.hardware=qcom' ] || die 'cmdline prefix wrong'
	sha256sum "$stock" | cut -d' ' -f1 > "$sec/.stamp"
}

# ---------------------------------------------------------------------------
# pack KERNEL RAMDISK OUT — v2, stock cmdline/os_version/addresses/dtb, no second stage.
# ---------------------------------------------------------------------------
pack() {
	local kernel=$1 ramdisk=$2 o=$3 cmd
	cmd=$(cat "$sec/cmdline")
	"$py" "$mkbootimg" --header_version 2 \
		--kernel "$kernel" --ramdisk "$ramdisk" --dtb "$sec/dtb-stock" \
		--base 0x0 --kernel_offset 0x8000 --ramdisk_offset 0x1000000 \
		--second_offset 0xf00000 --tags_offset 0x100 --dtb_offset 0x1f00000 \
		--pagesize 4096 --os_version 14.0.0 --os_patch_level 2024-05 \
		--cmdline "$cmd" -o "$o"
}

# footer OUT — unsigned AVB hash footer at the stock offset, zero fill to the partition size.
footer() {
	local o=$1 salt
	# deterministic salt (sha256 of the target name + the stock hash) so a rebuild reproduces the
	# same sha256 and the documented hashes stay valid instead of churning on avbtool's RNG
	salt=$("$py" -c 'import hashlib,sys; print(hashlib.sha256((sys.argv[1]+sys.argv[2]).encode()).hexdigest())' \
		"$(basename "$o")" "$(cat "$sec/.stamp")")
	"$py" "$avbtool" add_hash_footer --image "$o" --partition_size "$part" \
		--partition_name boot --algorithm NONE --salt "$salt" >/dev/null
	[ "$(wc -c < "$o")" = "$part" ] || die "$(basename "$o"): footer did not land on a $part-byte image"
	"$py" "$avbtool" info_image --image "$o" >/dev/null ||
		die "$(basename "$o"): avbtool cannot parse its own footer"
}

# finish IMG TARGET — check, hand-verify, sha256.
finish() {
	local o=$1 target=$2
	"$py" "$check" check "$o" "$target"
	bash "$verify" --verify "$o" > "$o.verify" 2>&1 ||
		{ cat "$o.verify"; die "$(basename "$o"): mkbootimg_v1.sh --verify failed"; }
	grep -q '^PASS' "$o.verify" || { cat "$o.verify"; die "$(basename "$o"): verify did not PASS"; }
	note "verify PASS: $(grep -E '^(PASS|WARN)' "$o.verify" | tr '\n' ' ')"
	sha256sum "$o" > "$o.sha256"
	note "sha256 $(cut -d' ' -f1 "$o.sha256")  $(basename "$o")"
}

# ---------------------------------------------------------------------------
s1() {
	echo 'S1: byte-identical copy of stock (control)'
	cp "$stock" "$out/S1.img"
	finish "$out/S1.img" s1
}

s2() {
	echo 'S2: stock bytes, only the AVB footer rebuilt by our avbtool'
	local o=$out/S2.img body
	# body = exactly the stock bytes up to the stock footer, so nothing but the footer differs
	body=$("$py" -c 'import struct,sys; d=open(sys.argv[1],"rb").read(); print(struct.unpack_from(">Q", d, len(d)-52)[0])' "$stock")
	head -c "$body" "$stock" > "$o"
	footer "$o"
	finish "$o" s2
}

s3() {
	echo 'S3: stock sections through our packer, kernel at its natural length (10 trailing zeros trimmed)'
	local k=$sec/kernel-trim
	head -c "$(( $(cat "$sec/gsize") - 10 ))" "$sec/kernel-stock" > "$k"
	pack "$k" "$sec/ramdisk-stock" "$out/S3.img"
	footer "$out/S3.img"
	finish "$out/S3.img" s3
}

s4() {
	echo 'S4: stock sections through our packer, kernel zero padded to the stock length'
	local k=$sec/kernel-padded gsize
	gsize=$(cat "$sec/gsize")
	cp "$sec/kernel-stock" "$k"
	[ "$(wc -c < "$k")" = "$gsize" ] || die 'stock kernel is already at the stock length'
	pack "$k" "$sec/ramdisk-stock" "$out/S4.img"
	footer "$out/S4.img"
	finish "$out/S4.img" s4
}

# the park payload is copied out of avicii/shim, never rebuilt here
park() {
	[ -f "$shimdir/Image.gz-dtb" ] || die "park kernel missing: $shimdir/Image.gz-dtb"
	[ -f "$shimdir/ramdisk.bin" ] || die "park ramdisk missing: $shimdir/ramdisk.bin"
	cp "$shimdir/Image.gz-dtb" "$sec/kernel-park"
	cp "$shimdir/ramdisk.bin" "$sec/ramdisk-park"
}

s5() {
	echo 'S5: park shim, kernel section zero padded to the stock length (stock weight)'
	park
	local k=$sec/kernel-park-padded gsize
	gsize=$(cat "$sec/gsize")
	cp "$sec/kernel-park" "$k"
	truncate -s "$gsize" "$k"
	pack "$k" "$sec/ramdisk-park" "$out/S5.img"
	footer "$out/S5.img"
	finish "$out/S5.img" s5
}

s6() {
	echo 'S6: park shim at its natural, small size'
	park
	pack "$sec/kernel-park" "$sec/ramdisk-park" "$out/S6.img"
	footer "$out/S6.img"
	finish "$out/S6.img" s6
}

matrix() {
	"$py" "$check" matrix | tee "$here/MATRIX.txt"
}

case "${1:-}" in
	all) sections; s1; s2; s3; s4; s5; s6; echo; matrix ;;
	s1|s2|s3|s4|s5|s6) sections; "$1" ;;
	matrix) matrix ;;
	*) die "usage: $0 all|s1|s2|s3|s4|s5|s6|matrix" ;;
esac
