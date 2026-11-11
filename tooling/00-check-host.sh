#!/bin/bash
# Report whether this host can run the iOS root image pipeline. Read-only.
#
#   tooling/00-check-host.sh
#
# Exit 0 only when every prerequisite is present. Nothing here needs root;
# the install lines are printed for you to run yourself.
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
bad=0

ok()   { printf 'ok      %s\n' "$*"; }
no()   { printf 'MISSING %s\n' "$*"; bad=1; }
warn() { printf 'warn    %s\n' "$*"; }

# hfsprogs: mkfs.hfsplus / fsck.hfsplus (absolute paths, they are in /usr/sbin)
for t in /usr/sbin/mkfs.hfsplus /usr/sbin/fsck.hfsplus; do
	if [[ -x $t ]]; then ok "$t ($($t -h 2>&1 | head -1 || true))"; else
		no "$t   -> sudo apt install hfsprogs"; fi
done
for t in rsync truncate xxd python3 curl df du stat; do
	if command -v "$t" >/dev/null; then ok "$t"; else no "$t"; fi
done
# apfs-fuse: not packaged on Mint 22.x - source build only
if command -v apfs-fuse >/dev/null; then ok "apfs-fuse $(apfs-fuse 2>&1 | head -1)"
else no "apfs-fuse (APFS read; source build, see docs/IOSROOT.md Requirements)"; fi
for t in cmake g++ git; do command -v "$t" >/dev/null || warn "$t (needed to build apfs-fuse)"; done
for h in fuse3 bzlib.h zlib.h cryptopp; do
	[[ -e /usr/include/$h || -d /usr/include/fuse3 ]] && ok "header $h" || warn "header $h (for apfs-fuse build)"
done

# Sparse-image tooling: ours, but fastboot/simg2img help for spot checks
[[ -x $root/tooling/sparse.py ]] && ok "tooling/sparse.py" || no "tooling/sparse.py"
for fb in "$root/tooling/opt/platform-tools/fastboot" "$(command -v fastboot || true)"; do
	[[ -x $fb ]] && { ok "fastboot ($fb)"; fb_found=1; break; }
done
[[ ${fb_found:-0} == 1 ]] || warn "fastboot (only needed for the on-device step, see 00-host-deps.sh)"

# Kernel hfsplus support for the loop mount during populate
if grep -qw hfsplus /proc/filesystems; then ok "kernel hfsplus (loop mount possible)"
elif modinfo -F filename hfsplus >/dev/null 2>&1; then
	warn "kernel hfsplus module present but not loaded -> sudo modprobe hfsplus"
else no "kernel hfsplus (CONFIG_HFSPLUS_FS) - no loop mount"; fi
[[ -e /dev/loop-control ]] && ok "/dev/loop-control" || no "/dev/loop-control (no loop devices)"

avail=$(df --output=avail -B1 "$root" | tail -1 | tr -d ' ')
need=$(( 9 * 1024 * 1024 * 1024 ))
(( avail > need )) && ok "free space $(numfmt --to=iec "$avail") on $root" \
	|| no "free space $(numfmt --to=iec "$avail") < $(numfmt --to=iec "$need")"

(( bad == 0 )) || { echo "host not ready"; exit 1; }
echo "host ready"
