# Host toolchain

What each host tool is for in the avicii port, which versions are pinned, why,
and how the two upstream build repositories are actually used. Host prep only —
nothing here touches the phone.

Two layers, deliberately separated:

| Layer | Script | Privilege |
| --- | --- | --- |
| Host packages, udev rules, group, hfsplus module | `tooling/00-host-deps.sh` | root, run by hand |
| Cross toolchain (clang/lld/ld64.lld, adb/fastboot, dtc) | `tooling/10-user-toolchain.sh` | none, runs now |

Both are idempotent. `10-user-toolchain.sh` was run to completion on this host;
the versions it installed and their `--version` output are quoted below.

## Role of each tool

**clang 18.1.8 (`tooling/opt/llvm/bin/clang`)** — the compiler. Compiles the
shim (`SHIM`/payload entry stubs), the static arm64 Mach-O payloads, and XNU
itself when built locally. Cross-targets with `-target arm64-apple-ios16.0`; no
Apple SDK is used, only the open-source headers in the XNU and shim trees.

**ld64.lld (`tooling/opt/llvm/bin/ld64.lld`)** — the Mach-O linker. Produces
the `kernel.*` Mach-O, the shim ELF-adjacent images and any hand-built payload.
`lld` (generic driver) dispatches to it; `ld64.lld` is what actually runs for
`-arch arm64` Mach-O output. This is why an LLVM release tarball is used instead
of the distro `binutils`, which cannot emit Mach-O at all.

**llvm-objcopy / llvm-strip / llvm-ar / llvm-nm**
(`tooling/opt/llvm/bin/…`) — payload surgery: `-O binary` flattening of a linked
Mach-O for the ramdisk, stripping symbols from the release payload, `llvm-nm`
for symbol checks while debugging, `llvm-ar` for the libkernel archive.

**adb / fastboot (`tooling/opt/platform-tools/`)** — the phone transport.
`fastboot flash boot_b shim/out/shim-boot.img`, `fastboot set_active b`,
`fastboot -S 512M flash userdata ios16-root.simg` (see
`docs/fajita-PORTING.md:153-161`), and `adb` from recovery for pulling `persist`,
`modemst1/2`, `fsg`, `fsc` and the boot log ring. On this board `fastboot boot`
is refused by the OOS ABL, so the flow is always "flash slot B, set active".

**dtc 1.7.2 (`tooling/opt/dtc/bin/dtc`)** — compiles the board's `.dts` into the
DTB that the shim passes upstream, and decompiles stock DTBs for diffing
(`-I dtb -O dts`). The shim needs the *stock* avicii DTB.

**mkfs.hfsplus / fsck.hfsplus (`hfsprogs`)** — builds and repairs the HFS+
volume that becomes the iOS root inside `userdata`.

**qemu-system-aarch64 (`qemu-system-arm`)** — boots the kernel under `virt` to
catch configuration errors before hardware. It cannot reach userland (no UFS, no
debug UART); a stop mid-boot is expected, not a failure.

**img2simg / simg2img (`android-sdk-libsparse-utils`)** — converts the raw root
image to sparse for `fastboot -S 512M` streaming, and back for inspection.

**cryptsetup** — opens the encrypted dmg layer of the IPSW. **libfuse3-dev /
fuse3** — build and run `apfs-fuse` for the unencrypted APFS dmg.

## Pinned versions and why

| Component | Pin | Why this and not newer |
| --- | --- | --- |
| LLVM/clang | **18.1.8** (`clang+llvm-18.1.8-x86_64-linux-gnu-ubuntu-18.04.tar.xz`) | XNU 8796 is 2022 code that upstream built with Xcode 14-era clang; 18.x is the closest still-supported LLVM that also ships a mature `ld64.lld`. LLVM 19+ tightens diagnostics that XNU's `-Werror` surfaces, and 20+ tarballs double in size (2.0 GB vs 1.04 GB) for no bring-up benefit. |
| platform-tools | **r37.0.3** | Current Google release; the only version whose SHA-1 is published in `repository2-3.xml`, so the download is verifiable rather than trusted. |
| dtc | **1.7.2** | Latest upstream; 1.7.x is what the board's vendor DTS syntax needs. |
| flex / bison | **2.6.4 / 3.8.2** | dtc ships only `.l`/`.y`, and neither tool is installed here, so both are built into `tooling/opt/bootstrap` first. Bootstrap-only — not on `PATH` after `env.sh`. |

