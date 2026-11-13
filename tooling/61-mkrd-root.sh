#!/usr/bin/env bash
# 61-mkrd-root.sh - build the minimal RAMDISK root for the first launchd exec.
#
# The volume root of the ladder in docs/LAUNCHD_BOOTSTRAP.md is an HFS volume on
# md0 (docs/RAMDISK_ROOT.md holds the code path and every divergence from the
# real 16 GiB root). This script only builds that image and checks it; it does
# not touch the phone and does not boot anything.
#
#   tooling/61-mkrd-root.sh --no-cache         # skeleton, ~4 MiB, stops at dyld
#   tooling/61-mkrd-root.sh                    # full set, ~2.9 GiB image
#   tooling/61-mkrd-root.sh --size 3GiB --out build/rd-root.img
#
#   --ipsw DIR     default build/ipsw-x - the DMGs from 30-fetch-ipsw.sh
#   --out IMG      default build/rd-root.img
#   --staging DIR  default build/rd-root.stage (kept; the checker runs on it)
#   --size SIZE    image size; default is the measured set x1.12 + 16 MiB
#   --no-cache     omit the dyld shared cache (43 files, 2.61 GiB)
#   --qemu         hand the image to tooling/60-qemu-boot.sh if it exists
#
# The image carries the ordered minimal set of docs/LAUNCHD_BOOTSTRAP.md
# section 5 (steps 1-9), and nothing else. Source files come from the DMGs
# mounted read-only through tooling/opt/apfs-fuse, never from the phone.
#
# Needs: apfs-fuse (32-build-apfsfuse.sh), tooling/opt/fstool (the patched
# unprivileged HFS+ writer), fuse3, hfsprogs. No root, no loop device.
set -euo pipefail

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
REPO=$(cd -- "$HERE/.." && pwd)
OPT="$HERE/opt"
APFS_FUSE="$OPT/apfs-fuse/bin/apfs-fuse"
FSTOOL="$OPT/fstool/bin/fstool"
FSCK=/usr/sbin/fsck.hfsplus
CHECK="$HERE/34-check-bootstrap.sh"
QEMU="$HERE/60-qemu-boot.sh"

ipsw=$REPO/build/ipsw-x
out=$REPO/build/rd-root.img
stage=$REPO/build/rd-root.stage
want_size=""
do_cache=1
do_qemu=0

OS_DMG=087-86698-044.dmg        # System volume - launchd, dyld, /private/etc
SYS_DMG=087-86593-047.dmg       # SystemOS cryptex - the dyld shared cache
CACHE_REL=System/Library/Caches/com.apple.dyld
CACHE_SRC=$CACHE_REL
CACHE_HOLD=private/var/db/.rdcache   # the cache files live here, hard-linked out
CMDLINE="rd=md0 keepsyms=1 debug=0x8 launchd_log_serial=1 launchd_disable_all_timeouts=1 -v"

say()  { printf '%s\n' "$*"; }
step() { printf '\n=== %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

while (( $# )); do
	case $1 in
		--ipsw)    ipsw=${2:?--ipsw needs a directory}; shift ;;
		--out)     out=${2:?--out needs a path}; shift ;;
		--staging) stage=${2:?--staging needs a path}; shift ;;
		--size)    want_size=${2:?--size needs a value}; shift ;;
		--no-cache) do_cache=0 ;;
		--qemu)    do_qemu=1 ;;
		-h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//' ; exit 0 ;;
		*) die "unknown argument: $1" ;;
	esac
	shift
done

[[ -x $APFS_FUSE ]] || die "no apfs-fuse at $APFS_FUSE - run tooling/32-build-apfsfuse.sh"
[[ -x $FSTOOL ]]    || die "no fstool at $FSTOOL - run tooling/33b-populate-root-unprivileged.sh --bootstrap"
[[ -x $FSCK ]]      || die "$FSCK missing (apt install hfsprogs)"
[[ -r /dev/fuse && -w /dev/fuse ]] || die "/dev/fuse not writable by $(id -un)"
command -v fusermount3 >/dev/null || die "fusermount3 missing (apt install fuse3)"
[[ -x $CHECK ]]     || die "no checker at $CHECK"
for d in "$ipsw/$OS_DMG" "$ipsw/$SYS_DMG"; do
	[[ -r $d ]] || die "missing $d - run tooling/30-fetch-ipsw.sh"
