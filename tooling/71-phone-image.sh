#!/bin/bash
# 71-phone-image.sh — one command from a kernel to a bootable phone image.
#
#   tooling/71-phone-image.sh --preset gui
#   tooling/71-phone-image.sh --preset touch --kernel avicii/shim/out/kernel-0110c --boot
#   tooling/71-phone-image.sh --preset console --extra "sweetscan=SpringBoard" --name dbg1
#
# Does what was four hand-typed steps on 2026-11-14 (mkpayload.py ->
# mkbootimg_v1.sh -> --verify -> 70-phone-boot.sh), with the command lines that
# booted on the handset kept as presets so a bring-up flag cannot leak into a
# GUI image again (sweetfb_console=1 made AppleCLCD::present() drop every frame).
#
# Presets (root is always the 16 GiB HFSX volume on userdata, rd=ufsroot0):
#   gui      iOS GUI on the panel, console hidden once iOS presents; keys and
#            touch on (touch defaults need kernel 0110 as of 2026-11-14 evening:
#            L13 + 1.8 V enable, 5 s start; older kernels need the touch preset)
#   touch    gui + touch bring-up logging (45 s start, rails/1v8 explicit,
#            sweettouchdebug=1: log flushed after every step)
#   usb      gui + USB CDC-ECM gadget (sweetusb=2): 192.168.7.2 on the phone,
#            kernel log streamed as UDP to 192.168.7.1:5140
#   console  kernel + launchd console on the panel, no GUI frames (bring-up)
#   noinput  gui with touch and keys off
#
# --kernel   a kernel.development.sweet file or a directory holding one
#            (default: the newest avicii/shim/out/kernel-*/kernel.development.sweet)
# --extra    boot-args appended to the preset
# --name     output name: build/phone/ufsroot.<name>.img (default: <preset>-<kernel dir>)
# --boot     after building, boot it with tooling/70-phone-boot.sh (from recovery
#            on adb), or straight with `fastboot boot` if the phone is already in
#            the bootloader. Nothing is flashed in either case.
#
# Outputs: build/phone/ufsroot.<name>.img, .cmdline, .sha256 and the payload
# build/phone/payload-<name>.bin. Prints the image sha256 for docs/IMAGE_PROVENANCE.md.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo"

SERIAL=${SERIAL:-64f70df8}
ADT=${ADT:-avicii/adt/avicii-live.adt}
SHIM=${SHIM:-build/phone/shim-out-d0/Image.gz-dtb}   # DIAG_STAGE=0: jumps, does not park

COMMON="debug=0xc cpus=8 sweetsmp=1 keepsyms=1 -noprogress nointr_consio=1 rd=ufsroot0 ufsroot=userdata unentitled_ios_sim_launch=1 ignition_level=1 wdt_test=no_user_checkin ufsrw=1 rootrw=1 launchd_unsecure_cache=1 wdt=-1 sweetlog=1"
declare -A PRESET=(
	[gui]="$COMMON sweetfb_hz=30 sweetecon=1 sweetfb_noconsole=1 sweettouch=1 sweetkeys=1"
	[touch]="$COMMON sweetfb_hz=10 sweetecon=1 sweetfb_noconsole=1 sweettouch=1 sweettouchdelay=45 sweettouchrails=2 sweettouch1v8=1 sweettouchdebug=1 sweetkeys=1"
	[usb]="$COMMON sweetfb_hz=60 sweetecon=1 sweetfb_noconsole=1 sweettouch=1 sweetkeys=1 sweetusb=2"
	[console]="$COMMON sweetfb_console=1 sweetecon=1 sweettouch=0 sweetkeys=1 launchd_log_serial=1 sweetexeclog=1 -v"
	[noinput]="$COMMON sweetfb_hz=10 sweetecon=1 sweetfb_noconsole=1 sweettouch=0 sweetkeys=0"
)

