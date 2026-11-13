#!/bin/bash
# Check a populated iOS root tree against the first-launchd-exec requirements
# in docs/LAUNCHD_BOOTSTRAP.md. Host only, unprivileged, nothing executed on
# the target and nothing written into the tree.
#
#   tooling/34-check-bootstrap.sh ROOT [--reference DIR] [--json] [--quiet]
#
#   ROOT        extracted or loop-mounted copy of the root volume to inspect
#               (the output of tooling/33-populate-root.sh, or a plain rsync
#               of the three DMGs)
#   --reference DIR   read-only DMG mount to compare bytes against. Without it
#               launchd and dyld are only checked against their pinned sha256.
#   --json      one JSON object per item instead of the aligned text form
#   --quiet     only absent/mismatch lines and the summary
#   --min-files N   populated-volume floor, default 100000 (lower it for a
#               partial fixture root)
#
# Every item is one line: STATUS<tab>STEP<tab>ITEM<tab>DETAIL with STATUS one of
#   ok        present and matching what a boot needs
#   absent    missing; the boot stops at this step
#   mismatch  present but wrong (arch, mode, signature, bytes, owner)
#   note      informational, absence is tolerated
#
# Exit status: 0 all ok, 1 something absent, 2 something mismatched, 64 usage.
#
# The ordered set below is derived from the launchd 16.7.16 binary, its
# compiled-in Boot job table and the kernel's bsd_init path; the step order is
# the order a boot can only be judged by. See the document for the evidence and
# for what this script cannot prove (all of it runtime behaviour).
set -uo pipefail

PROG=$(basename "$0")
root=""
reference=""
json=0
quiet=0
min_files=100000

usage() {
	sed -n '2,/^set -/p' "$0" | sed -n '/^set -/!s/^# \{0,1\}//p'
	exit 64
}

while (($#)); do
	case "$1" in
	--reference) reference=${2:-}; shift 2 || usage ;;
	--json) json=1; shift ;;
	--quiet) quiet=1; shift ;;
	--min-files) min_files=${2:-}; shift 2 || usage ;;
	-h | --help) usage ;;
	-*) echo "$PROG: unknown option $1" >&2; usage ;;
	*) [[ -z $root ]] || { echo "$PROG: one ROOT only" >&2; usage; }
	   root=$1; shift ;;
	esac
done
[[ -n $root ]] || usage
[[ -d $root ]] || { echo "$PROG: not a directory: $root" >&2; exit 64; }
[[ -z $reference || -d $reference ]] || { echo "$PROG: no such reference dir: $reference" >&2; exit 64; }
root=$(cd "$root" && pwd)
[[ -n $reference ]] && reference=$(cd "$reference" && pwd)

# Pinned identities of the 16.7.16 (20H392, iPhone10,3) binaries this port
# boots. A different build is a mismatch, not a warning: patches 0035/0036 mark
# exactly these signatures platform.
LAUNCHD_SHA256=12370e5ee35bf28ae479b6c4b4455f4f4693ab803e37c5eb3032537c18cac61c
DYLD_SHA256=5806834564fe6462ae981d0915d612b1eb2f6f168822b5d278bee56254933757

# Entitlements launchd's own startup path and the first boot jobs query. The
# kernel answers these from the XML blob (patch 0035); without them the calls
# fail closed.
LAUNCHD_ENTS=(
	com.apple.private.amfi.can-allow-non-platform
	com.apple.private.security.storage.launchd
	com.apple.private.spawn-subsystem-root
	com.apple.private.spawn-panic-crash-behavior
	com.apple.private.vfs.pivot-root
	com.apple.private.vfs.graftdmg
	com.apple.rootless.volume.Preboot
	com.apple.private.pmap.load-trust-cache
)

absent=0
mismatch=0

emit() { # status step item detail
	local st=$1
	case "$st" in
	absent) absent=$((absent + 1)) ;;
	mismatch) mismatch=$((mismatch + 1)) ;;
	esac
	if ((json)); then
		printf '{"status":"%s","step":"%s","item":"%s","detail":"%s"}\n' \
			"$st" "$2" "$3" "$(printf '%s' "$4" | sed 's/\\/\\\\/g; s/"/\\"/g')"
		return
	fi
	((quiet)) && [[ $st == ok || $st == note ]] && return
	printf '%-9s %-4s %-42s %s\n' "$st" "$2" "$3" "$4"
}

