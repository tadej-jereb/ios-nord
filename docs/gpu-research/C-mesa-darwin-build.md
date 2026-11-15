# Lane C — cross-building Mesa 25.0.7 freedreno + GLES for iOS 16 arm64 on this Linux host

Scope: `.hermes-lanes/gpu-lane-c-mesa.md` — can this Ubuntu host, with no Mac, no Xcode and no
Apple SDK, produce arm64 Mach-O dylibs of Mesa's freedreno Gallium driver plus an OpenGL ES front
end that load in iOS 16.7.16 on the OnePlus Nord (Adreno 620, `0x06020000`)? What is the recipe, and
where exactly does it stop?

Everything below was run on this host. Mesa was cloned and configured, the toolchain was driven to
a verified arm64 iOS dylib, and configure was then stopped by the missing SDK. Raw logs live in
`~/.hermes/cache/scratch/lane-c-mesa/` (named per step); nothing was built inside the repo, the
phone and `xnu-avicii/` were not touched, and no Apple binary was disassembled for this report.
Claims that are reasoning rather than measurement are marked **inferred**.

---

## Summary

**The configure command that would build this, as far as it can be run today** (host toolchain
`tooling/opt/llvm`, Mesa in scratch, no SDK — see §2 for the cross file):

```bash
PATH=$W/venv/bin:/home/tadej/ios-nord/tooling/opt/llvm/bin:$PATH \
meson setup build-ios $W/src/mesa-25.0.7 \
  --cross-file cross-ios-arm64.ini --wrap-mode=nofallback \
  --prefix=/redwood --libdir=lib --buildtype=release -Db_ndebug=true \
  -Dplatforms= -Dgallium-drivers=softpipe,freedreno -Dfreedreno-kmds=msm \
  -Dvulkan-drivers= -Dglx=disabled -Degl=disabled -Dgbm=disabled \
  -Dosmesa=true -Dgles2=enabled -Dshared-glapi=enabled -Dopengl=true -Dllvm=disabled \
  -Dzstd=disabled -Dxmlconfig=disabled -Dexpat=disabled -Dshader-cache=disabled \
  -Dvalgrind=disabled -Dlibunwind=disabled -Dglvnd=disabled -Dvideo-codecs= -Dtools= \
  -Dgallium-vdpau=disabled -Dgallium-va=disabled -Dgallium-xa=disabled -Dlmsensors=disabled \
  -Dbuild-tests=false
```

meson 1.12.1 accepts that option set (it got 1000 lines into `meson.build`), and it is the option set
the two public ports use (`refs/gsjsjzhznsz-hackios-xnu-userland/tools/mk-mesa.sh:126-132`,
`refs/ry-diffusion-Bergamota/gpu/eagl/mesa/build-mesa.sh`, its `meson setup` block). **No command that is missing an
argument can fix the rest**: it stops at a compile probe, because there is no libc on this host for
the `arm64-apple-ios16.0` target.

**How far the build got.** Configure only. It dies at `meson.build:971`, `ERROR: Could not get
define 'ETIME'`, whose cause is `fatal error: 'errno.h' file not found`. Independently of meson, the
first Mesa translation unit compiled by hand stops one header later, at `assert.h`
(`src/util/bitscan.h:32`). Nothing is compiled into a dylib; the only Mach-O this lane produced is a
toolchain proof (§1.6), not Mesa.

**Missing pieces, in order — each one blocks the next:**

1. **An iOS 16 SDK sysroot.** No `iPhoneOS*.sdk` exists anywhere on this machine (`find / -maxdepth 4
   -name 'iPhoneOS*.sdk'` → nothing; the two public ports get it from Theos or Xcode). It must
   supply: the ~30 C headers listed in §2.4, `libSystem.tbd` (whose `dyld_stub_binder` matters,
   §1.6), `libz.tbd` + `zlib.h`, `libc++.tbd` + `usr/include/c++/v1` (18 `.cc` files in
   `drivers/freedreno/a6xx` alone), and `crt1.o` for meson's link checks.
2. **A libdrm stand-in**, because freedreno's drm layer includes `<xf86drm.h>`
   (`src/freedreno/drm/freedreno_priv.h:21`) and upstream sets `dep_libdrm = null_dep` on darwin
   (`meson.build:1717`). Two working designs exist in `refs/` (§3); either needs the matching meson
   edit.
3. **The 12-file `freedreno-darwin` patch** (§3, table) — otherwise freedreno's `drm/` subdir is not
   even entered, and `mmap`/`lseek`/`sysinfo`/build-id paths are Linux-only.
4. **zlib headers on the target side** — mandatory: `src/freedreno/common/freedreno_rd_output.h:11`
   includes `<zlib.h>` unguarded, so `-Dzlib=disabled` is not an option.
5. **`LDID`-less signing is already solved** (§1.5): `ld64.lld -adhoc_codesign` writes the same
   CodeDirectory (0x20400, sha256, `CS_ADHOC|CS_LINKER_SIGNED`) the project's kernel now accepts.

Given 1–4, the remaining work is a build, not research: the reference build of exactly this
configuration produces **one** artifact, `libOSMesa.8.dylib`, 14 855 048 bytes before stripping
(§5).

---

## 1. Toolchain

### 1.1 What actually exists here

