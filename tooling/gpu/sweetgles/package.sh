#!/bin/bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
# Consume the other session's build output; never rebuild/edit sweeteagl here.
eagl="$repo/build/phone/gpu/SweetEAGL.dylib"
mesa="$repo/build/gpu/mesa-build-es/src/gallium/targets/osmesa/libOSMesa.8.dylib"
if [[ ! -f "$mesa" ]]; then
    mesa="$repo/build/gpu/mesa-build/src/gallium/targets/osmesa/libOSMesa.8.dylib"
fi
for input in "$here/Info.plist" "$eagl" "$mesa"; do
    [[ -f "$input" ]] || { echo "Missing prerequisite: $input" >&2; exit 1; }
done
python3 - "$eagl" <<'PY'
from pathlib import Path
import sys
assert b'/System/Library/Extensions/SweetGLES.bundle/libOSMesa.8.dylib\0' in Path(sys.argv[1]).read_bytes(), 'SweetEAGL lacks bundle Mesa path'
print('PASS SweetEAGL contains absolute bundle Mesa lookup')
PY
"$here/build.sh"
bundle="$repo/build/phone/SweetGLES.bundle"
mkdir -p "$bundle"
install -m 0644 "$repo/build/phone/sweetgles/SweetGLES" "$bundle/SweetGLES"
install -m 0644 "$eagl" "$bundle/SweetEAGL.dylib"
install -m 0644 "$mesa" "$bundle/libOSMesa.8.dylib"
# Normalize only the packaged copy. LLVM regenerates its ad-hoc signature;
# verify.py checks every CodeDirectory SHA256 page hash after this rewrite.
"$repo/tooling/opt/llvm/bin/llvm-install-name-tool" \
    -id /System/Library/Extensions/SweetGLES.bundle/libOSMesa.8.dylib \
    "$bundle/libOSMesa.8.dylib"
install -m 0644 "$here/Info.plist" "$bundle/Info.plist"
chmod 0755 "$bundle"
(cd "$repo/build/phone" && sha256sum SweetGLES.bundle/SweetGLES SweetGLES.bundle/SweetEAGL.dylib SweetGLES.bundle/libOSMesa.8.dylib SweetGLES.bundle/Info.plist) | tee "$repo/build/phone/SweetGLES.bundle.sha256"
echo "Mesa input: $mesa"
