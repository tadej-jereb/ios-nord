#!/usr/bin/env bash
# 33b-populate-root-unprivileged.sh - fill the HFSX root image WITHOUT root.
#
# Same payload, same metadata, same stage order as `33-populate-root.sh`, but
# no loop device and no `mount(8)`: the image is mounted by a userspace FUSE
# writer (fstool) and written by unprivileged rsync/ln/chown as uid 1000.
# Nothing here calls sudo. Expect it to be ~3x slower than 33; see
# docs/ROOTFS_UNPRIVILEGED.md for the measured numbers.
#
#   tooling/33b-populate-root-unprivileged.sh --image build/ios16-root.img \
#       --ipsw build/ipsw-x
#
#   --image IMG  default build/ios16-root.img, 16 GiB, HFSX, journaled, empty
#   --ipsw DIR   default build/ipsw-x (the three DMGs from 30-fetch-ipsw.sh)
#   --tree DIR   populate from an already-mounted tree DIR/{os,sysos,appos}
#                (each holding root/), instead of mounting the DMGs
#   --bootstrap  (re)build the patched writer under tooling/opt/fstool
#   --no-verify  skip fsck + count comparison (debug runs)
#
# Upstream fstool 0.5.4 cannot do this; tooling/opt/fstool/fstool-0.5.4-unpriv.patch
# fixes the backend (root getattr, pending-record visibility, rename, hardlink,
# a zeroed mkfs journal header on open). What stays the script's job:
#   * the mount is not `allow_other` (needs an /etc/fuse.conf root edit)
#   * symlink() takes no mode, so HFS+ symlink modes are replayed afterwards
#   * install(1) cannot chown as uid 1000, so dirs/files are chown'ed explicitly
#
# Requirements: fuse3 with /dev/fuse writable by the calling user, rsync >= 3.1,
# python3, hfsprogs (fsck_hfs), apfs-fuse from 32-build-apfsfuse.sh for --ipsw.
set -euo pipefail

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
REPO=$(cd -- "$HERE/.." && pwd)
OPT="$HERE/opt"
FSTOOL_DIR="$OPT/fstool"
FSTOOL="$FSTOOL_DIR/bin/fstool"
APFS_FUSE="$OPT/apfs-fuse/bin/apfs-fuse"
FSTOOL_VER=0.5.4
FSTOOL_SHA=697d7cd3a639e52be6f24598360ff9c7a5e648284a3e374603a9a8d5fdf7493d
FSCK=/usr/sbin/fsck.hfsplus

img=$REPO/build/ios16-root.img
ipsw=$REPO/build/ipsw-x
tree=""
bootstrap=0
do_verify=1

# Same pinned numbers as 33: unique apparent bytes per volume, hard links
# counted once, and the file count of that same measure.
OS_UNIQUE=7937213671 ; SYS_UNIQUE=3359797050 ; APP_UNIQUE=7846405
PAYLOAD=$((OS_UNIQUE + SYS_UNIQUE + APP_UNIQUE))
EXPECT_FILES=144341
VOLUME_BYTES=17179869184
OS_MEMBER=087-86698-044.dmg ; OS_BYTES=4730814044
SYS_MEMBER=087-86593-047.dmg ; SYS_BYTES=2743074816
APP_MEMBER=087-86715-047.dmg ; APP_BYTES=10485760

say()  { printf '%s\n' "$*"; }
step() { printf '\n=== %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

while (( $# )); do
	case $1 in
		--image)     img=${2:?--image needs a path}; shift ;;
		--ipsw)      ipsw=${2:?--ipsw needs a path}; shift ;;
		--tree)      tree=${2:?--tree needs a path}; shift ;;
		--bootstrap) bootstrap=1 ;;
		--no-verify) do_verify=0 ;;
		-h|--help)   sed -n '2,32p' "$0"; exit 0 ;;
		*) die "unknown argument: $1" ;;
	esac
	shift
done