preset=gui kernel="" extra="" name="" boot=0
while [ $# -gt 0 ]; do
	case $1 in
	--preset) preset=${2:?}; shift 2 ;;
	--kernel) kernel=${2:?}; shift 2 ;;
	--extra) extra=${2:?}; shift 2 ;;
	--name) name=${2:?}; shift 2 ;;
	--boot) boot=1; shift ;;
	-h|--help) sed -n '2,32p' "$0"; exit 0 ;;
	*) echo "error: unknown argument $1" >&2; exit 2 ;;
	esac
done

[ -n "${PRESET[$preset]+x}" ] || { echo "error: unknown preset '$preset' (${!PRESET[*]})" >&2; exit 2; }
if [ -z "$kernel" ]; then
	kernel=$(ls -td avicii/shim/out/kernel-*/kernel.development.sweet 2>/dev/null | head -1)
	[ -n "$kernel" ] || { echo "error: no avicii/shim/out/kernel-*/ kernel; pass --kernel" >&2; exit 2; }
fi
if [ -d "$kernel" ]; then
	# DEVELOPMENT build, else a RELEASE one (kernel.sweet)
	if [ -f "$kernel/kernel.development.sweet" ]; then kernel=$kernel/kernel.development.sweet; else kernel=$kernel/kernel.sweet; fi
fi
[ -f "$kernel" ] || { echo "error: no kernel at $kernel" >&2; exit 2; }
for f in "$ADT" "$SHIM"; do
	[ -f "$f" ] || { echo "error: missing $f" >&2; exit 2; }
done
if [ -f "$(dirname "$kernel")/SHA256SUMS" ]; then
	(cd "$(dirname "$kernel")" && sha256sum -c --ignore-missing --quiet SHA256SUMS) ||
		{ echo "error: $kernel does not match its SHA256SUMS" >&2; exit 3; }
fi

cmdline="${PRESET[$preset]}${extra:+ $extra}"
case $preset in
gui|touch|noinput)
	case " $cmdline " in
	*" sweetfb_console=1 "*) echo "error: sweetfb_console=1 in a GUI preset drops every iOS frame" >&2; exit 2 ;;
	esac ;;
esac
[ -n "$name" ] || name="$preset-$(basename "$(dirname "$kernel")")"
img=build/phone/ufsroot.$name.img
payload=build/phone/payload-$name.bin

python3 avicii/tools/mkpayload.py "$kernel" "$ADT" "$payload" --cmdline "$cmdline" >/dev/null
./avicii/tools/mkbootimg_v1.sh --kernel "$SHIM" --ramdisk "$payload" -o "$img" >/dev/null
./avicii/tools/mkbootimg_v1.sh --verify "$img" | tail -1
grep -qaF "$cmdline" "$img" || { echo "error: cmdline not found in $img" >&2; exit 4; }
echo "$cmdline" > "${img%.img}.cmdline"
sha256sum "$img" | tee "${img%.img}.sha256"
echo "kernel  $(sha256sum "$kernel" | cut -c1-64)  $kernel"
echo "preset  $preset"
echo "cmdline $cmdline"

[ "$boot" = 1 ] || exit 0
out=logs/phone/$(date -u +%Y%m%d-%H%M%S)-$name
mkdir -p "$out"
if [ -n "$(timeout 5 fastboot devices 2>/dev/null)" ]; then
	if [ "$(timeout 10 fastboot -s "$SERIAL" getvar is-userspace 2>&1 | sed -n 's/^is-userspace: //p')" = yes ]; then
		echo "phone is in fastbootd; moving to the bootloader"
		timeout 30 fastboot -s "$SERIAL" reboot bootloader
		sleep 8
	fi
	echo "== fastboot boot $(date -u +%H:%M:%S) ==" | tee "$out/boot.txt"
	timeout 300 fastboot -s "$SERIAL" boot "$img" 2>&1 | tee -a "$out/boot.txt"
else
	OUT=$out WAIT=20 ./tooling/70-phone-boot.sh --image "$img" --out "$out"
fi
echo "log dir $out"
