#!/bin/bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
out=${1:-$repo/build/phone/sweetgles}
mkdir -p "$out"
flags=(-target arm64-apple-ios16.0 -isysroot "$repo/build/gpu/sysroot"
    -DXNU_PLATFORM_iPhoneOS -I"$repo/build/gpu/mesa-src/include"
    -std=c11 -O2 -Wall -Wextra -Werror -fuse-ld=lld -Wl,-adhoc_codesign)
"$repo/tooling/opt/llvm/bin/clang" "${flags[@]}" -fvisibility=hidden -dynamiclib \
    -install_name /System/Library/Extensions/SweetGLES.bundle/SweetGLES \
    -Wl,-exported_symbol,_gldInitializeLibrary -Wl,-exported_symbol,_gldGetVersion \
    "$here/sweetgles.c" -o "$out/SweetGLES"
"$repo/tooling/opt/llvm/bin/clang" "${flags[@]}" -framework CoreFoundation -framework IOSurface \
    "$here/bundletest.c" -o "$out/bundletest"
sha256sum "$out/SweetGLES" "$out/bundletest"
