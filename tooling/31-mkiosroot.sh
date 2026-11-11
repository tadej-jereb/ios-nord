#!/bin/bash
# Build the iOS root image: one case-sensitive, journaled HFS+ volume holding
# the iPhone X OS root plus both cryptexes, for the phone's userdata partition.
#
#   sudo tooling/31-mkiosroot.sh IPSW_DIR [OUT.img] [SIZE]
#
#   IPSW_DIR  directory made by tooling/30-fetch-ipsw.sh (build/ipsw-x)
#   OUT.img   default build/ios16-root.img - must not exist
#   SIZE      volume size, default 16G; must exceed the payload by 15 %
#
# Phases and what needs root:
#   image     truncate + mkfs.hfsplus + dry-run/fsck proof   - no root needed
#   populate  apfs-fuse mounts, loop mount, rsync, links, log dirs, keybag,
#             tools/sweet-root-tweaks.py, fsck -fy, umount      - root needed
#   sparse    raw -> Android sparse .simg for fastboot         - no root needed
#
# This is upstream dipa-studio/ios-sweet tools/mkiosroot.sh made portable and
# size-guarded: the three source DMGs are read through apfs-fuse (APFS with
# LZBITMAP files; the HFS+ copy is therefore uncompressed), everything is
# copied as root with owners/modes/hard links intact, and the finished volume
# is fsck'd clean before it is converted. See docs/IOSROOT.md.
#
# Volume layout decisions (all upstream, verified by fsck output):
#   -s case-sensitive HFSX, -J journaled: XNU replays the journal after a panic
#   /System/Library/Caches/com.apple.dyld hard-links the SystemOS shared cache
#   (dyld looks there at ignition_level=1), cryptex files without an OS-root
#   counterpart are hard-linked to their root path, /private/var/keybags/
#   systembag.kb is the plain-plist keybag for the built-in AppleKeyStore, and
#   /private/var/db/{diagnostics,uuidtext}/.migrated keeps libtrace's log-store
#   migration from crashing.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
refs=${SWEET_REFS:-$root/refs/ios-sweet}
tweaks=${SWEET_TWEAKS:-$refs/sweet-root-tweaks.py}
TWEAKS_SHA256=d604e9fd74f8344b87a351cf573346f4b8d2a3f73e9b3948cb720abcefd56398
MKFS=/usr/sbin/mkfs.hfsplus
FSCK=/usr/sbin/fsck.hfsplus

# Apple IPSW member names -> role, bytes (pinned; see 30-fetch-ipsw.sh).
# BuildManifest.plist Identity names: OS, Cryptex1,SystemOS, Cryptex1,AppOS.
OS_MEMBER=087-86698-044.dmg ;          OS_BYTES=4730814044
SYS_MEMBER=087-86593-047.dmg ;         SYS_BYTES=2743074816
APP_MEMBER=087-86715-047.dmg ;         APP_BYTES=10485760
CONTENT=$((OS_BYTES + SYS_BYTES + APP_BYTES))

usage() { sed -n '2,16p' "$0"; exit 2; }
[[ ${1:-} == --help || ${1:-} == -h ]] && usage
# --phase-image: stop after the volume is created and proven (no root needed)
mkonly=0
skip_payload=0
# Set by our own sudo re-exec: the volume already exists and is proven.
resume=${RESUME:-0}
while [[ ${1:-} == --* ]]; do
	case $1 in
		--phase-image)      mkonly=1 ;;
		--no-payload-check) skip_payload=1 ;;
		*) usage ;;
	esac
	shift
done
(( $# >= 1 )) || usage

ipsw=$(realpath "$1")
out=${2:-$root/build/ios16-root.img}
size=${3:-16G}
[[ -d $ipsw ]] || { echo "no such IPSW dir: $ipsw" >&2; exit 1; }

# --- size argument -> bytes, plus payload/reserve check ----------------------
case $size in
	*[gG]) size_bytes=$(( ${size%?} * 1024 * 1024 * 1024 )) ;;
	*[mM]) size_bytes=$(( ${size%?} * 1024 * 1024 )) ;;
	*[kK]) size_bytes=$(( ${size%?} * 1024 )) ;;
	*)     size_bytes=$size ;;
