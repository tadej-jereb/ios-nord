#!/bin/bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
out=${1:-$repo/build/phone/gpu}
mkdir -p "$out"
flags=(-target arm64-apple-ios16.0 -isysroot "$repo/build/gpu/sysroot"
    -DXNU_PLATFORM_iPhoneOS -I"$repo/build/gpu/mesa-src/include"
    -std=c11 -O2 -Wall -Wextra -Werror -fuse-ld=lld -Wl,-adhoc_codesign
    -framework CoreFoundation -framework IOSurface)
"$repo/tooling/opt/llvm/bin/clang" "${flags[@]}" -shared \
    -Wl,-install_name,/private/var/root/gpu/SweetEAGL.dylib \
    "$here/sweeteagl.c" "$here/slots.c" "$here/objc.c" -o "$out/SweetEAGL.dylib"
"$repo/tooling/opt/llvm/bin/clang" "${flags[@]}" \
    "$here/eagltest.c" "$here/objc.c" -o "$out/eagltest"
sha256sum "$out/SweetEAGL.dylib" "$out/eagltest"
