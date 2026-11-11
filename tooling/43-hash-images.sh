#!/bin/sh
# 43-hash-images.sh — sha256 every image in a build directory and emit a
# copy-ready block for docs/IMAGE_PROVENANCE.md (one block per boot).
#
#   tooling/43-hash-images.sh BUILD_DIR [-o SUMMARY.md]
#
# Also writes <dir>/SHA256SUMS for `sha256sum -c`, and a SUMMARY.md next to it
# (default: the build dir) that you paste into the provenance doc.
#
# Images are matched on extension: .img .simg .bin .dtb .dtbo .elf .mbn.
# Exit: 0 hashed, 1 usage, 2 nothing matched.

set -eu

case ${1:-} in
-h|--help) sed -n '2,13p' "$0"; exit 0 ;;
esac

[ $# -ge 1 ] || { sed -n '2,13p' "$0"; exit 1; }
DIR=$1
shift
OUT=""
while [ $# -gt 0 ]; do
	case $1 in
	-o) shift; OUT=${1:?Error: -o needs a file}; shift ;;
	-h|--help) sed -n '2,13p' "$0"; exit 0 ;;
	*) echo "Error: unknown argument $1" >&2; exit 1 ;;
	esac
done

[ -d "$DIR" ] || { echo "Error: $DIR is not a directory" >&2; exit 1; }
DIR=$(cd "$DIR" && pwd)
command -v sha256sum >/dev/null 2>&1 || { echo "Error: sha256sum not found" >&2; exit 1; }

OUT=${OUT:-$DIR/SUMMARY.md}
SUMS=$DIR/SHA256SUMS

FILES=$(find "$DIR" -maxdepth 1 -type f \
	\( -name '*.img' -o -name '*.simg' -o -name '*.bin' \
	   -o -name '*.dtb' -o -name '*.dtbo' -o -name '*.elf' -o -name '*.mbn' \) \
	| sort)
[ -n "$FILES" ] || { echo "Error: no image files in $DIR" >&2; exit 2; }

# Provenance context: which tree and commit produced these.
GITC=$(git -C "$DIR" rev-parse --short=12 HEAD 2>/dev/null || echo "no-git")
GITD=$(git -C "$DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "-")
STAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
HOSTN=$(hostname 2>/dev/null || echo unknown)

: > "$SUMS"
{
	echo "## boot $(date -u '+%Y-%m-%d %H:%MZ') — $DIR"
	echo
	echo "| file | bytes | sha256 |"
	echo "|---|---|---|"
} > "$OUT"

echo "hashing in $DIR"
N=0
while IFS= read -r f; do
	[ -f "$f" ] || continue
	n=$(basename "$f")
	sz=$(wc -c < "$f" | tr -d ' ')
	sum=$(sha256sum "$f" | cut -d' ' -f1)
	printf '%s  %s\n' "$sum" "$n" >> "$SUMS"
	printf '| %s | %s | %s |\n' "$n" "$sz" "$sum" >> "$OUT"
	printf '  %-32s %10s %s\n' "$n" "$sz" "$sum"
	N=$((N + 1))
done <<EOF
$FILES
EOF
{
	echo
	echo "context: host=$HOSTN tree=${GITD}@${GITC} hashed=$STAMP"
	echo
	echo "| field | value |"
	echo "|---|---|"
	echo "| slot flashed | _a / _b_ |"
	echo "| cmdline / boot-args | _paste exact string_ |"
	echo "| kernel commit or CI run | \`$GITC\` / _run id_ |"
	echo "| boot result | _clean / panic after N s / no serial / black_ |"
	echo "| notes | |"
} >> "$OUT"

if [ -n "$(find "$DIR" -maxdepth 1 -type f \( -name '*.xz' -o -name '*.gz' -o -name '*.zip' \) 2>/dev/null)" ]; then
	echo "warn: archives also present; hash the unpacked files, they are what gets flashed" >&2
fi

echo
echo "=== paste into docs/IMAGE_PROVENANCE.md ==="
cat "$OUT"
echo "=== end block ==="
echo
echo "checksums: $SUMS  (verify: cd $DIR && sha256sum -c SHA256SUMS)"
echo "summary:   $OUT"
