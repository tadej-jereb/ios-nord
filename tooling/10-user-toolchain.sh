#!/usr/bin/env bash
#
# 10-user-toolchain.sh -- UNPRIVILEGED cross-toolchain install.
#
#   Usage:  ./tooling/10-user-toolchain.sh [llvm|platform-tools|dtc|all]
#
# Needs no root: everything lands under tooling/opt/ and is reached through
# tooling/env.sh. Re-runnable: a component that already verifies is skipped, a
# cached download whose SHA-256 still matches is reused instead of re-fetched.
#
# Pinned versions (see docs/TOOLCHAIN.md for why these and nothing newer):
#   LLVM/clang 18.1.8         official x86_64 Linux release tarball
#   platform-tools r37.0.3    official Google release (adb/fastboot)
#   dtc 1.7.2 + flex 2.6.4 + bison 3.8.2   dtc built from source
#
# The LLVM tarball is the 18.1.8 release asset built on Ubuntu 18.04; on a
# glibc-2.39 host two compatibility fixes are applied (libtinfo.so.5 shim and
# an explicit LC_ALL path check) so the binaries actually run here.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPT="$HERE/opt"
DL="$OPT/downloads"
LLVM="$OPT/llvm"
PTOOLS="$OPT/platform-tools"
BOOT="$OPT/bootstrap"
DTC_PREFIX="$OPT/dtc"

LLVM_TARBALL="clang+llvm-18.1.8-x86_64-linux-gnu-ubuntu-18.04.tar.xz"
LLVM_URL="https://github.com/llvm/llvm-project/releases/download/llvmorg-18.1.8/$LLVM_TARBALL"
LLVM_SHA256="54ec30358afcc9fb8aa74307db3046f5187f9fb89fb37064cdde906e062ebf36"

PT_ZIP="platform-tools_r37.0.3-linux.zip"
PT_URL="https://dl.google.com/android/repository/$PT_ZIP"
PT_SHA256="214548146cadb2ca3508143d8a1d4be4c59de5bb837253e3ede89ed74cf450d1"
PT_SHA1="e1579b288a7ae4e9bc28dedec6a154d78b3c04ed"   # published in repository2-3.xml

DTC_TAR="dtc-1.7.2.tar.xz"
DTC_URL="https://www.kernel.org/pub/software/utils/dtc/$DTC_TAR"
DTC_SHA256="92d8ca769805ae1f176204230438fe52808f4e1c7944053c9eec0e649b237539"
FLEX_TAR="flex-2.6.4.tar.gz"
FLEX_URL="https://github.com/westes/flex/releases/download/v2.6.4/$FLEX_TAR"
FLEX_SHA256="e87aae032bf07c26f85ac0ed3250998c37621d95f8bd748b31f15b33c45ee995"
BISON_TAR="bison-3.8.2.tar.xz"
BISON_URL="https://ftp.gnu.org/gnu/bison/$BISON_TAR"
BISON_SHA256="9bba0214ccf7f1079c5d59210045227bcf619519840ebfa80cd3849cff5a5bf2"

# 18.1.8 links libtinfo.so.5; glibc-2.39 distros ship only .so.6 and a bare
# symlink fails on the NCURSES_TINFO_5.0.19991023 version tag. Taken from the
# jammy package, extracted without root.
LT5_DEB="libtinfo5_6.3-2ubuntu0.3_amd64.deb"
LT5_URL="http://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/$LT5_DEB"
LT5_SHA256="4df4288404108f1a156d014e8764a064e977e34e6d44931ab60451694c03c90d"

JOBS="$(nproc 2>/dev/null || echo 4)"
LOGDIR="$HERE/../logs"
mkdir -p "$OPT" "$DL" "$LOGDIR"

say()  { printf '\n==> %s\n' "$*"; }
ok()   { printf '    OK   %s\n' "$*"; }
die()  { printf '    FAIL %s\n' "$*" >&2; exit 1; }

# run_quiet <logfile> <cmd...> ; prints tail of log on failure
run_quiet() {
  local log="$1"; shift
  if ! "$@" >>"$log" 2>&1; then
    printf '    ---- tail of %s ----\n' "$log" >&2
    tail -n 30 "$log" >&2
    die "command failed: $*"
  fi
}

