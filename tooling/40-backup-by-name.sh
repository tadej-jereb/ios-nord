#!/system/bin/sh
# 40-backup-by-name.sh — read-only dump of every by-name partition except
# userdata and super, with md5 per file and a manifest.
#
# Runs ON THE DEVICE (TWRP / adb root), pushed and invoked from the host:
#   adb push tooling/40-backup-by-name.sh /sdcard/
#   adb shell sh /sdcard/40-backup-by-name.sh
# Then pull and verify on the host with tooling/41-backup-pull.sh.
#
# Never writes to a partition. Output goes to /sdcard/backup (inside
# userdata, which is why userdata itself can only be recorded, not dumped).
#
# Exit: 0 ok, 1 no by-name dir, 2 not root, 3 not enough space.

set -u

case ${1:-} in
-h|--help) sed -n '2,13p' "$0"; exit 0 ;;
esac

BYNAME=${BYNAME:-/dev/block/by-name}
[ -d "$BYNAME" ] || BYNAME=/dev/block/bootdevice/by-name
if [ ! -d "$BYNAME" ]; then
	echo "FATAL: no by-name directory (tried /dev/block/by-name and" >&2
	echo "       /dev/block/bootdevice/by-name). Not booted into a recovery?" >&2
	exit 1
fi

UID_NOW=$(id -u 2>/dev/null || echo 3003)
if [ "$UID_NOW" != "0" ] && [ "${ALLOW_NONROOT:-0}" != "1" ]; then
	echo "FATAL: shell is uid $UID_NOW, need root. Run 'adb root' first" >&2
	echo "       (TWRP and OrangeFox adbd are root by default)." >&2
	exit 2
fi

OUT=${OUT:-/sdcard/backup}
mkdir -p "$OUT" || { echo "FATAL: cannot create $OUT" >&2; exit 1; }
MAN="$OUT/manifest.tsv"
INFO="$OUT/device.txt"
NOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)

# Record what the device is, so a later restore knows where these came from.
{
	echo "collected_utc=$NOW"
	echo "device=$(getprop ro.product.device 2>/dev/null)"
	echo "model=$(getprop ro.product.model 2>/dev/null)"
	echo "fingerprint=$(getprop ro.build.fingerprint 2>/dev/null)"
	echo "slot=$(getprop ro.boot.slot_suffix 2>/dev/null)"
	echo "kernel=$(uname -a 2>/dev/null)"
	echo "byname=$BYNAME"
} > "$INFO" 2>/dev/null

printf 'name\tsize_bytes\tmd5\tdevnode\tstatus\n' > "$MAN"

# userdata and super are recorded but not dumped:
#   userdata -> hundreds of GB, and the iOS root will replace its contents
#   super    -> ~14 GB of dynamic partitions, re-creatable by flashing the ROM
SKIP_NAMES="userdata super"

is_skipped() {
	for s in $SKIP_NAMES; do
		[ "$1" = "$s" ] && return 0
	done
	return 1
}

# A readable size for a block device, without blockdev if toybox lacks it.
dev_size() {
	sz=$(blockdev --getsize64 "$1" 2>/dev/null)
	if [ -z "${sz:-}" ] || [ "$sz" = 0 ] 2>/dev/null; then
		b=$(basename "$(readlink -f "$1" 2>/dev/null || echo x)")
		if [ -r "/sys/class/block/$b/size" ]; then
			sz=$(( $(cat "/sys/class/block/$b/size") * 512 ))
		elif [ -f "$1" ]; then
			# regular file (host-side dry runs)
			sz=$(wc -c < "$1" 2>/dev/null | tr -d ' ')
		fi
	fi
	case ${sz:-} in ''|*[!0-9]*) sz=0 ;; esac
	echo "$sz"
}

# Pass 1: total size, and a hard failure if most names have no size at all.
TOTAL=0
COUNT=0
for p in "$BYNAME"/*; do
	[ -e "$p" ] || continue
	is_skipped "$(basename "$p")" && continue
	sz=$(dev_size "$p")
	if [ "$sz" -gt 0 ] 2>/dev/null; then
		TOTAL=$((TOTAL + sz))
		COUNT=$((COUNT + 1))
	else
		echo "skip $(basename "$p"): size unreadable" >&2
	fi
done
[ "$COUNT" -gt 0 ] || { echo "FATAL: no sized partitions found under $BYNAME" >&2; exit 1; }

# Free space on /sdcard (df reports kilobytes in field 4).
AVAIL_K=$(df -k "$OUT" 2>/dev/null | awk 'NR==2{print $4}')
AVAIL=$(( ${AVAIL_K:-0} * 1024 ))
printf 'plan: %s partitions, %s bytes needed, %s bytes free in %s\n' \
	"$COUNT" "$TOTAL" "$AVAIL" "$OUT"
if [ "$AVAIL" -gt 0 ] && [ "$TOTAL" -gt "$AVAIL" ]; then
	echo "FATAL: not enough space on /sdcard; free ~$((TOTAL / 1048576 + 64)) MiB" >&2
	exit 3
fi

# Pass 2: dump + hash.
for p in "$BYNAME"/*; do
	[ -e "$p" ] || continue
	n=$(basename "$p")
	is_skipped "$n" && continue
	sz=$(dev_size "$p")
	[ "$sz" -gt 0 ] 2>/dev/null || continue

	img="$OUT/$n.img"
	printf '  %-24s %12s bytes ... ' "$n" "$sz"
	if ! dd if="$p" of="$img" bs=1048576 2>/dev/null; then
		printf 'DD FAILED\n'
		continue
	fi
	# dd ends on a short final block; make the file the exact device size.
	truncate -s "$sz" "$img" 2>/dev/null || true
	got=$(wc -c < "$img" 2>/dev/null | tr -d ' ')
	md5=$(md5sum "$img" 2>/dev/null | cut -d' ' -f1)
	if [ "${got:-0}" != "$sz" ] || [ -z "${md5:-}" ]; then
		printf 'SHORT/MD5 FAILED (%s bytes)\n' "${got:-0}"
		continue
	fi
	printf '%s\n' "$md5"
	printf '%s\t%s\t%s\t%s\tdumped\n' "$n" "$sz" "$md5" "$(readlink -f "$p")" >> "$MAN"
done

# Skipped ones, recorded with size so the slot layout is still visible.
for s in $SKIP_NAMES; do
	p="$BYNAME/$s"
	[ -e "$p" ] || continue
	printf '%s\t%s\t-\t%s\tskipped-recorded-only\n' "$s" "$(dev_size "$p")" \
		"$(readlink -f "$p")" >> "$MAN"
done

printf '# persisted, modemst1, modemst2, fsg, fsc, xbl*, abl*, tz* carry\n' >> "$MAN"
printf '# per-device data: never restore these onto another handset.\n' >> "$MAN"

echo
echo "=== manifest: $MAN ==="
cat "$MAN"
echo
echo "dumped $(grep -c 'dumped$' "$MAN") partitions; recorded-only: $(grep -c 'recorded-only' "$MAN")"
echo "Next: tooling/41-backup-pull.sh (host side, verifies md5)"