The LLVM tarball is the 18.1.8 asset built on Ubuntu 18.04 and it links
`libtinfo.so.5`, which noble dropped. A plain symlink to `libtinfo.so.6` is *not*
enough (`version 'NCURSES_TINFO_5.0.19991023' not found`), so the script
extracts the jammy `libtinfo5` package into `opt/llvm/lib` and lets the binary's
own rpath find it. No root, no `LD_PRELOAD`.

### Verification actually run on this host

```
$ ./tooling/10-user-toolchain.sh all
    OK   clang: clang version 18.1.8
    OK   ld64.lld: LLD 18.1.8
    OK   llvm-objcopy: llvm-objcopy, compatible with GNU objcopy
    OK   adb: Android Debug Bridge version 1.0.41
    OK   fastboot: fastboot version 37.0.3-16887417
    OK   dtc: Version: DTC 1.7.2-gf6126c5e
    OK   Device Tree Blob version 17, size=116, boot CPU=0          # dtc round-trip
    OK   Mach-O 64-bit arm64 object                                 # clang -target arm64-apple-ios16.0
```

End-to-end link through `env.sh` (unset `LD_LIBRARY_PATH`, rpath only):

```
$ . tooling/env.sh && clang -target arm64-apple-ios16.0 -c a.c -o a.o \
    && ld64.lld -arch arm64 -platform_version ios 16.0 16.0 -e __start -o t.macho a.o b.o
t.macho: Mach-O 64-bit arm64 executable, flags:<NOUNDEFS|DYLDLINK|TWOLEVEL|PIE>
$ llvm-objcopy -O binary t.macho t.bin    # 49312 bytes, links and flattens
```

Total download 1.06 GB (LLVM 1.04 GB + platform-tools 9.5 MB + dtc/flex/bison/
libtinfo5 ≈ 5 MB), well inside the 3 GB budget. On-disk footprint 8.2 GB.

Uses of `tooling/env.sh`: `PATH` (clang/lld/objcopy/strip/ar/nm, dtc, adb,
fastboot), `CC`, `CXX`, `LD=ld64.lld`, plus `LD_LIBRARY_PATH` for the LLVM lib
dir. Nothing else is exported.

## Gaps this layer does not close

- **`apfs-fuse` has no noble package** (`apt-cache policy apfs-fuse` → nothing).
  It is needed only to read the IPSW's unencrypted APFS dmg; build it from
  source with `cmake -DCMAKE_POLICY_VERSION_MINIMUM=3.5` (CMake ≥ 4 rejects its
  `cmake_minimum_required(VERSION 3.0)`), after `00-host-deps.sh` has installed
  `libfuse3-dev`, `libbz2-dev`, `zlib1g-dev`, `libattr1-dev`.
- **No local XNU build path is proven yet.** `clang`/`ld64.lld` here can drive
  XNU's makefiles, but the kernel is currently produced on GitHub's macOS
  runners (below), which is the only configuration known to produce a booting
  kernel. Treat a local Linux XNU link as experimental until it boots.
- **`gh` is not installed** and is required by the Actions path; it is in
  `00-host-deps.sh`'s sibling list via apt (`gh`), or install the official
  binary. `dtc`'s YAML backend is off (`NO_YAML`) because `libyaml-dev` is a root
  package; `00-host-deps.sh` adds it, after which a rebuild picks it up.

## The two upstream build repositories

### `blacktop/darwin-xnu-build` — how XNU is built, and why not on this box

Read: `README.md`, `build.sh` (main branch, fetched 2026-11-11).

What it actually is: a **macOS-only** wrapper around
`apple-oss-distributions/xnu`. `build.sh` hard-requires Xcode and macOS:

- `setup_xcode_toolchain()` resolves `DEVELOPER_DIR` via `xcode-select -p` and
  aborts with "Xcode Command Line Tools not found" otherwise;
- it rebuilds `PATH` to put
  `$(DEVELOPER_DIR)/Toolchains/XcodeDefault.xctoolchain/usr/bin` ahead of
  Homebrew, warning if Homebrew's LLVM or GNU coreutils are in the way;
- it verifies the clang in use is Xcode's, not Homebrew's;
- `install_deps` requires **homebrew**, plus `jq`, `gum`, `xcodes`, `ipsw`,
  `cmake`, `ninja` and the CodeQL CLI;