# fetch <url> <file> <sha256>  -- cached, hash-checked, atomic
fetch() {
  local url="$1" file="$DL/$2" want="$3"
  if [[ -f "$file" ]]; then
    if printf '%s  %s\n' "$want" "$file" | sha256sum -c --status -; then
      ok "cached $(basename "$file")"
      return 0
    fi
    say "cached $(basename "$file") hash mismatch -> re-downloading"
    rm -f "$file"
  fi
  say "downloading $(basename "$file")"
  curl -fL --retry 3 --retry-delay 2 --max-time 1800 -o "$file.part" "$url" \
    || die "download failed: $url"
  mv "$file.part" "$file"
  printf '%s  %s\n' "$want" "$file" | sha256sum -c --status - \
    || die "SHA-256 mismatch for $(basename "$file")"
  ok "sha256 verified $(basename "$file")"
}

# must_run <binary> -- executes --version and returns the version line.
# lld is a "generic driver" that prints its banner and exits 1, so a non-zero
# status is accepted when a banner was actually printed.
must_run() {
  local bin="$1" out rc=0
  [[ -x "$bin" ]] || die "missing or not executable: $bin"
  out="$("$bin" --version 2>&1 | head -n 1)" || rc=$?
  if [[ -z "$out" ]]; then die "$bin --version produced no output (rc=$rc)"; fi
  if [[ $rc -ne 0 ]]; then
    if grep -qiE 'version|lld|driver' <<<"$out"; then
      ok "$(basename "$bin"): $out (exit $rc, banner printed -> accepted)"
    else
      die "$bin --version failed: $out"
    fi
  else
    ok "$(basename "$bin"): $out"
  fi
}

# ---------------------------------------------------------------- llvm -------
llvm_good() {
  local b
  [[ -e "$LLVM/lib/libtinfo.so.5" ]] || return 1
  for b in clang clang++ lld ld64.lld llvm-objcopy llvm-strip llvm-ar llvm-nm; do
    [[ -x "$LLVM/bin/$b" ]] || return 1
    [[ -n "$("$LLVM/bin/$b" --version 2>&1 | head -n 1)" ]] || return 1
  done
  return 0
}

install_libtinfo5() {
  # Only installs once, and only if the pinned binary really cannot load.
  if [[ -e "$LLVM/lib/libtinfo.so.5.9" ]] \
     && ldd "$LLVM/bin/clang" | grep -c 'libtinfo\.so\.5 => /' >/dev/null; then
    ok "libtinfo.so.5 present and resolving"
    return 0
  fi
  fetch "$LT5_URL" "$LT5_DEB" "$LT5_SHA256"
  local tmp="$OPT/.lt5"
  rm -rf "$tmp"; mkdir -p "$tmp"
  dpkg-deb -x "$DL/$LT5_DEB" "$tmp" || die "could not extract $LT5_DEB"
  install -m 0644 "$tmp/lib/x86_64-linux-gnu/libtinfo.so.5.9" "$LLVM/lib/libtinfo.so.5.9"
  ln -sfn libtinfo.so.5.9 "$LLVM/lib/libtinfo.so.5"
  rm -rf "$tmp"
  ok "libtinfo.so.5.9 + symlink in $LLVM/lib (rpath resolves it)"
}

