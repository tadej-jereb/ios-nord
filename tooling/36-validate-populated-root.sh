#!/bin/bash
# 36-validate-populated-root.sh - the one post-populate command. Two
# independent legs, both of which must pass before a populated root is worth a
# boot round trip:
#
#   A  image bytes  tooling/35-verify-root-image.sh IMAGE REFERENCE
#      fsck, volume header, path set, bytes, symlink targets, mode, owner,
#      hard-link groups. Reads the image file, never mounts it.
#   B  the ordered launchd first-run set
#      tooling/34-check-bootstrap.sh TREE --reference REFERENCE
#      against a tree of the volume: the loop mount tooling/33 already holds
#      (--root), or a read-only userspace FUSE mount made here with
#      tooling/opt/fstool when no --root is given.
#
# Success is reported only when both legs ran to completion AND both exited 0.
# Anything else prints NOT READY with the failing leg named. Nothing here calls
# sudo and nothing here is executed on the phone.
#
#   tooling/36-validate-populated-root.sh IMAGE REFERENCE [options]
#
#   IMAGE       the populated image (build/ios16-root.img). Read; leg B's
#               userspace mount is a writer, so the image sha256 is printed
#               before and after and a change is called out.
#   REFERENCE   the tree the image should hold, as one directory (an extracted
#               or mounted copy of the DMGs). A live apfs-fuse mount is the
#               strongest form: it carries real owners. Read only.
#               Do not hand in the fstool mount made by leg B as REFERENCE: its
#               root readdir carries an empty name, which find(1) reports as
#               "No such file or directory" (the count is still right) and
#               which rsync refuses outright. It is fine as --root.
#
#   --reference-split DIR   REFERENCE is not merged but still split as the
#               three DMG mounts DIR/{os,sysos,appos}/root. They are merged
#               into a private hard-link tree (rsync --link-dest) so that
#               files the volume legitimately carries from sysos/appos are not
#               reported as extra. Falls back to a copy when the mount cannot
#               hard-link; that needs ~11.3 GB free and takes minutes.
#   --root DIR  tree of the volume to check with leg B instead of mounting the
#               image here - this is what tooling/33 passes while its own loop
#               mount is up. Implies --no-fsck (33 fsck's the image after its
#               unmount); --fsck forces leg A's fsck anyway.
#   --fsck      force leg A's fsck even with --root
#   --strict-extras  gate extra paths. A populated root carries files the DMGs
#               do not (/dev, /private/etc/fstab, the keybag, 33's boot set),
#               so by default leg A tolerates extras and the two counts they
#               move (file count, total bytes); everything else still fails.
#   --loud      show leg B's per-item lines (default: absent/mismatch only)
#   --ref-mount DIR, --expect-files N, --expect-bytes N, --limit N,
#   --keep, --reader P    passed to 35
#   --min-files N          passed to 34
#   -h | --help
#
# Verdict codes: 0 both legs passed; 1 leg A (volume) failed; 2 leg B
# (bootstrap set) failed; 4 a leg could not run at all; 3 both failed; 64 usage.
# 1/2 are the exit codes of 34 and 35 themselves.
#
# Both legs are read-only checks. What they still cannot prove is runtime
# behaviour: that launchd execs, that dyld resolves, that anything stays up.
set -uo pipefail

PROG=$(basename "$0")
HERE=$(cd -- "$(dirname -- "$0")" && pwd)
CHECK_BOOT=$HERE/34-check-bootstrap.sh
VERIFY_IMG=$HERE/35-verify-root-image.sh
FSTOOL=$HERE/opt/fstool/bin/fstool
FSTOOL_SHA_FILE=$HERE/opt/fstool/bin/fstool.sha256

img=""
ref=""
ref_split=""
root=""
ref_mount=""
expect_files=""
expect_bytes=""
limit=""
min_files=""
keep=0
loud=0
fsck=0
strict_extras=0
reader=""

say() { printf '%s\n' "$*"; }
die() { local c=${2:-64}; printf '%s: %s\n' "$PROG" "$1" >&2; exit "$c"; }
usage() { sed -n '2,/^set -/p' "$0" | sed -n '/^set -/!s/^# \{0,1\}//p'; exit 64; }
step() { printf '\n=== %s\n' "$*"; }

