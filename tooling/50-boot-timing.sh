#!/bin/bash
# 50-boot-timing.sh - measure the time from ABL hand-off to the next USB
# appearance, in milliseconds, for one image at a time.
#
# The question it answers with numbers instead of impressions: is the ~6 s
# "crash" a fixed host-side refusal, or does our code actually run and then
# reset the phone? A refusal and a self-reset look identical on the bench; they
# do not look identical on a millisecond clock.
#
# What it does per run, in this order:
#   1. adb kill-server        (a live adb daemon grabs the port back the moment
#                              Android comes up and hides the fastboot device)
#   2. fastboot flash <slot> <image>
#   3. fastboot reboot, t0 taken when the USB node *disappears* (that is the
#      hand-off; the reboot command returning is 100-300 ms too early)
#   4. poll lsusb every 20 ms for the phone's serial, up to 90 s, and record the
#      first sighting as ms-since-handoff plus what kind of device it is
#
# Nothing here is destructive beyond `flash boot_b` (the fallback slot the
# project reserved for exactly this). Never `flash boot` unslotted.
#
#   tooling/50-boot-timing.sh --image out-telem/stage-6/shim-boot.img --runs 5
#   tooling/50-boot-timing.sh --control --runs 5        # untouched stock image
#   tooling/50-boot-timing.sh --image X --runs 1 --no-flash   # device is already
#                                                           # in fastboot, image flashed
# Exit: 0 all runs measured, 1 setup problem, 2 unexpected device state.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
FASTBOOT=${FASTBOOT:-fastboot}
ADB=${ADB:-adb}
SLOT=${SLOT:-boot_b}
RUNS=${RUNS:-3}
IMAGE=""
CONTROL=0
NOFLASH=0
TIMEOUT_MS=${TIMEOUT_MS:-90000}
OUTDIR=${OUTDIR:-$repo/out-telem/timing}

while [ $# -gt 0 ]; do
	case $1 in
	--image) IMAGE=${2:?--image needs a path}; shift 2 ;;
	--runs) RUNS=${2:?--runs needs a count}; shift 2 ;;
	--slot) SLOT=${2:?--slot needs a name}; shift 2 ;;
	--control) CONTROL=1; shift ;;
	--no-flash) NOFLASH=1; shift ;;
	--out) OUTDIR=${2:?--out needs a directory}; shift 2 ;;
	-h | --help) sed -n '2,30p' "$0"; exit 0 ;;
	*) echo "error: unknown argument $1" >&2; exit 1 ;;
	esac
done

command -v "$FASTBOOT" >/dev/null || { echo "error: $FASTBOOT not in PATH" >&2; exit 1; }
command -v lsusb >/dev/null || { echo "error: lsusb not in PATH (usbutils)" >&2; exit 1; }

if [ "$CONTROL" = 1 ]; then
	[ -n "$IMAGE" ] || IMAGE=$repo/src/los21-boot.img
fi
[ -n "$IMAGE" ] || { echo "error: --image or --control" >&2; exit 1; }
IMAGE=$(readlink -f "$IMAGE")
[ -f "$IMAGE" ] || { echo "error: no such image: $IMAGE" >&2; exit 1; }

# --- preconditions ---------------------------------------------------------
state=$("$FASTBOOT" devices 2>/dev/null | awk 'NF{print $1; exit}')
[ -n "$state" ] || { echo "error: device not in fastboot (fastboot devices is empty)" >&2; exit 2; }
SERIAL=$("$FASTBOOT" -s "$state" getvar serialno 2>&1 | sed -n 's/^serialno:[[:space:]]*//p' | tr -d '\r')
[ -n "$SERIAL" ] || { echo "error: could not read the device serial" >&2; exit 2; }
cur_slot=$("$FASTBOOT" -s "$state" getvar current-slot 2>&1 | sed -n 's/^current-slot:[[:space:]]*//p' | tr -d '\r')
if [ "$cur_slot" != "b" ]; then
	echo "warning: current-slot is '${cur_slot:-?}', not 'b' - the boot after the flash boots slot ${cur_slot:-?}" >&2
fi

# Image gate: every image this project flashes must pass --verify first.
if [ "$NOFLASH" = 0 ]; then
	if ! "$repo/avicii/tools/mkbootimg_v1.sh" --verify "$IMAGE" | tail -1 | grep -q '^PASS'; then
		echo "error: --verify does not PASS on $IMAGE (gate)" >&2
		exit 1
	fi
fi

sha=$(sha256sum "$IMAGE" | awk '{print $1}')
stamp=$(date -u +%Y%m%dT%H%M%SZ)
run_dir=$OUTDIR/$stamp
mkdir -p "$run_dir"
tsv=$run_dir/runs.tsv
printf 'run\tserial\tms_to_first_sighting\tkind\tproduct\tsha256\timage\n' >"$tsv"
cp -f "$IMAGE" "$run_dir/" 2>/dev/null || true
"$repo/avicii/tools/mkbootimg_v1.sh" --verify "$IMAGE" >"$run_dir/image.verify" 2>&1 || true
date -u +%FT%TZ >"$run_dir/started"
echo "$sha  $IMAGE" >"$run_dir/sha256"
echo "image  : $IMAGE"
echo "sha256 : $sha"
echo "serial : $SERIAL  slot $SLOT  runs $RUNS  timeout ${TIMEOUT_MS}ms"
echo "out    : $run_dir"

