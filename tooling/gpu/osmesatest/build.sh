#!/bin/bash
# build.sh — build osmesatest + copy libOSMesa.8.dylib next to it, both ad-hoc signed.
#   tooling/gpu/osmesatest/build.sh [OUTDIR]      default OUTDIR: build/phone/gpu
# Needs build/gpu/sysroot and build/gpu/mesa-build (tooling/gpu/mesa-build.sh).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
llvm=$repo/tooling/opt/llvm/bin
sr=$repo/build/gpu/sysroot
mesa=$repo/build/gpu/mesa-build/src/gallium/targets/osmesa
out=${1:-$repo/build/phone/gpu}
mkdir -p "$out"
"$llvm/clang" -target arm64-apple-ios16.0 -isysroot "$sr" -DXNU_PLATFORM_iPhoneOS \
	-I"$repo/build/gpu/mesa-src/include" -O2 -Wall -Wextra -Wno-unused-parameter \
	-fuse-ld=lld -Wl,-adhoc_codesign \
	"$here/osmesatest.c" -o "$out/osmesatest"
cp "$mesa/libOSMesa.8.dylib" "$out/"
# relink keeps lld's ad-hoc signature; the copied dylib was signed at its own link.
"$llvm/llvm-objdump" --macho --dylibs-used "$out/osmesatest" | tail -n +2
sha256sum "$out/osmesatest" "$out/libOSMesa.8.dylib"