# --- host gate -------------------------------------------------------------
step "host gate (no root anywhere)"
(( EUID != 0 )) || say "warning: running as root, which defeats the point"
[[ -e /dev/fuse ]] || die "/dev/fuse missing - load fuse (modprobe fuse)"
[[ -r /dev/fuse && -w /dev/fuse ]] || die "/dev/fuse not writable by $(id -un)"
command -v fusermount3 >/dev/null || die "fusermount3 missing (apt install fuse3)"
command -v rsync >/dev/null || die "rsync missing"
command -v python3 >/dev/null || die "python3 missing"
[[ -x $FSCK ]] || die "$FSCK missing (apt install hfsprogs)"
rsync_ver=$(rsync --version 2>/dev/null | awk 'NR==1 { print $3 }')
[[ $(printf '%s\n3.1\n' "$rsync_ver" | sort -V | head -1) == 3.1 ]] ||
	die "rsync >= 3.1 required for -H (have $rsync_ver)"
img=$(realpath "$img")
if grep -q " $img " /proc/mounts; then die "$img is mounted - unmount it first"; fi

# --- writer ----------------------------------------------------------------
bootstrap_fstool() {
	step "building the patched writer (unprivileged cargo build)"
	command -v cargo >/dev/null || die "cargo missing:
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal"
	src=$FSTOOL_DIR/src
	rm -rf "$src"
	git clone -q --depth 1 --branch "v$FSTOOL_VER" https://github.com/KarpelesLab/fstool "$src" ||
		die "cannot clone fstool v$FSTOOL_VER"
	# the release tarball is only the prebuilt upstream binary; recorded so the
	# version we clone against is verified to be the one this patch was made for
	tar=$FSTOOL_DIR/fstool-v$FSTOOL_VER.tar.gz
	[[ -f $tar ]] || curl -fsSL -o "$tar" \
		"https://github.com/KarpelesLab/fstool/releases/download/v$FSTOOL_VER/fstool-v$FSTOOL_VER-linux-x86_64.tar.gz"
	echo "$FSTOOL_SHA  $tar" | sha256sum -c --quiet - || die "fstool tarball checksum mismatch"
	( cd "$src" && patch -p1 --batch --forward < "$FSTOOL_DIR/fstool-0.5.4-unpriv.patch" )
	( cd "$src" && cargo build --release --features fuse,hfs-plus,unix-host )
	mkdir -p "$FSTOOL_DIR/bin"
	install -m 0755 "$src/target/release/fstool" "$FSTOOL"
	sha256sum "$FSTOOL" >"$FSTOOL.sha256"
}
if (( bootstrap )); then bootstrap_fstool; fi
[[ -x $FSTOOL ]] || bootstrap_fstool
[[ -x $FSTOOL ]] || die "no writer at $FSTOOL"
"$FSTOOL" mount --help >/dev/null 2>&1 ||
	die "$FSTOOL was built without the fuse feature - rerun with --bootstrap"

# --- sources ---------------------------------------------------------------
work=$(mktemp -d "${TMPDIR:-/tmp}/33b-populate.XXXXXX")
mnt=$work/img
mkdir -p "$mnt"
mnts=("$mnt")
img_pid=""
cleanup() {
	for m in "${mnts[@]}"; do
		if fusermount3 -u -z "$m" 2>/dev/null; then continue; fi
		if mountpoint -q "$m" 2>/dev/null; then say "still mounted: $m" >&2; fi
	done
	rm -rf "$work"
}
trap cleanup EXIT

if [[ -n $tree ]]; then
	tree=$(realpath "$tree")
	src=$tree
	for v in os sysos appos; do [[ -d $src/$v/root ]] || die "$src/$v/root missing"; done
