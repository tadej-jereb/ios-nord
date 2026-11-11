#!/bin/bash
# Fetch only the IPSW members the iOS root image needs, verified and resumable.
#
#   tooling/30-fetch-ipsw.sh [--device-tree] [OUTDIR]     (default build/ipsw-x)
#
# The IPSW stays on Apple's CDN; members are pulled with HTTP range requests
# (tools/remotezip.py), so nothing multi-GB is buffered and no full 5.7 GiB
# IPSW is kept. Every member is pinned by name, byte size and zip CRC-32;
# a member that is already on disk with the right size and CRC is skipped,
# so the script is re-runnable and a dropped connection resumes.
#
#   --device-tree   fetch only Firmware/all_flash/DeviceTree.d22ap.im4p (34 KiB)
#
# Verified 2026-11-11 against the central directory of the pinned IPSW:
# names, sizes and CRCs below are the real ones (BuildManifest.plist maps
# OS -> 087-86698-044.dmg, Cryptex1,SystemOS -> 087-86593-047.dmg,
# Cryptex1,AppOS -> 087-86715-047.dmg).
set -euo pipefail

IPSW_URL='https://updates.cdn-apple.com/2025FallFCS/fullrestores/122-77006/1158E502-D76D-4226-AA06-ED5E30CD1111/iPhone10,3,iPhone10,6_16.7.16_20H392_Restore.ipsw'
IPSW_SHA256='ece1194f7e233e9109c5790a8d23a4564a10a254e15ec5b09978a343265568fb'
IPSW_BYTES=6171035648

root=$(cd "$(dirname "$0")/.." && pwd)
refs=${SWEET_REFS:-$root/refs/ios-sweet}
# name|uncompressed bytes|zip CRC-32|role
ALL=(
  '087-86698-044.dmg|4730814044|66ccd39f|OS volume (BuildManifest Identity: OS)'
  '087-86593-047.dmg|2743074816|7f8fabcd|SystemOS cryptex (Cryptex1,SystemOS)'
  '087-86715-047.dmg|10485760|ed284220|AppOS cryptex (Cryptex1,AppOS)'
  'Firmware/all_flash/DeviceTree.d22ap.im4p|33719|a9657430|D22AP device tree'
)
only_dt=0
if [[ ${1:-} == --device-tree ]]; then
	only_dt=1
	shift
fi
out=${1:-$root/build/ipsw-x}
members=("${ALL[@]}")
(( only_dt )) && members=("${ALL[3]}")

for t in curl python3; do
	command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; exit 1; }
done
# remotezip.py is not vendored: copy it out of the reference clone once.
if [[ ! -f $refs/remotezip.py ]]; then
	mkdir -p "$refs"
	echo "fetching $refs/remotezip.py from upstream"
	curl -fsSL --max-time 60 \
		'https://raw.githubusercontent.com/dipa-studio/ios-sweet/main/tools/remotezip.py' \
		-o "$refs/remotezip.py" || { echo "cannot get remotezip.py" >&2; exit 1; }
fi

# Needed bytes from the pin table, plus 1 GiB slack for .part files.
need=0
for m in "${members[@]}"; do
	IFS='|' read -r name bytes crc role <<<"$m"
	need=$((need + bytes))
done
need=$((need + (1 << 30)))
mkdir -p "$out"
avail=$(df --output=avail -B1 "$out" | tail -1 | tr -d ' ')
if (( avail < need )); then
	echo "need $need bytes free under $out, have $avail" >&2
	exit 1
fi
echo "IPSW   $IPSW_URL"
echo "sha256 $IPSW_SHA256 ($IPSW_BYTES bytes; not re-downloaded here)"
echo "outdir $out, need $need bytes, avail $avail"

check() { # path size crc -> 0 when the file is complete and correct
	python3 - "$1" "$2" "$3" <<-'EOF'
		import sys, zlib
		path, size, crc = sys.argv[1], int(sys.argv[2]), int(sys.argv[3], 16)
		try:
		    got = 0
		    with open(path, 'rb') as f:
		        while chunk := f.read(1 << 20):
		            got = zlib.crc32(chunk, got)
		        n = f.tell()
		except FileNotFoundError:
		    sys.exit(1)
		sys.exit(0 if (n, got) == (size, crc) else 1)
	EOF
}

fail=0
for m in "${members[@]}"; do
	IFS='|' read -r name bytes crc role <<<"$m"
	dest=$out/$name
	if check "$dest" "$bytes" "$crc"; then
		echo "ok       $name ($bytes bytes) already present"
		continue
	fi
	echo "fetching $name ($bytes bytes) - $role"
	# A same-size but corrupt file is "already complete" to remotezip: drop it.
	rm -f "$dest" "$dest.part"
	log=$out/logs/${name//\//_}.log
	mkdir -p "$out/logs"
	if ! python3 "$refs/remotezip.py" "$IPSW_URL" "$name" "$out" >"$log" 2>&1; then
		echo "FETCH FAILED: $name (see $log)" >&2
		tail -3 "$log" >&2 || true
		fail=1
		continue
	fi
	# remotezip already CRC-checks; assert size and CRC independently anyway.
	got=$(stat -c %s "$dest")
	if (( got != bytes )) || ! check "$dest" "$bytes" "$crc"; then
		echo "VERIFY FAILED: $name size $got != $bytes or CRC mismatch" >&2
		fail=1
		continue
	fi
	echo "ok       $name ($bytes bytes, CRC-32 $crc)"
done

# Manifest of what landed, for the builder to re-check and for the record.
man=$out/FETCH-MANIFEST.txt
{
	echo "# ios-nord IPSW members, $(date -Is)"
	echo "# source $IPSW_URL"
	echo "# sha256 $IPSW_SHA256"
	for m in "${members[@]}"; do
		IFS='|' read -r name bytes crc role <<<"$m"
		printf '%s  %s  bytes=%s crc32=%s  %s\n' \
			"$(sha256sum "$out/$name" 2>/dev/null | cut -d' ' -f1 || echo MISSING)" \
			"$name" "$bytes" "$crc" "$role"
	done
} >"$man"
echo "manifest $man"

if (( fail )); then
	echo "some members failed; re-run the same command to resume" >&2
	exit 1
fi
echo "all ${#members[@]} member(s) present and verified"