now_ms() { date +%s%3N; }
usb_line() { lsusb 2>/dev/null | grep -F "$SERIAL" | head -1; }

# --- one run ---------------------------------------------------------------
measure_once() {
	local run=$1 t0 t1 seen kind product
	"$ADB" kill-server >/dev/null 2>&1
	if [ "$NOFLASH" = 0 ]; then
		"$FASTBOOT" -s "$SERIAL" flash "$SLOT" "$IMAGE" >"$run_dir/flash-$run.log" 2>&1 \
			|| { echo "flash FAILED (run $run), see flash-$run.log"; return 1; }
	fi
	# Drop back to the ABL's own prompt so the reboot is from a known state.
	"$FASTBOOT" -s "$SERIAL" reboot >/dev/null 2>&1

	# t0 = the USB node disappearing. 5 s to go away, else give up on the run.
	local gone=0 deadline
	deadline=$(( $(now_ms) + 5000 ))
	while [ "$(now_ms)" -lt "$deadline" ]; do
		if [ -z "$(usb_line)" ]; then gone=1; break; fi
		sleep 0.02
	done
	t0=$(now_ms)
	if [ "$gone" = 0 ]; then
		echo "run $run: device never left USB (ABL stuck?), skipped"
		return 1
	fi

	deadline=$(( t0 + TIMEOUT_MS ))
	seen=""
	while [ "$(now_ms)" -lt "$deadline" ]; do
		seen=$(usb_line)
		[ -n "$seen" ] && break
		sleep 0.02
	done
	t1=$(now_ms)

	if [ -z "$seen" ]; then
		printf '%s\t%s\tNA\tno-sighting\t-\t%s\t%s\n' "$run" "$SERIAL" "$sha" "$(basename "$IMAGE")" >>"$tsv"
		echo "run $run: NO USB SIGHTING for ${TIMEOUT_MS}ms"
		return 0
	fi
	product=$(printf '%s' "$seen" | sed 's/.*ID [0-9a-f]*:[0-9a-f]* //')
	if printf '%s' "$seen" | grep -qi fastboot; then
		kind=fastboot
	elif "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
		kind=adb
	else
		kind=other
	fi
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$run" "$SERIAL" $(( t1 - t0 )) "$kind" "$product" "$sha" "$(basename "$IMAGE")" >>"$tsv"
	echo "run $run: first sighting after $(( t1 - t0 ))ms, kind=$kind"
}

for i in $(seq 1 "$RUNS"); do
	measure_once "$i" || true
	# Let the phone settle (or the park sit) before the next run: a fastboot
	# prompt means the ABL is back and ready for the next flash. A parked phone
	# never comes back on its own - say so instead of flashing into the void.
	ready=0
	for _ in $(seq 1 100); do
		"$FASTBOOT" devices 2>/dev/null | grep -q . && { ready=1; break; }
		sleep 0.1
	done
	if [ "$ready" = 0 ]; then
		echo
		echo "phone did not come back to fastboot after run $i (parked, or dead)."
		echo "That is a RESULT, not an error: power-cycle it and continue by hand."
		break
	fi
done

# --- summary ---------------------------------------------------------------
awk -F'	' 'NR>1 && $3 != "NA" { print $3 }' "$tsv" >"$run_dir/ms.txt"
if [ -s "$run_dir/ms.txt" ]; then
	sort -n "$run_dir/ms.txt" | awk '
		{a[NR] = $1; s += $1}
		END {
			printf "n=%d min=%d median=%d max=%d mean=%.0f\n", NR, a[1], a[int((NR+1)/2)], a[NR], s/NR
		}' | tee "$run_dir/summary"
	med=$(awk -F'[= ]' '{for (i = 1; i <= NF; i++) if ($i == "median") print $(i + 1)}' "$run_dir/summary")
	kind=$(awk -F'	' 'NR>1 && $4 != "no-sighting" { print $4 }' "$tsv" | sort | uniq -c | sort -rn | awk '{print $2; exit}')
	case "${med:-0}" in
	'') verdict="INDETERMINATE" ;;
	*)  if ! [ "$med" -ge 0 ] 2>/dev/null; then verdict="INDETERMINATE"
	    elif [ "$med" -lt 2500 ]; then verdict="REFUSED (ABL dropped the image fast; our code did not run)"
	    elif [ "$med" -lt 10000 ]; then verdict="RAN-AND-DIED (nothing parks at 2.5-10 s; the shim executed and reset)"
	    else verdict="BOOTED (something continued past 10 s: kind=$kind)"
	    fi ;;
	esac
	printf 'median %sms, sighting kind %s -> %s\n' "${med:-NA}" "${kind:-none}" "$verdict" | tee "$run_dir/verdict"
else
	echo "no run produced a sighting time (all runs parked or failed)" | tee "$run_dir/summary"
	echo "PARKED (>=${TIMEOUT_MS}ms with no USB sighting: the core never reset - code ran and parked)" | tee "$run_dir/verdict"
fi
echo
echo "interpret against docs/TIMING.md section 3. Record the summary and the sha256"
echo "in docs/IMAGE_PROVENANCE.md; the raw rows are $tsv."