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
BLOCKS=1025
NEED=$((BLOCKS * BLK))

dev=$($ADB shell 'for d in /dev/block/by-name/userdata /dev/block/bootdevice/by-name/userdata; do [ -e "$d" ] && readlink -f "$d" && break; done' 2>/dev/null | tr -d '\r')
[ -n "$dev" ] || { echo "Error: userdata block device not found on device" >&2; exit 1; }

bytes=$($ADB shell "blockdev --getsize64 '$dev' 2>/dev/null || cat /sys/class/block/\$(basename \$(readlink -f '$dev'))/size | { read s; echo \$((s*512)); }" 2>/dev/null | tr -d '\r')
case ${bytes:-} in ''|*[!0-9]*) echo "Error: could not read userdata size" >&2; exit 1 ;; esac
[ "$bytes" -gt "$NEED" ] || { echo "Error: userdata is only $bytes bytes" >&2; exit 1; }

skip=$((bytes / BLK - BLOCKS))
printf '%s: %s bytes, reading blocks %s..%s\n' "$dev" "$bytes" "$skip" "$((skip + BLOCKS - 1))" >&2

STAMP=$(date -u '+%Y%m%dT%H%M%SZ')
LOGDIR=$(cd "$(dirname "$0")/.." && pwd)/logs
mkdir -p "$LOGDIR"
BIN=${OUT:-$LOGDIR/sweet-log-$STAMP}.bin

$ADB exec-out "dd if='$dev' bs=$BLK skip=$skip count=$BLOCKS 2>/dev/null" > "$BIN"
got=$(wc -c < "$BIN" | tr -d ' ')
[ "$got" = "$NEED" ] || { echo "Error: read $got of $NEED bytes (short read)" >&2; exit 1; }

magic=$(dd if="$BIN" bs=8 count=1 2>/dev/null | tr -d '\000')
if [ "$magic" != "SWEETLOG" ]; then
	echo "Error: no SWEETLOG header at the end of userdata." >&2
	echo "  Either the kernel never flushed the log, userdata was reformatted," >&2
	echo "  or the ring is not at the last 1025 blocks. Raw area kept: $BIN" >&2
	exit 2
fi

if [ "$RAW" = 1 ]; then
	echo "$BIN"
else
	python3 - "$BIN" "${OUT:-}" <<'PY'
import struct, sys
data = open(sys.argv[1], 'rb').read()
magic, version, size, total, seq = struct.unpack_from('<8sIIQQ', data, 0)
if magic != b'SWEETLOG':
    sys.exit('no SWEETLOG header')
ring = data[4096:4096 + size]
if total <= size:
    text = ring[:total]
else:
    start = total % size
    text = ring[start:] + ring[:start]
out = text.decode('utf-8', 'replace').replace('\r', '')
print(f'# version {version}, ring {size}, total {total} bytes, flush #{seq}'
      f'{" (wrapped: oldest bytes lost)" if total > size else ""}', file=sys.stderr)
if len(sys.argv) > 2 and sys.argv[2]:
    open(sys.argv[2], 'w').write(out)
sys.stdout.write(out)
PY
fi

if [ "$KEEP" = 0 ]; then
	rm -f "$BIN"
else
	echo "raw area: $BIN" >&2
fi
[ -n "$OUT" ] && echo "decoded: $OUT" >&2