| Piece | Path | Version (measured) |
|---|---|---|
| clang / clang++ | `tooling/opt/llvm/bin/clang` | `clang version 18.1.8`, host `x86_64-unknown-linux-gnu`, cross-capable (all Darwin targets) |
| ld64 | `tooling/opt/llvm/bin/ld64.lld` | `LLD 18.1.8` |
| binutils-alikes | `tooling/opt/llvm/bin/llvm-ar`, `llvm-ranlib`, `llvm-strip`, `llvm-nm`, `llvm-otool`, `llvm-objdump`, `llvm-install-name-tool`, `llvm-readtapi`, `llvm-ifs` | 18.1.8 |
| bison / flex | `tooling/opt/bootstrap/bin/{bison,flex}` | present (needed by Mesa's GLSL front end) |
| pkg-config | `/usr/bin/pkg-config` | 1.8.1 |
| meson / ninja | not installed on the host → venv in scratch | meson **1.12.1** (Mesa requires ≥ 1.1), ninja `/usr/bin/ninja` |
| host python for meson | `~/.hermes/cache/scratch/lane-c-mesa/venv/bin/python3` | 3.12.3 + Mako 1.4.3, PyYAML 6.0.3, packaging 26.3 |
| `ldid` | **absent** — `which ldid` empty, `find / -maxdepth 6 -name ldid` empty | — |
| iOS SDK | **absent** | — |

`src/procursus/` is the Procursus `bootstrap-ssh-iphoneos-arm64` tarball; its `tree.txt` (4049
entries) has headers for **bash only** (`usr/include/bash/*`) and no `libSystem`, no `libz`
(only `libz-ng.2.dylib`), no SDK. It cannot serve as a sysroot.

`meson` had to be installed (network works; the Mesa clone and `pip install` both succeeded). The
host's own `python3` (3.12.3) has mako/pyyaml; the venv is used only to keep this lane's installs off
the system, and `meson setup` prints `Program python3 found: YES 3.12.3 (…/venv/bin/python3)`.

One non-obvious host-python requirement, found by hitting it: Mesa's mako check
(`meson.build:943-955`) imports `packaging.version` and falls back to `distutils` — which Python 3.12
removed. With `packaging` missing the check fails and meson reports
`ERROR: Problem encountered: Python (3.x) mako module >= 0.8.0 required to build mesa`, even though
Mako is installed. `pip install packaging` is part of the recipe (the Bergamota script installs it
too).

### 1.2 Target triple and deployment target

`-target arm64-apple-ios16.0` — verified in the `-cc1` line clang emits:

```
-triple arm64-apple-ios16.0.0 … -target-cpu apple-a7 -target-feature +v8a -target-abi darwinpcs
```

and in the resulting Mach-O: `LC_BUILD_VERSION platform 2 (PLATFORM_IOS) minos 16.0 sdk 16.0`.

Two consequences worth writing down:

* The deployment target is the last number of the triple (`ios16.0`), not a separate
  `-miphoneos-version-min` flag. The reference scripts use `-miphoneos-version-min=18.0` because on a
  Mac the SDK default is what it is; on this host the triple alone is sufficient and does the same
  job — clang turns it into `-platform_version ios 16.0 16.0` for the linker (seen in the
  `ld64.lld` command line below).
* clang's default CPU for this triple is `apple-a7` (ARMv8.0-A). That is a compatibility floor, not
  a limit; the Adreno path has no instruction-set requirement above v8.0. Nothing here needs
  `-march=armv8.2-a` for the Kryo 475.

### 1.3 Linker: this is the first thing that breaks, and it is fixable

Meson's first run without `-fuse-ld=lld` in the compiler argv fails at `project()`:

```
ERROR: Unable to detect linker for compiler `…/clang -target arm64-apple-ios16.0 -Wl,--version`
stderr: /usr/bin/ld: unrecognised emulation mode: llvm
        Supported emulations: elf_x86_64 …
```

The Linux clang driver hands a darwin target's link to the host `ld` unless told otherwise. Putting
`-fuse-ld=lld` in the `[binaries]` compiler argv fixes it and meson then reports the real linker:

```
C linker for the host machine: …/clang -target arm64-apple-ios16.0 -fuse-ld=lld (…) ld64.lld 18.1.8
```

A second, subtler trap: with `-fuse-ld=lld` in the argv, every **compile-only** probe fails, because
meson's probe flags end with `-Werror=unused-command-line-argument` and clang warns that
`-fuse-ld=lld` is unused while compiling. Meson then reports `Checking for size of "void*" : -1`, and
every `cc.compiles()`-based feature test in Mesa silently answers "no". The measured error:

```
clang: error: argument unused during compilation: '-fuse-ld=lld' [-Werror,-Wunused-command-line-argument]
```

`-Wno-unused-command-line-argument` does **not** fix it (later `-Werror=` wins);
`-Qunused-arguments` does. Both live in the cross file (§2.1). With it, `sizeof(void*)` = 8.

Also verified: `[built-in options] c_link_args` must not be used to pass multi-word Darwin link
flags — meson word-splits them and `-Wl,-platform_version ios 16.0 16.0` becomes three stray file
arguments (`clang: error: no such file or directory: 'ios'`), which breaks even linker detection. The
triple already covers it.

clang's exact link line for the target (from `-###`), which is what meson will use:

```
ld64.lld -demangle -dynamic -dylib -arch arm64 -platform_version ios 16.0.0 16.0.0 \
  -syslibroot <sysroot> -mllvm -enable-linkonceodr-outlining -o out.dylib obj.o -lSystem
```

### 1.4 Sysroot: the wall

There is no sysroot. With `-isysroot` pointed at an empty directory, clang's own header search is
clang's resource dir only, so every libc include is fatal:

```
$ clang -target arm64-apple-ios16.0 -isysroot $W/empty-sdk -c t.c     # t.c: #include <stdio.h>
t.c:1:10: fatal error: 'stdio.h' file not found
```

Worse, *without* `-isysroot` clang falls back to the **host's** `/usr/include` and finds glibc:

```
$ clang -target arm64-apple-ios16.0 -c t.c
/usr/include/stdio.h:28:10: fatal error: 'bits/libc-header-start.h' file not found
```

That failure mode is dangerous rather than merely fatal: a build that reaches far enough could pick
up glibc headers and x86_64 `-lz` (§2.5) without complaining at configure time. The cross file
therefore pins `-isysroot` explicitly.

### 1.5 Code signing: no `ldid` here, and none needed

How the root is signed today: it is not. `tooling/33b-populate-root-unprivileged.sh` and the rest of
`tooling/` never invoke a signer — the root is populated with Apple's own signed binaries out of the
IPSW, and `tooling/34-check-bootstrap.sh:174-278` merely *parses* the CodeDirectory to assert
`CMS signature, expected ad-hoc` and the CD fields. When the project needed to re-sign something it
built the blob in Python: the ad-hoc SuperBlob minter is `tools/mkinit.py` in the sibling trees
(`refs/marnov999-raphael-ios-gpu/tools/mkinit.py:69` — "SuperBlob holding one ad-hoc CodeDirectory
(version 0x20400)"), and the dyld-cache re-signing pass described in `docs/STATUS.md` used the same
shape (CD `0x64` → `0x20400`, which is what stock XNU's `cs_blob_create_validated` accepts).

For Mesa artifacts neither is needed, because **ld64.lld signs**. Measured, on the probe dylib of
§1.6:

* without `-adhoc_codesign` there is **no** `LC_CODE_SIGNATURE` at all, even for arm64 — the help
  text's "default for arm64 binaries" does not apply to `-dylib` output here;
* with `-Wl,-adhoc_codesign`: `LC_CODE_SIGNATURE dataoff 49424 datasize 544`, and the blob parses as
  `SuperBlob 0xfade0cc0, 1 slot` → `CodeDirectory magic 0xfade0c02 version 0x20400 flags 0x20002`
  (`CS_ADHOC|CS_LINKER_SIGNED`), `hashType 2` (sha256), `hashSize 32`, `pageSize 12` (4096),
  `nCodeSlots 13`, `identifier libprobe2.dylib`, `codeLimit 49424`.

So the artifact recipe is `ld64.lld` + `-Wl,-adhoc_codesign`; the resulting CD version is exactly the
`0x20400` the kernel in this tree already accepts for re-signed caches. Entitlements are **not**
covered by this: the blob has `nSpecialSlots 0`. A dylib to be injected into `backboardd` or
`SpringBoard` needs no entitlements of its own (**inferred** from the reference's `libredwood-gl.dylib`
being ad-hoc signed alone, `build-redwood-gl.sh:23` `ldid -Hsha256 -Cadhoc -S`), but a *process*
launched by launchd does (`docs/AMFI_LAUNCHD.md`).

### 1.6 Toolchain proof: a real arm64 iOS dylib, linked on this host

Because Mesa cannot compile, the linker half was verified on its own, in
`~/.hermes/cache/scratch/lane-c-mesa/probe/`:

1. A 20-line hand-written `libSystem.tbd` (TAPI v4, `targets: [arm64-ios]`, install-name
   `/usr/lib/libSystem.B.dylib`, exporting `_malloc,_free,_printf,_memcpy,_strlen,_memset,_abort,_exit,_dyld_stub_binder`)
   in `linksdk/usr/lib/`.
2. `clang -target arm64-apple-ios16.0 -isysroot linksdk -fuse-ld=lld -Qunused-arguments
   -Wl,-fixup_chains -Wl,-adhoc_codesign -dynamiclib -install_name /usr/local/lib/libprobe2.dylib …`
   → 49 968-byte Mach-O, `LC_ID_DYLIB /usr/local/lib/libprobe2.dylib`,
   `LC_BUILD_VERSION platform 2 minos 16.0 sdk 16.0`,
   `LC_LOAD_DYLIB /usr/lib/libSystem.B.dylib 1311.100.3`, `LC_DYLD_CHAINED_FIXUPS`, plus the
   signature above.

Two findings from doing it, both of which will bite whoever assembles a stub SDK:

* the file must be named **`libSystem.tbd`** — clang passes `-lSystem`, so an Apple-style
  `libSystem.B.tbd` alone gives `ld64.lld: error: library not found for -lSystem`;
* with a stub that only *exports* `dyld_stub_binder`, lazy binding still fails
  (`ld64.lld: error: undefined symbol: dyld_stub_binder >>> referenced by lazy binding`, and then
  `did you mean: dyld_stub_binder` from itself). Real libSystem re-exports `libdyld`, which is where
  that symbol lives; with a one-file stub the fix is `-Wl,-fixup_chains` (chained fixups, no lazy
  binding stubs). The real SDK needs neither workaround.

---

## 2. Meson cross file, options, and each dependency

### 2.1 The cross file (as used — contains no SDK yet)

`~/.hermes/cache/scratch/lane-c-mesa/cross-emptysdk.ini`, byte for byte:

```ini
[binaries]
c = ['/home/tadej/ios-nord/tooling/opt/llvm/bin/clang', '-target', 'arm64-apple-ios16.0', '-fuse-ld=lld', '-isysroot', '/home/tadej/.hermes/cache/scratch/lane-c-mesa/empty-sdk']
cpp = ['/home/tadej/ios-nord/tooling/opt/llvm/bin/clang++', '-target', 'arm64-apple-ios16.0', '-fuse-ld=lld', '-nostdinc++', '-isysroot', '/home/tadej/.hermes/cache/scratch/lane-c-mesa/empty-sdk']
objc = ['/home/tadej/ios-nord/tooling/opt/llvm/bin/clang', '-target', 'arm64-apple-ios16.0', '-fuse-ld=lld', '-isysroot', '/home/tadej/.hermes/cache/scratch/lane-c-mesa/empty-sdk']
ar = '/home/tadej/ios-nord/tooling/opt/llvm/bin/llvm-ar'
ranlib = '/home/tadej/ios-nord/tooling/opt/llvm/bin/llvm-ranlib'
strip = '/home/tadej/ios-nord/tooling/opt/llvm/bin/llvm-strip'

[built-in options]
c_args = ['-Qunused-arguments']
cpp_args = ['-Qunused-arguments']
objc_args = ['-Qunused-arguments']

[host_machine]
system = 'darwin'
subsystem = 'ios'
cpu_family = 'aarch64'
cpu = 'arm64'
endian = 'little'

[properties]
needs_exe_wrapper = true
```

Notes, all of them earned by a failure:

* `objc` is **required**, not optional: `meson.build:20-23` does `add_languages('objc')` when
  `host_machine.system() == 'darwin'` and adds `-fobjc-arc`; without the key meson stops before
  anything else.
* `subsystem = 'ios'` is accepted by meson and is what the two public cross files use
  (`build-mesa.sh`, its `[host_machine]` block); Mesa itself only tests `system == 'darwin'`.
* `ar`/`ranlib`/`strip` must be the LLVM ones — the GNU ones cannot mix Mach-O.
* `needs_exe_wrapper = true`: nothing can run the output. Meson still *links* test executables, so a
  `crt1.o` is required even for a dylib-only build (§4.3).
* Once an SDK exists, the only edits are the two `-isysroot` paths, plus
  `-fuse-cxa-atexit` and `-isystem $SDK/usr/include/c++/v1` in `cpp_args` (the reference needs both,
  `mk-mesa.sh:107`), plus `bison = '/home/tadej/ios-nord/tooling/opt/bootstrap/bin/bison'`.

The file is **not** committed as `tooling/gpu/cross-ios-arm64.ini`: the lane file allows that only
if a configure passes, and none does. It is kept verbatim in scratch and above.

### 2.2 Options and why each one

| Option | Why |
|---|---|
| `-Dplatforms=` | no X11/Wayland/surfaceless winsys on darwin; OSMesa renders into buffers with `null_sw_winsys` and pushes them to IOSurfaces (§3) |
| `-Dgallium-drivers=softpipe,freedreno` | both public ports keep softpipe as the always-works fallback; the B-class shim picks the GPU screen when it exists and falls back otherwise |
| `-Dfreedreno-kmds=msm` | `msm` is the kernel path; `virtio` is only for the virtio-gpu harness (and its `libvdrm` link is broken on darwin unless patched, §3) |
| `-Dvulkan-drivers=` | turnip is `freedreno` too but drags in wsi/libdrm; out of scope |
| `-Dglx=disabled -Degl=disabled -Dgbm=disabled` | see 2.6: EGL cannot be enabled on this target at all |
| `-Dosmesa=true` | the front end that survives: `libOSMesa.8.dylib` carries GLES **and** GL entry points |
| `-Dgles2=enabled -Dshared-glapi=enabled -Dopengl=true` | ES2 contexts through OSMesa (EGL is disabled, so `shared-glapi` is what makes the `gl*` entry points resolvable) |
| `-Dllvm=disabled` | no LLVM at run time: ir3 is the only compiler in this configuration, and llvmpipe is not built |
| `-Dzstd=disabled`, `-Dexpat=disabled`, `-Dxmlconfig=disabled` | optional; `xmlconfig` is patched back in for the freedreno driconf only where needed (§3) |
| `-Dshader-cache=disabled` | the disk cache cannot work without a build id on darwin (§3); the HackiOS port disables it, Bergamota keeps it on with the `LC_UUID` fix |
| `-Dvalgrind/-Dlibunwind/-Dglvnd/-Dgallium-vdpau/-Dgallium-va/-Dgallium-xa/-Dlmsensors=disabled`, `-Dvideo-codecs=`, `-Dtools=`, `-Dbuild-tests=false` | remove every dependency that is not Mesa's own source |
| `--wrap-mode=nofallback` | a missing dep must be an error, not a silently downloaded subproject |

### 2.3 Mako / PyYAML / bison / flex

Host-native, and meson finds them: Mako generates `freedreno_devices.h` from
`src/freedreno/common/freedreno_devices.py` (which contains
`add_gpus([GPUId(620)], A6xxGPUInfo(CHIP.A6XX, [a6xx_base, a6xx_gen1], num_ccu=1,
tile_align_w=32, tile_align_h=16, …))` at `freedreno_devices.py:515-531` — so **yes, 25.0.7 has
`GPUId(620)`**, matching `avicii/CONSTANTS.md`), PyYAML feeds the same generator, bison/flex build
the GLSL compiler. All verified present; the A620 device record therefore needs no patching.

### 2.4 The headers an SDK has to supply

Measured by scanning every `#include <…>` in the files this configuration compiles
(`src/util`, `src/freedreno`, `src/gallium/auxiliary`, `drivers/freedreno`,
`winsys/freedreno/drm`, `frontends/osmesa`, `targets/osmesa`, `src/compiler`, `src/mapi`,
`src/mesa`; 275 distinct `<…>` names) and dropping what clang ships itself. The portable core, with
occurrence counts, is:

```
stdio.h 169  stdlib.h 108  string.h 107  assert.h 102  unistd.h 62  errno.h 47
fcntl.h 44   sys/stat.h 35  sys/types.h 35  math.h 34  ctype.h 21  sys/mman.h 19
getopt.h 15  xf86drm.h 15  signal.h 10  dlfcn.h 9  sys/ioctl.h 9  dirent.h 7
pthread.h 7  sys/sysctl.h 7  time.h 7  poll.h 5  sys/file.h 5  sys/wait.h 5
sched.h 4    locale.h 3    setjmp.h 3    sys/param.h 3  sys/resource.h 3
sys/socket.h 3  sys/time.h 3  libgen.h 2  machine/endian.h 2  zlib.h 2
```

plus `alloca.h`, `byteswap.h`, `endian.h`, `ftw.h`, `malloc.h`, `pwd.h`, `regex.h`, `termios.h`,
`syslog.h`, `mach/mach_host.h`, `mach/vm_statistics.h`, `mach-o/dyld.h`. `xf86drm.h` is the one not
in any SDK — it comes from the libdrm stand-in (2.5). `windows.h`, `X11/*`, `android/*`,
`llvm/*`, `spirv-tools/*` also appear but only behind code paths these options disable.

The Linux-only ones are the portability list of §3: `sys/eventfd.h`, `sys/futex.h`, `sys/inotify.h`,
`sys/sysinfo.h`, `sys/syscall.h` (for `gettid`), `linux/futex.h`, `linux/memfd.h`,
`linux/sync_file.h`, `linux/dma-heap.h`, `byteswap.h`, `endian.h`, `cpu-features.h`, `libsync.h`.

### 2.5 Dependencies, one by one

| Dependency | State on this host | How it is satisfied |
|---|---|---|
| **libc / libSystem** | absent | SDK `usr/include` + `libSystem.tbd`. Minimum for a dylib: the symbol list; today's alternative is a TAPI stub generated from the extracted dyld cache's `libSystem.B.dylib` — `llvm-ifs` and `llvm-readtapi` are both present in `tooling/opt/llvm/bin`, so a `.tbd` can be synthesised without a Mac (**inferred**: not attempted, because the headers are still missing and the stub would be useless alone) |
| **libdrm** | absent, and `dep_libdrm = null_dep` on darwin | stand-in: `redwood-drm` (HackiOS) or `freedreno-sweet` (Bergamota) behind a `libdrm.pc`. See §3 |
| **zlib** | host x86_64 only (`pkg-config --libs zlib` → `-lz`, from `/usr/lib/x86_64-linux-gnu/pkgconfig`) | must be cross-built or taken from the iOS root; required headers-wise (`freedreno_rd_output.h:11`) and by `src/util/{compress,crc32}.c`. The reference needs an isolated `PKG_CONFIG_LIBDIR` holding only `zlib.pc`, because meson's `ZlibSystemDependency` probe breaks in a cross build — the reference's measured symptom is
`Could not get define 'ZLIB_VERSION'` (`mk-mesa.sh:84-103`). Left at host default in this run, this is the second silent-contamination hazard after `/usr/include` |
| **expat / icu / libudev / sensors / valgrind / libunwind / x11 / xcb / wayland** | disabled | options above |
| **C++ standard library** | absent | needed: `drivers/freedreno/a6xx` has 18 `.cc` files (fd6_draw.cc, fd6_blitter.cc, …). SDK `usr/include/c++/v1` + `libc++.tbd` |
| **bison, flex, mako, pyyaml, python3** | present | §1.1, §2.3 |
| **libarchive** | absent; not needed | only turnip's `/dev/dri` scan uses it; the reference has to disable its fallback path on darwin (`freedreno/meson.build` hunk, §3) |

---

## 3. Darwin portability: the Linux assumptions in the freedreno path

Two public patches solve the same problems differently; both are in `refs/` and both are 25.0.7
-ready. Table columns are "what upstream assumes" / "what HackiOS does" / "what Bergamota does"; the
upstream `file:line` are from the clone in scratch.

| # | Linux assumption | Upstream location | HackiOS (`tools/mesa/freedreno-darwin.patch`, 12 files / 365 lines) | Bergamota (`bergamota-mesa-25.0.7.patch`) |
|---|---|---|---|---|
| 1 | `dep_libdrm` is `null_dep`, so no `-I` for `<xf86drm.h>` and no `-ldrm` | `meson.build:1717` | replaces it with `declare_dependency(include_directories: 'src/redwood-drm', link_args: -framework IOKit -framework CoreFoundation)` when `system=='darwin' and with_gallium_freedreno` | forces `system_has_kms_drm = true` (meson.build hunk) and supplies a real `libdrm.pc` pointing at the stand-in + the official libdrm headers |
| 2 | `subdir('drm')` only under `system_has_kms_drm` | `src/freedreno/meson.build:25` | `if system_has_kms_drm or host_machine.system() == 'darwin'` | covered by #1 |
| 3 | `link_with: [libvdrm]` unconditionally on the drm lib | `src/freedreno/drm/meson.build:75` | `freedreno_kmds.contains('virtio') ? [libvdrm] : []`, and appends `../../redwood-drm/redwood_drm.c` to the drm sources on darwin | n/a |
| 4 | BO size from `lseek(fd, 0, SEEK_END)` on the DRM fd | `freedreno_bo.c:248` (import path) | `redwood_drm_surface(dev->fd, &surface)` returns `size` (the "fd" is an IOSurface ID here) | `whandle->size` for KMS-style handles |
| 5 | `os_mmap(… MAP_SHARED, dev->fd, offset)` — mmap of `/dev/dri/card0` | `freedreno_bo.c:628` `fd_bo_map_os_mmap` | `redwood_drm_map(fd, handle, size)` — the kernel driver does the mapping | `sweet_drm_mmap` |
| 6 | `os_munmap` | `freedreno_bo.c:483` `fd_bo_fini_common` | `redwood_drm_unmap()` | `sweet_drm_munmap` |
| 7 | `CLOCK_MONOTONIC` for wait timeouts; on Darwin that is not the clock that runs while asleep | `drm/msm/msm_priv.h:176` | `CLOCK_MONOTONIC_RAW` under `__APPLE__` (matches `mach_continuous_time` the kernel uses) | n/a |
| 8 | `<sys/sysinfo.h>` + `sysinfo()` for `screen->ram_size` | `freedreno_screen.c:28,1009` | drop the include; `os_get_total_physical_memory()` (mesa util) clamped to `UINT32_MAX` | `sysctlbyname("hw.memsize")` |
| 9 | ELF build-id note identifies a driver build for the shader disk cache | `ir3_disk_cache.c:33-56` | `return` early on `__APPLE__` — no cache at all | uses the Mach-O `LC_UUID` via `dladdr` |
| 10 | `glEGLImageTargetTexture2DOES` needs an EGL image | `frontends/osmesa/osmesa.c` | supplies `get_egl_image`/`validate_egl_image` callbacks that treat the "image" as an **IOSurface ID** and call `resource_from_handle` | same idea in its own `osmesa.c`/`sweet_hw.c` (440 new lines) |
| 11 | OSMesa's target links only swrast | `targets/osmesa/meson.build:39` | adds `driver_freedreno, idep_xmlconfig, dep_libdrm` | adds the `sweet_hw.c` glue + deps |
| 12 | screen creation is `null_sw_winsys` only | `targets/osmesa/osmesa_target.c:30-40` | `osmesa_create_gpu_screen()`: `drmOpenWithType("msm", NULL, DRM_NODE_RENDER)` → `fd_drm_screen_create_renderonly()`, soft fallback if NULL | same, in `sweet_hw.c` |
| 13 | a first draw that reads the framebuffer needs a CCU/UCHE flush the hardware does not imply | `a6xx/fd6_draw.cc:445` (genotype-specific bug, A642L) | `FD6_FLUSH_CCU_COLOR \| FD6_INVALIDATE_CACHE` when `fs->fb_read` follows a non-read draw (`freedreno_batch.h` gains `prev_draw_read_fb`) | not in its patch |
| 14 | the stand-in itself must compile without libdrm: it needs `<unistd.h>`, `<IOKit/IOKitLib.h>` | — | `redwood_drm.c:13` includes `unistd.h` directly | `sweet_drm.c` likewise |

Not in either patch, and still Linux-only in the freedreno code this configuration compiles:
`sys/eventfd.h`, `sys/futex.h`, `linux/futex.h`, `linux/memfd.h`, `linux/sync_file.h` are all behind
`#ifdef HAVE_LIBDRM`/`__linux__` guards in the drm layer, so with `dep_libdrm` replaced by a stand-in
they are not reached (**inferred from grep, not from a build**). `msm/msm_ringbuffer_sp*` uses the
`sync_file`/submit ioctls through the stand-in, which is why the stand-in has to fake `drmIoctl`
rather than only `drmOpen`.

The stand-in itself is small and reusable:

* HackiOS: `tools/mesa/redwood-drm/redwood_drm.c` (6 179 B) + `xf86drm.h` (3 497 B) — a hand-written
  `xf86drm.h` so nothing else is needed, and an IOKit user-client call (`RedwoodGPU`) instead of an
  ioctl.
* Bergamota: `gpu/freedreno-sweet/{sweet_drm.c,build.sh}` — built as `libdrm.2.dylib` and exported
  through `libdrm.pc` (`Version: 2.4.124`, `Cflags: -I<official libdrm headers>/include/drm`), so
  upstream `#include <xf86drm.h>` and `<drm/msm_drm.h>` resolve unchanged.

**Which to copy for avicii.** Ours is not IOKit-shaped: the kernel side is a cdev
(`xnu-avicii/patches/`, `SweetFramebuffer.cpp`), so the HackiOS design (one `redwood_drm.c` calling
into a named service) needs the service-name and ioctl translation changed, while the Bergamota
design (a real `libdrm` ABI subset) matches whatever `drmIoctl` our cdev answers. Either way the meson
edit is #1 or #2 — and #2 (force `system_has_kms_drm`) is the smaller change and keeps `HAVE_LIBDRM`
defined, which is what `drm-uapi` code expects.

---

## 4. The attempt, for real

All commands were run from `~/.hermes/cache/scratch/lane-c-mesa/`; `$W` is that directory, `$M` is
`$W/src/mesa-25.0.7`. Logs: `meson-setup-nosdk.log`, `meson-setup-emptysdk.log`,
`meson-setup-probe1.log`, and `build-*/meson-logs/meson-log.txt` for each.

### 4.1 Source

```
git clone --depth 1 --branch mesa-25.0.7 https://gitlab.freedesktop.org/mesa/mesa mesa-25.0.7
```
→ 368 MB working tree, `git log --oneline -1` = `742a20f VERSION: bump for 25.0.7`, `VERSION` =
25.0.7, `GPUId(620)` present (`src/freedreno/common/freedreno_devices.py:515`). No subproject was
fetched (`--wrap-mode=nofallback`); no patch applied for the run below — upstream 25.0.7 as cloned.

### 4.2 How far it gets, and the first hard error

```
$ meson setup build-emptysdk $M --cross-file cross-emptysdk.ini --wrap-mode=nofallback \
    --prefix=/redwood --libdir=lib --buildtype=release -Db_ndebug=true <the options of §2.2>
```

Toolchain detection is clean (all four compilers + `ld64.lld 18.1.8` + `sizeof(void*)` 8), macOS-only
deps are skipped, then:

```
src/mesa-25.0.7/meson.build:971:6: ERROR: Could not get define 'ETIME'
```

**First hard error, and its cause** — from `build-emptysdk/meson-logs/meson-log.txt:389-402`:

```
Command line: `clang -target arm64-apple-ios16.0 -fuse-ld=lld -isysroot …/empty-sdk …/testfile.c
              -E -P -Qunused-arguments -P -O0 -U_FORTIFY_SOURCE -Werror=implicit-function-declaration -std=c11`
stderr:
…/testfile.c:2:18: fatal error: 'errno.h' file not found
    2 |         #include <errno.h>
```

Mesa asks the preprocessor for `ETIME` with `prefix: '#include <errno.h>'`
(`meson.build:971`) as its "does this libc have ETIME" test, and meson treats a failed *compile* as a
hard error rather than "define absent" — so the very first libc include in configure is fatal. The
cause is not Mesa and not the compiler: **there is no libc for this target on this host.**

The same wall from the C side, one file at a time (run by hand, empty sysroot, upstream include
dirs):

```
$ clang -target arm64-apple-ios16.0 -isysroot $W/empty-sdk -I$M/include -I$M/src \
        -c $M/src/util/ralloc.c
…/src/util/ralloc.c:24:10: fatal error: 'assert.h' file not found
$ clang … -c $M/src/freedreno/drm/freedreno_pipe.c
…/src/util/bitscan.h:32:10: fatal error: 'assert.h' file not found
```

So Mesa's first libc header is `assert.h` via `src/util/bitscan.h:32`, reached from
`freedreno_drmif.h:14` → `util/bitset.h:34`.

### 4.3 What the next wall is (probe, not a fix)

To find out whether the SDK was the *only* blocker, `meson.build:971` was changed to `if false` in the
scratch clone (`git checkout --` restored it afterwards; `git status` clean) and configure re-run. It
went 340 lines further and stopped at:

```
src/mesa-25.0.7/meson.build:1312:20: ERROR: C shared or static library 'atomic' not found
… Checking if "GCC atomic builtins required -latomic" links: NO
```

The link test fails because there is no `crt1.o` and no libSystem to link an executable against, so
meson concludes `-latomic` is required and then cannot find it. This is the second missing SDK
component and it cannot be dodged by headers alone: **meson links test executables even in a
`needs_exe_wrapper` cross build**. With a full SDK both checks pass (they do in the reference builds);
with a hand-made sysroot one must also provide `crt1.o` (or an empty stub plus
`-Wl,-e,_main`, **inferred**).

Nothing beyond configure was reached, so there is no `build.ninja` and no `ninja` run to report. What
a successful `ninja` does is known from the reference (`mk-mesa.sh:133,156-166`): it compiles 1000+ objects
and links **one** dylib.

---

## 5. Output shape

### 5.1 Artifacts

The configuration of §2 produces **one** library, not a set:

```
$BUILD/src/gallium/targets/osmesa/libOSMesa.8.dylib
```

with `install_name` `/redwood/lib/libOSMesa.8.dylib` in the reference (`mk-mesa.sh:16,156-157`), i.e.
`--prefix=/redwood --libdir=lib`, `soversion '8'`/`version '8.0.0'`/`darwin_versions '9.0.0'` in
`src/gallium/targets/osmesa/meson.build` (so `LC_ID_DYLIB` comes out at 9.0.0). It contains
`libgallium` **statically** (mesa links gallium into the target, no `libgallium.dylib` exists in this
configuration), the whole of freedreno/a6xx including ir3, softpipe, glapi, GLSL and OSMesa's own
entry points. `driver_swrast` + `driver_freedreno` are both linked in by patch #11 of §3; without that
patch the driver would not be in the dylib at all even if it compiled.

Size, measured on the reference's real build (the only hard numbers available; ours cannot be built
yet):

* **14 855 048 B (14.2 MiB)** — `libOSMesa.8.dylib` as linked, quoted in HackiOS
  `tools/mk-mesa.sh:30-33` ("9 132 774 of 14 855 048 bytes different in the library" between two
  builds of the same source — Mesa's layout is not reproducible byte for byte, so no hash
  comparison is meaningful for it);
  then `llvm-strip -x` (keep global symbols — they *are* the GL API) and
  `llvm-install-name-tool -id /redwood/lib/libOSMesa.8.dylib` → `mk-mesa.sh:156-157`;
* `nm -gU … | awk '$3 ~ /^_gl/'` yields the exported `gl*` list (`out/exported-gl.txt`), which is what
  `userland/mkeagl.py` turns into the 409-slot EAGL shim (§5.3).

So expect an artifact of roughly 10–15 MiB after strip for `freedreno+softpipe+gles2`, and about
9.8 MB for the reference's separate `air_run` binary — the same order of magnitude either way. Both
are **inferred for our build**: nothing here was linked.

### 5.2 Install paths in the iOS root

The reference layout (`userland/build.sh:43-54,472-477`): `/redwood/lib/libOSMesa.8.dylib` plus
`/redwood/lib/libredwood-gl.dylib` (the EAGL shim, ~100 KB) and `/redwood/bin/*` test programs. For
this project the equivalent would be whatever path the kernel-side lane picks under the iOS root's
`/usr/local/lib` or `/redwood/lib`; nothing in `docs/` fixes it yet. The dylib needs
`-Wl,-rpath,@loader_path` (as `build-redwood-gl.sh:22` does) so a co-located `libdrm.2.dylib` stand-in
resolves.

### 5.3 The "OpenGL ES front end" is OSMesa, not EGL — and that is forced

`-Degl=enabled` cannot be used on this target:

```
meson.build:475-476  with_egl = get_option('egl')
                       .require(with_platform_windows or with_platform_haiku or with_dri
                                or with_platform_android, error_message : 'EGL requires DRI, Haiku, Windows or Android')
```

and `with_dri` needs `system_has_kms_drm` — false on darwin. So both public ports take the OSMesa route
and treat `libOSMesa`'s `gl*` symbols as the ES2 API: the app-facing shim is
`libredwood-gl.dylib`, a 409-slot EAGL replacement generated by `userland/mkeagl.py` from
`gl.xml` + `exported-gl.txt` against `eagl.c`, which forwards into `libOSMesa.8.dylib` through
`gl_osmesa.c`'s four functions. (marnov999's raphael build instead linked prebuilt
`libEGL.1.dylib`/`libGLESv2.2.dylib` from a tree not present in `refs/` —
(`refs/marnov999-raphael-ios-gpu/tools/build-redwood-gl.sh:19-22`; how those two were configured is
**inferred** and would need `with_dri`, i.e. a fake KMS/drm on darwin.)

What the freedreno path needs from the kernel, for whoever wires the stand-in: `drmOpenWithType("msm",
…)`, then `drmIoctl` for the msm submit/param/wait ioctls, plus a map/unmap and an "IOSurface ID →
buffer with stride/size/offset" query (§3, rows 4-6, 10). That is exactly the uAPI lane B catalogued.

---

## 6. What is verified, what is not

**Verified by running it here:** clang 18.1.8 cross-targets `arm64-apple-ios16.0`; `ld64.lld` is the
only usable linker and must be named with `-fuse-ld=lld`; `-Qunused-arguments` is required for meson's
compile probes; an arm64 iOS dylib links against a TAPI stub and comes out with
`LC_BUILD_VERSION platform 2 minos 16.0`, `LC_DYLD_CHAINED_FIXUPS` and, with `-adhoc_codesign`, a
CD-`0x20400` sha256 ad-hoc signature; `meson 1.12.1` accepts the whole option set of §2.2 for
25.0.7; configure dies at `ETIME` for lack of `<errno.h>`; the next wall is `-latomic` from a failing
link test; there is no `ldid`, no `codesign` and no `iPhoneOS*.sdk` on this host; `GPUId(620)` is in
25.0.7.

**Not verified:** any Mesa object file, the artifact size for our configuration (§5.1 numbers are the
reference's), the claim that the freedreno `drm/` layer compiles once a stand-in exists, the
`pkcs7`/entitlement side of signing for an injected dylib, and the dyld-cache-to-`.tbd` route (tools
present, never exercised).

**Deliberately not written:** `tooling/gpu/cross-ios-arm64.ini` and `tooling/gpu/build-mesa.sh`, which
the lane file allows only after a passing configure. The cross file exists verbatim in §2.1 and in
`~/.hermes/cache/scratch/lane-c-mesa/cross-emptysdk.ini`.
