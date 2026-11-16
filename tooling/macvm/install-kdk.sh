#!/bin/bash
# Same target KDK as pinned dxb build.sh (663906528d1cd5ea8fde7de6f16de73db9511549).
# Install interactively during provisioning, so launchd jobs need no sudo password.
set -euo pipefail
kdk_root=/Library/Developer/KDKs/KDK_13.5_22G74.kdk
if [[ -d "$kdk_root" ]]; then
    exit 0
fi
image=$(mktemp -t xnu-kdk)
mount_dir=$(mktemp -d)
trap 'hdiutil detach "$mount_dir" >/dev/null 2>&1 || true; rm -f "$image"; rmdir "$mount_dir" 2>/dev/null || true' EXIT
kdk_url=$(curl -fLsS https://raw.githubusercontent.com/dortania/KdkSupportPkg/gh-pages/manifest.json | jq -er '.[] | select(.name == "Kernel Debug Kit 13.5 build 22G74") | .url')
[[ "$kdk_url" == https://* ]]
curl -fL --max-time 900 "$kdk_url" -o "$image"
hdiutil attach "$image" -mountpoint "$mount_dir" -nobrowse
sudo installer -pkg "$mount_dir/KernelDebugKit.pkg" -target /
test -d "$kdk_root"