install_llvm() {
  say "LLVM / clang 18.1.8"
  if llvm_good; then
    ok "already installed and all binaries execute -> skip"
    return 0
  fi
  fetch "$LLVM_URL" "$LLVM_TARBALL" "$LLVM_SHA256"

  if [[ -d "$LLVM" ]]; then
    say "existing tree does not verify -> replacing"
    rm -rf "$LLVM"
  fi
  say "extracting (about 5 GB on disk)"
  rm -rf "$OPT/.llvm.tmp"; mkdir -p "$OPT/.llvm.tmp"
  tar -xJf "$DL/$LLVM_TARBALL" -C "$OPT/.llvm.tmp" --strip-components=1
  mv "$OPT/.llvm.tmp" "$LLVM"

  install_libtinfo5

  local unresolved
  unresolved="$(env -u LD_LIBRARY_PATH ldd "$LLVM/bin/clang" | grep 'not found' || true)"
  [[ -z "$unresolved" ]] || die "unresolved libraries for clang:
$unresolved"

  say "verifying every exposed binary actually runs"
  local b
  for b in clang clang++ lld ld64.lld llvm-objcopy llvm-strip llvm-ar llvm-nm; do
    must_run "$LLVM/bin/$b"
  done

  say "sanity: clang can target arm64-apple and ld64.lld links Mach-O"
  local probe="$OPT/.probe"; mkdir -p "$probe"
  printf 'int x = 42;\n' >"$probe/a.c"
  "$LLVM/bin/clang" -target arm64-apple-ios16.0 -c "$probe/a.c" -o "$probe/a.o" \
    || die "clang -target arm64-apple-ios16.0 produced no object"
  "$LLVM/bin/llvm-objcopy" -O binary "$probe/a.o" "$probe/a.bin" \
    || die "llvm-objcopy could not convert the Mach-O object"
  file "$probe/a.o" | grep -c 'Mach-O 64-bit arm64' >/dev/null \
    || die "clang did not emit Mach-O arm64: $(file -b "$probe/a.o")"
  ok "$(file -b "$probe/a.o")"
  rm -rf "$probe"
}

# -------------------------------------------------------- platform-tools -----
pt_good() { [[ -x "$PTOOLS/adb" && -x "$PTOOLS/fastboot" ]] \
  && "$PTOOLS/adb" version >/dev/null 2>&1 && "$PTOOLS/fastboot" --version >/dev/null 2>&1; }

install_ptools() {
  say "Android platform-tools r37.0.3 (adb, fastboot)"
  if pt_good; then
    ok "already installed and both binaries execute -> skip"
    return 0
  fi
  fetch "$PT_URL" "$PT_ZIP" "$PT_SHA256"
  printf '%s  %s\n' "$PT_SHA1" "$DL/$PT_ZIP" | sha1sum -c --status - \
    || die "SHA-1 differs from Google's published value"
  ok "sha1 matches Google repository2-3.xml"

  rm -rf "$PTOOLS" "$OPT/.pt.tmp"; mkdir -p "$OPT/.pt.tmp"
  unzip -q "$DL/$PT_ZIP" -d "$OPT/.pt.tmp"
  mv "$OPT/.pt.tmp/platform-tools" "$PTOOLS"
  rmdir "$OPT/.pt.tmp"
  chmod +x "$PTOOLS/adb" "$PTOOLS/fastboot"
  # adb/fastboot expect these next to themselves
  [[ -f "$PTOOLS/AdbWinApi.dll" ]] || true

  say "verifying"
  must_run "$PTOOLS/adb"
  must_run "$PTOOLS/fastboot"
}

# ----------------------------------------------------------------- dtc -------
dtc_good() { command -v dtc >/dev/null 2>&1 && dtc --version >/dev/null 2>&1; }

build_bootstrap() {
  # dtc ships .l/.y only; the release tarball has no generated parser, so an
  # unprivileged install needs its own flex and bison first.
  if [[ -x "$BOOT/bin/bison" && -x "$BOOT/bin/flex" ]] \
     && "$BOOT/bin/bison" --version >/dev/null 2>&1 && "$BOOT/bin/flex" --version >/dev/null 2>&1; then
    ok "bootstrap bison/flex already present"
    return 0
  fi
  command -v gcc >/dev/null || die "gcc required to build flex/bison"
  command -v m4  >/dev/null || die "m4 required to build bison"
  mkdir -p "$BOOT/src" "$BOOT/bin"

  say "building m4-based bison 3.8.2 (bootstrap only)"
  fetch "$BISON_URL" "$BISON_TAR" "$BISON_SHA256"
  rm -rf "$BOOT/src/bison"; mkdir -p "$BOOT/src/bison"
  run_quiet "$LOGDIR/bison-build.log" \
    tar -xJf "$DL/$BISON_TAR" -C "$BOOT/src/bison" --strip-components=1
  ( cd "$BOOT/src/bison" \
    && run_quiet "$LOGDIR/bison-build.log" ./configure --prefix="$BOOT" --disable-nls \
    && run_quiet "$LOGDIR/bison-build.log" make -j"$JOBS" \
    && run_quiet "$LOGDIR/bison-build.log" make install )

  say "building flex 2.6.4 (bootstrap only)"
  fetch "$FLEX_URL" "$FLEX_TAR" "$FLEX_SHA256"
  rm -rf "$BOOT/src/flex"; mkdir -p "$BOOT/src/flex"
  run_quiet "$LOGDIR/flex-build.log" \
    tar -xzf "$DL/$FLEX_TAR" -C "$BOOT/src/flex" --strip-components=1
  ( cd "$BOOT/src/flex" \
    && run_quiet "$LOGDIR/flex-build.log" ./configure --prefix="$BOOT" --disable-shared \
    && run_quiet "$LOGDIR/flex-build.log" make -j"$JOBS" \
    && run_quiet "$LOGDIR/flex-build.log" make install )

  must_run "$BOOT/bin/bison"
  must_run "$BOOT/bin/flex"
}

