#!/bin/bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
export PYTHONDONTWRITEBYTECODE=1
bash -n "$here/build.sh" "$here/package.sh" "$here/check.sh"
"$here/package.sh"
python3 "$here/verify.py"
repo=$(cd "$here/../../.." && pwd)
cc -std=c11 -O2 -Wall -Wextra -Werror "$here/hosttest.c" -o "$repo/build/phone/sweetgles/hosttest"
"$repo/build/phone/sweetgles/hosttest"