esac
[[ $size_bytes =~ ^[0-9]+$ ]] || { echo "bad SIZE: $size" >&2; exit 1; }
(( size_bytes % 4096 == 0 )) || { echo "SIZE must be a multiple of 4096" >&2; exit 1; }
# Without the payload the 15 % reserve is meaningless: keep only the journal.
if (( skip_payload )); then
	minimum=$(( 64 * 1024 * 1024 ))
else
	minimum=$(( CONTENT + CONTENT / 100 * 15 + 64 * 1024 * 1024 ))
fi
if (( size_bytes < minimum )); then
	echo "SIZE $size ($size_bytes B) too small: payload is $CONTENT B," >&2
	echo "need at least $minimum B (payload + 15 % + 64 MiB journal)" >&2
	exit 1
fi

# --- inputs ----------------------------------------------------------------
for m in "$OS_MEMBER:$OS_BYTES" "$SYS_MEMBER:$SYS_BYTES" "$APP_MEMBER:$APP_BYTES"; do
	f=$ipsw/${m%:*}; want=${m##*:}
	if (( skip_payload )) && [[ ! -f $f ]]; then
		echo "skip payload: no $f"; continue
	fi
	[[ -f $f ]] || { echo "missing $f - run tooling/30-fetch-ipsw.sh" >&2; exit 1; }
	got=$(stat -c %s "$f")
	(( got == want )) || { echo "$f: $got bytes, expected $want" >&2; exit 1; }
done
[[ -f $tweaks ]] || { echo "missing tweaks script $tweaks" >&2; exit 1; }
have_tweaks=$(sha256sum "$tweaks" | cut -d' ' -f1)
[[ $have_tweaks == "$TWEAKS_SHA256" ]] || {
	echo "warning: $tweaks sha256 $have_tweaks != pinned $TWEAKS_SHA256" >&2
	echo "         (SWEET_TWEAKS override or upstream changed)" >&2
}

# --- tools / space ---------------------------------------------------------
missing=()
for t in "$MKFS" "$FSCK" "$(command -v rsync || echo rsync)" "$(command -v mount || echo mount)"; do
	[[ -x $t ]] || missing+=("$(basename "$t")")
done
if (( ${#missing[@]} )); then
	echo "missing tools: ${missing[*]}" >&2
	echo "  sudo tooling/00-host-deps.sh   # hfsprogs, rsync, kmod" >&2
	exit 1
fi

# apfs-fuse is only needed from the populate gate on: the image phase runs
# without it, so a missing binary is a warning here and fatal there.
insist_apfs() {
	command -v apfs-fuse >/dev/null && return 0
	echo "apfs-fuse missing: it reads the APFS DMGs of the populate phase" >&2
	echo "  no distro packages it (not on noble) - source build, ~1 min:" >&2
	echo "    sudo apt install libfuse3-dev libbz2-dev zlib1g-dev libcrypto++-dev cmake g++ git" >&2
	echo "    git clone https://github.com/sgan81/apfs-fuse ~/apfs-fuse && cd ~/apfs-fuse" >&2
	echo "    git submodule update --init && cmake -B build && cmake --build build -j 8" >&2
	echo "    sudo cmake --install build" >&2
	return 1
}
if ! command -v apfs-fuse >/dev/null && ! (( mkonly )); then
	echo "warning: apfs-fuse not installed - the populate phase below will stop" >&2
fi

mkdir -p "$(dirname "$out")"
if (( resume )); then
	[[ -f $out ]] || { echo "resume: $out is gone" >&2; exit 1; }
	[[ $(stat -c %s "$out") == "$size_bytes" ]] || {
		echo "resume: $out is not $size_bytes bytes" >&2; exit 1; }
else
	[[ ! -e $out ]] || { echo "refusing to overwrite $out" >&2; exit 1; }
	[[ ! -e $out.simg ]] || { echo "refusing to overwrite $out.simg" >&2; exit 1; }
fi
# Sparse build: only the payload is really written, so ask for payload + 20 %.
need=$(( CONTENT + CONTENT / 100 * 20 ))
avail=$(df --output=avail -B1 "$(dirname "$out")" | tail -1 | tr -d ' ')
if (( avail < need )); then
	echo "need $need bytes free next to $out, have $avail" >&2
	exit 1
fi
echo "payload  $CONTENT B from $ipsw"
echo "volume   $size ($size_bytes B), free next to output $avail B"

# --- phase: image (unprivileged) -------------------------------------------
logdir=$root/logs; mkdir -p "$logdir"
stamp=$(date +%Y%m%dT%H%M%S)
mkfslog=$logdir/31-mkfs-$stamp.log
{
	echo "# $size_bytes bytes, $size, $(date -Is)"
	"$MKFS" -N "$size_bytes" -s -J -b 4096 -c b=1024 -v iOSRoot
} >"$mkfslog" 2>&1 || { echo "mkfs.hfsplus -N dry run failed" >&2; cat "$mkfslog" >&2; exit 1; }
grep -q 'case-sensitive\|volume name: "iOSRoot"' "$mkfslog" || true
echo "dry run  $mkfslog"

if (( resume )); then
	echo "resume   $out exists and is the right size, re-proving the header"
else
	truncate -s "$size" "$out"
	"$MKFS" -s -J -b 4096 -c b=1024 -v iOSRoot "$out" | tee -a "$mkfslog"
	"$FSCK" -n "$out" | tee -a "$mkfslog"
fi
# Signatures: 0x482b "H+" = HFS Plus, 0x4858 "HX" = HFSX (case-sensitive).
sig=$(xxd -s 1024 -l 2 -p "$out")
[[ $sig == 4858 ]] || { echo "volume header signature $sig, expected 4858 (HFSX)" >&2; exit 1; }
python3 - "$out" <<-'EOF' | tee -a "$mkfslog"
	import struct, sys
	d = open(sys.argv[1], 'rb').read(1100)
	attrs, = struct.unpack_from('>I', d, 1024 + 4)
	assert attrs & 0x2000, 'journaled bit not set'
	print(f'volume header ok: HFSX, attributes {attrs:#010x} (journaled bit set)')
EOF
echo "phase image done: $out"
if (( mkonly )); then
	echo "--phase-image: stopping before populate (volume is empty)"
	exit 0
fi

# --- phase: populate (root) ------------------------------------------------
if (( EUID )); then
	echo "re-executing under sudo for apfs-fuse, loop mount and rsync"
	args=("$0")
	(( skip_payload )) && args+=(--no-payload-check)
	args+=("$ipsw" "$out" "$size")
	exec sudo -- env "SWEET_REFS=$refs" "SWEET_TWEAKS=$tweaks" RESUME=1 \
		bash "${args[@]}"
fi
(( EUID == 0 )) || { echo "populate needs root" >&2; exit 1; }
insist_apfs || exit 1
if ! grep -qw hfsplus /proc/filesystems; then
	echo "kernel has no hfsplus: the HFS+ loop mount cannot work" >&2
	echo "  sudo modprobe hfsplus   (module ships in linux-modules-extra)" >&2
	exit 1
fi

work=$(mktemp -d /var/tmp/mkiosroot.XXXXXX)
mnts=()
cleanup() {
	for m in "${mnts[@]}"; do
		mountpoint -q "$m" && umount "$m" 2>/dev/null || true
	done
	for m in "${mnts[@]}"; do mountpoint -q "$m" && echo "still mounted: $m" >&2; done
	for m in "${mnts[@]}"; do mountpoint -q "$m" || rmdir "$m" 2>/dev/null || true; done
	rm -f "$work"/*.dmg 2>/dev/null || true
	rmdir "$work" 2>/dev/null || true
}
trap cleanup EXIT

apfs_mount() { # dmg name
	ln -s "$1" "$work/$2.dmg"
	mkdir "$work/$2"
	apfs-fuse "$work/$2.dmg" "$work/$2"
	mnts+=("$work/$2")
}
apfs_mount "$ipsw/$OS_MEMBER" os
apfs_mount "$ipsw/$SYS_MEMBER" sysos
apfs_mount "$ipsw/$APP_MEMBER" appos
for v in os sysos appos; do
	[[ -d $work/$v/root ]] || { echo "$v: no /root in image" >&2; exit 1; }
done

mkdir "$work/root"
mount -t hfsplus -o loop,force "$out" "$work/root"
mnts=("$work/root" "${mnts[@]}")

copy() {
	echo "copy ${1#"$work/"} -> ${2#"$work/root"}"
	mkdir -p "$2"
	rsync -aH --numeric-ids "$1/" "$2/"
}
copy "$work/os/root"   "$work/root"
copy "$work/sysos/root" "$work/root/private/preboot/Cryptexes/OS"
copy "$work/appos/root" "$work/root/private/preboot/Cryptexes/App"

# Shared cache where dyld looks at ignition level 1: hard links, no space cost.
dsc=private/preboot/Cryptexes/OS/System/Library/Caches/com.apple.dyld
mkdir -p "$work/root/System/Library/Caches/com.apple.dyld"
for f in "$work/root/$dsc"/*; do
	ln "$f" "$work/root/System/Library/Caches/com.apple.dyld/${f##*/}"
done

# dyld does not search the cryptexes at level 1: hard-link every cryptex file
# that has no OS-root counterpart to its root path (Linux hfsplus cannot
# hard-link symlinks, so those are copied).
for c in OS App; do
	(cd "$work/root/private/preboot/Cryptexes/$c" &&
	 find . ! -type d ! -path './System/Library/Caches/com.apple.dyld/*') |
	while IFS= read -r f; do
		f=${f#./}
		if ! test -e "$work/root/$f" && ! test -L "$work/root/$f"; then
			mkdir -p "$work/root/$(dirname "$f")"
			src=$work/root/private/preboot/Cryptexes/$c/$f
			if test -L "$src"; then cp -P "$src" "$work/root/$f"; else ln "$src" "$work/root/$f"; fi
		fi
	done
done

# logd's log stores, normally created at restore: owner _logd (272), modes and
# a .migrated marker, else libtrace crashes on "Failed to migrate directory".
db=$work/root/private/var/db
install -d -o 272 -g 272 -m 0751 "$db/diagnostics"
install -d -o 272 -g 272 -m 0755 "$db/uuidtext" "$db/diagnostics/timesync"
for d in diagnostics uuidtext diagnostics/timesync; do
	install -o 272 -g 272 -m 0644 /dev/null "$db/$d/.migrated"
done

# System keybag for the built-in AppleKeyStore (no passcode).
install -d -m 0700 -o 0 -g 0 "$work/root/private/var/keybags"
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
	'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	'<plist version="1.0"><dict><key>KeyBagKeys</key><data>U1dFRVQ=</data></dict></plist>' |
	install -m 0600 -o 0 -g 0 /dev/stdin "$work/root/private/var/keybags/systembag.kb"

df -h "$work/root"
python3 "$tweaks" "$work/root"

echo "unmounting and checking"
umount "$work/root"
mnts=("${mnts[@]:1}")
for m in "$work/os" "$work/sysos" "$work/appos"; do umount "$m"; done
mnts=()

# Linux hfsplus decomposes some non-ASCII names differently from Apple's
# tables; let fsck rewrite them, then require a clean check.
"$FSCK" -f -y "$out" | grep -v 'Illegal name' || true
"$FSCK" -f -n "$out"

# --- phase: sparse ---------------------------------------------------------
used=$(du -h --apparent-size "$out" | cut -f1)
on_disk=$(du -h "$out" | cut -f1)
python3 "$root/tooling/sparse.py" encode "$out" "$out.simg"
python3 "$root/tooling/sparse.py" info "$out.simg"
echo
echo "built    $out ($used apparent, $on_disk on disk)"
echo "sparse   $out.simg ($(stat -c %s "$out.simg") bytes) - flash this"
echo "sizes    volume $size, payload $CONTENT B, simg $(stat -c %s "$out.simg") B"
echo "GATE: verify the target partition is at least $size_bytes B before flashing:"
echo "      fastboot getvar partition-size:userdata"
