#!/bin/bash
# Build the H-series hybrid kernels (H1x, H1, H2, H3, H4) and the contingent finer
# series (F1..F3) that localise why stock's kernel runs on this ABL and ours does not.
#
#   bash avicii/shim/hybrid/mk.sh all        # every image, in ladder order
#   bash avicii/shim/hybrid/mk.sh h1         # one target
#   bash avicii/shim/hybrid/mk.sh table      # expected/observed table from the .result files
#
# The whole series starts from byte-identical agreement with stock: every image keeps
# stock's cmdline, ramdisk, dtb section, addresses, pagesize, header v2 and stock's exact
# os_version 0x1c000185 (14.0.0 / 2024-05 - the value the ABL's anti-rollback wants, and
# the value in stock's own header; the v1 wrapper's 12.0.0 default is only its floor).
#
# Nothing here is flashed. Writes only avicii/shim/hybrid/. Reads src/los21-boot.img and
# avicii/shim/out-diag/p0f/Image (the exact payload proven refused, 6070 ms, 3x).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
stock=$root/src/los21-boot.img
our=$root/avicii/shim/out-diag/p0f/Image
sec=$here/sections
out=$here/out
part=100663296
py=${PYTHON:-python3}
mkbootimg=$root/avicii/tools/mkbootimg.py
avbtool=$root/avicii/tools/avbtool.py
check=$here/check.py
verify=$root/avicii/tools/mkbootimg_v1.sh

die() { echo "error: $*" >&2; exit 1; }
note() { echo "  $*"; }

# Stock's own values, measured from the header, not from a table.
GSIZE=$(od -An -tu4 -j8 -N4 "$stock" | tr -d ' ')
RSIZE=$(od -An -tu4 -j16 -N4 "$stock" | tr -d ' ')
TSIZE=$(od -An -tu4 -j1648 -N4 "$stock" | tr -d ' ')
OSV=$(od -An -tx4 -j44 -N4 "$stock" | tr -d ' ')
[ "$OSV" = 1c000185 ] || die "stock os_version is 0x$OSV, expected 0x1c000185"

