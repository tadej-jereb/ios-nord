#!/usr/bin/env bash
#
# run.sh <sysroot-dir>  -- re-run the two sysroot smoke tests from lane 1.
#
# Test 1 (step1.c): the sysroot's C header surface compiles for arm64-ios16.
# Test 2 (step2.c): printf/pthread_create/dlopen link against the .tbd stubs,
#                   and the resulting dylib names libSystem.B + libz.1.
# Control       : the same link with libSystem.B.tbd renamed away must FAIL.
#
# Nothing is written into <sysroot-dir>; all output goes to $OUT.
# Usage: ./run.sh ~/.hermes/cache/scratch/sysroot-ios16
#
set -u

SR="${1:-}"
if [ -z "$SR" ]; then
	echo "usage: $0 <sysroot-dir>" >&2
	exit 2
fi
# Refuse to run against anything that is not a sysroot with text-based stubs.
if [ ! -f "$SR/usr/lib/libSystem.B.tbd" ]; then
	echo "FATAL: $SR/usr/lib/libSystem.B.tbd is missing -- not an iOS .tbd sysroot" >&2
	exit 2
fi
SR=$(cd "$SR" && pwd)

TC=/home/tadej/ios-nord/tooling/opt/llvm/bin
CC="$TC/clang"
OBJDUMP="$TC/llvm-objdump"
for t in "$CC" "$OBJDUMP"; do
	[ -x "$t" ] || { echo "FATAL: $t not executable" >&2; exit 2; }
done

HERE=$(cd "$(dirname "$0")" && pwd)
OUT="${OUT:-/home/tadej/.hermes/cache/scratch/sysroot-test-out}"
rm -rf "$OUT"
mkdir -p "$OUT"

# Exactly the proof flags: target the phone, use only -isysroot (no -nostdinc),
# and drive the LLVM linker so .tbd parsing is lld's own.
FLAGS=(-target arm64-apple-ios16.0 -isysroot "$SR" -DXNU_PLATFORM_iPhoneOS -fuse-ld=lld)

rc=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1  ($2)"; rc=1; }

echo "sysroot: $SR"
echo "cc     : $CC"
echo "out    : $OUT"
echo

# ---- test 1: headers compile -------------------------------------------------
if "$CC" "${FLAGS[@]}" -c "$HERE/step1.c" -o "$OUT/step1.o" >"$OUT/step1.log" 2>&1; then
	pass "step1: C headers compile for arm64-apple-ios16.0"
else
	fail "step1: C headers compile for arm64-apple-ios16.0" "see $OUT/step1.log"
fi

# ---- test 2: link against the tbds, then check the load commands -------------
if "$CC" "${FLAGS[@]}" -dynamiclib "$HERE/step2.c" -lz \
		-o "$OUT/libstep2.dylib" >"$OUT/step2.log" 2>&1; then
	"$OBJDUMP" --macho --private-headers "$OUT/libstep2.dylib" \
		>"$OUT/step2.headerdump" 2>&1
	missing=""
	grep -q 'name /usr/lib/libSystem.B.dylib' "$OUT/step2.headerdump" ||
		missing="$missing LC_LOAD_DYLIB(libSystem.B)"
	grep -q 'name /usr/lib/libz.1.dylib' "$OUT/step2.headerdump" ||
		missing="$missing LC_LOAD_DYLIB(libz.1)"
	grep -q 'platform ios' "$OUT/step2.headerdump" ||
		missing="$missing LC_BUILD_VERSION(platform ios)"
	grep -q 'minos 16.0' "$OUT/step2.headerdump" ||
		missing="$missing minos(16.0)"
	if [ -z "$missing" ]; then
		pass "step2: dylib links and names libSystem.B + libz.1, platform ios, minos 16.0"
	else
		fail "step2: dylib links and names libSystem.B + libz.1, platform ios, minos 16.0" \
			"missing:$missing"
	fi
else
	fail "step2: dylib links against the tbds" "see $OUT/step2.log"
fi

# ---- control: the same link must fail without libSystem.B.tbd ----------------
# Work on a copy so the shared sysroot is never modified.
NEG="$OUT/sysroot-neg"
mkdir -p "$NEG"
cp -a "$SR"/. "$NEG"/ 2>/dev/null
mv "$NEG/usr/lib/libSystem.B.tbd" "$NEG/usr/lib/libSystem.B.tbd.gone"
NEG_FLAGS=(-target arm64-apple-ios16.0 -isysroot "$NEG" -DXNU_PLATFORM_iPhoneOS -fuse-ld=lld)
if "$CC" "${NEG_FLAGS[@]}" -dynamiclib "$HERE/step2.c" -lz \
		-o "$OUT/libstep2-neg.dylib" >"$OUT/neg.log" 2>&1; then
	fail "control: link fails with libSystem.B.tbd renamed away" \
		"it succeeded -- a host library leaked in"
else
	pass "control: link fails with libSystem.B.tbd renamed away"
fi

echo
if [ $rc -eq 0 ]; then echo "ALL PASS"; else echo "SOME TESTS FAILED"; fi
exit $rc