while (($#)); do
	case $1 in
	--reference-split) ref_split=${2:-}; shift 2 || usage ;;
	--root) root=${2:-}; shift 2 || usage ;;
	--fsck) fsck=1; shift ;;
	--strict-extras) strict_extras=1; shift ;;
	--loud) loud=1; shift ;;
	--ref-mount) ref_mount=${2:-}; shift 2 || usage ;;
	--expect-files) expect_files=${2:-}; shift 2 || usage ;;
	--expect-bytes) expect_bytes=${2:-}; shift 2 || usage ;;
	--limit) limit=${2:-}; shift 2 || usage ;;
	--min-files) min_files=${2:-}; shift 2 || usage ;;
	--keep) keep=1; shift ;;
	--reader) reader=${2:-}; shift 2 || usage ;;
	-h | --help) usage ;;
	-*) printf '%s: unknown option %s\n' "$PROG" "$1" >&2; usage ;;
	*)
		if [[ -z $img ]]; then img=$1
		elif [[ -z $ref ]]; then ref=$1
		else printf '%s: one IMAGE and one REFERENCE only\n' "$PROG" >&2; usage
		fi
		shift ;;
	esac
done

[[ -n $img ]] || usage
[[ -n $ref || -n $ref_split ]] || usage
[[ -z $ref || -z $ref_split ]] || usage "give REFERENCE or --reference-split, not both"

# --- preflight: refuse a leg that cannot run rather than silently skip it ----
[[ -f $img ]] || die "not a file: $img"
[[ -r $img ]] || die "cannot read: $img"
[[ -x $CHECK_BOOT ]] || die "missing $CHECK_BOOT"
[[ -x $VERIFY_IMG ]] || die "missing $VERIFY_IMG"
img=$(cd -- "$(dirname -- "$img")" && pwd)/$(basename -- "$img")
[[ -s $img ]] || die "image is empty: $img"

# Volume header signature, read straight off the volume: names the mistake
# cheaply instead of letting leg A discover it. HFSX is what the root must be;
# H+ (a fixture image) still runs, leg A fails it on the signature.
sig_note=""
sig=$(od -An -tx1 -j 1024 -N 2 "$img" | tr -d ' \n')
case $sig in
4858) ;;
482b) sig_note="HFS+ (H+), not HFSX - leg A will fail it on the signature" ;;
*) die "not an HFS volume (no HX/H+ signature at 0x400): $img" ;;
esac

if [[ -n $root ]]; then
	[[ -d $root ]] || die "no such tree: $root"
	root=$(cd -- "$root" && pwd)
elif [[ -z $ref ]]; then
	die "--reference-split needs --root or a merged REFERENCE"
fi

if [[ -n $ref ]]; then
	[[ -d $ref ]] || die "no such reference dir: $ref"
	ref=$(cd -- "$ref" && pwd)
fi
if [[ -n $ref_split ]]; then
	[[ -d $ref_split ]] || die "no such split reference: $ref_split"
	ref_split=$(cd -- "$ref_split" && pwd)
	for v in os sysos appos; do
		[[ -d $ref_split/$v/root ]] || die "split reference lacks $v/root: $ref_split"
	done
fi
[[ -z $ref_mount || -d $ref_mount ]] || die "no such overlay: $ref_mount"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/validate-root.XXXXXX") || die "cannot make a temp dir"
mnt=$tmp/root
merged=""
tree=${root:-}
mounted=0
fstool_pid=""

cleanup() {
	if (( mounted )); then
		fusermount3 -u "$mnt" 2>/dev/null || true
		if (( fstool_pid )); then
			kill "$fstool_pid" 2>/dev/null || true
			wait "$fstool_pid" 2>/dev/null || true
		fi
		mounted=0
	fi
	(( keep )) && say "raw inventories kept under $tmp"
}
trap cleanup EXIT INT TERM