# inspect PATH -> key=value lines: type, mode, size, nlink, uid, gid, magic,
# filetype, cputype, dylinker, sha256, sigcd, csflags, entcount, enthash_ok,
# pages_ok, libs
inspect() {
	python3 - "$1" <<'PY'
import hashlib, json, os, stat, struct, sys

p = sys.argv[1]
o = {"path": p}
try:
    st = os.lstat(p)
except OSError as e:
    print("type=absent"); sys.exit(0)
o["type"] = "regular" if stat.S_ISREG(st.st_mode) else (
    "link" if stat.S_ISLNK(st.st_mode) else (
        "dir" if stat.S_ISDIR(st.st_mode) else "other"))
o["mode"] = "%04o" % stat.S_IMODE(st.st_mode)
o["size"] = st.st_size
o["nlink"] = st.st_nlink
o["uid"] = st.st_uid
o["ws"] = "1" if os.access(p, os.W_OK) and os.access(os.path.dirname(p) or "/", os.W_OK) else "0"
if o["type"] != "regular":
    print("\n".join("%s=%s" % kv for kv in o.items())); sys.exit(0)

d = open(p, "rb").read()
o["sha256"] = hashlib.sha256(d).hexdigest()
if d[:4] != b"\xcf\xfa\xed\xfe":
    print("\n".join("%s=%s" % kv for kv in o.items())); sys.exit(0)
ft = struct.unpack_from("<I", d, 12)[0]
cpu = struct.unpack_from("<i", d, 4)[0]
o["magic"] = "macho64"
o["filetype"] = {1: "OBJECT", 2: "EXECUTE", 6: "DYLIB", 7: "DYLINKER", 8: "BUNDLE"}.get(ft, str(ft))
o["cputype"] = "arm64" if cpu == 0x010000_0C else "0x%x" % (cpu & 0xFFFFFFFF)

# load commands: dylinker path, dylibs, LC_CODE_SIGNATURE
ncmds = struct.unpack_from("<I", d, 16)[0]
off, sig, libs = 32, None, []
for _ in range(ncmds):
    cmd, csz = struct.unpack_from("<II", d, off)
    if cmd == 0xE:  # LC_LOAD_DYLINKER
        n = struct.unpack_from("<I", d, off + 8)[0]
        o["dylinker"] = d[off + n:off + csz].split(b"\0")[0].decode("utf-8", "replace")
    elif cmd == 0xC:  # LC_LOAD_DYLIB
        n = struct.unpack_from("<I", d, off + 8)[0]
        libs.append(d[off + n:off + csz].split(b"\0")[0].decode("utf-8", "replace"))
    elif cmd == 0x1D:  # LC_CODE_SIGNATURE
        sig = struct.unpack_from("<II", d, off + 8)
    off += csz
o["libs"] = ",".join(libs)

if sig:
    so, ss = sig
    b = d[so:so + ss]
    try:
        magic, length, count = struct.unpack_from(">III", b, 0)
    except struct.error:
        print("\n".join("%s=%s" % kv for kv in o.items())); sys.exit(0)
    if magic != 0xFADE0CC0 or length > ss:
        o["sigcd"] = "bad-superblob"
        print("\n".join("%s=%s" % kv for kv in o.items())); sys.exit(0)
    slots = {}
    for i in range(count):
        t, o_ = struct.unpack_from(">II", b, 12 + 8 * i)
        slots.setdefault(t, []).append(o_)
    o["sigcd"] = "present"
    o["cms"] = "1" if 0x10000 in slots and struct.unpack_from(">I", b, slots[0x10000][0] + 4)[0] > 8 else "0"
    cd = struct.unpack_from(">I", b, 16)[0]
    m2, l2 = struct.unpack_from(">II", b, cd)
    if m2 != 0xFADE0C02:
        o["sigcd"] = "bad-cd"
        print("\n".join("%s=%s" % kv for kv in o.items())); sys.exit(0)
    (ver, flags, hashoff, identoff, nspecial, ncode, codelimit,
     hsize, htype, platform, pgsz) = struct.unpack_from(">IIIIIIIBBBB", b, cd + 8)
    o["csflags"] = "0x%x" % flags
    o["adhoc"] = "1" if flags & 0x2 else "0"
    o["hashType"] = str(htype)
    # entitlements: slot 5 is hashed as the payload without its 8-byte header
    ok = "na"
    if 5 in slots:
        eo = slots[5][0]
        em, el = struct.unpack_from(">II", b, eo)
        payload = b[eo:eo + el]  # blob as stored, header included
        stored = b[cd + hashoff - 5 * hsize:cd + hashoff - 4 * hsize]
        alg = {1: "sha1", 2: "sha256", 3: "sha256", 4: "sha384"}.get(htype, "sha256")
        ok = "1" if hashlib.new(alg, payload).digest() == stored else "0"
        try:
            txt = payload.decode("utf-8", "replace")
            o["entcount"] = str(txt.count("<key>"))
            o["entkeys"] = ",".join(
                l.split("<key>")[1].split("</key>")[0]
                for l in txt.splitlines() if "<key>" in l and "</key>" in l)
        except UnicodeDecodeError:
            o["entcount"] = "0"
            o["entkeys"] = ""
    o["enthash_ok"] = ok
    # page hashes: codelimit / page size, sha* of each page vs slot (nspecial+i)
    if htype in (1, 2, 3, 4) and codelimit <= len(d) and pgsz <= 16:
        alg = {1: "sha1", 2: "sha256", 3: "sha256", 4: "sha384"}[htype]
        psz = 1 << pgsz
        bad = 0
        for i in range(ncode):
            page = d[i * psz:min((i + 1) * psz, codelimit)]
            want = b[cd + hashoff + i * hsize:cd + hashoff + (i + 1) * hsize]
            if hashlib.new(alg, page).digest() != want:
                bad += 1
        o["pages_ok"] = "1" if bad == 0 else "0(%d/%d bad)" % (bad, ncode)
    else:
        o["pages_ok"] = "na"
print("\n".join("%s=%s" % kv for kv in o.items()))
PY
}

