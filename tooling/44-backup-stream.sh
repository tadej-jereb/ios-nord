#!/bin/bash
# Stream the critical partitions off the phone over adb, no on-device staging.
# Works from TWRP (adb is root there) or from a rooted Android, not from stock OOS.
#
#   tooling/44-backup-stream.sh            # critical set, excludes userdata/super
#   tooling/44-backup-stream.sh --super    # also super (6-8 GB, slow)
#
# Output: backup/<serial>/<partition>.img + sizes + md5 manifest.
set -uo pipefail
cd "$(dirname "$0")/.."
source tooling/env.sh 2>/dev/null || true

WITH_SUPER=0
[ "${1:-}" = "--super" ] && WITH_SUPER=1

[ "$(adb shell 'su -c id -u' 2>/dev/null | tr -d '\r')" = "0" ] || {
	echo "error: adb shell is not root (su -c id -u != 0); grant shell superuser in Magisk first" >&2
	exit 1
}
serial=$(adb get-serialno | tr -d '\r')
out="backup/$serial"
mkdir -p "$out"
echo "backing up to $out"

# lito keeps nearly all firmware partitions slotted (_a/_b); the unsuffixed names do not
# exist on this device, so both slots are dumped explicitly.
COMMON="persist modemst1 modemst2 fsg fsc misc
abl_a abl_b aop_a aop_b bluetooth_a bluetooth_b devcfg_a devcfg_b dsp_a dsp_b
hyp_a hyp_b keymaster_a keymaster_b multiimgoem qupfw_a qupfw_b tz_a tz_b
uefisecapp_a uefisecapp_b xbl_a xbl_b xbl_config_a xbl_config_b modem_a modem_b
boot_a boot_b dtbo_a dtbo_b vbmeta_a vbmeta_b vbmeta_system_a vbmeta_system_b"
[ "$WITH_SUPER" = 1 ] && COMMON="$COMMON super"

names=$(adb shell "su -c 'ls /dev/block/by-name/'" | tr -d '\r')
{
	echo "# backup manifest  serial=$serial  date=$(date -Is)"
	echo "# present partitions:"
	echo "$names" | sed 's/^/#   /'
} > "$out/MANIFEST.txt"

for p in $COMMON; do
	printf '%-18s' "$p"
	if ! echo "$names" | grep -qx "$p"; then
		echo "absent"; echo "absent $p" >> "$out/MANIFEST.txt"; continue
	fi
	size=$(adb shell "su -c 'blockdev --getsize64 /dev/block/by-name/$p 2>/dev/null'" | tr -d '\r')
	if [ -z "$size" ] || [ "$size" -le 0 ] 2>/dev/null; then echo "no size"; continue; fi
	adb exec-out "su -c 'dd if=/dev/block/by-name/$p bs=1M 2>/dev/null'" > "$out/$p.img"
	got=$(stat -c%s "$out/$p.img")
	if [ "$got" != "$size" ]; then
		echo "SHORT ($got of $size)"; echo "SHORT $p $got/$size" >> "$out/MANIFEST.txt"
	else
		md5=$(md5sum "$out/$p.img" | cut -d' ' -f1)
		echo "$size bytes md5 $md5"
		echo "$p $size $md5" >> "$out/MANIFEST.txt"
	fi
done

# also record the partition map and sizes of the skipped ones
adb shell "su -c 'ls -l /dev/block/by-name/'" 2>/dev/null | tr -d '\r' > "$out/BYNAME-LS.txt"
adb shell 'cat /proc/partitions' 2>/dev/null | tr -d '\r' > "$out/PARTITIONS.txt"

echo
echo "critical partitions done; userdata and super are excluded"
echo "now run: tooling/41-backup-pull.sh  (pulls and re-verifies against the manifest)"
