#!/bin/bash
# Build apfs-fuse from source into tooling/opt/apfs-fuse, unprivileged.
#
#   tooling/32-build-apfsfuse.sh [--rebuild] [--check]
#
#   --rebuild  throw the existing build tree away and build again
#   --check    after the build, mount one IPSW DMG read-only, list it,
#              unmount - proves FUSE + the DMG reader work on this host
#
# No root, no apt: the binary links only libfuse3/libz/libbz2 from the host and
# carries the vendored Crypto/ + lzfse sources itself (crypto++ is NOT needed,
# contrary to the README). Nothing is installed outside tooling/opt.
#
# Pinned upstream: sgan81/apfs-fuse @ 66b86bd (2023-03-12), submodule
# 3rdparty/lzfse @ e634ca5. apfs-fuse is GPL-2.0; see LICENSE in the source.
# Re-runnable: an existing working binary is kept unless --rebuild is given.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
prefix=$root/tooling/opt/apfs-fuse
src=$root/tooling/opt/src/apfs-fuse
repo=https://github.com/sgan81/apfs-fuse.git
pin=66b86bd525e8cb90f9012543be89b1f092b75cf3
lzfse_pin=e634ca58b4821d9f3d560cdc6df5dec02ffc93fd
jobs=${JOBS:-$(nproc)}
bin=$prefix/bin/apfs-fuse

rebuild=0
check=0
while (( $# )); do
	case $1 in
		--rebuild) rebuild=1 ;;
		--check)   check=1 ;;
		-h|--help) sed -n '2,17p' "$0"; exit 0 ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
	shift
done

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# --- preconditions ---------------------------------------------------------
missing=()
for t in cmake git pkg-config cc c++ ninja; do
	command -v "$t" >/dev/null || missing+=("$t")
done
(( ${#missing[@]} == 0 )) || die "missing tools: ${missing[*]}"
for h in /usr/include/fuse3/fuse.h /usr/include/zlib.h /usr/include/bzlib.h; do
	[[ -e $h ]] || missing+=("$(basename "$h")")
done
if (( ${#missing[@]} )); then
	echo "missing build headers: ${missing[*]}" >&2
	echo "  sudo apt install libfuse3-dev libbz2-dev zlib1g-dev cmake g++ git ninja-build" >&2
	exit 1
fi
[[ -e /dev/fuse ]] || die "/dev/fuse missing - FUSE mounts are impossible on this host"
pkg-config --exists fuse3 || die "pkg-config cannot see fuse3.pc (libfuse3-dev)"

# --- already built? --------------------------------------------------------
verify_bin() {
	[[ -x $bin ]] || return 1
	# No --help in upstream; bare invocation prints usage and exits non-zero.
	out=$("$bin" 2>&1 || true)
	grep -q 'apfs-fuse \[options\] <device> <dir>' <<<"$out" || return 1
	ldd "$bin" | grep -q 'not found' && return 1
	return 0
}
if (( ! rebuild )) && verify_bin; then
	say "apfs-fuse already built: $bin"
	say "  rebuild with: tooling/32-build-apfsfuse.sh --rebuild"
else
	mkdir -p "$(dirname "$src")" "$prefix"
	if [[ ! -d $src/.git ]]; then
		say "cloning $repo"
		git clone --quiet "$repo" "$src"
	fi
	git -C "$src" fetch --quiet origin
	git -C "$src" checkout --quiet --detach "$pin"
	git -C "$src" submodule --quiet update --init --recursive
	[[ "$(git -C "$src" rev-parse HEAD)" == "$pin" ]] || die "checkout did not land on $pin"
	[[ "$(git -C "$src/3rdparty/lzfse" rev-parse HEAD)" == "$lzfse_pin" ]] || \
		die "lzfse submodule is not at $lzfse_pin"

	# Release + -O2 is CMakeLists' own default; keep the vendored crypto/lzfse
	# paths and only override the fuse generation (3 is required on 64-bit).
	say "configuring"
	CC=${CC:-cc} CXX=${CXX:-c++} cmake -S "$src" -B "$src/build" -G Ninja \
		-DUSE_FUSE3=ON -DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$prefix" >"$src/build.log" 2>&1 || {
			tail -30 "$src/build.log" >&2; die "cmake configure failed (see $src/build.log)"; }
	say "building with $jobs jobs"
	cmake --build "$src/build" -j "$jobs" >>"$src/build.log" 2>&1 || {
		tail -40 "$src/build.log" >&2; die "build failed (see $src/build.log)"; }
	cmake --install "$src/build" >>"$src/build.log" 2>&1
	verify_bin || die "built, but $bin does not print usage"
	say "installed $bin"
fi

# --- optional proof --------------------------------------------------------
if (( check )); then
	dmg=$(ls -1 "$root"/build/ipsw-x/*.dmg 2>/dev/null | head -1 || true)
	[[ -n $dmg ]] || die "no DMG under build/ipsw-x - run tooling/30-fetch-ipsw.sh"
	tmp=$(mktemp -d "${TMPDIR:-/tmp}/apfsfuse-check.XXXXXX")
	trap 'fusermount3 -uz "$tmp" 2>/dev/null || true; rmdir "$tmp" 2>/dev/null || true' EXIT
	say "check: mounting $(basename "$dmg") read-only (no root, no loop device)"
	"$bin" -o ro "$dmg" "$tmp"
	for i in {1..20}; do mountpoint -q "$tmp" && break; sleep 0.5; done
	mountpoint -q "$tmp" || die "mount did not appear (see: tooling/32-build-apfsfuse.sh --rebuild)"
	n=$(ls -A "$tmp" | wc -l)
	[[ -d $tmp/root/System/Library ]] || die "mounted, but no /root/System/Library inside"
	say "check: mounted, $n top-level entries, /root/System/Library present"
	fusermount3 -u "$tmp"
	sleep 0.5
	mountpoint -q "$tmp" && die "unmount failed"
	say "check: unmounted cleanly"
fi
say "ok: $bin"