done

work=$(mktemp -d "${TMPDIR:-/tmp}/rd-root.XXXXXX")
mkdir -p "$work/img"	# early: fstool mount stats the mountpoint right after mounting
mnts=()
cleanup() {
	local m
	for m in "${mnts[@]}"; do fusermount3 -u "$m" 2>/dev/null || true; done
	[[ ${RD_KEEP:-0} == 1 ]] && { say "work kept: $work"; return; }
	rm -rf "$work"
}
trap cleanup EXIT

mount_dmg() {	# mount_dmg DMG MOUNTPOINT
	mkdir -p "$2"
	"$APFS_FUSE" "$1" "$2" >"$work/$(basename "$2").log" 2>&1 ||
		die "apfs-fuse failed on $1: $(tail -1 "$work/$(basename "$2").log")"
	mnts+=("$2")
}

step "mounting the DMGs read-only through apfs-fuse"
mount_dmg "$ipsw/$OS_DMG"  "$work/os"
mount_dmg "$ipsw/$SYS_DMG" "$work/sysos"
os=$work/os/root
sysos=$work/sysos/root
[[ -f $os/sbin/launchd ]] || die "no /sbin/launchd in $OS_DMG"
[[ -f $os/usr/lib/dyld ]] || die "no /usr/lib/dyld in $OS_DMG"
if (( do_cache )); then
	[[ -d $sysos/$CACHE_SRC ]] || die "no $CACHE_SRC in $SYS_DMG"
fi

# ---------------------------------------------------------------------------
# The set. Kept in one table so the size report, the staging and the checker
# look at exactly the same paths: docs/LAUNCHD_BOOTSTRAP.md section 5, steps 1-9.
# ---------------------------------------------------------------------------

# dirs: path, mode, owner  (step 5 and 7 directories, plus parents)
dirs=(
	"/:0755:0:0"
	"/dev:0555:0:0"				# 1 - devfs mount point bsd_init.c:977
	"/sbin:0755:0:0" "/usr:0755:0:0" "/usr/lib:0755:0:0" "/usr/libexec:0755:0:0" "/usr/sbin:0755:0:0"
	"/private:0755:0:0" "/private/etc:0755:0:0"
	"/private/tmp:1777:0:0"			# 5 - mkdtemp
	"/private/var:0755:0:0"
	"/private/var/tmp:1777:0:0"
	"/private/var/run:0755:0:0"
	"/private/var/db:0755:0:0"
	"/private/var/keybags:0700:0:0"
	"/private/var/db/diagnostics:0751:272:272"	# logd stores, libtrace
	"/private/var/db/uuidtext:0755:272:272"
	"/System:0755:0:0" "/System/Library:0755:0:0"
	"/System/Library/LaunchDaemons:0755:0:0"		# 7 - scan dir
	"/System/Library/LaunchAgents:0755:0:0"
	"/System/Library/CoreServices:0755:0:0"
	"/System/Library/Caches:0755:0:0"
	"/System/Library/Caches/com.apple.dyld:0755:0:0"	# 4 - dyld's first path
	"/System/Library/PrivateFrameworks:0755:0:0"
	"/System/Library/PrivateFrameworks/MobileAccessoryUpdater.framework:0755:0:0"
	"/System/Library/PrivateFrameworks/MobileAccessoryUpdater.framework/Support:0755:0:0"
)

