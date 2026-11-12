#!/bin/bash
# 51-imem-read.sh - read and decode the shim's IMEM record from a normally
# booted, rooted phone.
#
# The record (avicii/shim/tel.h) is written by DIAG_STAGE>=6 images before
# anything else, and survives an ABL refusal because the ABL never touches
# IMEM+0xb00. Readback is the whole point of it, so this script is the readback:
# two physical reads, a decode table and an explicit verdict.
#
#   tooling/51-imem-read.sh                 # decode
#   tooling/51-imem-read.sh --raw           # hexdump only, no interpretation
#   tooling/51-imem-read.sh --addr 0x146abb00 --words 16
#
# Channel notes, in the order tried:
#   1. /dev/mem through dd            (works when CONFIG_STRICT_DEVMEM is off,
#                                      or when the range is not System RAM -
#                                      IMEM at 0x146ab000 is not in /proc/iomem
#                                      on this kernel, which is what makes it
#                                      likely to pass)
#   2. toybox devmem                  (same /dev/mem, per-word)
#   3. neither                        -> exit 3, "unreadable", which is itself
#                                      a result: write it down in
#                                      docs/IMAGE_PROVENANCE.md
#
# Nothing is written to the phone. Requires root (su); LineageOS 21 + Magisk is
# the log host slot this project keeps.
#
# Exit: 0 record decoded, 2 no device/root, 3 /dev/mem unreadable,
#       4 address reads back unstable.
set -uo pipefail

ADB=${ADB:-adb}
RR_ADDR=0x146ab65c    # restart_reason, the proven-but-consumable word
REC_ADDR=0x146abb00   # our record, 16 words
RAW=0

while [ $# -gt 0 ]; do
	case $1 in
	--raw) RAW=1; shift ;;
	--addr) REC_ADDR=$2; shift 2 ;;
	--words) shift 2 ;;
	--rr-addr) RR_ADDR=$2; shift 2 ;;
	-h | --help) sed -n '2,30p' "$0"; exit 0 ;;
	*) echo "error: unknown argument $1" >&2; exit 1 ;;
	esac
done

command -v "$ADB" >/dev/null || { echo "error: adb not in PATH" >&2; exit 1; }
SERIAL=${ANDROID_SERIAL:-}
[ -n "$SERIAL" ] || SERIAL=$("$ADB" devices | awk 'NR>1 && $2=="device"{print $1; exit}')
[ -n "$SERIAL" ] || { echo "error: no adb device (phone must be booted normally)" >&2; exit 2; }

su_() { "$ADB" -s "$SERIAL" shell "su -c '$1'" 2>/dev/null | tr -d '\r'; }
su_ 'id -u' | grep -qx 0 || { echo "error: no root on the device (su)" >&2; exit 2; }

# tval -> decimal, from 0x... form
dec() { printf '%d' "$1"; }

# Raw passthrough: no tr here, a 0x0d byte in memory would be eaten.
raw_() { "$ADB" -s "$SERIAL" shell "su -c '$1'" 2>/dev/null; }

word() {  # word <addr>  -> decimal value of 4 bytes, or empty
	local a; a=$(dec "$1")
	raw_ "dd if=/dev/mem bs=4 skip=$(( a / 4 )) count=1" | od -An -tu4 | tr -s ' ' | sed 's/^ //;s/ $//'
}

MAGIC=$((0x4c455431))
TEL_OK=$((0x600d))

probe() {
	local a v1 v2
	a=$(dec "$1")
	v1=$(raw_ "dd if=/dev/mem bs=4 skip=$(( a / 4 )) count=1" | wc -c)
	[ "$v1" = 4 ] || return 1           # 0 bytes = open/mmap refused
	v1=$(word "$1"); v2=$(word "$1")
	[ -n "$v1" ] && [ "$v1" = "$v2" ] || return 2
	return 0
}

if [ "$RAW" = 1 ]; then
	su_ "dd if=/dev/mem bs=4 skip=$(( $(dec "$REC_ADDR") / 4 )) count=16" | od -An -tx4
	exit 0
fi

# --- probe the channel before claiming anything ----------------------------
probe "$REC_ADDR"
case $? in
	0) ;;
	2) echo "UNREADABLE: $REC_ADDR reads back unstable (twice, different)"; exit 4 ;;
	*) echo "UNREADABLE: /dev/mem refused at $REC_ADDR."
	   echo "  CONFIG_STRICT_DEVMEM is probably on, or su is not real root."
	   echo "  Try: adb shell su -c 'toybox devmem $REC_ADDR'"
	   echo "  Or pull the region from the TWRP slot instead."
	   exit 3 ;;