- it installs SDK headers into a fakeroot (`FAKEROOT_DIR`) and builds with
  `ARCH_CONFIG=ARM64 MACHINE_CONFIG=…` (default `VMAPPLE`).

So it cannot run on Linux as-is: it needs Apple's SDK, `xcodebuild`-era
toolchain and Homebrew. That is precisely why `dipa-studio/ios-sweet` invokes it
from `xnu.yml` on a **macOS 13.5 GitHub runner** (`docs/anonbeat1-NOTES.md:1088`).
`MACHINE_CONFIG` is what gets changed for a non-Apple board; for avicii the
in-tree avicii patches supply the platform layer and the config name must match
whatever the port's `config/` describes.

Consequences for this host layer: local clang is used for the shim, payloads and
DTB — **not** for a canonical kernel build. The kernel comes from the Actions
artifact. `00-host-deps.sh` therefore installs `jq`, `cmake`, `ninja`-adjacent
tooling and `gh` for driving that workflow, not for emulating Xcode.

### `2010475745xie/ios16-xnu-bringup` — the host-side recipe

Read: `README.md`, `docs/01-environment.md`, `docs/03-kernel.md`,
`docs/04-qemu.md`, `scripts/setup-wsl.sh` (main, fetched 2026-11-11; copies kept
in `refs/upstream/`).

Scope: host side only, no Apple binaries in the repo, target userland iPhone X
16.7.16, XNU baseline `xnu-8796` from `dipa-studio/ios-sweet`. Written for
Windows 11 + WSL2, Ubuntu 26.04, 32 GB RAM, QEMU 10.2.1 `virt`/cortex-a76. It
states plainly that the kernel is built by forking `ios-sweet`, enabling the
`xnu` workflow and running `gh workflow run xnu.yml -R <you>/ios-sweet` —
~8 minutes on macOS minutes, artifact `xnu-kernel`, then `unzip` into
`xnu/out/` and `sha256sum -c`.

What it tells us that matters here, and where it differs from this box:

- Its `setup-wsl.sh` installs `hfsprogs`, `rsync`,
  `android-sdk-libsparse-utils`, `device-tree-compiler`, `dwarves`, `llvm`,
  `apfs-fuse` (source build when apt lacks it — the same gap noted above) and
  `mkbootimg`, and builds a **custom WSL kernel** with `CONFIG_HFSPLUS_FS=y`
  because 26.04 dropped `hfsplus` from `linux-modules-extra`. On Mint 22.3
  (6.8.0-149) `hfsplus.ko.zst` ships in `linux-modules-extra`, so
  `00-host-deps.sh` only loads the module instead of rebuilding a kernel.
  Verified: `modinfo hfsplus` → `/lib/modules/6.8.0-149-generic/kernel/fs/hfsplus/hfsplus.ko.zst`.
- Its patch discipline matters regardless of host: the build script **silently
  skips patches that fail to apply**, so a "successful" build can be missing
  one; it ships `tools/check-hunk-counts.py` to guard hunk counts. Run that
  against `xnu/patches/` after any patch edit.
- QEMU is `qemu-system-aarch64` from `qemu-system-arm` (confirmed: the package's
  file list provides it) plus `llvm` only for `--kernel` font extraction. Its
  `--qemu` ADT moves the GIC base, `CNTFRQ`, timer INTID and CPU count and drops
  the UFS node — the `--highmem` ADT must not be reused for a QEMU run.
- Disk: 6 GB IPSW, 14 GB extracted dmgs, 38 GB peak. This host has 347 GB free.

Not portable from that repo, and not attempted: the WSL2 kernel rebuild, the
`%USERPROFILE%\.wslconfig` swap, and the Windows USB passthrough advice —
`docs/fajita-PORTING.md:158` already records that fastboot must run on the host
directly, which on Linux means native `fastboot`, not WSL.

## Root script state

`tooling/00-host-deps.sh` has not been run (no passwordless sudo here). Its
state, from `--check` on this host: **32 packages already installed, 27 to
install**, every name resolved against noble by `apt-cache policy` immediately
before the run and re-checked by the script itself before it touches apt. It
installs no service, only packages, one udev rule file
(`/etc/udev/rules.d/51-android-ios-nord.rules`), the `plugdev` group membership
and `/etc/modules-load.d/hfsplus.conf`.

Run it, then re-source `env.sh` in a new shell (group membership needs a fresh
login):

```
sudo /home/tadej/ios-nord/tooling/00-host-deps.sh
```