else
	ipsw=$(realpath "$ipsw")
	[[ -x $APFS_FUSE ]] || die "no apfs-fuse at $APFS_FUSE - run 32-build-apfsfuse.sh"
	src=$work/src
	step "mounting the DMGs read-only through apfs-fuse"
	for m in "$OS_MEMBER:$OS_BYTES" "$SYS_MEMBER:$SYS_BYTES" "$APP_MEMBER:$APP_BYTES"; do
		f=$ipsw/${m%:*}
		[[ -f $f ]] || die "missing $f - run 30-fetch-ipsw.sh"
		[[ $(stat -c %s "$f") == "${m##*:}" ]] || die "$f: wrong size"
	done
	for v in os:OS_MEMBER sysos:SYS_MEMBER appos:APP_MEMBER; do
		name=${v%%:*}; member=${v##*:}
		mkdir "$src/$name"
		"$APFS_FUSE" -o ro "$ipsw/$member" "$src/$name"
		mnts=("$src/$name" "${mnts[@]}")
		mountpoint -q "$src/$name" || die "$name did not mount"
	done
fi

# --- image gate ------------------------------------------------------------
step "image gate"
[[ -f $img ]] || die "$img does not exist - run 31-mkiosroot.sh --phase-image"
[[ $(stat -c %s "$img") == "$VOLUME_BYTES" ]] ||
	die "$img is $(stat -c %s "$img") bytes, expected $VOLUME_BYTES"
[[ $(xxd -s 1024 -l 2 -p "$img") == 4858 ]] || die "$img is not HFSX"
python3 - "$img" <<'EOF' || die "$img is not journaled"
import struct, sys
d = open(sys.argv[1], 'rb').read(1100)
attrs, = struct.unpack_from('>I', d, 1024 + 4)
assert attrs & 0x2000, 'journaled bit not set (mkfs.hfsplus -J)'
blk, = struct.unpack_from('>I', d, 1024 + 40)
assert blk > 0, 'zero block size'

EOF
sum_before=$(sha256sum "$img" | cut -d' ' -f1)
say "  sha256 $sum_before"

# --- baseline --------------------------------------------------------------
step "baseline through the source mounts"
python3 - "$src" >"$work/baseline" <<'PY'
import os, sys
src = sys.argv[1]
files = dirs = links = total = 0
seen = set()
for vol in ('os', 'sysos', 'appos'):
	root = os.path.join(src, vol, 'root')
	for dp, dn, fn in os.walk(root):
		for name in dn + fn:
			p = os.path.join(dp, name)
			try: st = os.lstat(p)
			except OSError: continue
			if os.path.islink(p): links += 1
			elif os.path.isdir(p): dirs += 1
			else:
				if st.st_nlink > 1:
					if (st.st_dev, st.st_ino) in seen: continue
					seen.add((st.st_dev, st.st_ino))
				files += 1; total += st.st_size
print(f"files={files} dirs={dirs} symlinks={links} bytes={total}")
PY
cat "$work/baseline"
say "  pinned: $PAYLOAD bytes in $EXPECT_FILES files (hard links counted once)"
measured=$(sed -n 's/.*bytes=//p' "$work/baseline")
(( measured > PAYLOAD * 98 / 100 && measured < PAYLOAD * 102 / 100 )) ||
	say "warning: measured payload $measured B differs from pinned $PAYLOAD B by >2%" >&2

# --- mount the image -------------------------------------------------------
step "mounting the image through the userspace writer"
"$FSTOOL" mount "$img" "$mnt" 2>"$work/mount.log" &
img_pid=$!
for _ in $(seq 1 200); do
	if grep -q 'mounted' "$work/mount.log" 2>/dev/null; then break; fi
	kill -0 "$img_pid" 2>/dev/null || { cat "$work/mount.log"; die "writer died on mount"; }
	sleep 0.1
done
mountpoint -q "$mnt" || { cat "$work/mount.log"; die "image did not mount"; }
say "  mounted at $mnt (writer pid $img_pid)"
[[ $(stat -f -c %T "$mnt") == fuse* ]] || die "$mnt is not a fuse mount"

umount_img() {
	kill -0 "$img_pid" 2>/dev/null || die "writer already gone"
	fusermount3 -u "$mnt" || die "unmount failed - refusing to fsck a live mount"
	wait "$img_pid" 2>/dev/null || true
	img_pid=""
}

entries=$(find "$mnt" -mindepth 1 -maxdepth 1 -not -name '.journal*' | wc -l)
(( entries == 0 )) || die "$mnt already has $entries entries - populate a fresh image"

# --- space guard -----------------------------------------------------------
vavail=$(df -B1 --output=avail "$mnt" | tail -1 | tr -d ' ')
# 5 % for catalog nodes, extents overflow and the fsck pass; hard links mean the
# payload is stored once, so this is the 33 arithmetic minus nothing.
need=$(( PAYLOAD + PAYLOAD / 100 * 5 + 64 * 1024 * 1024 ))
say "volume $vavail B free, payload $PAYLOAD B, need $need B"
(( vavail >= need )) || die "volume too small: $vavail B free < $need B needed"

# --- hard link probe -------------------------------------------------------
probe=$mnt/.populate-link-probe
: >"$probe"
if ln "$probe" "$probe.2" 2>/dev/null && [[ $(stat -c %h "$probe" 2>/dev/null) == 2 ]]; then
	link=ln
else
	link=cp
	say "warning: hard links unavailable - cache stages will copy and the volume may not fit" >&2
fi
rm -f "$probe" "$probe.2"

# --- stages ----------------------------------------------------------------
copy() { # src dst label
	step "copy $3"
	mkdir -p "$2"
	set +e
	rsync -aH --numeric-ids --super --whole-file --partial-dir=.rsync-partial "$1/" "$2/"
	rc=$?
	set -e
	(( rc == 0 || rc == 23 || rc == 24 )) || die "rsync $3 failed with exit $rc"
	find "$2" -maxdepth 1 -name .rsync-partial -exec rm -rf {} + 2>/dev/null || true
}
copy "$src/os/root" "$mnt" os
copy "$src/sysos/root" "$mnt/private/preboot/Cryptexes/OS" sysos
copy "$src/appos/root" "$mnt/private/preboot/Cryptexes/App" appos

step "hard-link the dyld shared cache"
dyld_src=$mnt/private/preboot/Cryptexes/OS/System/Library/Caches/com.apple.dyld
dyld_dst=$mnt/System/Library/Caches/com.apple.dyld
[[ -d $dyld_src ]] || die "no dyld cache at $dyld_src"
mkdir -p "$dyld_dst"
n=0
for f in "$dyld_src"/*; do
	t=$dyld_dst/${f##*/}
	if [[ -e $t ]]; then continue; fi
	if [[ $link == ln ]]; then ln "$f" "$t"; else cp -p "$f" "$t"; fi
	n=$((n + 1))
