#!/usr/bin/env bash
# dump-live.sh — collect every avicii hardware constant that only exists on the
# running device, into one timestamped directory, then hash the lot.
#
# Why: /home/tadej/ios-nord/avicii/CONSTANTS.md marks a handful of values as
# live-only (RAM split, touch IC, panel model, board id, CPU bins, ICE state).
# Guessing any of them boots "almost" and fails silently. Run this first,
# before the first payload.
#
# Usage:   ./dump-live.sh                 (ANDROID_SERIAL honoured if set)
#          OUT=/some/dir ./dump-live.sh   (override output root)
# Requires: adb, device rooted (adb root / su), unlocked bootloader.
# Output:  $OUT/run-YYYYmmdd-HHMMSS/  + MD5SUMS
# Notes:   read-only. Nothing is written to the device. Run from a TWRP
#          `/adb shell` if the ROM has no su.

set -u

ADB="${ADB:-adb}"
OUT="${OUT:-/home/tadej/ios-nord/logs/dumps}"
STAMP="$(date +%Y%m%d-%H%M%S)"
RUN="$OUT/run-$STAMP"

# ---------------------------------------------------------------- preflight
mkdir -p "$RUN" || { echo "cannot create $RUN" >&2; exit 1; }

if ! command -v "$ADB" >/dev/null 2>&1; then
	echo "adb not found in PATH" >&2
	exit 1
fi

if [ -z "$("$ADB" get-serialno 2>/dev/null | tr -d '\r\n' | sed 's/^unknown$//')" ]; then
	echo "no device on adb" >&2
	exit 1
fi

UID_DEV="$("$ADB" shell id -u 2>/dev/null | tr -d '\r\n')"
echo "device uid: '${UID_DEV}'"
if [ "$UID_DEV" != "0" ]; then
	echo "NOT root (uid=$UID_DEV). Run 'adb root' (or use TWRP / adb shell su) and retry." >&2
	exit 2
fi

SERIAL="$("$ADB" get-serialno | tr -d '\r\n')"
echo "device: $SERIAL  ->  $RUN"
printf '%s\n' "$SERIAL" >"$RUN/00-serial.txt"
printf '%s\n' "$STAMP" >"$RUN/00-stamp.txt"

# shell capture (text), via /bin/sh on the device
sh_() { "$ADB" shell "$1" >"$RUN/$2" 2>&1; }
# raw capture (binary-safe, no CRLF translation)
raw_() { "$ADB" exec-out "cat $1" >"$RUN/$2" 2>/dev/null; }

# ------------------------------------------------------- identity / build
sh_ 'uname -a' 01-uname.txt
sh_ 'getprop ro.product.device' 01-device.txt
sh_ 'getprop ro.boot.project_name' 01-project.txt
sh_ 'getprop ro.boot.hardware' 01-hardware.txt
sh_ 'getprop ro.boot.hardware.sku' 01-hw-sku.txt
sh_ 'getprop ro.build.fingerprint' 01-fingerprint.txt
sh_ 'getprop ro.boot.baseband' 01-baseband.txt
sh_ 'getprop ro.boot.verifiedbootstate' 01-vbstate.txt
sh_ 'getprop' 01-getprop-all.txt
sh_ 'cat /proc/sys/kernel/random/boot_id' 01-bootid.txt
sh_ 'cat /proc/uptime' 01-uptime.txt

# --------------------------------------------------------- device tree (truth)
raw_ /sys/firmware/fdt 10-fdt.dtb
sh_ 'od -An -tx4 /proc/device-tree/memory/reg' 10-memory-reg-hex.txt
raw_ /proc/device-tree/memory/reg 10-memory-reg.bin
sh_ 'od -An -tx4 /proc/device-tree/qcom,board-id' 10-board-id-hex.txt
sh_ 'od -An -tx4 /proc/device-tree/qcom,msm-id' 10-msm-id-hex.txt
raw_ /proc/device-tree/model 10-model.txt
sh_ 'tr -d "\0" < /proc/device-tree/compatible' 10-compatible.txt
sh_ 'ls -l /proc/device-tree/' 10-dt-root-list.txt
sh_ 'ls -l /proc/device-tree/reserved-memory/' 10-dt-reserved-list.txt
sh_ 'cat /proc/device-tree/reserved-memory/*/reg | od -An -tx4' 10-dt-reserved-reg-hex.txt
sh_ 'ls -d /proc/device-tree/soc/*mdss_dsi*' 10-dt-dsi-nodes.txt
sh_ 'ls -d /proc/device-tree/soc/*ufs*' 10-dt-ufs-nodes.txt
sh_ 'ls -d /proc/device-tree/soc/*i2c@984000*' 10-dt-se7-node.txt
sh_ 'ls -l /proc/device-tree/soc/*i2c@984000*' 10-dt-se7-children.txt

# ------------------------------------------------------------ RAM / memory
sh_ 'cat /proc/iomem' 20-iomem.txt
sh_ 'cat /proc/meminfo' 20-meminfo.txt
sh_ 'cat /proc/cmdline' 20-cmdline.txt
sh_ 'cat /sys/devices/system/memory/*/state' 20-memory-block-state.txt
sh_ 'ls /sys/devices/system/memory/' 20-memory-blocks.txt
sh_ 'cat /proc/zoneinfo' 20-zoneinfo.txt

