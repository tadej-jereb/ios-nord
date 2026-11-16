#!/bin/bash
# CI-only: reset our dedicated scratch clones; retain compatible build objects.
set -euo pipefail
: "${GITHUB_WORKSPACE:?}" "${DXB_REPO:?}" "${DXB_SHA:?}" "${XNU_REPO:?}" "${XNU_TAG:?}"
root="$HOME/xnu-ci"
mkdir -p "$root/dxb"
# The runner executes one job at a time. Do not run two runners sharing this root.
git -C "$root/dxb" init -q
git -C "$root/dxb" fetch -q --depth 1 "$DXB_REPO" "$DXB_SHA"
git -C "$root/dxb" reset --hard FETCH_HEAD
git -C "$root/dxb" clean -fdx -e xnu/ -e build/ -e .cache/
if [[ ! -d "$root/dxb/xnu/.git" ]]; then
    git clone -q --depth 1 --branch "$XNU_TAG" "$XNU_REPO" "$root/dxb/xnu"
fi
git -C "$root/dxb/xnu" fetch -q --depth 1 "$XNU_REPO" "refs/tags/$XNU_TAG"
git -C "$root/dxb/xnu" reset --hard FETCH_HEAD
git -C "$root/dxb/xnu" clean -fdx
# dxb places OBJROOT in dxb/build, outside xnu. Invalidate it on toolchain or
# configuration changes; ordinary patch changes are handled by make + ccache.
key=$(printf '%s\n' "$DXB_SHA" "$XNU_TAG" "${KERNEL_CONFIG:?}" "${MACHINE_CONFIG:?}"; xcodebuild -version)
if [[ -d "$root/dxb/build" && $(cat "$root/dxb/build/.toolchain-key" 2>/dev/null || true) != "$key" ]]; then
    rm -rf "$root/dxb/build"
fi
mkdir -p "$root/dxb/build"
printf '%s\n' "$key" > "$root/dxb/build/.toolchain-key"
# build.sh skips make if its final kernel exists. Never reuse that kernel or
# allow the workflow's post-link fallback to accept an artifact from an old run.
find "$root/dxb/build" -type f -name 'kernel.*' -delete
# checkout cleans the workspace each job; the persistent clone lives outside it.
ln -s "$root/dxb" "$GITHUB_WORKSPACE/dxb"