sections() {
	local tmp
	mkdir -p "$sec" "$out"
	[ -f "$stock" ] || die "stock image missing: $stock"
	[ -f "$our" ] || die "refused payload missing: $our"
	tmp=$(mktemp -d)
	"$py" - "$stock" "$sec" "$tmp" <<'PY'
import struct, sys
src, dst, tmp = sys.argv[1], sys.argv[2], sys.argv[3]
d = open(src, 'rb').read()
k = struct.unpack_from('<I', d, 8)[0]
r = struct.unpack_from('<I', d, 16)[0]
t = struct.unpack_from('<I', d, 1648)[0]
if d[:8] != b'ANDROID!' or struct.unpack_from('<I', d, 36)[0] != 4096:
    sys.exit('stock: bad magic or pagesize')
if struct.unpack_from('<I', d, 1644)[0] != 1660:
    sys.exit('stock: not a v2 header')
ro = 4096 + -(-k // 4096) * 4096
do = ro + -(-r // 4096) * 4096
if d[do:do + 4] != b'\xd0\x0d\xfe\xed':
    sys.exit('stock: no FDT magic where the dtb section must be')
if struct.unpack_from('>I', d, do + 4)[0] != t:
    sys.exit('stock: dtb totalsize mismatch')
open(f'{tmp}/kernel-stock', 'wb').write(d[4096:4096 + k])
open(f'{tmp}/ramdisk-stock', 'wb').write(d[ro:ro + r])
open(f'{tmp}/dtb-stock', 'wb').write(d[do:do + t])
open(f'{tmp}/cmdline', 'wb').write(d[64:64 + 235])
PY
	# publish only after every assertion held
	for f in kernel-stock ramdisk-stock dtb-stock cmdline; do mv "$tmp/$f" "$sec/$f"; done
	rmdir "$tmp"
	[ "$(wc -c < "$sec/cmdline")" = 235 ] || die 'cmdline is not the 235 stock bytes'
	[ "$(head -c 25 "$sec/cmdline")" = 'androidboot.hardware=qcom' ] || die 'cmdline prefix wrong'
	[ "$(wc -c < "$sec/kernel-stock")" = "$GSIZE" ] || die 'stock kernel section length wrong'
}

# compose TARGET OUT - build the kernel section for one target, with the branch and
# field patches applied and every resulting byte asserted against the recipe.
compose() {
	local target=$1 k=$sec/kernel-$1
	"$py" - "$target" "$k" "$sec" "$our" "$TSIZE" <<'PY'
import struct, sys
target, dst, sec, ourpath, _ = sys.argv[1:6]
stock = open(f'{sec}/kernel-stock', 'rb').read()
our = open(ourpath, 'rb').read()
PARK = bytes.fromhex('5f2003d5ffffff17')          # wfe ; b .
Z = lambda n: bytes(n)
STUB = 0x1000                                      # stock's first page: code0 + real stub


def brk(disp):
    assert disp % 4 == 0 and disp // 4 < 1 << 26, disp
    return struct.pack('<I', 0x14000000 | (disp // 4))


def patch(buf, code0=None, text_offset=None, image_size=None):
    buf = bytearray(buf)
    if code0 is not None:
        buf[0:4] = brk(code0)
    if text_offset is not None:
        struct.pack_into('<Q', buf, 0x08, text_offset)
    if image_size is not None:
        struct.pack_into('<Q', buf, 0x10, image_size)
    return bytes(buf)


assert our[0x38:0x3c] == b'ARMd'
assert stock[0x38:0x3c] == b'ARMd'
stock_code0 = struct.unpack_from('<I', stock, 0)[0]
assert stock_code0 >> 26 == 0x5
land = (stock_code0 & 0x3ffffff) * 4            # stock's real landing offset
assert land == 0x2480000, hex(land)

if target == 'h1':                              # stock page 0, park on stock's landing
    k = stock[:STUB] + Z(land - STUB) + PARK
elif target == 'h1x':                           # brief-literal: park at 0x92000
    k = stock[:STUB] + Z(0x92000 - STUB) + PARK
elif target == 'h2':                            # our 0..0x40, stock stub 0x40..0x1000
    k = our[:0x40] + stock[0x40:0x800] + PARK + stock[0x808:STUB] + Z(land - STUB) + PARK
elif target == 'h3':                            # our image, far branch +0x92000
    k = our + Z(0x92000 - len(our)) + PARK
    k = patch(k, code0=0x92000, text_offset=0x80000, image_size=0x93000)
elif target == 'h4':                            # our image, entry == base+text_offset
    k = our + Z(0x80000 - len(our)) + PARK
    k = patch(k, code0=0x80000, text_offset=0x80000, image_size=0x81000)
elif target == 'f1':                            # H1 with our text_offset (0) only
    k = patch(stock[:STUB] + Z(land - STUB) + PARK, text_offset=0)
elif target == 'f2':                            # H1 with our image_size only
    k = patch(stock[:STUB] + Z(land - STUB) + PARK, image_size=0x4d000)
elif target == 'f3':                            # H1 with our code0 only (+ park moved to it)
    k = brk(0x800) + stock[4:0x800] + PARK + stock[0x808:STUB] + Z(land - STUB) + PARK
else:
    sys.exit(f'unknown target {target}')

# where code0 must branch, and where the park must be, for each target
CODE0 = {t: land for t in ('h1', 'h1x', 'f1', 'f2')}
CODE0.update(h2=0x800, f3=0x800, h3=0x92000, h4=0x80000)
PARKS = dict(h1=(land,), h1x=(0x92000,), h2=(0x800, land), h3=(0x92000,), h4=(0x80000,),
             f1=(land,), f2=(land,), f3=(0x800, land))
assert k[0:4] == struct.pack('<I', 0x14000000 | (CODE0[target] // 4))
for off in PARKS[target]:
    assert k[off:off + 8] == PARK, hex(off)
open(dst, 'wb').write(k)
print(f'  composed {target}: {len(k)} B, code0 branch +{CODE0[target]:#x}, '
      f'text_offset {struct.unpack_from("<Q", k, 8)[0]:#x}, image_size {struct.unpack_from("<Q", k, 0x10)[0]:#x}, '
      f'park at {", ".join(hex(o) for o in PARKS[target])}')
PY
}

pack() {
	local kernel=$1 o=$2
	"$py" "$mkbootimg" --header_version 2 \
		--kernel "$kernel" --ramdisk "$sec/ramdisk-stock" --dtb "$sec/dtb-stock" \
		--base 0x0 --kernel_offset 0x8000 --ramdisk_offset 0x1000000 \
		--second_offset 0xf00000 --tags_offset 0x100 --dtb_offset 0x1f00000 \
		--pagesize 4096 --os_version 14.0.0 --os_patch_level 2024-05 \
		--cmdline "$(cat "$sec/cmdline")" -o "$o"
}

footer() {
	local o=$1 salt
	salt=$("$py" -c 'import hashlib,sys; print(hashlib.sha256((sys.argv[1]+sys.argv[2]).encode()).hexdigest())' \
		"$(basename "$o")" "$(sha256sum "$stock" | cut -d' ' -f1)")
	"$py" "$avbtool" add_hash_footer --image "$o" --partition_size "$part" \
		--partition_name boot --algorithm NONE --salt "$salt" >/dev/null
	[ "$(wc -c < "$o")" = "$part" ] || die "$(basename "$o"): footer did not land on a $part-byte image"
}

finish() {
	local o=$1 target=$2 magic=$3
	"$py" "$check" "$o" "$sec/kernel-$target" "$magic"
	bash "$verify" --verify "$o" > "$o.verify" 2>&1 || { cat "$o.verify"; die "$target: verify failed"; }
	grep -q '^PASS' "$o.verify" || { cat "$o.verify"; die "$target: verify did not PASS"; }
	note "verify PASS: $(grep -E '^(PASS|WARN)' "$o.verify" | tr '\n' ' ')"
	sha256sum "$o" > "$o.sha256"
	note "sha256 $(cut -d' ' -f1 "$o.sha256")  $(basename "$o")"
}

# recipe TARGET - the per-image card the flasher reads
recipe() {
	local target=$1
	"$py" - "$target" "$out/$target.recipe" "$OSV" "$part" <<'PY'
import sys
sys.path.insert(0, '/home/tadej/ios-nord/avicii/shim/hybrid')
from cards import CARDS
t, dst, osv, part = sys.argv[1:5]
c = CARDS[t]
open(dst, 'w').write(
    f'target        : {t}\n'
    f'payload       : {c["why"]}\n'
    f'code0         : {c["code0"]}\n'
    f'expected      : {c["exp"]}\n'
    f'proves        : {c["proves"]}\n'
    f'if refused    : {c["next"]}\n'
    f'os_version    : 0x{osv} (stock)\n'
    f'partition     : {part} B\n'
    'flash         : boot_b, restore_image backup/64f70df8/boot_b.img between runs\n'
    'measure       : tooling/50-boot-timing.sh, plateau vs the stock control\n')
PY
}

one() {
	local target=$1 magic
	case $target in
	h1x) magic='+0x92000 (brief literal)' ;;
	h1) magic='+0x2480000 (stock landing)' ;;
	h2) magic='+0x800 (our header)' ;;
	h3) magic='+0x92000 far, text_offset 0x80000' ;;
	h4) magic='+0x80000 == text_offset' ;;
	f1) magic='+0x2480000, our text_offset' ;;
	f2) magic='+0x2480000, our image_size' ;;
	f3) magic='+0x800, stock text_offset' ;;
	esac
	echo "$target: build"
	compose "$target"
	recipe "$target"
	pack "$sec/kernel-$target" "$out/$target.img"
	footer "$out/$target.img"
	finish "$out/$target.img" "$target" "$magic"
}

case "${1:-}" in
all)
	sections
	for t in h1 h1x h2 h3 h4 f1 f2 f3; do one "$t"; done
	echo
	"$py" "$here/table.py" ;;
h1|h1x|h2|h3|h4|f1|f2|f3) sections; one "$1" ;;
table) "$py" "$here/table.py" ;;
*) die "usage: $0 all|h1|h1x|h2|h3|h4|f1|f2|f3|table" ;;
esac
