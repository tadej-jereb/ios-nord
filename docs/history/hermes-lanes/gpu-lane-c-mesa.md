# GPU lane C — building Mesa (freedreno, Adreno 620) for iOS 16 / Darwin arm64 on this Linux host

Read `gpu-shared.md` first.

**Question:** what does it take to cross-build Mesa's freedreno Gallium driver (and an OpenGL ES
front end) as arm64 Mach-O dylibs that load in iOS 16.7.16, from this Ubuntu host, with no Mac?
Produce a working recipe as far as it goes, and say exactly where it stops.

## Inputs

* Mesa upstream: start from **25.0.7** (the version the HackiOS patches target; check
  `refs/gsjsjzhznsz-hackios-xnu-userland/` if lane B has cloned it — read only, do not wait for it)
  and note whether 24.2.8+ `GPUId(620)` is present in that version.
* Toolchain already on the host: `tooling/opt/llvm` (check what it contains: clang, ld64.lld,
  llvm-ar, llvm-install-name-tool), `tooling/opt/bootstrap`, `src/procursus` (Procursus bootstrap,
  may contain an iOS SDK-like sysroot or `.deb`s with headers/libs).
* An iOS SDK: if none is on the machine, say so — do not download Xcode or an Apple SDK. Find
  out what the minimum is (which headers and `.tbd` stubs) and whether Procursus or the
  extracted dyld cache (stubs generated from it) can supply it. Record exactly which files
  would be needed.
* `refs/marnov999-raphael-ios-gpu/tools/build-redwood-gl.sh` and `tools/xnu-cc.py` — how raphael
  built its userland; reuse their approach where it fits.

## What to determine

1. **Toolchain.** clang target triple (`arm64-apple-ios16.0`), linker (`ld64.lld`) flags,
   sysroot, deployment target, code signing (ad-hoc `ldid` / `codesign` replacement available on
   Linux; how the existing root signs binaries — see `docs/` and `tooling/`).
2. **Meson cross file.** A working `cross-ios-arm64.ini` and the meson options for a minimal build:
   `-Dgallium-drivers=freedreno -Dvulkan-drivers=[] -Dplatforms=[] -Dglx=disabled
   -Degl=…`, `-Dgles2=enabled`, `-Dshared-glapi`, `-Dllvm=disabled`, freedreno-specific options.
   Which Mesa dependencies (expat, zlib, libdrm-or-replacement, python mako/pyyaml on the host)
   are needed and how each is satisfied.
3. **Darwin portability.** Where upstream Mesa assumes Linux for the freedreno path (`libdrm`,
   `drm.h`, `dma-buf`, `eventfd`, `memfd`, `futex`, `sync_file`, `/dev/dri`), and how the HackiOS
   "freedreno-darwin" patch handles each (if lane B's clone exists; otherwise list them for later).
4. **Try it.** Run the configure and as much of the build as the toolchain allows, inside
   `~/.hermes/cache/scratch/lane-c-mesa/` (never in the repo). Record the first hard error and
   its cause. A partial build that stops at a clear, explained wall is a good result.
5. **Output shape.** What the final artifacts would be (`libGLESv2`, `libEGL`/EAGL shim,
   `libgallium` / `freedreno_dri`), their install paths in the iOS root, and how big they are if
   you got that far.

## Owns

* `docs/gpu-research/C-mesa-darwin-build.md` (new). One file, sections 1–5.
* `tooling/gpu/cross-ios-arm64.ini` and `tooling/gpu/build-mesa.sh` (new) — only if you got a
  configure to pass; the script must be idempotent, build outside the repo, and take the Mesa
  source dir and output dir as arguments.
* Everything under `~/.hermes/cache/scratch/lane-c-mesa/`.

## Report

The file above, with a top summary: the exact command that configures Mesa for iOS arm64 (or
the reason none can yet), how far the build gets, and the list of missing pieces in order.
