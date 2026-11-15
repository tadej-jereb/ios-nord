#!/bin/bash
# Native Linux proof. Only the private -host source/build directories are written.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
export PATH="$repo/tooling/opt/mesa-venv/bin:$PATH"
pristine=${MESA_PRISTINE:-$HOME/.hermes/cache/scratch/lane-3/pristine}
src=$repo/build/gpu/mesa-src-host
bld=$repo/build/gpu/mesa-build-host
export CCACHE_DIR="$bld/ccache"
patches=("$repo"/tooling/gpu/mesa-patches/000[1-7]-*.patch)
test "${#patches[@]}" = 7
receipt=$(cd "$repo/tooling/gpu/mesa-patches" && sha256sum 000[1-7]-*.patch)
if [[ ! -e $src ]]; then
    cp -a "$pristine" "$src"
    for p in "${patches[@]}"; do
        echo "Dry-run and apply: $(basename "$p")"
        patch --batch --fuzz=0 -d "$src" -p1 --dry-run < "$p"
        patch --batch --fuzz=0 -d "$src" -p1 < "$p"
    done
    printf '%s\n' "$receipt" > "$src/.ios-nord-patches"
fi
test -f "$src/.ios-nord-patches"
test "$(cat "$src/.ios-nord-patches")" = "$receipt"
echo 'PASS source: pristine + all seven patches (no Linux exceptions)'
if [[ ! -f $bld/build.ninja ]]; then
    meson setup "$bld" "$src" --buildtype=release \
        -Dgallium-drivers=softpipe -Dosmesa=true -Dplatforms= -Dglx=disabled \
        -Degl=disabled -Dgbm=disabled -Dllvm=disabled -Dvulkan-drivers= \
        -Dshared-glapi=enabled -Dgles1=disabled -Dgles2=enabled -Dopengl=true \
        -Dzstd=disabled -Dxmlconfig=disabled -Dexpat=disabled -Dshader-cache=disabled \
        -Dvalgrind=disabled -Dlibunwind=disabled -Dglvnd=disabled -Dvideo-codecs= -Dtools= \
        -Dgallium-vdpau=disabled -Dgallium-va=disabled -Dgallium-xa=disabled \
        -Dlmsensors=disabled -Dbuild-tests=false --wrap-mode=nodownload
fi
ninja -C "$bld" -j "${JOBS:-8}"
cc -std=c11 -O2 -Wall -Wextra -Werror -I"$src/include" \
    "$here/gles-host-test.c" -L"$bld/src/gallium/targets/osmesa" \
    -Wl,-rpath,"$bld/src/gallium/targets/osmesa" -lOSMesa -o "$bld/gles-host-test"
# Overrides must not turn the negative control into an ES context or fake strings.
unset MESA_GL_VERSION_OVERRIDE MESA_GLES_VERSION_OVERRIDE MESA_GLSL_VERSION_OVERRIDE
unset MESA_EXTENSION_OVERRIDE MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER
echo 'INFO gles2=enabled supplies ES dispatch; shared-glapi=enabled unchanged; gles1 not needed'
"$bld/gles-host-test"
echo 'PASS run.sh (native Linux softpipe; iOS GPU execution remains unverified)'