# The boot table, verbatim from /sbin/launchd __TEXT,__config Boot dict
# (file 411743..420021, 29 entries). 18 of the 25 Program keys resolve in
# 20H392; HorizonSetup and darwinos-boot-task are iOS 17/18 leftovers.
boot_progs=(
	/System/Library/PrivateFrameworks/MobileAccessoryUpdater.framework/Support/auearlyboot
	/usr/libexec/dirs_cleaner
	/sbin/mount
	/usr/libexec/keybagd
	/usr/libexec/cc_fips_test
	/usr/libexec/FinishRestoreFromBackup
	/usr/libexec/tzinit
	/usr/libexec/init_data_protection
	/usr/sbin/nvram
	/sbin/fsck
	/usr/libexec/sysstatuscheck
	/usr/libexec/mobile_obliterator
	/usr/libexec/finish_demo_restore
	/usr/libexec/usermanagerd
	/usr/libexec/init_featureflags
	/usr/libexec/prng_seedctl
	/usr/libexec/launchd_cache_loader
	/usr/libexec/MSUEarlyBootTask
	/usr/libexec/seputil			# data-protection CSIdentityOverride
	/usr/libexec/xpcproxy			# spawns the XPC boot tasks
	/usr/libexec/xpcroleaccountd
)

# etc files: /private/etc source, mode (step 6)
etc=(
	"master.passwd:0600" "group:0644" "passwd:0644" "ttys:0644" "hosts:0644"
)

need=0
add_bytes() { need=$((need + $(stat -c %s "$1"))); }

rm -rf "$stage"
mkdir -p "$stage"

step "staging the set in $stage"
for d in "${dirs[@]}"; do
	IFS=: read -r p m u g <<<"$d"
	mkdir -p "$stage$p"
	chmod "$m" "$stage$p"
done

install -m 0755 "$os/sbin/launchd" "$stage/sbin/launchd"; add_bytes "$os/sbin/launchd"
install -m 0755 "$os/usr/lib/dyld" "$stage/usr/lib/dyld"; add_bytes "$os/usr/lib/dyld"
# dyld must be 0755 and is the LC_LOAD_DYLINKER target of launchd; the kernel
# loads it itself before any userland runs.

for p in "${boot_progs[@]}"; do
	[[ -f $os$p ]] || die "boot Program missing in $OS_DMG: $p"
	install -m 0755 "$os$p" "$stage$p"
	add_bytes "$os$p"
done

