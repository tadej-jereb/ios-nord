#!/bin/bash
# build.sh — build drmtest (an iOS arm64 Mach-O, ad-hoc signed) without an SDK.
#   tooling/gpu/drmtest/build.sh [OUT]        default OUT: build/phone/drmtest
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
llvm=$repo/tooling/opt/llvm/bin
out=${1:-$repo/build/phone/drmtest}
mkdir -p "$(dirname "$out")"
"$llvm/clang" -target arm64-apple-ios16.0 -ffreestanding -fno-builtin -nostdlib -nostdinc \
	-O2 -fno-stack-protector -Wall -Wextra -Wno-unused-parameter -fuse-ld=lld -Qunused-arguments \
	-Wl,-platform_version,ios,16.0,16.0 -Wl,-fixup_chains -Wl,-adhoc_codesign \
	"$here/drmtest.c" "$here/libSystem.tbd" -o "$out"
"$llvm/llvm-objdump" --macho --dylibs-used "$out" | tail -n +2
sha256sum "$out"
