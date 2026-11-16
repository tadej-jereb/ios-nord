#!/bin/bash
# Run inside the macOS VM as its admin user, never under sudo or bash -x.
set +x
set -euo pipefail
if [[ $(uname -s) != Darwin || $(uname -m) != x86_64 || $(id -u) == 0 ]]; then
    echo 'Run as the non-root admin user inside the Intel macOS VM.' >&2
    exit 1
fi
registration_token=${1:-}
script_dir=$(cd "$(dirname "$0")" && pwd)
runner_dir="$HOME/actions-runner"
# Homebrew refuses Intel macOS, so the Deps tools come from pinned release
# archives (sha256 checked) into /usr/local/bin; bash 5 is built from GNU source.
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
gh_rel=https://github.com
fetch() { # url sha256 file
    curl -fLsS "$1" -o "$3"
    echo "$2  $3" | shasum -a 256 -c -
}
tools_tmp=$(mktemp -d)
cd "$tools_tmp"
if ! /usr/local/bin/jq --version 2>/dev/null | grep -q '^jq-1\.8\.2$'; then
    fetch $gh_rel/jqlang/jq/releases/download/jq-1.8.2/jq-macos-amd64 \
        e94b266e3c26690550006abe63152b782280f4e14374accdf04cbde844f00bc0 jq
    sudo install -m 755 jq /usr/local/bin/jq
fi
if ! /usr/local/bin/gum --version 2>/dev/null | grep -q '2\.0\.2'; then
    fetch $gh_rel/charmbracelet/gum/releases/download/v2.0.2/gum_2.0.2_Darwin_x86_64.tar.gz \
        5374966c7c7199ea879fcaa525ddc6d447a098d3d35496e430a9a1ef38d30485 gum.tgz
    tar -xzf gum.tgz
    sudo install -m 755 gum_2.0.2_Darwin_x86_64/gum /usr/local/bin/gum
fi
if ! /usr/local/bin/ninja --version 2>/dev/null | grep -q '^1\.13\.2$'; then
    fetch $gh_rel/ninja-build/ninja/releases/download/v1.13.2/ninja-mac.zip \
        c99048673aa765960a99cf10c6ddb9f1fad506099ff0a0e137ad8960a88f321b ninja.zip
    unzip -o -q ninja.zip
    sudo install -m 755 ninja /usr/local/bin/ninja
fi
if ! /usr/local/bin/ccache --version 2>/dev/null | grep -q 'version 4\.14\.3'; then
    fetch $gh_rel/ccache/ccache/releases/download/v4.14.3/ccache-4.14.3-darwin.tar.gz \
        764dd2a8100ff83e6bbd7b9a1e2016cc401be34bee8a70ea99698186622c34d5 ccache.tgz
    tar -xzf ccache.tgz
    sudo install -m 755 ccache-4.14.3-darwin/ccache /usr/local/bin/ccache
fi
if ! /usr/local/bin/cmake --version 2>/dev/null | grep -q '4\.5\.0'; then
    fetch $gh_rel/Kitware/CMake/releases/download/v4.5.0/cmake-4.5.0-macos-universal.tar.gz \
        a645d69fd21e521759cc0c64e7c60462d43faf0c7214ac05f75c80f7c5037dde cmake.tgz
    tar -xzf cmake.tgz
    sudo rm -rf /Applications/CMake.app
    sudo mv cmake-4.5.0-macos-universal/CMake.app /Applications/
    sudo ln -sf /Applications/CMake.app/Contents/bin/cmake /usr/local/bin/cmake
fi
cd "$HOME"
rm -rf "$tools_tmp"
xcode_app=''
for candidate in /Applications/Xcode-16.0.0.app /Applications/Xcode.app /Applications/Xcode_16.app; do
    if [[ -d "$candidate/Contents/Developer" ]]; then
        xcode_app=$candidate
        break
    fi
done
if [[ -z "$xcode_app" ]]; then
    echo 'Install Xcode 16.0 first (xcodes install 16.0 -> /Applications/Xcode-16.0.0.app).' >&2
    exit 1