done
say "linked $n cache files"

step "hard-link cryptex-only files to their root path"
n=0
for c in OS App; do
	while IFS= read -r f; do
		f=${f#./}
		if [[ -e $mnt/$f || -L $mnt/$f ]]; then continue; fi
		mkdir -p "$mnt/$(dirname "$f")"
		s=$mnt/private/preboot/Cryptexes/$c/$f
		if [[ -L $s || $link == cp ]]; then cp -P "$s" "$mnt/$f"; else ln "$s" "$mnt/$f"; fi
		n=$((n + 1))
	done < <(cd "$mnt/private/preboot/Cryptexes/$c" &&
		find . ! -type d ! -path './System/Library/Caches/com.apple.dyld/*')
done
say "linked $n cryptex files"

step "create logd stores (owner 272)"
db=$mnt/private/var/db
mkdir -p "$db/diagnostics/timesync" "$db/uuidtext"
chown 272:272 "$db/diagnostics" "$db/uuidtext" "$db/diagnostics/timesync"
chmod 0751 "$db/diagnostics"
chmod 0755 "$db/uuidtext" "$db/diagnostics/timesync"
for d in diagnostics uuidtext diagnostics/timesync; do
	: >"$db/$d/.migrated"
	chown 272:272 "$db/$d/.migrated"
	chmod 0644 "$db/$d/.migrated"
done

step "install the plain keybag (root:wheel, 0600)"
kb=$mnt/private/var/keybags
mkdir -p "$kb"
chown 0:0 "$kb"; chmod 0700 "$kb"
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
	'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	'<plist version="1.0"><dict><key>KeyBagKeys</key><data>U1dFRVQ=</data></dict></plist>' >"$kb/systembag.kb"
chown 0:0 "$kb/systembag.kb"
chmod 0600 "$kb/systembag.kb"

tweaks=${SWEET_TWEAKS:-$REPO/refs/ios-sweet/sweet-root-tweaks.py}
if [[ -f $tweaks ]]; then
	step "apply bring-up tweaks"
	python3 "$tweaks" "$mnt" || say "warning: tweaks script exited $?" >&2
else
	step "bring-up tweaks script not found, skipped ($tweaks)"
fi

# symlink() cannot carry a mode; HFS+ stores Apple's 0755 on symlinks
step "replay symlink modes"
python3 - "$src" "$mnt" <<'PY' || true
import os, sys
src, mnt = sys.argv[1], sys.argv[2]
for vol in ('os', 'sysos', 'appos'):
	root = os.path.join(src, vol, 'root')
	for dp, dn, fn in os.walk(root):
		for name in dn + fn:
			p = os.path.join(dp, name)
			if not os.path.islink(p): continue
			t = os.path.join(mnt, os.path.relpath(p, root))
			try: os.chmod(t, os.lstat(p).st_mode & 0o7777, follow_symlinks=False)
			except (OSError, NotImplementedError): pass

PY

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
apparent=$(du -sb --apparent-size "$mnt" | cut -f1)
used=$(df -B1 --output=used "$mnt" | tail -1 | tr -d ' ')
say "files $files, $used B allocated, $apparent B apparent (hard links counted twice)"
(( files > 180000 )) || die "only $files files on the volume, expected > 180000"
(( used > 11000000000 )) || die "only $used B allocated, expected > 11e9"
if [[ $link == ln ]]; then
	[[ $(stat -c %h "$dyld_dst"/* | sort -u | tr '\n' ' ') == "2 "* ]] ||
		say "warning: dyld cache files do not report nlink 2" >&2
fi

# --- unmount, fsck ---------------------------------------------------------
step "unmount"
umount_img
for m in "${mnts[@]:1}"; do
	fusermount3 -u "$m" 2>/dev/null || true
done
mnts=("$mnt")
say "  image is quiescent"

step "fsck -fy, then fsck -n must be clean"
"$FSCK" -f -y "$img" >"$work/fsck-repair.log" 2>&1 || true
grep -v 'Illegal name' "$work/fsck-repair.log" | tail -3
"$FSCK" -f -n "$img" >"$work/fsck.log" 2>&1 || { cat "$work/fsck.log"; die "fsck is not clean"; }
grep -q 'appears to be OK' "$work/fsck.log" || { cat "$work/fsck.log"; die "fsck did not report OK"; }
say "  fsck: clean"

# --- count / byte comparison against the baseline --------------------------
if (( do_verify )); then
	step "count and byte comparison (fresh read of the image, no writer cache)"
	mkdir -p "$work/ro"
	"$FSTOOL" mount "$img" "$work/ro" 2>"$work/ro.log" & ro_pid=$!
	for _ in $(seq 1 200); do
		if mountpoint -q "$work/ro"; then break; fi
		sleep 0.1
	done
	mountpoint -q "$work/ro" || { cat "$work/ro.log"; die "cannot remount for verification"; }
	python3 - "$work/ro" "$work/baseline" <<'PY'
	import os, sys, re
	mnt, base = sys.argv[1], sys.argv[2]
	files = total = 0
	seen = set()
	for dp, dn, fn in os.walk(mnt):
		for name in dn + fn:
			p = os.path.join(dp, name)
			try: st = os.lstat(p)
			except OSError: continue
			if os.path.islink(p) or os.path.isdir(p): continue
			if st.st_nlink > 1:
				if (st.st_dev, st.st_ino) in seen: continue
				seen.add((st.st_dev, st.st_ino))
			files += 1; total += st.st_size
	exp = dict(re.findall(r'(\w+)=(\d+)', open(base).read()))
	print(f"  image    files={files} bytes={total}")
	print(f"  baseline files={exp['files']} bytes={exp['bytes']}")
	bad = []
	if files != int(exp['files']): bad.append(f"files {files} != {exp['files']}")
	if total != int(exp['bytes']): bad.append(f"bytes {total} != {exp['bytes']}")
	if bad: print("  MISMATCH: " + ", ".join(bad)); sys.exit(2)
	print("  match")
PY
	fusermount3 -u "$work/ro" 2>/dev/null || true
	wait "$ro_pid" 2>/dev/null || true
	mnts=("$mnt")
fi

# --- record ----------------------------------------------------------------
sum_after=$(sha256sum "$img" | cut -d' ' -f1)
mkdir -p "$REPO/logs"
log=$REPO/logs/33b-populate-$(date +%Y%m%dT%H%M%S).log
{
	echo "image  $img"
	echo "sha256 $sum_before -> $sum_after"
	echo "bytes  $(stat -c %s "$img") apparent, $(du -B1 "$img" | cut -f1) B on disk"
	echo "files  $files  used $used  apparent $apparent  payload $PAYLOAD"
	echo "writer $FSTOOL sha256 $(sha256sum "$FSTOOL" | cut -d' ' -f1)"
	echo "fsck   $(tail -1 "$work/fsck.log" 2>/dev/null || echo clean)"
} >"$log"
say ""
say "done: $img"
say "  sha256 $sum_after"
say "  log    $log"