# --- merge a split reference into one tree ---------------------------------
merge_split() {
	local v first=1 mode=link
	merged=$tmp/ref
	mkdir -p "$merged" || die "cannot create $merged"
	for v in os sysos appos; do
		rsync -aH --link-dest="$ref_split/$v/root/" "$ref_split/$v/root/" "$merged/" \
			>"$tmp/merge-$v.log" 2>&1
		if (( first )) && [[ -z $(find "$merged" -xdev -type f -links +1 -print -quit) ]]; then
			mode=copy
			say "  note: the reference cannot be hard-linked, copying instead (~11.3 GB)"
			rsync -aH "$ref_split/$v/root/" "$merged/" >"$tmp/merge-$v.log" 2>&1
		fi
		first=0
	done
	say "  reference merged (mode: $mode) from $ref_split"
	ref=$merged
}

# --- leg B's tree -----------------------------------------------------------
mount_tree() {
	[[ -e /dev/fuse ]] || { say "  /dev/fuse missing (modprobe fuse)" >&2; return 1; }
	[[ -r /dev/fuse && -w /dev/fuse ]] || { say "  /dev/fuse not writable by $(id -un)" >&2; return 1; }
	command -v fusermount3 >/dev/null || { say "  fusermount3 missing (fuse3)" >&2; return 1; }
	[[ -x $FSTOOL ]] || { say "  no $FSTOOL (build it: tooling/33b... --bootstrap)" >&2; return 1; }
	if [[ -f $FSTOOL_SHA_FILE ]]; then
		local want got
		want=$(cut -d' ' -f1 "$FSTOOL_SHA_FILE")
		got=$(sha256sum "$FSTOOL" | cut -d' ' -f1)
		[[ $want == "$got" ]] || { say "  $FSTOOL changed (sha256 mismatch)" >&2; return 1; }
	fi
	mkdir -p "$mnt"
	say "  mounting the image read/write through $(basename "$FSTOOL")"
	"$FSTOOL" mount "$img" "$mnt" 2>"$tmp/mount.log" &
	fstool_pid=$!
	local i
	for ((i = 0; i < 300; i++)); do
		mountpoint -q "$mnt" && break
		kill -0 "$fstool_pid" 2>/dev/null || { cat "$tmp/mount.log" >&2; return 1; }
		sleep 0.1
	done
	mountpoint -q "$mnt" || { cat "$tmp/mount.log" >&2; return 1; }
	[[ $(stat -f -c %T "$mnt") == fuse* ]] || { say "  $mnt is not a fuse mount" >&2; return 1; }
	mounted=1
	tree=$mnt
	say "  mounted at $mnt (writer pid $fstool_pid)"
	say "  note: the userspace root readdir adds an empty name; find(1) reports it as"
	say "        \"No such file or directory\" for the mount root - the count is correct"
	return 0
}

unmount_tree() {
	(( mounted )) || return 0
	fusermount3 -u "$mnt" || { leg_b_note="unmount failed: $mnt"; return 1; }
	mounted=0
	if (( fstool_pid )); then
		kill "$fstool_pid" 2>/dev/null || true
		wait "$fstool_pid" 2>/dev/null || true
		fstool_pid=""
	fi
	return 0
}