esac

rr=$(word "$RR_ADDR")
w0=$(word "$REC_ADDR")
w1=$(word $(( $(dec "$REC_ADDR") + 4 )))
w2=$(word $(( $(dec "$REC_ADDR") + 8 )))
w3=$(word $(( $(dec "$REC_ADDR") + 12 )))
lo=$(word $(( $(dec "$REC_ADDR") + 16 )))
hi=$(word $(( $(dec "$REC_ADDR") + 20 )))
t0=$(word $(( $(dec "$REC_ADDR") + 24 )))
w7=$(word $(( $(dec "$REC_ADDR") + 28 )))
r0=$(word $(( $(dec "$REC_ADDR") + 32 )))
r1=$(word $(( $(dec "$REC_ADDR") + 36 )))
r2=$(word $(( $(dec "$REC_ADDR") + 40 )))
r3=$(word $(( $(dec "$REC_ADDR") + 44 )))
r4=$(word $(( $(dec "$REC_ADDR") + 48 )))
r5=$(word $(( $(dec "$REC_ADDR") + 52 )))
alive=$(word $(( $(dec "$REC_ADDR") + 56 )))
w15=$(word $(( $(dec "$REC_ADDR") + 60 )))

hx() { printf '0x%08x' "$1"; }

echo "restart_reason : $(hx "$rr")"
if [ "$w0" != "$MAGIC" ]; then
	echo "record magic   : $(hx "$w0")  -> NO RECORD (this SMEM word was not written by a DIAG_STAGE>=6 image)"
	echo
	echo "VERDICT: NO EVIDENCE. Either the image never ran, or it ran a build below stage 6."
	exit 0
fi

echo "record magic   : 0x4c455431 \"1TEL\"  OK"
echo "stage compiled : $w1"
echo "marks          : $w2"
printf 'last code      : %s\n' "$(hx "$w3")"
if [ "$w7" = "$TEL_OK" ]; then
	echo "self-check     : 0x600d OK (record read back exactly as written while running)"
else
	echo "self-check     : $(hx "$w7") (0xdead = write/readback mismatch; the address is suspect)"
fi
printf 'load base      : 0x%08x%08x\n' "$hi" "$lo"
printf 't0 ticks       : %s\n' "$t0"
printf 'alive ms       : %s (ticks word %s)\n' "$w15" "$alive"
printf 'results        : gpio_ctl=%s spmi_ver=%s pmic=%s i2c=%s apid_en=%s\n' \
	"$(hx "$r0")" "$(hx "$r2")" "$(hx "$r3")" "$(hx "$r4")" "$(hx "$r5")"

case "$w3" in
 1536) name="S6 begin" ;;
 1537) name="S6 magic written" ;;
 1538) name="S6 self-check" ;;
 1539) name="S6 verified" ;;
 1540) name="S6 console clear" ;;
 1541) name="S6 done, ring/console next" ;;
 1792) name="S7 begin" ;;
 1793) name="S7 gpio ctl" ;;
 1794) name="S7 gpio pattern" ;;
 1795) name="S7 gpio released" ;;
 1796) name="S7 spmi begin" ;;
 1797) name="S7 spmi version" ;;
 1798) name="S7 spmi ppid map" ;;
 1799) name="S7 pm8150l revid" ;;
 1800) name="S7 pm7250b revid" ;;
 1801) name="S7 panel reset pulse" ;;
 1802) name="S7 done" ;;
 2048) name="S8 begin" ;;
 2049) name="S8 pins" ;;
 2050) name="S8 clocks" ;;
 2051) name="S8 geni" ;;
 2052) name="S8 reset pulse" ;;
 2053) name="S8 id read" ;;
 2054) name="S8 soft reset" ;;
 2055|2056|2057) name="S8 buzz" ;;
 2063) name="S8 done" ;;
 *) name="(unknown code)" ;;
esac
echo "last step      : $name"
echo
if [ "$w7" = "$TEL_OK" ] && [ "${w2:-0}" -gt 0 ] 2>/dev/null; then
	printf 'VERDICT: CODE RAN. IMEM record present and self-verified, at load base 0x%08x%08x,\n' "$hi" "$lo"
	echo "         last step \"$name\" after about $w15 ms alive."
else
	echo "VERDICT: record present but not self-verified - trust the address, not the content."
fi
