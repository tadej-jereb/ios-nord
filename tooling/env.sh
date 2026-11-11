# shellcheck shell=bash
# Source this, do not execute it:   . /home/tadej/ios-nord/tooling/env.sh
# Points PATH/CC/CXX/LD at the pinned toolchain installed by
# 10-user-toolchain.sh. Only those four variables plus the one library path
# that makes the LLVM 18.1.8 binaries run on a glibc-2.39 host.

IOSN_TOOLING="/home/tadej/ios-nord/tooling"
IOSN_LLVM="$IOSN_TOOLING/opt/llvm"
IOSN_DTC="$IOSN_TOOLING/opt/dtc"

export PATH="$IOSN_LLVM/bin:$IOSN_DTC/bin:$IOSN_TOOLING/opt/platform-tools:$PATH"
export CC="$IOSN_LLVM/bin/clang"
export CXX="$IOSN_LLVM/bin/clang++"
export LD="$IOSN_LLVM/bin/ld64.lld"
export LD_LIBRARY_PATH="$IOSN_LLVM/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
