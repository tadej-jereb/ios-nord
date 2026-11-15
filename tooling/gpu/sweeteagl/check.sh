#!/bin/bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
export PYTHONDONTWRITEBYTECODE=1
python3 "$here/gen_slots.py" --check
"$here/build.sh"
python3 "$here/verify.py"
