#!/bin/bash
# Populate the built iOS root image from the three IPSW DMGs. Root only.
#
#   tooling/33-populate-root.sh --dry-run        (no root: preflight only)
#   sudo tooling/33-populate-root.sh [--image IMG] [--ipsw DIR] [--simg]
#                                    [--restart] [--adopt]
#
#   --image   default build/ios16-root.img - must already exist (31-mkiosroot.sh)
#   --ipsw    default build/ipsw-x
#   --simg    also write IMG.simg (Android sparse) after the clean fsck
#   --restart forget the resume marker and populate from the top
#   --adopt   allow a volume that already has content but no marker
#   --dry-run stop before the loop mount: mount the DMGs read-only, measure the
#             real payload, check tools/space and print the plan. Needs no root
#             (apfs-fuse alone is unprivileged) and changes nothing.
#
# This is the one step that needs root: modprobe hfsplus, the loop mount of the
# HFS+ image, and writing root/mobile-owned files. It never creates or
# reformats the image, so re-running it is safe.
#
# Stages, in order, each recorded in IMG.populate-state after success:
#   os sysos appos  rsync of OS root, SystemOS cryptex, AppOS cryptex
#   dyld            hard links /System/Library/Caches/com.apple.dyld -> SystemOS
#   cryptexlinks    hard links of cryptex files that have no OS-root counterpart
#   logdirs         /private/var/db/{diagnostics,uuidtext}/.migrated (owner _logd)
#   keybag          /private/var/keybags/systembag.kb, plain plist
#   tweaks          refs/ios-sweet/sweet-root-tweaks.py (pinned sha256)
#   fsck            umount, fsck -fy, fsck -n must be clean
# A re-run skips recorded stages; rsync stages are idempotent anyway. The image
# sha256 is recorded in the marker, so a different image forces --restart.
#
# Layout reasons: see the header of tooling/31-mkiosroot.sh and docs/IOSROOT.md.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
refs=${SWEET_REFS:-$root/refs/ios-sweet}
tweaks=${SWEET_TWEAKS:-$refs/sweet-root-tweaks.py}
TWEAKS_SHA256=d604e9fd74f8344b87a351cf573346f4b8d2a3f73e9b3948cb720abcefd56398
FSCK=/usr/sbin/fsck.hfsplus

img=$root/build/ios16-root.img
ipsw=$root/build/ipsw-x
do_simg=0
restart=0
adopt=0
dry_run=0
while (( $# )); do
	case $1 in
		--image)   img=${2:?--image needs a path}; shift ;;
		--ipsw)    ipsw=${2:?--ipsw needs a path}; shift ;;
		--simg)    do_simg=1 ;;
		--restart) restart=1 ;;
		--adopt)   adopt=1 ;;
		--dry-run) dry_run=1 ;;
		-h|--help) sed -n '2,38p' "$0"; exit 0 ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
	shift
done