fi
sudo xcode-select -s "$xcode_app/Contents/Developer"
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
xcodebuild -version
xcrun --find iig
# bash 5 (build.sh needs bash-4 features); built here because it needs the Xcode toolchain.
if ! /usr/local/bin/bash -c '[[ ${BASH_VERSINFO[0]} -ge 5 ]]' 2>/dev/null; then
    bash_tmp=$(mktemp -d)
    fetch https://ftp.gnu.org/gnu/bash/bash-5.2.37.tar.gz \
        9599b22ecd1d5787ad7d3b7bf0c59f312b3396d1e281175dd1f8a4014da621ff "$bash_tmp/bash.tgz"
    tar -xzf "$bash_tmp/bash.tgz" -C "$bash_tmp"
    (cd "$bash_tmp/bash-5.2.37" && ./configure --prefix=/usr/local --without-bash-malloc >/dev/null && make -j"$(sysctl -n hw.ncpu)" >/dev/null && sudo make install >/dev/null)
    rm -rf "$bash_tmp"
fi
/usr/local/bin/bash --version | head -1
bash "$script_dir/install-kdk.sh"
# dxb checks only that this executable exists; Xcode is installed by the owner
# with the real xcodes (keep it if present).
if [[ ! -x /usr/local/bin/xcodes ]]; then
    printf '#!/bin/sh\nexit 0\n' | sudo tee /usr/local/bin/xcodes >/dev/null
    sudo chmod +x /usr/local/bin/xcodes
fi
export CCACHE_DIR="$HOME/ccache"
export CCACHE_MAXSIZE=20G
mkdir -p "$CCACHE_DIR" "$HOME/xnu-ci" "$runner_dir"
ccache --set-config=max_size=20G
if [[ ! -f "$runner_dir/.runner" ]]; then
    if [[ -z "$registration_token" ]]; then
        echo 'First registration requires a fresh GitHub registration token as argument 1.' >&2
        exit 1
    fi
    release_json=$(mktemp)
    runner_archive=$(mktemp)
    trap 'rm -f "$release_json" "$runner_archive"' EXIT
    curl -fLsS https://api.github.com/repos/actions/runner/releases/latest -o "$release_json"
    runner_url=$(jq -er '.assets[] | select(.name | test("^actions-runner-osx-x64-.*\\.tar\\.gz$")) | .browser_download_url' "$release_json")
    runner_digest=$(jq -er '.assets[] | select(.name | test("^actions-runner-osx-x64-.*\\.tar\\.gz$")) | .digest | select(startswith("sha256:"))' "$release_json")
    curl -fLsS "$runner_url" -o "$runner_archive"
    printf '%s  %s\n' "${runner_digest#sha256:}" "$runner_archive" | shasum -a 256 -c -
    tar -xzf "$runner_archive" -C "$runner_dir"
    cd "$runner_dir"
    ./config.sh --unattended --url https://github.com/tadej-jereb/ios-nord \
        --token "$registration_token" --name xnu-vm --labels xnu-vm --work _work
    # GitHub supplies self-hosted, macOS and X64 automatically.
fi
unset registration_token
cd "$runner_dir"
# launchd's default PATH omits /usr/local/bin.
printf '%s' /usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin > .path
python3 - <<'PY'
from pathlib import Path
import os
p = Path('.env')
lines = p.read_text().splitlines() if p.exists() else []
for key in ('CCACHE_DIR', 'CCACHE_MAXSIZE'):
    lines = [line for line in lines if not line.startswith(key + '=')]
    lines.append(key + '=' + os.environ[key])
p.write_text('\n'.join(lines) + '\n')
PY
if [[ ! -f .service ]]; then
    ./svc.sh install
fi
service_name=$(cat .service)
if ! launchctl list "$service_name" >/dev/null 2>&1; then
    ./svc.sh start
fi
./svc.sh status
ccache --show-config
printf 'Runner ready. Persistent sources: %s/xnu-ci; cache: %s\n' "$HOME" "$CCACHE_DIR"
