#!/bin/bash
# Run inside the macOS VM as its admin user, never under sudo or bash -x.
set +x
set -euo pipefail
if [[ $(uname -s) != Darwin || $(uname -m) != x86_64 || $(id -u) == 0 ]]; then
    echo 'Run as the non-root admin user inside the Intel macOS VM.' >&2
    exit 1
fi
registration_token=${1:-}
runner_dir="$HOME/actions-runner"
if ! command -v brew >/dev/null 2>&1; then
    if [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    else
        install_script=$(mktemp)
        curl -fLsS https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$install_script"
        /bin/bash "$install_script"
        rm -f "$install_script"
        eval "$(/usr/local/bin/brew shellenv)"
    fi
fi
brew install jq gum bash cmake ninja ccache
xcode_app=''
for candidate in /Applications/Xcode.app /Applications/Xcode_16.app; do
    if [[ -d "$candidate/Contents/Developer" ]]; then
        xcode_app=$candidate
        break
    fi
done
if [[ -z "$xcode_app" ]]; then
    echo 'Install Xcode 16.0 as /Applications/Xcode.app or Xcode_16.app first.' >&2
    exit 1
fi
sudo xcode-select -s "$xcode_app/Contents/Developer"
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
xcodebuild -version
xcrun --find iig
bash "$(dirname "$0")/install-kdk.sh"
# dxb checks only for this executable; Xcode is installed by the owner.
printf '#!/bin/sh\nexit 0\n' | sudo tee /usr/local/bin/xcodes >/dev/null
sudo chmod +x /usr/local/bin/xcodes
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
# Save brew's PATH for launchd, whose default PATH omits Homebrew.
printf '%s' "$PATH" > .path
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