# kv_get FILE KEY -> value
kv_get() {
	sed -n "s/^$2=//p" "$1" | head -1
}

# check_bin STEP ITEM PATH [--ents ...] [--sha256 HEX] [--filetype T]
check_bin() {
	local step=$1 item=$2 path=$3 want_ft=$4 want_sha=$5
	shift 5
	local kv t
	kv=$(mktemp)
	inspect "$root$path" >"$kv"
	t=$(kv_get "$kv" type)
	if [[ $t == absent ]]; then
		emit absent "$step" "$item" "$path: missing"
		rm -f "$kv"
		return
	fi
	if [[ $t == link ]]; then
		# symlink into the same volume (init_data_protection -> seputil):
		# check the target, the kernel resolves it for the exec too
		local tgt
		tgt=$(readlink "$root$path")
		emit note "$step" "$item" "$path -> $tgt"
		path=$(cd "$(dirname "$root$path")" && readlink -f "$(basename "$path")")
		path=${path#"$root"}
		inspect "$root$path" >"$kv"
		t=$(kv_get "$kv" type)
	fi
	if [[ $t != regular ]]; then
		emit mismatch "$step" "$item" "$path: is a $t, not a regular file"
		rm -f "$kv"
		return
	fi
	local m=$(kv_get "$kv" mode) sz=$(kv_get "$kv" size) ct=$(kv_get "$kv" cputype)
	local ft=$(kv_get "$kv" filetype) sha=$(kv_get "$kv" sha256)
	if [[ $sz == 0 ]]; then
		emit mismatch "$step" "$item" "$path: 0 bytes (truncated copy)"
	elif [[ $ct != arm64 ]]; then
		emit mismatch "$step" "$item" "$path: cputype $ct, not arm64"
	elif [[ -n $want_ft && $ft != "$want_ft" ]]; then
		emit mismatch "$step" "$item" "$path: Mach-O $ft, expected $want_ft"
	elif [[ $m != 0755 && $m != 0555 ]]; then
		emit mismatch "$step" "$item" "$path: mode $m, expected 0755 or 0555"
	elif [[ -n $want_sha && $sha != "$want_sha" ]]; then
		emit mismatch "$step" "$item" "$path: sha256 $sha, pinned $want_sha"
	else
		emit ok "$step" "$item" "$path: $sz B arm64 mode $m sha256 ${sha:0:12}"
	fi
	rm -f "$kv"
}

# check_sig STEP ITEM PATH -- require ad-hoc, valid entitlements/page hashes
check_sig() {
	local step=$1 item=$2 path=$3 kv cd eh pg
	kv=$(mktemp)
	inspect "$root$path" >"$kv"
	cd=$(kv_get "$kv" sigcd)
	eh=$(kv_get "$kv" enthash_ok)
	pg=$(kv_get "$kv" pages_ok)
	if [[ -z $cd ]]; then
		emit mismatch "$step" "$item" "$path: no LC_CODE_SIGNATURE (kernel refuses: CS_SIGNED missing)"
	elif [[ $cd != present ]]; then
		emit mismatch "$step" "$item" "$path: $cd"
	elif [[ $(kv_get "$kv" cms) == 1 ]]; then
		emit mismatch "$step" "$item" "$path: CMS signature, expected ad-hoc"
	elif [[ $(kv_get "$kv" adhoc) != 1 ]]; then
		emit mismatch "$step" "$item" "$path: CS_ADHOC not set (flags $(kv_get "$kv" csflags))"
	elif [[ $eh == 0 ]]; then
		emit mismatch "$step" "$item" "$path: entitlements blob does not match CD slot -5"
	elif [[ $pg == 0* ]]; then
		emit mismatch "$step" "$item" "$path: page hashes ${pg#0}"
	else
		emit ok "$step" "$item" "$path: ad-hoc, entitlements hash ok, page hashes ok"
	fi
	rm -f "$kv"
}

# check_dir STEP ITEM PATH MODE [--may-be-empty]
check_dir() {
	local step=$1 item=$2 path=$3 want_mode=$4 may_empty=${5:-}
	local kv t m n
	kv=$(mktemp)
	inspect "$root$path" >"$kv"
	t=$(kv_get "$kv" type)
	if [[ $t == absent ]]; then
		emit absent "$step" "$item" "$path: missing"
	elif [[ $t != dir ]]; then
		emit mismatch "$step" "$item" "$path: is a $t, not a directory"
	else
		m=$(kv_get "$kv" mode)
		if [[ -n $want_mode && $m != "$want_mode" ]]; then
			emit mismatch "$step" "$item" "$path: mode $m, expected $want_mode"
		elif [[ -z $may_empty ]]; then
			n=$(find "$root$path" -mindepth 1 -maxdepth 1 | wc -l)
			if ((n == 0)); then
				emit mismatch "$step" "$item" "$path: empty"
			else
				emit ok "$step" "$item" "$path: dir $m, $n entries"
			fi
		else
			emit ok "$step" "$item" "$path: dir $m"
		fi
	fi
	rm -f "$kv"
}

if ((!quiet && !json)); then printf '%-9s %-4s %-42s %s\n' STATUS STEP ITEM DETAIL; fi
emit note 0 "root" "inspecting $root"

# --- step 0: is this a populated volume at all ------------------------------
if [[ ! -e $root/System/Library/CoreServices/SystemVersion.plist ]]; then
	emit absent 0 "populated-volume" "no SystemVersion.plist: volume is not populated"
else
	n=$(find "$root" -xdev -type f 2>/dev/null | wc -l)
	if ((n < min_files)); then
		emit mismatch 0 "populated-volume" "$n files, floor $min_files"
	else
		emit ok 0 "populated-volume" "$n files"
	fi
fi

# --- step 1: /dev must exist before devfs can mount on it -------------------
# bsd_init:977 devfs_kernel_mount("/dev") -> kernel_mount -> namei("/dev");
# no directory means ENOENT (2) and devfs never mounts.
check_dir 1 "dev-mountpoint" /dev "" --may-empty
kv=$(mktemp)
inspect "$root/dev" >"$kv"
if [[ $(kv_get "$kv" type) == dir ]]; then
	if [[ $(kv_get "$kv" uid) != 0 ]]; then
		# copies made by an unprivileged user cannot keep uid 0
		if [[ $(stat -c %u "$root") == 0 ]]; then
			emit mismatch 1 "dev-owner" "/dev uid $(kv_get "$kv" uid), devfs mounts as root"
		else
			emit note 1 "dev-owner" "/dev uid $(kv_get "$kv" uid) (unprivileged copy)"
		fi
	fi
	# 0555 is what the DMG carries and is enough: mount needs no write bit
	[[ $(kv_get "$kv" mode) == 0555 || $(kv_get "$kv" mode) == 0755 ]] ||
		emit mismatch 1 "dev-mode" "/dev mode $(kv_get "$kv" mode), expected 0555 or 0755"
fi
rm -f "$kv"

# --- step 2: /sbin/launchd, the exec target of load_init_program -------------
check_bin 2 "launchd-binary" /sbin/launchd EXECUTE "$LAUNCHD_SHA256"
kv=$(mktemp)
inspect "$root/sbin/launchd" >"$kv"
dl=$(kv_get "$kv" dylinker)
if [[ -z $dl ]]; then
	[[ $(kv_get "$kv" type) == regular ]] && emit mismatch 2 "launchd-dylinker" "no LC_LOAD_DYLINKER (kernel cannot start dyld)"
elif [[ $dl != /usr/lib/dyld ]]; then
	emit mismatch 2 "launchd-dylinker" "LC_LOAD_DYLINKER $dl, expected /usr/lib/dyld"
else
	emit ok 2 "launchd-dylinker" "$dl"
fi
libs=$(kv_get "$kv" libs)
if [[ -n $libs ]]; then
	emit note 2 "launchd-libs" "$libs (only resolvable through the shared cache)"
fi
rm -f "$kv"
check_sig 2 "launchd-signature" /sbin/launchd
kv=$(mktemp)
inspect "$root/sbin/launchd" >"$kv"
ents=$(kv_get "$kv" entkeys)
for e in "${LAUNCHD_ENTS[@]}"; do
	if [[ ",$ents," == *",$e,"* ]]; then
		emit ok 2 "entitlement:$e" "present in the XML blob"
	else
		emit mismatch 2 "entitlement:$e" "not in the XML blob; kernel query fails closed"
	fi
done
rm -f "$kv"

# --- step 3: /usr/lib/dyld ---------------------------------------------------
check_bin 3 "dyld" /usr/lib/dyld DYLINKER "$DYLD_SHA256"
check_sig 3 "dyld-signature" /usr/lib/dyld

# --- step 4: the shared cache, the only home of libSystem ------------------
cache=/System/Library/Caches/com.apple.dyld
check_dir 4 "cache-dir" "$cache" "" --may-empty
cj=$cache/dyld_shared_cache_arm64
if [[ -f $root$cj ]]; then
	emit ok 4 "cache-image" "$cj: $(stat -c %s "$root$cj") B"
	n=$(find "$root$cache" -maxdepth 1 -type f | wc -l)
	if ((n < 43)); then
		emit mismatch 4 "cache-subcaches" "$n cache files, the 20H392 cache has 44"
	else
		emit ok 4 "cache-subcaches" "$n subcaches"
	fi
	if [[ -f $root$cache/dyld_shared_cache_arm64.dyldlinkedit || -f $root$cache/dyld_shared_cache_arm64.42.dyldlinkedit ]]; then
		emit ok 4 "cache-linkedit" "dyldlinkedit subcache present"
	else
		emit absent 4 "cache-linkedit" "no .dyldlinkedit subcache: bind info missing"
	fi
	for lib in libSystem.B.dylib libobjc.A.dylib; do
		# the first cache file carries the dylib path table
		if grep -qa "/usr/lib/$lib" "$root$cj"; then
			emit ok 4 "cache-has:$lib" "listed in the cache path table"
		else
			emit note 4 "cache-has:$lib" "not found by string search (verify by boot)"
		fi
	done
else
	emit absent 4 "cache-image" "$cj: missing"
fi
for lib in /usr/lib/libSystem.B.dylib /usr/lib/libobjc.A.dylib; do
	if [[ -e $root$lib ]]; then
		nl=$(stat -c %h "$root$lib")
		if ((nl < 2)); then
			emit mismatch 4 "rootfs-lib:$lib" "link count $nl: copy of the cryptex file, not a hard link"
		else
			emit ok 4 "rootfs-lib:$lib" "hard link into the cryptex (nlink $nl, vnode on the root volume)"
		fi
	else
		emit note 4 "rootfs-lib:$lib" "no file anywhere (only inside the cache); dyld resolves it there"
	fi
done
if [[ -L $root/System/Cryptexes/OS ]]; then
	emit note 4 "cryptex-graft" "$(readlink "$root/System/Cryptexes/OS") (dyld searches this too)"
fi

# --- step 5: chdir("/") and launchd's writable scratch --------------------
check_dir 5 "chdir-root" / ""
check_dir 5 "var-tmp" /private/var/tmp 1777 --may-empty
check_dir 5 "var-run" /private/var/run "" --may-empty
check_dir 5 "tmp" /private/tmp 1777 --may-empty
check_dir 5 "var-db" /private/var/db "" --may-empty
check_dir 5 "var-keybags" /private/var/keybags 0700 --may-empty

# --- step 6: /private/etc files (setlogin, getpwnam, getfsent, ttys) ------
for f in master.passwd group ttys hosts passwd; do
	if [[ -f $root/private/etc/$f ]]; then
		emit ok 6 "etc:$f" "$(stat -c '%a %U' "$root/private/etc/$f")"
	else
		emit absent 6 "etc:$f" "/private/etc/$f missing"
	fi
done
# mount-phase-1 (RequireSuccess+RequireRun) calls setfsent(); the avicii ADT has
# no /filesystems/fstab node, so the file is the only source of the checklist.
if [[ -f $root/private/etc/fstab ]]; then
	# the phase loop only mounts entries whose 4th field is ro/rw/rq and that
	# do not carry noauto
	if awk '$4 == "ro" || $4 == "rw" || $4 == "rq" {
		if ($0 !~ /noauto/) { found = 1 } } END { exit !found }' \
		"$root/private/etc/fstab"; then
		emit ok 6 "etc:fstab" "/private/etc/fstab present, wearable phase entry"
	else
		emit mismatch 6 "etc:fstab" "no ro/rw/rq entry without noauto: setfsent succeeds, nothing mounts"
	fi