install_dtc() {
  say "device-tree-compiler (dtc) 1.7.2"
  if dtc_good; then
    ok "dtc already on PATH ($(command -v dtc)) -> skip"
    return 0
  fi
  if [[ -x "$DTC_PREFIX/bin/dtc" ]] && "$DTC_PREFIX/bin/dtc" --version >/dev/null 2>&1; then
    ok "private dtc already built ($DTC_PREFIX/bin/dtc) -> skip"
    return 0
  fi

  build_bootstrap
  fetch "$DTC_URL" "$DTC_TAR" "$DTC_SHA256"

  local src="$OPT/.dtc.src"
  rm -rf "$src"; mkdir -p "$src"
  run_quiet "$LOGDIR/dtc-build.log" tar -xJf "$DL/$DTC_TAR" -C "$src" --strip-components=1

  # libyaml headers are absent here: NO_YAML=1 drops the YAML backend only.
  say "compiling dtc (NO_YAML, NO_PYTHON)"
  ( cd "$src" \
    && run_quiet "$LOGDIR/dtc-build.log" make -j"$JOBS" \
         NO_YAML=1 NO_PYTHON=1 BISON="$BOOT/bin/bison" LEX="$BOOT/bin/flex" dtc )
  mkdir -p "$DTC_PREFIX/bin"
  install -m 0755 "$src/dtc" "$DTC_PREFIX/bin/dtc"
  rm -rf "$src"

  say "verifying"
  must_run "$DTC_PREFIX/bin/dtc"

  say "sanity: compile and decompile a real .dts"
  local probe="$OPT/.dtsprobe"; mkdir -p "$probe"
  printf '/dts-v1/;\n/ { model = "probe"; n = <0x1>; };\n' >"$probe/t.dts"
  "$DTC_PREFIX/bin/dtc" -I dts -O dtb -o "$probe/t.dtb" "$probe/t.dts" \
    || die "dtc could not compile a .dts"
  "$DTC_PREFIX/bin/dtc" -I dtb -O dts "$probe/t.dtb" | grep -c 'probe' >/dev/null \
    || die "dtc round-trip produced unexpected output"
  ok "$(file -b "$probe/t.dtb")"
  rm -rf "$probe"
}

# ---------------------------------------------------------------- main -------
case "${1:-all}" in
  llvm)           install_llvm ;;
  platform-tools) install_ptools ;;
  dtc)            install_dtc ;;
  all)            install_llvm; install_ptools; install_dtc ;;
  *) die "usage: $0 [llvm|platform-tools|dtc|all]" ;;
esac

say "summary"
for spec in "clang:$LLVM/bin/clang" "lld:$LLVM/bin/lld" "ld64.lld:$LLVM/bin/ld64.lld" \
            "llvm-objcopy:$LLVM/bin/llvm-objcopy" "llvm-strip:$LLVM/bin/llvm-strip" \
            "llvm-ar:$LLVM/bin/llvm-ar" "adb:$PTOOLS/adb" "fastboot:$PTOOLS/fastboot" \
            "dtc:${DTC_PREFIX}/bin/dtc"; do
  name="${spec%%:*}"; path="${spec#*:}"
  printf '    %-14s %s\n' "$name" "$("$path" --version 2>&1 | head -n 1)"
done
printf '\nsource %s/env.sh   # then use clang/lld/ld64.lld/adb/fastboot/dtc\n' "$HERE"