# ------------------------------------------------------------ partitions / UFS
sh_ 'ls -l /dev/block/by-name' 30-by-name.txt
sh_ 'ls -l /dev/block/platform/soc/1d84000.ufshc/by-name' 30-by-name-ufshc.txt
sh_ 'cat /proc/partitions' 30-partitions.txt
sh_ 'ls -l /dev/block/bootdevice/by-name' 30-by-name-bootdevice.txt
sh_ 'cat /sys/class/scsi_host/host0/../../*/ufs*/.. 2>/dev/null' 30-ufs-attr-probe.txt
sh_ 'find /sys/devices -maxdepth 6 -name "*ufs*" -type d' 30-ufs-sysfs-dirs.txt
sh_ 'cat /sys/devices/platform/soc/*ufs*/lanes_per_direction 2>/dev/null' 30-ufs-lanes.txt
sh_ 'cat /proc/mounts' 30-mounts.txt

# ------------------------------------------------------------------- panel
sh_ 'cat /sys/class/graphics/fb0/name' 40-fb0-name.txt
sh_ 'cat /sys/class/graphics/fb0/modes' 40-fb0-modes.txt
sh_ 'cat /sys/class/graphics/fb0/virtual_size' 40-fb0-vsize.txt
sh_ 'ls -l /sys/class/drm/' 40-drm-list.txt
sh_ 'cat /sys/class/drm/card0-DSI-1/modes' 40-drm-modes.txt
sh_ 'cat /sys/class/drm/card0-DSI-1/status' 40-drm-status.txt
sh_ 'cat /sys/class/drm/card0-DSI-1/enabled' 40-drm-enabled.txt
sh_ 'ls -d /proc/device-tree/soc/*mdss_dsi*/*/*' 40-dt-panel-nodes.txt
sh_ 'grep -a -o -E "ams[0-9a-z]+|sw[0-9]{5}|ss[0-9a-f]{2,}|samsung|tianma|boe|visionox" /proc/device-tree/soc/*mdss_dsi*/*/*/compatible' 40-dt-panel-compat.txt
sh_ 'cat /sys/class/backlight/*/max_brightness' 40-backlight-max.txt
sh_ 'cat /sys/class/backlight/*/actual_brightness' 40-backlight-cur.txt
sh_ 'dmesg | grep -iE "panel|dsi|mdss|ams644|sw43404"' 40-dmesg-panel.txt

# ------------------------------------------------------------------- touch
sh_ 'ls -l /sys/bus/i2c/devices/' 50-i2c-devices.txt
sh_ 'for f in /sys/bus/i2c/devices/*/name; do echo "$f $(cat $f 2>/dev/null)"; done' 50-i2c-names.txt
sh_ 'cat /sys/bus/i2c/devices/*/name' 50-i2c-names-raw.txt
sh_ 'ls -l /sys/bus/i2c/devices/4-0049/' 50-i2c-4-0049.txt
sh_ 'ls -l /sys/bus/i2c/devices/4-005d/' 50-i2c-4-005d.txt
sh_ 'cat /sys/class/input/*/name' 50-input-names.txt
sh_ 'dmesg | grep -iE "fts|goodix|gt9886|gt885|touch|synaptics"' 50-dmesg-touch.txt
sh_ 'ls -l /proc/device-tree/soc/*i2c@984000*/' 50-dt-se7-all.txt

# -------------------------------------------------------------------- keys
sh_ 'cat /sys/class/input/*/capabilities/key' 60-input-keys.txt
sh_ 'ls -l /sys/class/input/' 60-input-list.txt
sh_ 'ls -l /proc/device-tree/soc/*spmi*/*/*/*' 60-dt-spmi-children.txt
sh_ 'cat /sys/class/regulator/*/name' 60-regulator-names.txt
sh_ 'for r in /sys/class/regulator/*; do echo "$r $(cat $r/name 2>/dev/null) $(cat $r/microvolts 2>/dev/null)"; done' 60-regulator-state.txt
sh_ 'ls -l /proc/device-tree/soc/qcom,spmi@c440000' 60-dt-spmi.txt

# ------------------------------------------------------------- CPU / clocks
sh_ 'for p in /sys/devices/system/cpu/cpufreq/policy*; do echo "$p $(cat $p/scaling_max_freq 2>/dev/null) $(cat $p/cpuinfo_max_freq 2>/dev/null) $(cat $p/scaling_governor 2>/dev/null)"; done' 70-cpufreq-policies.txt
sh_ 'cat /proc/cpuinfo' 70-cpuinfo.txt
sh_ 'cat /sys/devices/system/cpu/possible' 70-cpu-possible.txt
sh_ 'cat /sys/devices/system/cpu/present' 70-cpu-present.txt
sh_ 'cat /sys/devices/system/cpu/cpu*/topology/core_id' 70-core-ids.txt
sh_ 'cat /sys/devices/system/cpu/cpu*/topology/physical_package_id' 70-package-ids.txt
sh_ 'ls -d /proc/device-tree/cpus/cpu@*' 70-dt-cpu-nodes.txt
sh_ 'cat /proc/interrupts' 70-interrupts.txt
sh_ 'cat /proc/softirqs' 70-softirqs.txt
sh_ 'ls -l /proc/device-tree/soc/interrupt-controller@17a00000' 70-dt-gic.txt

# ------------------------------------------------------------ WLAN / SPMI misc
sh_ 'ls /sys/module/' 80-modules.txt
sh_ 'cat /sys/bus/platform/devices/*icnss*/uevent 2>/dev/null' 80-icnss.txt
sh_ 'ls /sys/bus/platform/devices/' 80-platform-devices.txt
sh_ 'cat /proc/devices' 80-devices.txt
sh_ 'cat /proc/version' 80-version.txt

# ------------------------------------------------------------- hash + index
( cd "$RUN" && md5sum ./* >MD5SUMS 2>/dev/null )
echo "files: $(ls -1 "$RUN" | wc -l)  dir: $RUN"
echo "next: dtc -I dtb -O dts $RUN/10-fdt.dtb  (compare against avicii/CONSTANTS.md)"
exit 0