# --- the two legs -----------------------------------------------------------
run_volume_leg() {
	local s=$SECONDS rc
	local a=(--limit "${limit:-5}")
	[[ -n $ref_mount ]] && a+=(--ref-mount "$ref_mount")
	[[ -n $expect_files ]] && a+=(--expect-files "$expect_files")
	[[ -n $expect_bytes ]] && a+=(--expect-bytes "$expect_bytes")
	(( keep )) && a+=(--keep)
	[[ -n $reader ]] && a+=(--reader "$reader")
	if [[ -n $root ]] && (( ! fsck )); then
		a+=(--no-fsck)
		say "  fsck skipped (--root given; 33 fsck's the image after unmount, --fsck overrides)"
	fi
	# If the image is mounted right now, the header's dirty bits are expected:
	# pass --mounted so the gate notes them instead of failing on them. The mount
	# source is a loop device, not the image path, so ask losetup.
	if losetup -j "$img" 2>/dev/null | grep -q . || grep -q " $img " /proc/mounts 2>/dev/null; then
		a+=(--mounted)
		say "  volume is mounted: dirty bits are notes, not failures"
	fi
	"$VERIFY_IMG" "$img" "$ref" "${a[@]}" 2>&1 | tee "$tmp/leg-a.log"
	rc=${PIPESTATUS[0]}
	printf 'leg A exit %s in %ss\n' "$rc" "$((SECONDS - s))"
	if (( rc == 0 )); then
		leg_a=pass
		return
	fi
	# A populated root legitimately carries files the DMGs do not (the /dev
	# mount point, /private/etc/fstab, the keybag, the logd stores; 33's boot
	# set). That surfaces as extra paths and, through them, in the two derived
	# counts. Those three classes are not fatal unless asked; everything else
	# still is (a missing path, a byte difference, a broken link group).
	if (( ! strict_extras )); then
		local total other n_extra
		total=$(grep -c ' FAIL' "$tmp/leg-a.log")
		n_extra=$(awk '/^extra paths .* FAIL/ { n = $NF } END { print n + 0 }' "$tmp/leg-a.log")
		other=$(grep ' FAIL' "$tmp/leg-a.log" |
			grep -vc '^extra paths .* FAIL\|^file count .* FAIL\|^total bytes .* FAIL')
		if (( total > 0 && n_extra > 0 && other == 0 )); then
			leg_a=pass
			leg_a_note="${n_extra} extra path(s) beyond the reference tolerated; --strict-extras gates them"
			say "  extras and their derived counts do not gate (--strict-extras does)"
			return
		fi
	fi
	leg_a="fail($rc)"
	leg_a_rc=$rc
}

run_bootstrap_leg() {
	local s=$SECONDS rc
	local a=(--quiet)
	(( loud )) && a=()
	[[ -n $min_files ]] && a+=(--min-files "$min_files")
	a+=(--reference "$ref")
	"$CHECK_BOOT" "$tree" "${a[@]}" 2>&1 | tee "$tmp/leg-b.log"
	rc=${PIPESTATUS[0]}
	printf 'leg B exit %s in %ss\n' "$rc" "$((SECONDS - s))"
	unmount_tree
	if (( rc == 0 )); then leg_b=pass; else leg_b="fail($rc)"; leg_b_rc=$rc; fi
}

# --- run --------------------------------------------------------------------
step "preflight"
say "  image      $img"
say "  sha256     $(sha256sum "$img" | cut -d' ' -f1)"
say "  reference  ${ref:-$ref_split (split, will be merged)}"
say "  leg B tree ${root:-<userspace mount of the image>}"
[[ -n $sig_note ]] && say "  note       $sig_note"
[[ -n $ref_split ]] && merge_split

leg_a="not-run"; leg_a_rc=4
leg_b="not-run"; leg_b_rc=4
leg_b_note=""
leg_a_note=""

step "leg A: volume bytes (35-verify-root-image.sh)"
run_volume_leg

step "leg B: launchd first-run set (34-check-bootstrap.sh)"
if [[ -z $root ]]; then
	if mount_tree; then run_bootstrap_leg; else leg_b="not-run"; leg_b_rc=4; fi
else
	run_bootstrap_leg
fi

step "verdict"
printf '  leg A volume bytes     %s\n' "$leg_a"
printf '  leg B bootstrap set    %s\n' "$leg_b"
[[ -n $leg_a_note ]] && printf '  note                   %s\n' "$leg_a_note"
[[ -n $leg_b_note ]] && printf '  note                   %s\n' "$leg_b_note"
if (( mounted )); then
	printf '  note                   still mounted at %s\n' "$mnt"
elif [[ -n $root ]]; then
	printf '  note                   %s left as found (--root)\n' "$root"
fi
say "  sha256 after           $(sha256sum "$img" | cut -d' ' -f1)"
say ""
if [[ $leg_a == pass && $leg_b == pass ]]; then
	say "READY TO BOOT - both legs passed; the volume is populated through the first launchd exec."
	exit 0
fi
say "NOT READY - do not boot this volume yet."
rc=0
[[ $leg_a == pass ]] || rc=$((rc | 1))
[[ $leg_b == pass ]] || rc=$((rc | 2))
[[ $leg_a == not-run || $leg_b == not-run ]] && rc=$((rc | 4))
exit $rc
