#!/bin/bash
# Build the whole avicii diag ladder and verify every rung's boot image.
#
#   ./build-diag.sh                 # rungs 1-8 + read-only rungs 1-2, verify all
#   ./build-diag.sh -s "1 2"        # only these rungs
#   ./build-diag.sh --no-ro         # skip the DIAG_LOG=0 (write-nothing) pair
#
# Every rung is the real thing: real board DTB appended, header v1, verified
# with ../tools/mkbootimg_v1.sh --verify afterwards. A rung that does not
# verify stops the run.
#
# Stage 1 and 2 are also built with DIAG_LOG=0 ("ro1", "ro2"): the ladder's
# ring writes 4 MiB into the tail of userdata, and the read-only pair is what
# to boot first if you do not want that yet.
#
# Output: out-diag/stage-N/shim-boot.img and out-diag/SHA256SUMS.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
cd "$here"

DTB=${DTB:-$repo/src/avicii-board.dtb}
OUTDIR=${OUTDIR:-$here/out-diag}
STAGES="1 2 3 4 5 6 7 8"
RO=1

while [ $# -gt 0 ]; do
	case $1 in
	-s) STAGES=${2:?}; shift 2 ;;
	--no-ro) RO=0; shift ;;
	-h|--help) sed -n '2,18p' "$0"; exit 0 ;;
	*) echo "error: unknown argument $1" >&2; exit 1 ;;
	esac
done

[ -f "$DTB" ] || { echo "error: no board DTB at $DTB (set DTB=)" >&2; exit 1; }
[ -f ../../tooling/env.sh ] && . ../../tooling/env.sh

mkdir -p "$OUTDIR"
: > "$OUTDIR/SHA256SUMS"

# name stage log
build_one() {
	local name=$1 stage=$2 log=$3 out=$OUTDIR/$1
	echo "=== $name (DIAG_STAGE=$stage DIAG_LOG=$log)"
	if ! DIAG_STAGE=$stage DIAG_LOG=$log OUT=$out DTB=$DTB ./build.sh >"$out.log" 2>&1; then
		echo "--- build FAILED, tail of $out.log:" >&2
		tail -25 "$out.log" >&2
		return 1
	fi
	if ! ../tools/mkbootimg_v1.sh --verify "$out/shim-boot.img" | tee "$out.verify" | tail -1 | grep -q '^PASS'; then
		echo "--- verify FAILED for $name:" >&2
		cat "$out.verify" >&2
		return 1
	fi
	( cd "$out" && sha256sum shim-boot.img ) | sed "s|shim-boot.img|$name/shim-boot.img|" >> "$OUTDIR/SHA256SUMS"
	echo "--- $name PASS  $(grep -c . "$out.verify") verify lines, sha256 recorded"
}

fails=0
for s in $STAGES; do
	[ -n "$s" ] || continue
	build_one "stage-$s" "$s" 1 || fails=$((fails + 1))
done
if [ "$RO" = 1 ]; then
	for s in 1 2; do
		build_one "ro$s" "$s" 0 || fails=$((fails + 1))
	done
fi

echo
echo "images under $OUTDIR (<name>/shim-boot.img), sha256 in $OUTDIR/SHA256SUMS"
echo "boot order: stage-1 first, then 2..5; 6..8 are the telemetry builds (docs/TELEMETRY.md)."
[ "$fails" = 0 ] || { echo "$fails rung(s) failed" >&2; exit 1; }