elif grep -qa fstab "${ADT:-/home/tadej/ios-nord/avicii/adt/avicii-live.adt}" 2>/dev/null; then
	emit note 6 "etc:fstab" "absent, but the ADT carries /filesystems/fstab"
else
	emit mismatch 6 "etc:fstab" "absent and the ADT has no /filesystems/fstab: mount -P 1 exits 1"
fi
if [[ -f $root/private/etc/com.apple.xpc.launchd.limits.plist ]]; then
	emit ok 6 "etc:limits" "limits plist present"
else
	emit note 6 "etc:limits" "no limits plist (launchd logs and uses defaults)"
fi

# --- step 7: the bootstrap scan directories ------------------------------
check_dir 7 "launchdaemons" /System/Library/LaunchDaemons "" --may-empty
for d in /System/Library/LaunchAgents /System/Library/LaunchAngels \
	/System/Library/NanoLaunchDaemons /System/Library/NanoLaunchDaemonsAltAccount \
	/System/Library/DeveloperModeLaunchDaemons; do
	[[ -d $root$d ]] && emit ok 7 "scan:$d" "present" || emit note 7 "scan:$d" "absent (scan skips it)"
done
dangling=0
for p in "$root"/System/Library/LaunchDaemons/*.plist; do
	[[ -e $p ]] || continue
	prog=$(sed -n 's/.*<key>Program<\/key>[[:space:]]*<string>\(.*\)<\/string>.*/\1/p' "$p" | head -1)
	[[ -n $prog ]] || continue
	[[ -e $root$prog ]] || { dangling=$((dangling + 1)); emit mismatch 7 "job-program" "$prog (from $(basename "$p")) missing"; }
