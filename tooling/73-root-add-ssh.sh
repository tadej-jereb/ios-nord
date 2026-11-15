#!/bin/bash
# 73-root-add-ssh.sh — put OpenSSH (Procursus rootless bootstrap) and an sshd
# launchd job into the iOS root image, unprivileged, through fstool's FUSE writer.
#
#   tooling/73-root-add-ssh.sh BOOTSTRAP.tar.zst PUBKEY [IMAGE]
#
#   BOOTSTRAP  https://apt.procurs.us/bootstraps/1900/bootstrap-ssh-iphoneos-arm64.tar.zst
#              (6584 entries under ./var/jb; the same bootstrap the spacewar port used)
#   PUBKEY     the host's ssh public key for root (key-only login)
#   IMAGE      default build/ios16-root.img (modified in place; sha256 before/after printed)
#
# What lands in the image (the recipe the spacewar port proved on hardware,
# refs/anonbeat1-ios-sweet/tools/sweet-ssh-setup.py and NOTES.md "SSH WORKS"):
#   /private/var/jb/...                 the bootstrap, owners and modes as in the tar
#   /private/var/jb/usr/libexec/sshd-keygen-wrapper   tooling/ssh/sshd-keygen-wrapper.sh
#                                       (pwd_mkdb, etc/shells, authorized_keys on first use)
#   /private/var/jb/etc/ssh/sshd_config UsePAM no, PasswordAuthentication no,
#                                       PermitRootLogin prohibit-password
#   /bin/sh -> /var/jb/bin/sh           root's login shell (iOS has no /bin/sh)
#   /private/var/root/.ssh/authorized_keys
#   launchd.plist job com.openssh.sshd  inetd-style on port 22, root:wheel, no
#                                       SessionCreate (that put sshd in user/501);
#                                       keyed under /System/Library/LaunchDaemons
#                                       (a /var/jb key was ignored); the previous
#                                       table is kept as launchd.plist.pre-ssh.
# The image must not be in use (not mounted, not being written to the phone).
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo"
FSTOOL=tooling/opt/fstool/bin/fstool
die() { echo "error: $*" >&2; exit 1; }

boot=${1:?usage: $0 BOOTSTRAP.tar.zst PUBKEY [IMAGE]}
pub=${2:?usage: $0 BOOTSTRAP.tar.zst PUBKEY [IMAGE]}
img=${3:-build/ios16-root.img}
[ -f "$boot" ] && [ -f "$pub" ] && [ -f "$img" ] || die "missing input"
grep -qE '^ssh-(ed25519|rsa) ' "$pub" || die "$pub is not an ssh public key"
command -v zstd >/dev/null || die "zstd missing"
command -v fusermount3 >/dev/null || die "fusermount3 missing"


