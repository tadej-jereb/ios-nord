#!/bin/sh
# 41-backup-pull.sh — pull /sdcard/backup off the phone and verify every
# md5 against the manifest the device wrote. Refuses to run on any mismatch.
#
#   tooling/41-backup-pull.sh [-s SERIAL] [DEST]
#
# DEST defaults to backup/ next to this repository. Pulled files land in
# DEST/<serial>/ so two handsets never mix.
#
# Exit: 0 all files verified, 1 usage/adb problem, 2 any mismatch or gap.
#
# Read-only on the device. Run 40-backup-by-name.sh first.

set -eu

ADB="adb"
if [ "${1:-}" = "-s" ]; then
	shift
	SERIAL=${1:?Error: -s requires a device serial}
	shift
	ADB="adb -s $SERIAL"
fi

[ "${1:-}" = "-h" ] && { sed -n '2,13p' "$0"; exit 0; }

command -v adb >/dev/null 2>&1 || { echo "Error: adb not found in PATH" >&2; exit 1; }

REPO=$(cd "$(dirname "$0")/.." && pwd)
DEST=${1:-$REPO/backup}
SRC=/sdcard/backup

if ! $ADB get-state >/dev/null 2>&1; then
	echo "Error: no device (adb get-state failed). Recovery booted and USB attached?" >&2
	exit 1
fi
DEV_SERIAL=$($ADB get-serialno 2>/dev/null | tr -d '\r')
[ -n "$DEV_SERIAL" ] || { echo "Error: could not read device serial" >&2; exit 1; }

if ! $ADB shell "[ -f $SRC/manifest.tsv ]" 2>/dev/null; then
	echo "Error: $SRC/manifest.tsv missing on device — run 40-backup-by-name.sh first." >&2
	exit 1
fi

OUT="$DEST/$DEV_SERIAL"
mkdir -p "$OUT"
echo "Pulling $SRC from $DEV_SERIAL into $OUT"

$ADB pull "$SRC/manifest.tsv" "$OUT/manifest.tsv" >/dev/null
$ADB pull "$SRC/device.txt" "$OUT/device.txt" >/dev/null 2>&1 || echo "warn: no device.txt" >&2
MAN="$OUT/manifest.tsv"

md5_of() {
	if command -v md5sum >/dev/null 2>&1; then md5sum "$1" | cut -d' ' -f1
	else md5 -q "$1"; fi
}

# Pull each dumped entry, then verify it.
FAIL=0
MISSING=0
N=0
while IFS="$(printf '\t')" read -r name size md5 devnode status; do
	case $name in
	''|\#*) continue ;;
	esac
	[ "$status" = "dumped" ] || continue
	N=$((N + 1))
	if ! $ADB pull "$SRC/$name.img" "$OUT/$name.img" >/dev/null 2>&1; then
		echo "PULL FAILED  $name"
		MISSING=$((MISSING + 1))
		continue
	fi
	got_md5=$(md5_of "$OUT/$name.img")
	got_size=$(wc -c < "$OUT/$name.img" | tr -d ' ')
	if [ "$got_md5" != "$md5" ]; then
		echo "MD5 MISMATCH $name (manifest $md5, file $got_md5)"
		FAIL=$((FAIL + 1))
	elif [ "$got_size" != "$size" ]; then
		echo "SIZE MISMATCH $name (manifest $size, file $got_size)"
		FAIL=$((FAIL + 1))
	else
		printf 'ok %s\n' "$name"
	fi
done < "$MAN"

if [ "$N" -eq 0 ]; then
	echo "Error: manifest lists no dumped partitions" >&2
	exit 2
fi

if [ "$FAIL" -ne 0 ] || [ "$MISSING" -ne 0 ]; then
	rm -f "$OUT/VERIFIED"
	echo
	echo "REFUSING: $FAIL mismatch(es), $MISSING unpullable, of $N listed." >&2
	echo "Do not flash or wipe until this is clean. Re-run 40 while still in recovery." >&2
	exit 2
fi

# Extra files on the device that the manifest does not describe are a smell.
for f in $($ADB shell "ls $SRC" 2>/dev/null | tr -d '\r' | grep '\.img$' || true); do
	grep -q "^$(echo "$f" | sed 's/\.img$//')	" "$MAN" || echo "warn: $f on device but not in manifest" >&2
done

{
	echo "verified_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
	echo "device=$DEV_SERIAL"
	echo "partitions=$N"
	echo "host=$(hostname 2>/dev/null)"
} > "$OUT/VERIFIED"

echo
echo "All $N partitions pulled and md5-verified. Marker: $OUT/VERIFIED"
echo "Keep at least one copy off this machine before flashing."