done
((dangling == 0)) && emit ok 7 "job-programs" "every Program key resolves"

# --- step 8: the first boot jobs, in launchd's compiled-in order ----------
# 0x1000654b0 __config: auearlyboot, mount-phase-1, mount-phase-2, keybag,
# restore-datapartition, fips, finish-restore, tzinit, data-protection,
# recovery-mode, fsck-safe, fsck, sysstatuscheck, ...
check_bin 8 "job:auearlyboot" \
	/System/Library/PrivateFrameworks/MobileAccessoryUpdater.framework/Support/auearlyboot EXECUTE ""
check_sig 8 "job:auearlyboot.sig" \
	/System/Library/PrivateFrameworks/MobileAccessoryUpdater.framework/Support/auearlyboot
check_bin 8 "job:mount" /sbin/mount EXECUTE ""
check_sig 8 "job:mount.sig" /sbin/mount
check_bin 8 "job:keybagd" /usr/libexec/keybagd EXECUTE ""
check_sig 8 "job:keybagd.sig" /usr/libexec/keybagd
check_bin 8 "job:cc_fips_test" /usr/libexec/cc_fips_test EXECUTE ""
check_bin 8 "job:tzinit" /usr/libexec/tzinit EXECUTE ""
check_bin 8 "job:init_data_protection" /usr/libexec/init_data_protection EXECUTE ""
check_bin 8 "job:seputil" /usr/libexec/seputil EXECUTE ""
check_bin 8 "job:fsck" /sbin/fsck EXECUTE ""
check_bin 8 "job:xpcroleaccountd" /usr/libexec/xpcroleaccountd EXECUTE ""
check_bin 8 "job:prng_seedctl" /usr/libexec/prng_seedctl EXECUTE ""
check_bin 8 "job:xpcproxy" /usr/libexec/xpcproxy EXECUTE ""

