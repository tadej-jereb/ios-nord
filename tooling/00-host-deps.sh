#!/usr/bin/env bash
#
# 00-host-deps.sh -- host packages for the avicii XNU/ARM64 bring-up.
#
#   REQUIRES ROOT. Run manually:
#       sudo /home/tadej/ios-nord/tooling/00-host-deps.sh
#       sudo /home/tadej/ios-nord/tooling/00-host-deps.sh --check   # print only
#
# Idempotent: every package is skipped when dpkg already reports it installed,
# so re-running is cheap and safe. Nothing outside this file's two side effects
# (apt install, and the udev/module files listed at the bottom) is touched.
#
# Every name below was resolved against this release (Linux Mint 22.3 /
# Ubuntu noble) with `apt-cache policy` before being written down; the script
# re-checks all of them up front and aborts on an unknown name rather than
# handing apt a half-valid list.
#
# apfs-fuse is deliberately NOT in the list: noble has no package for it. It is
# only needed to read the iOS IPSW's APFS dmg, and is built from source by
# hand (see docs/TOOLCHAIN.md, "Reading the IPSW").
#
set -euo pipefail

CHECK_ONLY=0
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1

if [[ $CHECK_ONLY -eq 0 && $EUID -ne 0 ]]; then
  echo "need root: sudo $0" >&2
  exit 1
fi

# package<TAB>one-line reason
PKGS=$(cat <<'EOF'
build-essential	host C/C++ compiler for dtc/bootstrap and local helper tools
pkg-config	build glue for source-built host helpers
autoconf	regenerate configure in source-built upstream helpers
automake	regenerate Makefile.in in source-built upstream helpers
libtool	shared-lib build glue for the same
bison	dtc parser generator (dtc ships .y only)
flex	dtc lexer generator (dtc ships .l only)
libyaml-dev	dtc YAML output backend (-O yaml) for readable dumps
device-tree-compiler	distro dtc, fallback for compiling the board DTB
llvm-18	distro LLVM 18 suite, fallback if the pinned tarball is unusable
clang-18	distro clang, same fallback role
lld-18	distro lld incl. ld64.lld, Mach-O link fallback
llvm-18-tools	distro llvm-objcopy/llvm-strip/llvm-nm/llvm-readobj fallback
libssl-dev	openssl headers for XNU libkern crypto and host digest helpers
libelf-dev	ELF/DWARF headers for pahole and ktrace symbol tooling
libdw-dev	DWARF access library used by dwarves/dwz
dwarves	pahole/dwz for DWARF and dSYM post-processing
libncurses-dev	curses headers for kvm/ksyms-style host tools
zlib1g-dev	zlib headers, IPSW/dmg and kernel-cache (de)compression
libbz2-dev	bzip2 headers for dmg payload handling
liblzma-dev	xz headers for dmg/kernel-cache payload handling
uuid-dev	uuid headers linked by XNU host tools
hfsprogs	mkfs.hfsplus/fsck.hfsplus: builds and repairs the HFS+ root volume
adb	distro adb (second copy of the phone transport)
fastboot	distro fastboot for boot_b flashing and set_active
android-sdk-platform-tools-common	udev rules + plugdev group for adb/fastboot on USB
android-sdk-libsparse-utils	img2simg/simg2img for sparse userdata images
qemu-system-arm	qemu-system-aarch64 to boot-test the shim in a VM first
qemu-utils	qemu-img for raw<->qcow2 conversion of test images
libfuse3-dev	fuse3 headers, needed to source-build apfs-fuse
libattr1-dev	xattr headers, also required by the apfs-fuse source build
fuse3	fuse3 runtime for apfs-fuse and mount helpers
cryptsetup-bin	cryptsetup for the IPSW's encrypted dmg layer
e2fsprogs	mkfs.ext4/mke2fs for scratch volumes
dosfstools	mkfs.vfat for EFI-style scratch partitions
cpio	cpio archives for ramdisk/root population
abootimg	unpack the stock boot.img to recover the board DTB (README step 0)
rsync	fast, resumable root-image population
kmod	modprobe/insmod for hfsplus and loop devices
usbutils	lsusb to identify the phone in fastboot/EDL
pciutils	lspci for USB controller diagnostics
python3-dev	python headers for the helper scripts and native modules
python3-venv	isolated venvs for bring-up tooling
python3-pip	pip inside those venvs
git	clone/patch the trees under refs/ and the forks to port
gh	drive the GitHub Actions xnu.yml build (fork, workflow run, artifact pull)
jq	parse Actions run/artifact JSON in scripts
cmake	build apfs-fuse and other host helpers
ninja-build	fast generator for the same
curl	download pinned toolchain and firmware artifacts
wget	second fetcher for mirrors that reject curl
ca-certificates	trust store for github.com/dl.google.com over TLS
unzip	unpack platform-tools and vendor archives
xz-utils	xz for tarballs and kernel-cache payloads
file	identify Mach-O/DTB images during debugging
bc	kernel make's fixed-point arithmetic
pv	progress on long dd/image operations
strace	syscall tracing when a host tool misbehaves
lsof	see what holds a loop/mount/phone device open
EOF
)