# The populated root carries the journaled attribute and a journal whose header
# was never written (fstool check: "journal header has no JNLx magic"); XNU's HFS
# initialises it on the first rw mount ("hfs: Initializing the journal"), but
# fstool's writer refuses to write such a volume (EIO on every file). Clear the
# journaled bit and journalInfoBlock in both volume headers for the write, and
# put them back afterwards so the phone sees exactly the state it initialises.
vh() {   # vh get|clear|set IMAGE [ATTR JIB]
	python3 -I - "$@" <<'PY'
import os, struct, sys
op, p = sys.argv[1], sys.argv[2]
size = os.path.getsize(p)
with open(p, 'r+b') as f:
    for off in (1024, size - 1024):
        f.seek(off); sig, ver, attr, lmv, jib = struct.unpack('>2sHI4sI', f.read(16))
        assert sig in (b'H+', b'HX'), sig
        if op == 'get':
            print(attr, jib); break
        if op == 'clear':
            f.seek(off + 4); f.write(struct.pack('>I', attr & ~0x2000))
            f.seek(off + 12); f.write(struct.pack('>I', 0))
        if op == 'set':
            f.seek(off + 4); f.write(struct.pack('>I', int(sys.argv[3])))
            f.seek(off + 12); f.write(struct.pack('>I', int(sys.argv[4])))
PY
}
echo "image before: $(sha256sum "$img" | cut -c1-64)"
read -r vh_attr vh_jib < <(vh get "$img")
journaled=0
if (( vh_attr & 0x2000 )); then journaled=1; vh clear "$img"; echo "journaled bit cleared for the write (attr $vh_attr jib $vh_jib)"; fi
work=$(mktemp -d "${TMPDIR:-/tmp}/73-ssh.XXXXXX")
mnt=$work/img
mkdir -p "$mnt"
pid=""
cleanup() {
	if mountpoint -q "$mnt" 2>/dev/null; then fusermount3 -u "$mnt" || true; fi
	[ -n "$pid" ] && wait "$pid" 2>/dev/null || true
	rm -rf "$work"
}
trap cleanup EXIT
mount_img() {
	: > "$work/mount.log"
	"$FSTOOL" mount "$img" "$mnt" 2>"$work/mount.log" &
	pid=$!
	for _ in $(seq 1 200); do
		grep -q mounted "$work/mount.log" 2>/dev/null && break
		kill -0 "$pid" 2>/dev/null || { cat "$work/mount.log"; die "writer died"; }
		sleep 0.1
	done
	mountpoint -q "$mnt" || die "image did not mount"
}
umount_img() {
	sync
	fusermount3 -u "$mnt"
	wait "$pid" 2>/dev/null || true
	pid=""
}

# fstool's FUSE writer creates new files, links and directories and chowns and
# chmods them, but cannot change an existing file (open with O_TRUNC: ENOSYS;
# unlink then create the same name: EEXIST). So: phase 1 only creates, and stages
# the three changed files on the host; phase 2 swaps them offline with
# `fstool rm` + `fstool add`; phase 3 puts back their owner and mode.
REPL=(
	/private/var/jb/usr/libexec/sshd-keygen-wrapper
	/private/var/jb/etc/ssh/sshd_config
	/System/Library/xpc/launchd.plist
)
mkdir -p "$work/new"

echo "== phase 1: create"
mount_img
[ -d "$mnt/private/var" ] && [ -f "$mnt/System/Library/xpc/launchd.plist" ] || die "not an iOS root"
[ ! -e "$mnt/private/var/jb" ] || die "/private/var/jb already exists; refusing to overlay"

echo "== bootstrap -> /private/var/jb"
# -P: without it GNU tar writes a placeholder file for every absolute-target
# symlink (bin/ls -> /var/jb/usr/bin/ls) and swaps the link in at the end, which
# is the unlink-then-create the writer refuses. Member names are all ./var/jb/...
# (checked: no absolute or .. names), so -P changes nothing else.
zstd -dc "$boot" | tar -P --same-owner --no-overwrite-dir -xpf - -C "$mnt/private" ./var/jb
n=$(find "$mnt/private/var/jb" | wc -l)
echo "   $n entries"
[ -x "$mnt/private/var/jb/usr/sbin/sshd" ] || die "sshd not extracted"

echo "== sshd wrapper and config (staged)"
# The bootstrap ships a plain wrapper; ours adds the first-use setup (pwd.db,
# etc/shells, authorized_keys) that dpkg's postinst would have done.
cp tooling/ssh/sshd-keygen-wrapper.sh "$work/new/0"
cfg=$mnt/private/var/jb/etc/ssh/sshd_config
cp -p "$cfg" "$cfg.orig"
python3 -I - "$cfg" "$work/new/1" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
want = {'UsePAM': 'no', 'PasswordAuthentication': 'no', 'PermitRootLogin': 'prohibit-password'}
for k, v in want.items():
    s, n = re.subn(r'(?m)^#?\s*%s\s+.*$' % k, '%s %s' % (k, v), s)
    if not n:
        s += '\n%s %s\n' % (k, v)