# --- step 9: state the first jobs read ----------------------------------
for spec in "private/var/keybags/systembag.kb:0600" "private/var/db/diagnostics/.migrated:0644" \
	"private/var/db/uuidtext/.migrated:0644"; do
	f=${spec%:*}
	want=${spec##*:}
	kv=$(mktemp)
	inspect "$root/$f" >"$kv"
	if [[ $(kv_get "$kv" type) == absent ]]; then
		emit absent 9 "state:$f" "/$f missing"
	elif [[ $(kv_get "$kv" mode) != "$want" ]]; then
		emit mismatch 9 "state:$f" "mode $(kv_get "$kv" mode), expected $want"
	else
		emit ok 9 "state:$f" "mode $want"
	fi
	rm -f "$kv"
done
emit note 9 "dev-nodes" "console/tty/null/zero/urandom/random/klog/fd come from devfs, not from the tree"

# --- reference comparison, if one was given -----------------------------
if [[ -n $reference ]]; then
	n=0
	while IFS= read -r f; do
		f=${f#./}
		[[ -f $root/$f && -f $reference/$f ]] || continue
		if ! cmp -s -- "$root/$f" "$reference/$f"; then
			emit mismatch 10 "bytes:$f" "differs from the DMG copy"
			n=$((n + 1))
		fi
	done < <(cd "$reference" && find . -maxdepth 6 \( -path ./private/var -o -path ./private/preboot \) -prune -o \
		-type f \( -name launchd -o -name dyld -o -path '*/LaunchDaemons/*' -o -path '*/LaunchAgents/*' \) -print)
	((n == 0)) && emit ok 10 "bytes" "sampled binaries identical to the reference"
fi

if ((json)); then
	printf '{"summary":true,"absent":%d,"mismatch":%d}\n' "$absent" "$mismatch"
else
	printf '\n%s: absent %d, mismatch %d, %s\n' "$PROG" "$absent" "$mismatch" \
		"$([[ $mismatch -gt 0 ]] && echo 'fix mismatches first' || { [[ $absent -gt 0 ]] && echo 'boot stops at the first absent step' || echo 'ready to boot'; })"
fi
((mismatch > 0)) && exit 2
((absent > 0)) && exit 1
exit 0