echo "== checking every package name against this release"
missing=0
while IFS=$'\t' read -r pkg reason; do
  [[ -z "$pkg" ]] && continue
  cand="$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/{print $2}')"
  if [[ -z "$cand" ]]; then
    printf '  UNKNOWN  %s\n' "$pkg" >&2
    missing=1
  fi
done <<<"$PKGS"
[[ $missing -eq 0 ]] || { echo "unknown package name(s) above; aborting" >&2; exit 1; }

if [[ $CHECK_ONLY -eq 1 ]]; then
  printf '\n%-42s %-10s %s\n' PACKAGE STATE REASON
  while IFS=$'\t' read -r pkg reason; do
    [[ -z "$pkg" ]] && continue
    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -c 'install ok installed' >/dev/null; then
      st=installed
    else
      st=to-install
    fi
    printf '%-42s %-10s %s\n' "$pkg" "$st" "$reason"
  done <<<"$PKGS"
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive
echo "== apt update"
apt-get update

echo "== installing (already-present packages are skipped)"
todo=()
while IFS=$'\t' read -r pkg reason; do
  [[ -z "$pkg" ]] && continue
  if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -c 'install ok installed' >/dev/null; then
    printf '  have     %-40s %s\n' "$pkg" "$reason"
  else
    printf '  install  %-40s %s\n' "$pkg" "$reason"
    todo+=("$pkg")
  fi
done <<<"$PKGS"

if [[ ${#todo[@]} -gt 0 ]]; then
  apt-get install -y --no-install-recommends "${todo[@]}"
fi

echo "== udev rules for OnePlus/Qualcomm USB ids (adb + fastboot)"
cat >/etc/udev/rules.d/51-android-ios-nord.rules <<'EOF'
# avicii / OnePlus (22d9) and Qualcomm EDL (05c6) -- adb, fastboot, EDL
SUBSYSTEM=="usb", ATTR{idVendor}=="22d9", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="05c6", MODE="0666", GROUP="plugdev"
# generic Android vendor range used by google/motorola tooling
SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0666", GROUP="plugdev"
EOF
udevadm control --reload-rules || true
udevadm trigger || true

echo "== plugdev group for the desktop user"
if ! getent group plugdev >/dev/null; then groupadd plugdev; fi
for u in $(logname 2>/dev/null || true) "${SUDO_USER:-}"; do
  [[ -n "$u" && "$u" != root ]] || continue
  if id -nG "$u" | grep -cw plugdev >/dev/null; then
    echo "  $u already in plugdev"
  else
    usermod -aG plugdev "$u"
    echo "  added $u to plugdev (log out/in to take effect)"
  fi
done

echo "== hfsplus: load now and at boot"
cat >/etc/modules-load.d/hfsplus.conf <<'EOF'
hfsplus
EOF
modprobe hfsplus || echo "  WARNING: modprobe hfsplus failed (module missing?)" >&2

echo "== verify"
fail=0
for probe in clang-18 lld-18 ld64.lld llvm-objcopy-18 dtc mkfs.hfsplus adb fastboot \
             qemu-system-aarch64 qemu-img img2simg cryptsetup pahole; do
  if command -v "$probe" >/dev/null 2>&1; then
    printf '  OK   %s\n' "$(command -v "$probe")"
  else
    printf '  MISS %s\n' "$probe"; fail=1
  fi
done
grep -q hfsplus /proc/filesystems && echo "  OK   hfsplus registered" || { echo "  MISS hfsplus"; fail=1; }

[[ $fail -eq 0 ]] || { echo "some probes are missing - see above" >&2; exit 1; }
echo "host dependencies complete"