say()  { printf '%s\n' "$*"; }
step() { printf '\n=== %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# --- pinned inputs ---------------------------------------------------------
# BuildManifest Identity names: OS, Cryptex1,SystemOS, Cryptex1,AppOS.
OS_MEMBER=087-86698-044.dmg ;  OS_BYTES=4730814044
SYS_MEMBER=087-86593-047.dmg ; SYS_BYTES=2743074816
APP_MEMBER=087-86715-047.dmg ; APP_BYTES=10485760
VOLUME_BYTES=17179869184
# Unique apparent bytes per volume (measure: every regular file, hard links
# counted once). This is the real transfer, the compressed member size above is
# not. Reproduced in docs/ROOTFS_READY.md.
OS_UNIQUE=7937213671
SYS_UNIQUE=3359797050
APP_UNIQUE=7846405
PAYLOAD=$((OS_UNIQUE + SYS_UNIQUE + APP_UNIQUE))

# --- inputs / tools --------------------------------------------------------
img=$(realpath "$img"); ipsw=$(realpath "$ipsw")
[[ -f $img ]] || die "$img does not exist - run tooling/31-mkiosroot.sh --phase-image"
[[ -d $ipsw ]] || die "no such IPSW dir: $ipsw"
for m in "$OS_MEMBER:$OS_BYTES" "$SYS_MEMBER:$SYS_BYTES" "$APP_MEMBER:$APP_BYTES"; do
	f=$ipsw/${m%:*}; want=${m##*:}
	[[ -f $f ]] || die "missing $f - run tooling/30-fetch-ipsw.sh"
	got=$(stat -c %s "$f")
	(( got == want )) || die "$f: $got bytes, expected $want"
done
[[ -f $tweaks ]] || die "missing tweaks script $tweaks"
[[ "$(sha256sum "$tweaks" | cut -d' ' -f1)" == "$TWEAKS_SHA256" ]] || \
	die "$tweaks changed (sha256 mismatch) - review it, then update TWEAKS_SHA256"

command -v rsync >/dev/null || die "rsync missing (sudo tooling/00-host-deps.sh)"
[[ -x $FSCK ]] || die "$FSCK missing (sudo apt install hfsprogs)"
apfs_fuse=$root/tooling/opt/apfs-fuse/bin/apfs-fuse
[[ -x $apfs_fuse ]] || apfs_fuse=$(command -v apfs-fuse || true)
[[ -x ${apfs_fuse:-} ]] || die "apfs-fuse missing - run tooling/32-build-apfsfuse.sh"
if (( ! dry_run )) && (( EUID != 0 )); then
	# apfs-fuse alone is unprivileged, the hfsplus loop mount is not.
	echo "needs root (or --dry-run), run:" >&2
	echo "  sudo tooling/33-populate-root.sh$([[ $do_simg == 1 ]] && echo ' --simg')" >&2
	exit 1
fi

# --- image identity --------------------------------------------------------
[[ "$(stat -c %s "$img")" == "$VOLUME_BYTES" ]] || \
	die "$img is $(stat -c %s "$img") bytes, expected $VOLUME_BYTES"
[[ "$(xxd -s 1024 -l 2 -p "$img")" == 4858 ]] || die "$img is not HFSX (header)"
python3 - "$img" <<-'EOF' || exit 1
	import struct, sys
	d = open(sys.argv[1], 'rb').read(1100)
	attrs, = struct.unpack_from('>I', d, 1024 + 4)
	assert attrs & 0x2000, 'journaled bit not set'
EOF

state=$img.populate-state
[[ $restart == 1 ]] && rm -f "$state"

# The documented gate leaves a baseline checksum next to the image; a fresh run
# must match it, so an accidentally different image cannot be half-filled.
base=$img.sha256.pre-populate
if [[ -f $base ]] && [[ ! -s $state ]]; then
	(cd "$(dirname "$img")" && sha256sum -c --status "$(basename "$base")") || \
		die "$img does not match $base - re-make it or delete the baseline deliberately"
	say "baseline ok $(cut -d' ' -f1 "$base")"
fi

say "image   $img ($(numfmt --to=iec "$VOLUME_BYTES"), HFSX, journaled)"
say "payload $PAYLOAD B unique ($(numfmt --to=iec "$PAYLOAD"))"

# --- host space ------------------------------------------------------------
# A sparse .simg holds only the used blocks (~payload), so ask for payload+8 %
# next to the image; without --simg only the fsck rewrite room is needed.
if (( do_simg )); then need=$(( PAYLOAD + PAYLOAD / 100 * 8 )); else need=$(( PAYLOAD / 2 )); fi
avail=$(df --output=avail -B1 "$(dirname "$img")" | tail -1 | tr -d ' ')
(( avail >= need )) || die "need $need B free next to $img, have $avail B"
say "host ok $avail B free next to the image"

# --- mounts ----------------------------------------------------------------
if ! grep -qw hfsplus /proc/filesystems; then
	if (( EUID == 0 )); then
		say "loading hfsplus module"
		modprobe hfsplus || die "modprobe hfsplus failed (linux-modules-extra installed?)"
		grep -qw hfsplus /proc/filesystems || die "hfsplus still not in /proc/filesystems"
	elif command -v modinfo >/dev/null && modinfo -F filename hfsplus >/dev/null 2>&1; then
		echo "note: hfsplus module present but not loaded; the script runs modprobe as root" >&2
	else
		echo "note: no hfsplus support in this kernel - the loop mount will fail" >&2
	fi
elif (( dry_run )); then
	say "hfsplus already loaded"
fi

work=$(mktemp -d /var/tmp/populate-root.XXXXXX)
mnt=$work/root
mkdir -p "$mnt"
mnts=("$mnt")
cleanup() {
	for m in "${mnts[@]}"; do mountpoint -q "$m" && umount "$m" 2>/dev/null || true; done
	for m in "${mnts[@]}"; do mountpoint -q "$m" && echo "still mounted: $m" >&2; done
	rm -rf "$work"
}
trap cleanup EXIT

apfs_mount() { # dmg name  -> $work/NAME
	mkdir "$work/$2"
	"$apfs_fuse" "$1" "$work/$2"
	mnts=("$work/$2" "${mnts[@]}")
}
# DMG members are read directly by apfs-fuse (it decodes the UDIF chunk table
# itself); no loop device and no third mount are involved.
step "mounting DMGs read-only through apfs-fuse"
apfs_mount "$ipsw/$OS_MEMBER" os
apfs_mount "$ipsw/$SYS_MEMBER" sysos
apfs_mount "$ipsw/$APP_MEMBER" appos
for v in os sysos appos; do
	mountpoint -q "$work/$v" || die "$v did not mount"
	[[ -d $work/$v/root ]] || die "$v: no /root in image"
done

if (( dry_run )); then
	step "dry run: measuring the payload through the DMG mounts"
	py=$(mktemp)
	cat >"$py" <<'PY'
import os, sys
names = ('OS', 'SystemOS', 'AppOS')
total_app = total_blocks = 0
for name, top in zip(names, sys.argv[1:]):
    seen = {}
    for d, _, fs in os.walk(top):
        for f in fs:
            p = os.path.join(d, f)
            try:
                st = os.lstat(p)
            except OSError:
                continue
            seen[st.st_ino] = st.st_size
    n = sum(seen.values())
    blocks = sum((s + 4095) // 4096 * 4096 for s in seen.values())
    total_app += n
    total_blocks += blocks
    print('%-9s %8d files %14d B apparent %14d B in 4k blocks'
          % (name, len(seen), n, blocks))
print('%-9s %26d B apparent %14d B in 4k blocks' % ('total', total_app, total_blocks))
print('copy mode instead of hard links costs the dyld+cryptex bytes twice')
print('TOTAL %d %d' % (total_app, total_blocks))
PY
	set +e
	summary=$(python3 "$py" "$work/os/root" "$work/sysos/root" "$work/appos/root")
	set -e
	rm -f "$py"
	printf '%s\n' "$summary" | grep -v '^TOTAL'
	measured=$(printf '%s\n' "$summary" | awk '/^TOTAL/ { print $2 }')
	# The pinned constants drive the space guard; they must track the DMGs.
	if (( measured > PAYLOAD * 102 / 100 || measured < PAYLOAD * 98 / 100 )); then
		echo "warning: measured $measured B vs pinned $PAYLOAD B - update the constants" >&2
	else
		say "measured payload matches the pinned constants within 2 %"
	fi
	say "raw volume $VOLUME_BYTES B, payload must fit with the 15 % reserve"
	step "dry run stops here; with root it would mount rw, rsync, link, fsck"
	say "  sudo tooling/33-populate-root.sh$( (( do_simg )) && say ' --simg' )"
	exit 0
fi

step "loop-mounting $img read-write"
mount -t hfsplus -o loop,force "$img" "$mnt" || \
	die "mount failed - is the hfsplus module loaded, is the image fsck-clean?"
grep -qw rw /proc/mounts || true
findmnt -no OPTIONS --target "$mnt" | grep -q '^rw\|,rw' || die "$mnt is not read-write"

# --- volume state / space --------------------------------------------------
entries=$(find "$mnt" -mindepth 1 -maxdepth 1 \
	-not -name '.HFS+ Private Data' -not -name 'lost+found' | wc -l)
if [[ -s $state ]]; then
	cur=$(sha256sum "$img" | cut -d' ' -f1)
	# The recorded sha is from before fsck; an fsck pass can change it, so a
	# finished run records the new one and resume accepts either.
	if ! grep -qx -e "image_sha=$cur" -e "image_sha_final=$cur" "$state"; then
		die "marker belongs to $(sed -n 's/^image_sha=//p' "$state"), image is $cur - use --restart"
	fi
	say "resuming: $(sed -n 's/^stage=//p' "$state" | tr '\n' ' ')"
elif (( entries > 0 )) && (( ! restart )); then
	(( adopt )) || die "$mnt already has $entries entries but no marker - --adopt or --restart"
	say "adopting a volume that already has $entries entries"
fi
if [[ ! -s $state ]] || (( restart )); then
	printf 'image_sha=%s\nstarted=%s\npayload=%s\n' \
		"$(sha256sum "$img" | cut -d' ' -f1)" "$(date -Is)" "$PAYLOAD" >"$state"
fi

# Hard links carry both cache stages; HFS+ on Linux supports them for files but
# not for symlinks. Probe instead of assuming: without them the cryptex copy
# doubles and the volume can run out.
probe=$mnt/.populate-link-probe
: >"$probe"
if ln "$probe" "$probe.2" 2>/dev/null && [[ "$(stat -c %h "$probe")" == 2 ]]; then
	link=ln; rm -f "$probe" "$probe.2"
else
	link=cp; rm -f "$probe" "$probe.2"
	echo "warning: this hfsplus driver cannot hard-link - cache stages will copy" >&2
fi

remaining=0
have_stage() { grep -qx "stage=$1" "$state" 2>/dev/null; }
have_stage os    || remaining=$((remaining + OS_UNIQUE))
have_stage sysos || remaining=$((remaining + SYS_UNIQUE))
have_stage appos || remaining=$((remaining + APP_UNIQUE))
[[ $link == cp ]] && remaining=$((remaining * 2))   # dyld + cryptex as copies
# 5 % for catalog nodes, extent overflow, and the fsck pass afterwards.
need=$(( remaining + remaining / 100 * 5 + 64 * 1024 * 1024 ))
vavail=$(df --output=avail -B1 "$mnt" | tail -1 | tr -d ' ')
say "volume  $vavail B free, remaining payload $remaining B, need $need B"
(( vavail >= need )) || die "volume too small: $vavail B free < $need B needed"

# --- stages ----------------------------------------------------------------
mark() { printf 'stage=%s\ntime=%s\n' "$1" "$(date -Is)" >>"$state"; }

copy() { # src dst label
	step "copy $3"
	mkdir -p "$2"
	set +e
	rsync -aH --numeric-ids --partial-dir=.rsync-partial "$1/" "$2/"
	rc=$?
	set -e
	(( rc == 0 || rc == 24 )) || die "rsync $3 failed with exit $rc"
	find "$2" -maxdepth 1 -name .rsync-partial -exec rm -rf {} + 2>/dev/null || true
	mark "$3"
}

have_stage os    || copy "$work/os/root"    "$mnt"                                        os
have_stage sysos || copy "$work/sysos/root" "$mnt/private/preboot/Cryptexes/OS"           sysos
have_stage appos || copy "$work/appos/root" "$mnt/private/preboot/Cryptexes/App"          appos

# dyld reads the SystemOS shared cache through this path at ignition level 1.
if ! have_stage dyld; then
	step "hard-link the dyld shared cache"
	src=$mnt/private/preboot/Cryptexes/OS/System/Library/Caches/com.apple.dyld
	dst=$mnt/System/Library/Caches/com.apple.dyld
	[[ -d $src ]] || die "no dyld cache at $src"
	mkdir -p "$dst"
	n=0
	for f in "$src"/*; do
		t=${dst}/${f##*/}
		[[ -e $t ]] && continue
		if [[ $link == ln ]]; then ln "$f" "$t"; else cp -p "$f" "$t"; fi
		n=$((n + 1))
	done
	say "linked $n cache files"
	mark dyld
fi

# dyld does not search the cryptexes at level 1: every cryptex file without an
# OS-root counterpart gets a root-path hard link (symlinks are copied).
if ! have_stage cryptexlinks; then
	step "hard-link cryptex-only files to their root path"
	n=0
	for c in OS App; do
		while IFS= read -r f; do
			f=${f#./}
			[[ -e $mnt/$f || -L $mnt/$f ]] && continue
			mkdir -p "$mnt/$(dirname "$f")"
			src=$mnt/private/preboot/Cryptexes/$c/$f
			if [[ -L $src || $link == cp ]]; then cp -P "$src" "$mnt/$f"; else ln "$src" "$mnt/$f"; fi
			n=$((n + 1))
		done < <(cd "$mnt/private/preboot/Cryptexes/$c" &&
			find . ! -type d ! -path './System/Library/Caches/com.apple.dyld/*')
	done
	say "linked $n cryptex files"
	mark cryptexlinks
fi

# libtrace's log stores are made at restore; without the marker it crashes on
# "Failed to migrate directory". Owner _logd is 272.
if ! have_stage logdirs; then
	step "create logd stores"
	db=$mnt/private/var/db
	install -d -o 272 -g 272 -m 0751 "$db/diagnostics"
	install -d -o 272 -g 272 -m 0755 "$db/uuidtext" "$db/diagnostics/timesync"
	for d in diagnostics uuidtext diagnostics/timesync; do
		install -o 272 -g 272 -m 0644 /dev/null "$db/$d/.migrated"
	done
	mark logdirs
fi

if ! have_stage keybag; then
	step "install the plain keybag"
	install -d -m 0700 -o 0 -g 0 "$mnt/private/var/keybags"
	printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0"><dict><key>KeyBagKeys</key><data>U1dFRVQ=</data></dict></plist>' |
		install -m 0600 -o 0 -g 0 /dev/stdin "$mnt/private/var/keybags/systembag.kb"
	mark keybag
fi

if ! have_stage tweaks; then
	step "apply bring-up tweaks"
	python3 "$tweaks" "$mnt"
	mark tweaks
fi

# --- verify before unmount -------------------------------------------------
step "verify the volume content"
for p in System/Library/CoreServices/SystemVersion.plist \
	private/preboot/Cryptexes/OS/System/Library/Caches/com.apple.dyld \
	private/preboot/Cryptexes/App/usr/libexec/webbookmarksd usr/libexec/fseventsd \
	private/var/keybags/systembag.kb private/var/db/diagnostics/.migrated \
	private/var/mobile Library/Frameworks; do
	[[ -e $mnt/$p ]] || die "missing after populate: /$p"
done
files=$(find "$mnt" -xdev -type f | wc -l)
used=$(df -B1 --output=used "$mnt" | tail -1 | tr -d ' ')
apparent=$(du -sb --apparent-size "$mnt" | cut -f1)
say "files $files, $used B in blocks, $apparent B apparent (hard links counted twice)"
(( files > 180000 )) || die "only $files files on the volume, expected > 180000"
(( used > 11000000000 )) || die "only $used B allocated, expected > 11e9"
if [[ $link == ln ]]; then
	[[ "$(stat -c %h "$mnt/System/Library/Caches/com.apple.dyld"/* | sort -u | tr '\n' ' ')" == "2 "* ]] || \
		echo "warning: dyld cache files are not hard-linked" >&2
fi

# --- umount, fsck ----------------------------------------------------------
step "unmount"
umount "$mnt"
mnts=("${mnts[@]:1}")
for m in "$work/os" "$work/sysos" "$work/appos"; do umount "$m"; done
mnts=()

if ! have_stage fsck; then
	step "fsck -fy (Linux decomposes some names differently; let fsck fix them)"
	"$FSCK" -f -y "$img" 2>&1 | grep -v 'Illegal name' || true
	"$FSCK" -f -n "$img" || die "fsck is not clean"
	mark fsck
else
	step "fsck -n (already cleaned in an earlier run)"
	"$FSCK" -f -n "$img" || die "fsck is not clean"
fi

# --- hash ------------------------------------------------------------------
step "hash"
sum=$(sha256sum "$img" | cut -d' ' -f1)
printf 'image_sha_final=%s\nfinished=%s\n' "$sum" "$(date -Is)" >>"$state"
mkdir -p "$root/logs"
log=$root/logs/33-populate-$(date +%Y%m%dT%H%M%S).log
{
	echo "image  $img"
	echo "sha256 $sum"
	echo "bytes  $(stat -c %s "$img") apparent, $(du -B1 "$img" | cut -f1) B on disk"
	echo "files  $files blocks $used apparent $apparent"
	echo "marker $state"
} | tee "$log"

if (( do_simg )); then
	step "sparse encode"
	python3 "$root/tooling/sparse.py" encode "$img" "$img.simg"
	python3 "$root/tooling/sparse.py" info "$img.simg"
	sha256sum "$img.simg" | tee -a "$log"
fi

# --- provenance ------------------------------------------------------------
prov=$root/docs/IMAGE_PROVENANCE.md
{
	echo
	echo "## root image populate $(date -u '+%Y-%m-%d %H:%MZ')"
	echo
	echo "| file | bytes | sha256 |"
	echo "|---|---|---|"
	printf '| %s | %s | %s |\n' "$(basename "$img")" "$(stat -c %s "$img")" "$sum"
	if (( do_simg )); then
		printf '| %s.simg | %s | %s |\n' "$(basename "$img")" \
			"$(stat -c %s "$img.simg")" "$(sha256sum "$img.simg" | cut -d' ' -f1)"
	fi
	echo
	echo "context: host=$(hostname) payload=$PAYLOAD files=$files used=$used tweaks=$TWEAKS_SHA256"
} >>"$prov"
say "provenance block appended to $prov"

say ""
say "done: $img"
say "  sha256 $sum"
say "  verify: the commands in docs/ROOTFS_READY.md"
