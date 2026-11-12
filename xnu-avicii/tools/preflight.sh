#!/bin/bash
# Local pre-flight: prove the whole series applies to a clean xnu-8796.141.3
# tree before spending a CI run.
#
#   xnu-avicii/tools/preflight.sh --tree ~/xnu-8796.141.3          # apply for real
#   xnu-avicii/tools/preflight.sh --tree ~/xnu-8796.141.3 --dry    # apply, then reset the tree
#
# What runs, in series order:
#   1. the hunk-count check (git apply silently drops trailing lines on a short
#      declared count instead of failing)
#   2. `copy` entries are executed in the tree - the three stage scripts fetch
#      pinned Apple/BearSSL sources into the tree, exactly as dxb runs them
#   3. `apply` entries get `git apply --check`, then `git apply` (--dry resets after)
#
# Use a scratch checkout of xnu-8796.141.3: the tree is modified in place (a
# later patch's --check can only be honest that way). `--tree` must be a git
# checkout; the script refuses a dirty tree unless --force is given.
# Exit: 0 pass, 1 fail, 2 usage.
set -u

here=$(cd "$(dirname "$0")" && pwd)
series="$here/../series"
tree=""
force=0
dry=0

while [ $# -gt 0 ]; do
	case "$1" in
	--tree) tree=$2; shift 2 ;;
	--force) force=1; shift ;;
	--dry) dry=1; shift ;;
	*) echo "usage: $0 --tree <clean-xnu-8796.141.3-dir> [--dry] [--force]" >&2; exit 2 ;;
	esac
done

if [ -z "$tree" ] || [ ! -d "$tree/.git" ]; then
	echo "need --tree pointing at a clean xnu-8796.141.3 git checkout" >&2
	exit 2
fi
tree=$(cd "$tree" && pwd)

if [ "$force" -eq 0 ] && [ -n "$(git -C "$tree" status --porcelain --untracked=no)" ]; then
	echo "$tree has modified tracked files; use --force or a fresh checkout" >&2
	exit 2
fi

echo "== hunk counts =="
python3 "$here/check-hunk-counts.py" "$here/../patches" || exit 1

# The stage scripts end by copying TargetConditionals.h out of the macOS SDK.
# On Linux there is no xcrun; a stub SDK with that one header is enough for the
# pre-flight (the real header only matters for a sweet_libpthread/HFS compile,
# which this check does not do).
shimroot=""
if ! command -v xcrun >/dev/null 2>&1; then
	shimroot=$(mktemp -d)
	mkdir -p "$shimroot/bin" "$shimroot/sdk/usr/include"
	printf '#!/bin/sh\necho "%s/sdk"\n' "$shimroot" >"$shimroot/bin/xcrun"
	chmod +x "$shimroot/bin/xcrun"
	printf '/* pre-flight stub: real header comes from the macOS SDK in CI */\n' \
		>"$shimroot/sdk/usr/include/TargetConditionals.h"
	PATH="$shimroot/bin:$PATH"
	echo "(no xcrun: using a stub SDK for the stage scripts)"
fi
trap '[ -n "$shimroot" ] && rm -rf "$shimroot"' EXIT

# Patches depend on their predecessors, so --dry also applies them (a bare
# --check against the pristine tree fails from 0007 on); the tree is reset at
# the end instead of being left patched.
if [ "$dry" -eq 1 ]; then
	trap 'git -C "$tree" checkout -q .; git -C "$tree" clean -qfd' EXIT
fi

echo "== series ($([ "$dry" -eq 1 ] && echo 'apply, then reset' || echo 'apply')) =="
n=0
while read -r verb file; do
	case "$verb" in
	''|'#') continue ;;
	esac
	name="$here/../patches/$file"
	n=$((n + 1))
	if [ ! -f "$name" ]; then
		echo "MISSING  $file"
		exit 1
	fi

	if [ "$verb" = "copy" ]; then
		if ! ( cd "$tree" && MACHINE_CONFIG=SWEET MACOS_VERSION=13.5 bash "$name" ) >"/tmp/preflight.$$" 2>&1; then
			echo "FAIL     $file (stage script)"
			sed 's/^/    /' "/tmp/preflight.$$"
			rm -f "/tmp/preflight.$$"
			exit 1
		fi
		echo "ok(stage) $file"
		continue
	fi

	if ! git -C "$tree" apply --check --whitespace=nowarn "$name" 2>"/tmp/preflight.$$"; then
		echo "FAIL     $file (after $((n - 1)) entries)"
		sed 's/^/    /' "/tmp/preflight.$$"
		rm -f "/tmp/preflight.$$"
		exit 1
	fi
	if ! git -C "$tree" apply --whitespace=nowarn "$name"; then
		echo "FAIL     $file (apply after a clean check)"
		exit 1
	fi
	echo "ok       $file"
done < "$series"
rm -f "/tmp/preflight.$$"

echo
if [ "$dry" -eq 1 ]; then
	echo "PASS (dry): all $n series entries check out and apply in order; $tree reset"
else
	echo "PASS: all $n series entries applied in order to $tree"
fi
