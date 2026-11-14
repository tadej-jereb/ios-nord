#!/bin/bash
# 70-phone-boot.sh — boot one payload image on the real avicii, read the ring back.
#
#   tooling/70-phone-boot.sh --image build/phone/rd-root.phone.img
#   tooling/70-phone-boot.sh --image ... --reboot-only      # leave the phone in fastboot
#   tooling/70-phone-boot.sh --pull                          # ring pull only (phone in adb)
#
# Non-destructive by construction: `adb reboot bootloader` and `fastboot boot` only.
# No `fastboot flash`, no erase, no dd, no partition write. boot_a/boot_b are never
# named; `fastboot boot` runs the image from RAM and nothing is persisted but the ring
# the iOS kernel writes itself.
#
# The gate is the same one lane 6 used by hand: image bytes <= `fastboot getvar
# max-download-size`. On this unit max-download-size is 805306368 (768 MiB) and the
# packer pads to the 96 MiB boot partition, so a payload of up to ~700 MiB passes.
#
# Ring: before the boot the phone must be on adb (recovery/adbd is uid 0, no su
# needed; a Magisk ROM goes through su). After `fastboot boot` the kernel may take
# USB down entirely — this script polls for adb/fastboot for --wait seconds and then
# says so; a power-cycle back to recovery is the documented way to read the ring
# afterwards (the ring lives in the last 4100 KiB of userdata and survives).
#
# --recover closes the loop for you: the ABL fallback returns the phone in fastboot
# after ~2 min, `fastboot reboot recovery` restores recovery in ~12 s, and recovery's
# adbd may ask for the RSA key on the panel (`unauthorized` = waiting for a tap).
set -uo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
SERIAL=${SERIAL:-64f70df8}
ADB="adb -s $SERIAL"
FB="fastboot -s $SERIAL"
IMG=""
WAIT=${WAIT:-90}
SETTLE=${SETTLE:-20}
PULL=0
RECOVER=0
REBOOT_ONLY=0
STAMP=$(date -u '+%Y%m%d-%H%M%S')
OUT=${OUT:-$repo/logs/phone/$STAMP}

while [ $# -gt 0 ]; do
	case $1 in
	--image) IMG=$2; shift 2 ;;
	--wait) WAIT=$2; shift 2 ;;
	--out) OUT=$2; shift 2 ;;
	--pull) PULL=1; shift ;;
	--recover) RECOVER=1; shift ;;
	--reboot-only) REBOOT_ONLY=1; shift ;;
	-h|--help) sed -n '2,27p' "$0"; exit 0 ;;
	*) echo "error: unknown argument $1" >&2; exit 2 ;;
	esac
done
mkdir -p "$OUT"

pull_ring() {   # $1 = tag
	"$repo/tooling/42-log-pull.sh" -s "$SERIAL" --keep-bin -o "$OUT/ring-$1.txt" \
		> "$OUT/ring-$1.stdout" 2> "$OUT/ring-$1.stderr"
	local rc=$?
	echo "ring-$1: exit $rc -> $OUT/ring-$1.txt"
	[ -f "$OUT/ring-$1.txt" ] && tail -n 3 "$OUT/ring-$1.txt"
	return $rc
}

if [ "$PULL" = 1 ]; then
	pull_ring post; exit $?
fi

[ -n "$IMG" ] || { echo "error: --image required" >&2; exit 2; }
[ -f "$IMG" ] || { echo "error: no image at $IMG" >&2; exit 2; }

echo "== ring before =="
pull_ring pre || echo "   (no ring read; not fatal, noted)"

echo "== adb -> bootloader =="
timeout 60 $ADB reboot bootloader || { echo "error: adb reboot failed" >&2; exit 3; }
for i in $(seq 1 25); do
	sleep 2
	if [ -n "$(timeout 8 fastboot devices 2>/dev/null)" ]; then break; fi
done
dev=$(timeout 8 fastboot devices 2>/dev/null | head -1)
[ -n "$dev" ] || { echo "error: no fastboot device after 2 tries of 25x2 s" >&2; exit 4; }
echo "fastboot: $dev"

echo "== device facts =="
for v in current-slot max-download-size product unlocked version-bootloader; do
	timeout 20 $FB getvar "$v" 2>&1 | head -1
done | tee "$OUT/getvars.txt"

max=$(timeout 20 $FB getvar max-download-size 2>&1 | sed -n 's/^max-download-size: *//p' | tr -d '\r')
size=$(stat -c %s "$IMG")
echo "image $IMG: $size bytes, max-download-size ${max:-?}" | tee "$OUT/gate.txt"
case ${max:-} in ''|*[!0-9]*) echo "error: could not read max-download-size" >&2; exit 5 ;; esac
[ "$size" -le "$max" ] || { echo "error: image is larger than max-download-size" >&2; exit 5; }
echo "gate: PASS ($((max - size)) bytes headroom)" | tee -a "$OUT/gate.txt"

[ "$REBOOT_ONLY" = 1 ] && { echo "left in fastboot as asked"; exit 0; }

echo "== fastboot boot $(date -u +%H:%M:%S) =="
echo "cmd: fastboot -s $SERIAL boot $IMG" | tee "$OUT/boot-command.txt"
timeout 300 $FB boot "$IMG" 2>&1 | tee "$OUT/fastboot-boot.txt"
rc=${PIPESTATUS[0]}
[ "$rc" = 0 ] || { echo "error: fastboot boot exited $rc"; exit 6; }
sha256sum "$IMG" | tee "$OUT/image.sha256"

# The bootloader's USB interface lingers for a moment after `Booting OKAY`, so a
# poll started immediately reads fastboot and calls a live kernel "back in fastboot".
echo "== settling ${SETTLE}s before polling =="
sleep "$SETTLE"

wait_adb() {	# $1 = seconds
	local end=$(( $(date +%s) + $1 )) st
	while [ "$(date +%s)" -lt "$end" ]; do
		st=$(timeout 6 adb devices 2>/dev/null | sed -n 2p)
		case "$st" in
		*unauthorized*) echo "   adb: unauthorized — tap Allow on the panel" >&2 ;;
		*device*) echo "adb back: $st"; return 0 ;;
		esac
		sleep 5
	done
	return 1
}

echo "== waiting up to ${WAIT}s for adb =="
if wait_adb "$WAIT"; then pull_ring post; exit $?; fi

if [ "$RECOVER" = 1 ]; then
	echo "== no adb; waiting up to 240s for the ABL fallback (fastboot) =="
	for i in $(seq 1 48); do
		if [ -n "$(timeout 8 fastboot devices 2>/dev/null)" ]; then
			echo "fastboot back at $(date -u +%H:%M:%S); rebooting into recovery"
			timeout 60 $FB reboot recovery || true
			echo "== waiting up to 180s for recovery adb =="
			if wait_adb 180; then pull_ring post; exit $?; fi
			echo "error: recovery adb not back (screen may be asking for the RSA key)" >&2
			exit 9
		fi
		sleep 5
	done
	echo "error: neither adb nor fastboot came back; the phone is still in the kernel" >&2
	exit 8
fi

if [ -n "$(timeout 6 fastboot devices 2>/dev/null)" ]; then
	echo "phone is back in fastboot, not adb (use --recover to loop it into recovery)"
	exit 7
fi
echo "no adb and no fastboot after ${WAIT}s: the phone is in the kernel (or hung there)."
echo "ring is unwritten-to-disk until the next power-cycle; power it off/on into recovery,"
echo "then: tooling/70-phone-boot.sh --pull --out $OUT"
exit 8
