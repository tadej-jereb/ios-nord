#!/bin/sh
# 42-log-pull.sh — read the ios-sweet persistent console ring out of the
# userdata partition and print it. Read-only; nothing is written to the phone.
#
#   tooling/42-log-pull.sh [-s SERIAL] [-o OUT.txt] [--keep-bin] [--raw]
#
# Mechanism (refs/dipa-studio-ios-sweet tools/sweet-log-pull.sh, kernel patch
# 0047): the kernel keeps a 4 MiB ring at the *end* of userdata. The area read
# is the last 1025 blocks of 4096 bytes: block 0 is the header
# ("SWEETLOG", u32 version, u32 ring size, u64 total bytes, u64 flush seq) and
# the ring follows. Byte n of the console is at ring offset n % ring_size.
#
# Offset = userdata_size - 1025*4096, length = 1025*4096.
# Requires a rooted adb shell (TWRP) — the phone can be running iOS or Android,
# the area is raw blocks either way.
#
# Exit: 0 log decoded, 1 setup problem, 2 no valid ring header.

set -eu

ADB="adb"
OUT=""
KEEP=0
RAW=0
while [ $# -gt 0 ]; do
	case $1 in
	-s) shift; SERIAL=${1:?Error: -s needs a serial}; ADB="adb -s $SERIAL"; shift ;;
	-o) shift; OUT=${1:?Error: -o needs a file}; shift ;;
	--keep-bin) KEEP=1; shift ;;
	--raw) RAW=1; shift ;;
	-h|--help) sed -n '2,22p' "$0"; exit 0 ;;
	*) echo "Error: unknown argument $1" >&2; exit 1 ;;
	esac
done

command -v adb >/dev/null 2>&1 || { echo "Error: adb not found in PATH" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "Error: python3 needed to decode" >&2; exit 1; }

$ADB get-state >/dev/null 2>&1 || { echo "Error: no device attached" >&2; exit 1; }

BLK=4096
# Layout at the tail, because the shim ring must not share a block with the
# kernel's console ring (diaglog.c KERNEL_AREA):
#   block 0             shim header, ring follows for SHIM_BLOCKS
#   then KERNEL_BLOCKS  kernel console ring, its own header first
SHIM_BLOCKS=1024
KERNEL_BLOCKS=1025
BLOCKS=$((1 + SHIM_BLOCKS + KERNEL_BLOCKS))	# + the shim header block itself
NEED=$((BLOCKS * BLK))

dev=$($ADB shell 'for d in /dev/block/by-name/userdata /dev/block/bootdevice/by-name/userdata; do [ -e "$d" ] && readlink -f "$d" && break; done' 2>/dev/null | tr -d '\r')
[ -n "$dev" ] || { echo "Error: userdata block device not found on device" >&2; exit 1; }

# Root: on a Magisk-rooted ROM adb shell is uid 2000 and every read needs su;
# recovery's adbd is already root and has no su at all. Take whichever exists.
if $ADB shell "su -c 'id -u'" 2>/dev/null | tr -d '\r' | grep -qx 0; then
	SU="su -c"
elif $ADB shell id -u 2>/dev/null | tr -d '\r' | grep -qx 0; then
	SU=""
else
	echo "Error: no root (neither su nor a root adbd) on the device" >&2
	exit 1
fi
bytes=$($ADB shell "${SU:+$SU }blockdev --getsize64 $dev" 2>/dev/null | tr -d '\r')
case ${bytes:-} in
''|*[!0-9]*)
	sectors=$($ADB shell "${SU:+$SU }cat /sys/class/block/$(basename "$dev")/size" 2>/dev/null | tr -d '\r')
	case ${sectors:-} in ''|*[!0-9]*) bytes="" ;; *) bytes=$((sectors * 512)) ;; esac ;;
esac
case ${bytes:-} in ''|*[!0-9]*) echo "Error: could not read userdata size" >&2; exit 1 ;; esac
[ "$bytes" -gt "$NEED" ] || { echo "Error: userdata is only $bytes bytes" >&2; exit 1; }

skip=$((bytes / BLK - BLOCKS))	# last block index is bytes/BLK-1, header is BLOCKS-1 before it
printf '%s: %s bytes, reading blocks %s..%s\n' "$dev" "$bytes" "$skip" "$((skip + BLOCKS - 1))" >&2

STAMP=$(date -u '+%Y%m%dT%H%M%SZ')
LOGDIR=$(cd "$(dirname "$0")/.." && pwd)/logs
mkdir -p "$LOGDIR"
BIN=${OUT:-$LOGDIR/sweet-log-$STAMP}.bin

$ADB exec-out "${SU:+$SU }dd if=$dev bs=$BLK skip=$skip count=$BLOCKS 2>/dev/null" > "$BIN"
got=$(wc -c < "$BIN" | tr -d ' ')
[ "$got" = "$NEED" ] || { echo "Error: read $got of $NEED bytes (short read)" >&2; exit 1; }

if [ "$RAW" = 1 ]; then
	echo "$BIN"
else
	python3 - "$BIN" "${OUT:-}" "$SHIM_BLOCKS" "$KERNEL_BLOCKS" <<'PYDEC'
import struct, sys
data = open(sys.argv[1], 'rb').read()
out_path, shim_blocks, kernel_blocks = sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
shim_hdr_off, kernel_hdr_off = 0, (shim_blocks + 1) * 4096


def decode(hdr_off, limit):
    """Text of one ring, or None when this area holds no header."""
    magic, version, size, total, seq = struct.unpack_from('<8sIIQQ', data, hdr_off)
    if magic != b'SWEETLOG':
        return None
    ring = data[hdr_off + 4096:hdr_off + 4096 + size]
    limit = min(size, limit * 4096)
    if total <= limit:
        text = ring[:total]
    else:
        start = total % size
        text = ring[start:] + ring[:start]
    # The newest line is written without a header rewrite, so it lies past
    # `total`: take it to the next block boundary (see avicii/shim/diaglog.h).
    off = total % 4096
    if off:
        text += ring[total % size:][:4096 - off]
    print(f'# version {version}, ring {size}, total {total} bytes, flush #{seq}'
          f'{" (wrapped: oldest bytes lost)" if total > size else ""}', file=sys.stderr)
    return text.decode('utf-8', 'replace').replace('\r', '')


parts = []
shim, kern = decode(shim_hdr_off, shim_blocks), decode(kernel_hdr_off, kernel_blocks)
if shim is None and kern is None:
    sys.exit('no SWEETLOG header in either area')
if shim is not None:
    parts.append('# --- shim ring (loader / diag) ---\n' + shim.rstrip('\x00'))
if kern is not None:
    parts.append('# --- kernel console ring ---\n' + kern.rstrip('\x00'))
out = '\n'.join(parts) + '\n'
if out_path:
    open(out_path, 'w').write(out)
sys.stdout.write(out)
PYDEC
fi

if [ "$KEEP" = 0 ]; then
	rm -f "$BIN"
else
	echo "raw area: $BIN" >&2
fi
[ -n "$OUT" ] && echo "decoded: $OUT" >&2