for e in "${etc[@]}"; do
	f=${e%:*}; m=${e##*:}
	[[ -f $os/private/etc/$f ]] || die "no /private/etc/$f in $OS_DMG"
	install -m "$m" "$os/private/etc/$f" "$stage/private/etc/$f"
	add_bytes "$os/private/etc/$f"
done

# mount-phase-1's setfsent() needs a real file: the avicii ADT has no
# /filesystems/fstab node. On a ramdisk root /private/var is on the same
# volume, so the entry names md0 itself; ro keeps it honest.
printf '/dev/md0 /private/var hfs ro 0 2\n' >"$stage/private/etc/fstab"
add_bytes "$stage/private/etc/fstab"

install -m 0444 "$os/System/Library/CoreServices/SystemVersion.plist" \
	"$stage/System/Library/CoreServices/SystemVersion.plist"
add_bytes "$os/System/Library/CoreServices/SystemVersion.plist"

# keybag placeholder, byte-identical to the populate script's
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
	'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	'<plist version="1.0"><dict><key>KeyBagKeys</key><data>U1dFRVQ=</data></dict></plist>' \
	>"$stage/private/var/keybags/systembag.kb"
chmod 0600 "$stage/private/var/keybags/systembag.kb"
add_bytes "$stage/private/var/keybags/systembag.kb"

for f in private/var/db/diagnostics/.migrated private/var/db/uuidtext/.migrated; do
	install -m 0644 /dev/null "$stage/$f"
done

if (( do_cache )); then
	step "hard-linking the dyld shared cache (43 files, .symbols left out)"
	# The cache files are copied once into .rdcache and hard-linked out, so the
	# dyld path is a second name of the same blocks (nlink 2), not a copy - the
	# same shape the cryptexlinks stage gives the real volume.
	install -d -m 0755 "$stage/$CACHE_HOLD"
	n=0
	for f in "$sysos/$CACHE_SRC"/*; do
		b=$(basename "$f")
		[[ $b == *.symbols ]] && continue		# 592 MiB, symbolication only
		install -m 0755 "$f" "$stage/$CACHE_HOLD/$b"
		add_bytes "$f"
		n=$((n + 1))
	done
	(( n >= 43 )) || die "only $n cache files in $sysos/$CACHE_SRC"
	for f in "$stage/$CACHE_HOLD"/*; do
		ln "$f" "$stage/$CACHE_REL/$(basename "$f")"
	done
	say "$n cache files, $(stat -c %h "$stage/$CACHE_REL/dyld_shared_cache_arm64") links on the base cache"
else
	say "cache omitted (--no-cache): dyld will stop with 'Library not loaded'"
fi

# ---------------------------------------------------------------------------
# Size. The image is RAM, so it is sized tight: 112 % of the payload plus
# 16 MiB covers the 4K block rounding and the catalog for ~150 entries, with
# ~10 % left over. --size overrides.
# ---------------------------------------------------------------------------
if [[ -n $want_size ]]; then
	size=$want_size
else
	size=$(( need + need * 12 / 100 + 16 * 1024 * 1024 ))
	size=$(( (size + 1024 * 1024 - 1) / (1024 * 1024) ))
	size=$(( size > 32 ? size : 32 ))M
fi

step "building $out ($size, HFS+, unjournaled 4K)"
rm -f "$out"
"$FSTOOL" create --type hfs+ --output "$out" --size "$size" \
	-O volume_label=RD-root -O block_size=4096 -O journaled=false "$stage"
# fstool create cannot chown an HFS+ tree, so the owners go on through a mount.
mkdir -p "$work/img"
"$FSTOOL" mount "$out" "$work/img" >>"$work/img.log" 2>&1 &
mpid=$!
# The mountpoint is a plain directory until the FUSE handshake finishes; only
# then does its filesystem type read back as "fuse*".
for _ in $(seq 600); do
	[[ $(stat -f -c %T "$work/img" 2>/dev/null) == fuse* ]] && break
	kill -0 "$mpid" 2>/dev/null || break
	sleep 0.2
done
[[ $(stat -f -c %T "$work/img" 2>/dev/null) == fuse* ]] || die "fstool mount failed: $(tail -2 "$work/img.log")"
mnts+=("$work/img")
say "mounted; note: fstool cannot getattr the mountpoint root (stat/chown of \"/\" fail), children are fine"

step "applying owners and modes in the image"
# fstool's FUSE layer cannot getattr the *root* path itself (ENOENT on the root
# inode), so find/chown on the mountpoint fail while children work. The paths
# are therefore walked on the staging tree and replayed one by one here.
(cd "$stage" && find . -mindepth 1) | sed 's|^\./||' | while read -r p; do
	case $p in
		# hard links: chown through fstool writes a second catalog record for
		# the link name and breaks the shared CNID ("Incorrect number of file
		# hard links" in fsck). Nothing to do - 0755 from the staging is right.
		*/Caches/com.apple.dyld/*|private/var/db/.rdcache/*) continue ;;
	esac
	chown -h 0:0 "$work/img/$p"
	chmod "$(stat -c %a "$stage/$p")" "$work/img/$p"
done
chown -h 272:272 "$work/img/private/var/db/diagnostics" "$work/img/private/var/db/uuidtext" \
	"$work/img/private/var/db/diagnostics/.migrated" "$work/img/private/var/db/uuidtext/.migrated"
chmod 0751 "$work/img/private/var/db/diagnostics"
chmod 0755 "$work/img/private/var/db/uuidtext"
# Hard-linked files cannot be chown'ed through fstool (silent no-op, the link
# attrs are synthetic), so the cache keeps the staging uid; 0755 root:wheel
# would be the DMG's, 1000:1000 reads the same for every user.

probes=("sbin/launchd:0:0:755" "private/var/keybags/systembag.kb:0:0:600" \
	"dev:0:0:555" "private/var/tmp:0:0:1777")
if (( do_cache )); then
	probes+=("System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64:1000:1000:755")
fi

for probe in "${probes[@]}"; do
	IFS=: read -r p u g m <<<"$probe"
	got=$(stat -c '%u:%g:%a' "$work/img/$p")
	[[ $got == "$u:$g:$m" ]] || die "/$p is $got, expected $u:$g:$m"
done

# The checker runs on the staging tree: same relative set, same modes; the
# image only adds the owners, which are asserted above. The image itself is
# checked below by count, link count and byte comparison, because the checker
# cannot stat a fstool mountpoint root (getattr ENOENT on "/").
"$CHECK" "$stage" --min-files 0 >"$work/check.log" 2>&1 || true
awk '$1 != "ok" && $1 != "STATUS" && $1 != "note"' "$work/check.log"
summary=$(tail -1 "$work/check.log")
say "checker: $summary"
case $summary in *"absent 0, mismatch 0"*) rc=0 ;; *) rc=1 ;; esac

step "checking the image content"
# find(1) exits 1 on the mountpoint root (getattr ENOENT) but still descends,
# so its status is dropped and only the count is used.
s_n=$(find "$stage" -type f | wc -l)
i_n=$( (find "$work/img" -type f 2>/dev/null || true) | wc -l )
[[ $i_n == "$s_n" ]] || die "image has $i_n files, staging has $s_n"
say "$i_n files, same count as the staging"
for f in sbin/launchd usr/lib/dyld private/etc/master.passwd private/etc/fstab \
	private/var/keybags/systembag.kb; do
	cmp -s "$work/img/$f" "$stage/$f" || die "/$f differs between staging and image"
done
say "launchd, dyld and the etc files are byte-identical to the staging copy"
if (( do_cache )); then
	nl=$(stat -c %h "$work/img/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64")
	[[ $nl == 2 ]] || die "cache base has link count $nl, expected 2"
	[[ $( (find "$work/img/System/Library/Caches/com.apple.dyld" -maxdepth 1 -type f 2>/dev/null || true) | wc -l) == 43 ]] ||
		die "cache dir does not hold 43 files in the image"
	say "43 cache files, link count 2, all in the image"
fi

sync
fusermount3 -u "$work/img" || die "unmount failed - refusing to fsck a live mount"
wait "$mpid" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Verify the artifact
# ---------------------------------------------------------------------------
step "verifying the image"
sig=$(xxd -s 1024 -l 2 -p "$out")
[[ $sig == 482b ]] || die "volume header magic $sig, expected 482b (HFS+)"
mach=$(xxd -l 4 -p "$out")
case $mach in
	cffaedfe|feedface|bebafeca|cafebabe|cefaedfe|feedfacf)
		die "block 0 starts with a Mach-O magic ($mach): mockfs would take the device" ;;
esac
"$FSTOOL" check "$out" | tail -1
fsckout=$("$FSCK" -n "$out" | tail -1)
say "fsck: $fsckout"
grep -q 'appears to be OK' <<<"$fsckout" || die "fsck is not clean"

bytes=$(stat -c %s "$out")
say "image $out: $bytes B ($(numfmt --to=iec "$bytes"))"
say "set ${need} B ($(numfmt --to=iec "$need")), $(find "$stage" -type f | wc -l) files, $(du -sb "$stage" | cut -f1) B apparent"
say "sha256 $(sha256sum "$out" | cut -d' ' -f1)"

cat <<EOF

boot it with:
  mkpayload line:  --ramdisk $out
  cmdline:         $CMDLINE
  ADT:             /chosen/memory-map "RAMDisk" = <phys, size> is written by
                   avicii/tools/mkpayload.py --ramdisk; the md driver makes md0
                   from it and rd=md0 roots on it (IOKitBSDInit.cpp:760-790)
  checker:         $CHECK $stage --min-files 0   (exit $rc)
EOF

if (( rc != 0 )); then
	say "warning: the checker reported absent/mismatch items (see above and docs/RAMDISK_ROOT.md)"
fi

if (( do_qemu )); then
	if [[ -x $QEMU ]]; then
		step "booting under QEMU"
		"$QEMU" --ramdisk "$out" --cmdline "$CMDLINE"
	else
		say "no $QEMU yet - nothing to boot"
	fi
fi
