#!/bin/bash
# mesa-build.sh — cross-build Mesa freedreno + OSMesa for iOS 16 arm64 (no Apple SDK).
#   tooling/gpu/mesa-build.sh setup     write the cross file, meson setup
#   tooling/gpu/mesa-build.sh [build]   ninja
# Inputs (not in git): build/gpu/sysroot (tooling/gpu/mksysroot.sh, with the libSystem
# alias fix), build/gpu/mesa-src (Mesa 25.0.7 + tooling/gpu/mesa-patches/*).
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
export PATH=$repo/tooling/opt/mesa-venv/bin:$PATH
llvm=$repo/tooling/opt/llvm/bin
sr=$repo/build/gpu/sysroot
src=$repo/build/gpu/mesa-src
bld=$repo/build/gpu/mesa-build
cross=$repo/build/gpu/cross-ios16.ini
# -DXNU_PLATFORM_iPhoneOS: without it cdefs.h links $UNIX2003 symbols.
# -D_USE_EXTENDED_LOCALES_: Libc xlocale.h hides the *_l prototypes libc++ <locale> needs.
common="'-target', 'arm64-apple-ios16.0', '-fuse-ld=lld', '-isysroot', '$sr', '-DXNU_PLATFORM_iPhoneOS', '-D_USE_EXTENDED_LOCALES_', '-Qunused-arguments'"
case ${1:-build} in
setup)
	cat >"$cross" <<EOF
[binaries]
c = ['$llvm/clang', $common]
cpp = ['$llvm/clang++', $common, '-nostdinc++', '-isystem', '$sr/usr/include/c++/v1']
objc = ['$llvm/clang', $common]
ar = '$llvm/llvm-ar'
ranlib = '$llvm/llvm-ranlib'
strip = '$llvm/llvm-strip'
pkg-config = '/usr/bin/false'

[built-in options]
c_link_args = ['-Wl,-adhoc_codesign']
cpp_link_args = ['-Wl,-adhoc_codesign']

[host_machine]
system = 'darwin'
subsystem = 'ios'
cpu_family = 'aarch64'
cpu = 'arm64'
endian = 'little'

[properties]
needs_exe_wrapper = true
EOF
	rm -rf "$bld"
	meson setup "$bld" "$src" --cross-file="$cross" --buildtype=release \
		-Dplatforms= -Dgallium-drivers=softpipe,freedreno -Dfreedreno-kmds=msm -Dvulkan-drivers= \
		-Dosmesa=true -Dglx=disabled -Degl=disabled -Dgbm=disabled -Dllvm=disabled \
		-Dshared-glapi=enabled -Dgles1=disabled -Dgles2=enabled -Dopengl=true \
		-Dzstd=disabled -Dxmlconfig=disabled -Dexpat=disabled -Dshader-cache=disabled \
		-Dvalgrind=disabled -Dlibunwind=disabled -Dglvnd=disabled -Dvideo-codecs= -Dtools= \
		-Dgallium-vdpau=disabled -Dgallium-va=disabled -Dgallium-xa=disabled \
		-Dlmsensors=disabled -Dbuild-tests=false --wrap-mode=nodownload
	;;
build) ninja -C "$bld" -k 0 ;;
esac