open(sys.argv[2], 'w').write(s)
PY
grep -E '^(UsePAM|PasswordAuthentication|PermitRootLogin) ' "$work/new/1"

echo "== /bin/sh and root's key"
[ -e "$mnt/bin/sh" ] || ln -s /var/jb/bin/sh "$mnt/bin/sh"
mkdir -p "$mnt/private/var/root/.ssh"
[ ! -e "$mnt/private/var/root/.ssh/authorized_keys" ] || die "authorized_keys already exists"
cat "$pub" > "$mnt/private/var/root/.ssh/authorized_keys"
chown 0:0 "$mnt/private/var/root/.ssh" "$mnt/private/var/root/.ssh/authorized_keys"
chmod 0700 "$mnt/private/var/root/.ssh"
chmod 0600 "$mnt/private/var/root/.ssh/authorized_keys"

echo "== launchd job (staged)"
x=$mnt/System/Library/xpc
[ -e "$x/launchd.plist.pre-ssh" ] || cp -p "$x/launchd.plist" "$x/launchd.plist.pre-ssh"
python3 -I - "$x/launchd.plist" "$work/new/2" <<'PY'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], 'rb'))
key = '/System/Library/LaunchDaemons/com.openssh.sshd.plist'
d['LaunchDaemons'][key] = {
    'Label': 'com.openssh.sshd',
    'Program': '/var/jb/bin/sh',
    'ProgramArguments': ['/var/jb/bin/sh', '/var/jb/usr/libexec/sshd-keygen-wrapper', '-i'],
    'Sockets': {'Listeners': {'SockServiceName': '22', 'SockType': 'stream'}},
    'inetdCompatibility': {'Wait': False},
    'UserName': 'root',
    'GroupName': 'wheel',
    'POSIXSpawnType': 'Interactive',
    'ProcessType': 'Interactive',
}
data = plistlib.dumps(d, fmt=plistlib.FMT_BINARY)
open(sys.argv[2], 'wb').write(data)
print('   %d jobs, %d bytes' % (len(d['LaunchDaemons']), len(data)))
PY
for i in 0 1 2; do stat -c '%u %g %a' "$mnt${REPL[$i]}" > "$work/new/$i.st"; echo "   was $(cat "$work/new/$i.st") ${REPL[$i]}"; done
umount_img

echo "== phase 2: replace offline"
for i in 0 1 2; do
	"$FSTOOL" rm "$img" "${REPL[$i]}" >/dev/null
	"$FSTOOL" add "$img" "$work/new/$i" "${REPL[$i]}" >/dev/null
done

echo "== phase 3: owner and mode"
mount_img
for i in 0 1 2; do
	read -r u g m < "$work/new/$i.st"
	chown "$u:$g" "$mnt${REPL[$i]}"
	chmod "$m" "$mnt${REPL[$i]}"
	stat -c '   now %u %g %a %s %n' "$mnt${REPL[$i]}"
done
umount_img

"$FSTOOL" check "$img" | tail -2
if (( journaled )); then vh set "$img" "$vh_attr" "$vh_jib"; echo "journaled bit restored (attr $vh_attr jib $vh_jib)"; fi
# Read everything back from the unmounted image (not through the FUSE cache).
for i in 0 1 2; do "$FSTOOL" cat "$img" "${REPL[$i]}" | cmp - "$work/new/$i" || die "readback ${REPL[$i]}"; done
"$FSTOOL" cat "$img" /private/var/root/.ssh/authorized_keys | cmp - "$pub" || die "readback authorized_keys"
python3 -I -c 'import plistlib,sys; d=plistlib.load(open(sys.argv[1],"rb")); print("   readback: %d jobs, sshd %s" % (len(d["LaunchDaemons"]), "/System/Library/LaunchDaemons/com.openssh.sshd.plist" in d["LaunchDaemons"]))' "$work/new/2"
echo "image after:  $(sha256sum "$img" | cut -c1-64)"
