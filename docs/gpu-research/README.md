# GPU / userland research: synthesis

Three lanes, one question: what does it take to get real GPU rendering on the Nord instead of the
CPU rasterizer that caps SpringBoard at ~24 fps. Read the lane reports for the evidence; this page
is the decision surface only. Nothing here was built or flashed — kernel layers 1–5 are separate
work (`xnu-avicii/patches/0119`, `0122`, `0123`, `0125`; the kernel lane has since landed 0125, the
compute-store and triangle tests).

Reports: [A `docs/gpu-research/A-quartzcore-compositing.md`](A-quartzcore-compositing.md) ·
[B `docs/gpu-research/B-hackios-inventory.md`](B-hackios-inventory.md) ·
[C `docs/gpu-research/C-mesa-darwin-build.md`](C-mesa-darwin-build.md)

## The one thing to take away

QuartzCore picks its renderer in `EAGLServer::renderer()`, in a fixed order: Metal → OpenGL ES 3 →
CPU. The CPU is the last rung and it is where we are, because `0107` publishes `IOAcceleratorES`
empty and nothing answers `EAGLContext`. Every rung above the CPU is a *userland* object, so the
cheapest way off the CPU is to answer the GLES rung — not to build Metal.

## 1. Recommended seam (lane A)

**Answer the OpenGL ES step.** Supply an `EAGLContext` (`initWithAPI:3` + `properties:` with the
`EAGLContextProperty*` keys) implemented over Mesa freedreno, loaded as an insert dylib, and publish
`IOGLESBundleName` / `IOGLESMetalBundleName` / `IOGLESDefaultUseMetal=false` on `IOAcceleratorES`.
`CA_ENABLE_OGL` already defaults on; `CA::OGL::Renderer`, `GLESContext`, the shader cache and the
layer tree are QuartzCore's own code and run unchanged over plain `gl*` calls.

Why not Metal: it costs a second ABI (the full IOGPU device/queue/resource/submit selector table is
in A §4 for reference), a `MTLIOAccelDevice` plugin and registry-driven discovery. raphael
built a shim Metal, then still kept the window server on GLES — a process handed a half-made device
aborts instead of falling back. Scanout is renderer-agnostic (`finish_update` submits surface IDs),
so a GLES renderer is indistinguishable from the CPU one at the display path.

Kernel side of this seam is two things, not an ABI: surfaces must be GPU-addressable
(`IOSurfaceClientBindAccel`, selector `0xc` → SMMU mapping) and `SweetFramebuffer` must set a
wait-for-GPU property so `present()` paces on the fence instead of a per-frame `glFinish()`
(raphael: `RedwoodWaitsForGPU`, 3–14 ms/frame saved). `SweetSurface` already produces the
client-mapped buffer this binds.

## 2. Kernel uAPI the userland will call, in order (lane B)

freedreno drives this sequence; rows 3–11 must *succeed*, not `EINVAL` — a failed `GMEM_SIZE`,
`CHIP_ID` or `MAX_FREQ` aborts `fd_screen_create` (`freedreno_screen.c:923,955`). Selectors are the
low byte of the Linux ioctl code.

    1  drmGetVersion fabricated (1.7, "msm")      shim, not an ioctl
    2  DRM_CAP_SYNCOBJ -> 0                       shim
    3  MSM_GET_PARAM GPU_ID   0x01 -> 0
    4  MSM_GET_PARAM GMEM_SIZE 0x02 -> 524288
    5  MSM_GET_PARAM CHIP_ID  0x03 -> 0x06020000
    6  MSM_GET_PARAM GMEM_BASE 0x06 -> our IOVA, = UCHE_GMEM_RANGE base
    7  SUBMITQUEUE_NEW 0x0a -> id
    8  MSM_GET_PARAM ×7 from fd_screen_create (GMEM_SIZE/GMEM_BASE/MAX_FREQ 625e6/TIMESTAMP/GPU_ID/CHIP_ID/PRIORITIES 1)
    9  MSM_GET_PARAM GLOBAL_FAULTS 0x09, SUSPENDS 0x0a, PP_PGTABLE 0x08 -> 0
    10 MSM_GET_PARAM HIGHEST_BANK_BIT 0x10 -> 14, UBWC_SWIZZLE 0x12 -> 6, MACROTILE_MODE 0x13 -> 1
    11 MSM_GET_PARAM VA_START 0x0e / VA_SIZE 0x0f -> our IOVA window
    12 GEM_NEW 0x02 per buffer (write-combined)
    13 IOSurface import (private; davinci 0x85 / HackiOS surface req 0x7e)
    14 GEM_INFO GET_IOVA 0x03 -> handle's IOVA
    15 mmap of a buffer (IOSurface map 0x80 / IOConnectMapMemory64), +64 KiB mapped past the end
    16 GEM_CPU_PREP 0x04, honour MSM_PREP_NOSYNC
    17 GEM_SUBMIT 0x06 per frame, fence raises atomically, fence_fd = -1
    18 WAIT_FENCE 0x07, honour timeout + queueid
    19 GEM_CLOSE 0x09
    20 SET_PARAM 0x01 / CPU_FINI 0x05 / GEM_MADVISE 0x08 / SUBMITQUEUE_CLOSE 0x0b / SUBMITQUEUE_QUERY 0x0c — may be no-ops, must return success
    21 present: hand a fence to the framebuffer (HackiOS 0x7f, davinci 0x81-0x83) — not a DRM request

Two shapes of this exist. HackiOS does it as an IOKit user client; our own lineage
(`refs/marnov999-raphael-ios-gpu`, `0113-sweet_gpu.c` → `sweet_gpu.c`) does it as
`/dev/dri/renderD128` + `/dev/kgsl-3d0` cdevs. B calls the cdev route the cheaper port for
`xnu-avicii/` — it is the shape our tree already starts from.

## 3. State of the Mesa build (lane C)

**Configure only; no Mesa object exists yet.** meson 1.12.1 accepts the whole option set (971 lines
into `meson.build`) against clang 18.1.8 + `ld64.lld` and then stops at

    src/mesa-25.0.7/meson.build:971:6: ERROR: Could not get define 'ETIME'

cause `'errno.h' file not found`: **there is no libc for `arm64-apple-ios16.0` on this host.** The
only Mach-O produced is a deliberate toolchain proof (49 968 B arm64 iOS dylib, `platform 2`,
`minos 16.0`, chained fixups, ad-hoc CD) — the toolchain works, the sysroot does not exist.

Blocking pieces, ordered, each gating the next: (1) iOS 16 SDK sysroot — ~30 headers,
`libSystem.tbd`, `libz.tbd`+`zlib.h`, `libc++.tbd`+`c++/v1` (18 `.cc` in `a6xx` alone), `crt1.o`;
(2) libdrm stand-in (`<xf86drm.h>` at `freedreno_priv.h:21`); (3) the 12-file `freedreno-darwin`
patch (14 Linux-isms, both public fixes tabled); (4) unguarded `<zlib.h>` in `freedreno_rd_output.h:11`;
(5) signing — already solved, `ld64.lld -adhoc_codesign` (not default for `-dylib`).

Two toolchain traps worth the ink: `-fuse-ld=lld` and `-Qunused-arguments` are both mandatory, else
meson picks GNU `ld` or silently disables features on failed probes. `A620` needs no Mesa patch —
`GPUId(620)` is at `freedreno_devices.py:515`.

## 4. Conflicts between the lanes

1. **Front end: `libEGL`/`libGLESv2` vs `libOSMesa`.** A names the seam as an `EAGLContext` over
   `libEGL`/`libGLESv2` (raphael's prebuilts); B and C converge on `libOSMesa.8.dylib`, because
   `-Degl=enabled` is impossible on this target (meson `:475` needs DRI/Haiku/Windows/Android).
   Both public ports use OSMesa and treat its `gl*` symbols as the ES API. **OSMesa is the buildable
   answer**; the raphael EGL prebuilts have no source in `refs/`, so they are the riskier base.
2. **Kernel interface shape: IOKit client vs cdev.** A's requirements are stated over the
   `IOAcceleratorES`/`IOSurface` kernel clients; B says port the cdev form. Both agree on the
   selectors — only the transport differs, and the cdev form is what `0113` already starts from.
3. **`highest_bank_bit`:** `CONSTANTS.md:311` says 14 (dts `lito-gpu.dtsi`), Mesa 25.0.7's
   GPUId(620) block inherits the class default **15**. Gallium never reads `MSM_PARAM_HIGHEST_BANK_BIT`
   (only Vulkan does), so the GLES path is insensitive — still UNVERIFIED and worth a live read.
4. **One object, two lanes.** A needs `IOAcceleratorES` published non-empty with the IOGLES
   properties; B needs `GET_PARAM` CHIP_ID `0x06020000` answered. Both land on the same service, and
   `0107` currently publishes it empty and skipped.

## 5. Order of work this implies

1. Answer the twelve `GET_PARAM` values on the existing cdev (rows 3–11) — no new ABI, table-driven.
2. Publish `IOAcceleratorES` with the IOGLES properties + `SweetFramebuffer` wait-for-GPU; confirm
   the GLES rung is taken (`EAGLContext` reached, CPU rasterizer out of the log).
3. `GEM_NEW`/`SUBMIT`/`WAIT_FENCE`/`GEM_CLOSE` with a null submit, then a real one.
4. Surface import + SMMU bind (`0xc`), then drop the per-frame `glFinish()`.
5. The Mesa artifact is gated on the SDK, not on us; it proceeds in parallel from C §2.1 once a
   sysroot exists.

## Round 3

Round 3 broke the remaining userland work into five parallel lanes: a sysroot (`D`), the EAGL/GL
surface spec (`E`), the libdrm stand-in and Mesa patches (`F`), the idle-CPU cause
(`../perf-research/I`), and deployment into backboardd (`G`). Rounds 1–2 established the seam, the
kernel uAPI and the wall (no libc for the target); this round converts that into artifacts. Every
lane here is read-only on the phone — the commands to run come with the reports.

### Lane 5 — deployment, and why the property set is the whole game (`G-gl-deploy.md`)

**Recommended: route (c).** `IOAcceleratorES` carries `IOGLESBundleName = "SweetGLES"`,
`IOGLESMetalBundleName = "AppleMetalGLRenderer"`, `IOGLESDefaultUseMetal = false`; `libGFXShared`
(`_gfxInitializeLibrary`) reads them off the service, builds
`/System/Library/Extensions/SweetGLES.bundle/SweetGLES`, `dlopen`s it and `dlsym`s
`gldInitializeLibrary` (`G:153-176`, disassembly in `G` §3c). A bundle that fails to load is
silently skipped, so the seam fails soft — no plist edit, no shim, no `DYLD_*`, nothing on
backboardd's spawn path. The properties are gated behind boot-arg `sweetgles`, default off, so
undo is one reboot: with the flag unset `0107` still publishes the service empty and today's CPU
path is untouched (`G` §4, §6.2). Costs: the property set is all-or-nothing and applies to every
process, so a *broken* bundle leaves no renderer at all (§3c risks; §6 keeps a `.good` copy).

Two of the three routes are dead ends worth recording. `DYLD_INSERT_LIBRARIES` looks like the
obvious answer and is blocked twice: launchd filters job `EnvironmentVariables` through
`job_is_dyld_var()` (only `LD_LIBRARY_PATH` and `DYLD_PRINT_*` pass, `G:103-134`) *and* dyld
prunes the rest unless AMFI answers `__mac_syscall("AMFI", 0x5a, …)` — which our `"SWEET AMFI"`
policy cannot, having no `mpo_policy_syscall`, so every `DYLD_*` is discarded (`G:61-96`). Both
public ports patched both halves; it is the named fallback, and it needs a re-exec shim in
`ProgramArguments`. Shadowing `OpenGLES.framework` fails on its own because the framework binary
is not a file on this root — only `Info.plist`, `GLEngine.bundle/` and `_CodeSignature/` are, the
image lives in the dyld cache, so a file at that path is ignored (`G:135-152`).

Signing is already answered: ad-hoc suffices, and no trustcache entry can be added because no
trust cache exists (`0015`). `CS_SIGNED` (`0036:23`) plus placement on the root filesystem
(`CS_PLATFORM_BINARY`, `0035:252-254`) is enough for the exec path (`0104:29`); library validation
never runs because `mpo_file_check_library_validation` is unregistered and `CS_REQUIRE_LV` is
never set (`G:61-100`).

Worst case is a backboardd crash-loop, and it is survivable: the job has `KeepAlive` but no
`_PanicOnCrash` (the seven jobs that had one are already renamed by `61-mkrd-root.sh:463-484`), so
launchd throttles and respawns instead of panicking; sshd is a separate inetd job on 22 and USB
ECM is a kernel `ifnet`, so the repair channel stays up and no fastboot recovery is needed
(`G:285-310`).

### Lane 2 — the shim contract is a table, not a symbol set (`E-eagl-shim-spec.md`)

Lane 2 rewrote the shape of the job. **QuartzCore imports no `gl*` symbol at all** — its only
OpenGL ES bindings are `_OBJC_CLASS_$_EAGLContext` and the two `kEAGLContextProperty*` strings
(`E:34-61`). Every GL call is an indirect call through a function-pointer table: each stub in
`OpenGLES.framework` is six instructions — `mrs x8, TPIDRRO_EL0; ldr x8,[x8,#0xf0];
ldr x3,[x8,#0x20+T]; ldr x0,[x8,#0x20]; br x3` — and `-[EAGLContext getMacroContextPrivate]` is
literally `return _private + 0x20` (`E:90-131`). So the shim exports nothing GL-shaped: it fills a
table of **58 slots over 229 call sites** with a `0x2068`-byte table, `calloc(0x2088)`,
`table[0] = ctx`, and installs it into the `_private` ivar. Consequence worth a rule: a `NULL`
slot is a branch to address 0, so every one of the 58 offsets must be non-NULL even if it only
logs and returns; and since `_private` is set, `-[EAGLContext dealloc]` reaches
`gliDestroyContext` through the sharegroup, so either `dealloc` or the sharegroup has to be
stubbed.

The selection path is pinned too: `CA::OGL::EAGLServer::renderer()` builds the property dict
(`kEAGLContextPropertyAccelerated`, `…ClientRetainRelease` → `kCFBooleanTrue`), calls
`initWithAPI:3 properties:`, `setParameter:0x260`, checks `[ctx API]==3`, then constructs
`CA::OGL::GLESContext` whose ctor does three `glGetString` and sixteen `check_extension`
substring searches against `GL_EXTENSIONS` (`E:62-89`). That extension string is therefore load
bearing — the `CA_DISABLED_EXTENSIONS` env var is honoured in the same routine. The IOSurface path
is a fixed order: gen texture → bind → four `texParameteri` → `attachImage` → gen FBO → bind FBO
→ `glFramebufferTexture2D` → unbind, and teardown is textures before FBOs, in that order
(`E:234-275`). §6-7 of the report cross-check HackiOS's `eagl.c` and list what *not* to copy from
it; §9 is the minimal test program, §11 the scratch.

### Lane 3 — the stand-in is 14 functions and 6 patches, and they apply clean
(`F-libdrm-darwin.md`)

The libdrm surface freedreno actually uses is **14 functions** (16 provided so the linker is
satisfied), all in one `xf86drm.h` + `drm_darwin.c` under `src/freedreno/drm/darwin/`, over
`ioctl(2)` on `/dev/dri/renderD128`. No `drmMode*`, no event loop, no fence/BO layer of our own
(`F:9-31`, function table at `F:68-95`). The one kernel-contract detail that would have cost a
day: XNU's `_IOW` carries `IOC_IN` while the pure-`_IOW` requests
(`GEM_CLOSE`, `GEM_CPU_PREP`, `SUBMITQUEUE_*`) must be *encoded* with `IOC_IN` by the shim to match
0126, and `SET_PARAM` (`0x41`) is not implemented at all — it answers `ENOTTY`, so the shim must
not require it (`F:32-67`).

The deliverable is now concrete: `tooling/gpu/mesa-patches/` holds six plain patches against Mesa
25.0.7 — `0001` meson wiring, `0002` the shim itself (+470), `0003` drm-layer mmap/import/clock,
`0004` no-`sysinfo`/no-build-id, `0005` OSMesa GPU screen + surface textures, `0006` the a6xx
fb-read barrier. Total **+726/−9 across 18 files (2 new)**, and all six apply with
`patch -p1 --dry-run` in order to a pristine 25.0.7, 6/6 clean, then really apply (`F:218-247`,
patch list `F:291-303`). Fourteen Linux-isms are enumerated at `F:160-194`. The patches are drafts:
nothing in the tree applies them, and none has been built beyond a syntax/compile pass of the
`drm/` layer.

### Lane 1 — the sysroot exists, links, and Mesa configures (`D-ios-sysroot.md`)

This lane's first agent hit its iteration cap with the report unwritten, so the round was finished by
four agents on one file each. The result is real: a minimal iOS 16 arm64 sysroot that compiles C
headers and links Mach-O against `.tbd` stubs generated from our own dyld cache — `platform ios`,
`minos 16.0`, `LC_LOAD_DYLIB /usr/lib/libSystem.B.dylib` + `/usr/lib/libz.1.dylib` with the cache's
own `current version 1319.100.3` / `1.2.11`. The proof is re-runnable and includes the control that
matters: rename `libSystem.B.tbd` away and the link fails, so the stubs are demonstrably the thing
linking (`tooling/gpu/sysroot-test/PROOF.txt`, 3/3 PASS; independently reproduced here at 65 976 B).
`tooling/gpu/mksysroot.sh` (46 KB) is the reproducible generator — nine upstream tarballs pinned by
tag *and* sha256, a `MANIFEST.sha256` of inputs and outputs, staging into `$OUT/.work.$$` and merged
without deleting, `.tbd` generation skipped under `--no-tbd` when no cache is mounted (`:53`, `:84`).

Nothing here is Apple code: APSL-2.0 apple-oss-distributions, LLVM-18 libc++ under Apache-2.0 WITH
LLVM-exception, zlib 1.2.11 under the zlib licence, plus four synthesized headers (listed as such in
the report) and `.tbd` stubs from the device cache.

**The Mesa build moved further than in any previous round, and that is the point of the lane.**
`meson setup` now **passes** — the `ETIME` probe that stopped lane C returns `101`. `ninja` on all
targets stops at 34/752 with **zero Mesa objects failed**; both `FAILED` are the libarchive
subproject (`openssl/evp.h`, `CommonCrypto/CommonCryptor.h`). Targeted builds all exit 0 and the
build dir holds 275 objects and 5 archives including `libfreedreno.a` (85 objects, C++ among them)
and `libgallium.a` (151). Three traps worth the ink: `-DXNU_PLATFORM_iPhoneOS` is **mandatory** (without
it `cdefs.h` leaves `__DARWIN_ONLY_UNIX_CONFORMANCE 0` and the link dies on `_pthread_join$UNIX2003`);
lane C's option set is self-inconsistent (`-Dosmesa=true` without softpipe/llvmpipe aborts at
`meson.build:2052`); and with `-Dplatforms=` there is no `src/gles/`, so `-Dgles2=enabled` builds no
`libGLESv2` — a config decision, not a sysroot gap.

One sysroot gap stays open and it is narrow — with two known fixes now. `<locale>` failed on
`strtoll_l` (+4 `_l` forms) because Libc's `xlocale.h` gates those prototypes on `#ifdef
_STDLIB_H_` and libc++ 18's `__locale` includes `<xlocale.h>` first: fixed by the compile flag
`-D_USE_EXTENDED_LOCALES_`, no header edit. Behind it sits the real blocker: `libSystem.B.tbd`
drops **20 plain libc aliases** (`_strlen`, `_memcmp`, `_memmove`, …) while keeping their
`__platform_*` twins, because `gen_tbd.py` skips `REEXPORT` trie entries — so no C++ dylib links
at all, and it has nothing to do with libc++. Patched in the copy (7894 → 7914 symbols), after
which the C++ dylib links at 71 296 B with **no libc++ ABI delta** — every `std::__1` import
resolves against the 1500.65.0 stub (`~/.hermes/cache/scratch/lane-1d/RECIPE.md:134`, `§6` delta).
Two smaller corrections from the same lane: canonical's `__config_site` says `HARDENING_MODE_FAST`
where `NONE` matches the shipped dylib, and `_LIBCPP_PSTL_CPU_BACKEND_SERIAL` is mandatory or the
build reports `Invalid CPU backend choice`. No `crt1.o`/`dylib1.o` is needed for `-dylib` or even a
dynamic executable — lld defaults `LC_MAIN` to `_main`, so nothing runs `__libc_init`; only
`-static` demands `-lcrt0.o`, and no open-source tree here defines `start()`.

## Round 3: what is still unsolved, and the next three steps

Nothing in this round ran on the phone. Every lane is an artefact: a sysroot, a spec, patches, a plan.
That is the correct order — but it means the seam is still unproven end to end, and the honest
statement of state is "builds a driver, never driven it".

1. **Apply the two known fixes, then push `ninja`.** Take `§6` of `lane-1d/RECIPE.md`: the
   `gen_tbd.py` alias fixup (4 lines, so `REEXPORT` entries stop being skipped) and
   `-D_USE_EXTENDED_LOCALES_` in the cross file, plus `HARDENING_MODE_NONE` and the mandatory PSTL
   macro in `__config_site`. Verify by the C++ test-3 link exiting 0 and `ninja` moving past 34/752;
   the walls already queued behind it are `usr/include/pwd.h`, `mach-o/dyld.h` and a
   `host_statistics64` declaration (`D` §Status steps 2-4). Disable libarchive with `--wrap-mode` or
   `-Dlibarchive=disabled` rather than porting OpenSSL into the sysroot.
2. **Decide the front end before building it.** `-Dgles2=enabled` cannot produce `libGLESv2` on this
   config, so take F's OSMesa-only path (`libOSMesa.8.dylib` + `@loader_path`) and record the
   decision in `C`/`F`; verify with `nm -gU` that the shim's 58 slots (E §4) are satisfied by
   OSMesa's exports, slot by slot, before a single byte goes to the phone.
3. **The driver gate, still without the compositor.** Build and ad-hoc sign the two dylibs, scp the
   `SweetGLES.bundle` and a test binary per G stage 0, and run OSMesa `clear` + readback over SSH.
   That touches `GET_PARAM`, `GEM_NEW`, `SUBMIT`, `WAIT_FENCE` and `GEM_CLOSE` in one go. Only after
   it passes does G stage 1 (`sweetgles=1`, a throwaway `EAGLContext` process) become worth a boot.

## Round 4 (main agent): why QuartzCore picks a 10-bit 'b3a8' framebuffer on the GL path

First backboardd run on SweetGLES (`logs/phone/backboardd-gles-3.txt`): QuartzCore created an ES 3.2
context on Mesa, then asked for its screen render target as `'b3a8'` (2 planes, 1125x2436, bpr 4544),
which SweetEAGL rejects, so the panel went black. The CPU renderer swaps plain `'BGRA'`.

* `IOMFBDisplay::framebuffer_pixel_format` (0x1882c5320) returns `'b3a8'` when bit 3 of
  `Display+0x220` is set (0x1882c541c `tbnz w8,#3`), else tail-calls with `'BGRA'`.
* Bit 3 is `supportsExtendedColors` (`-[CAWindowServerDisplay supportsExtendedColors]` 0x1884e700c,
  `ubfx w0,w8,#3,#1`). `AppleDisplay::AppleDisplay` sets it (0x1883ad034, `orr #0x8`) iff the byte
  written by `CADeviceUseCIF10`'s once-block is non-zero.
* `___CADeviceUseCIF10_block_invoke` (0x188381f38):
  `enable = MGGetBoolAnswer("Aixt/MEN2O2B7f+8m4TxUA")`; if true,
  `CFPreferencesGetAppBooleanValue("CAEnableDeepFramebuffer", <current app>, &valid)` overrides it
  when `valid`. CFString constants at 0x1d5b5f1c0 / 0x1d5b5f1e0.
* Off switch, no binary change: `CAEnableDeepFramebuffer = false` in backboardd's domain
  (`/var/mobile/Library/Preferences/com.apple.backboardd.plist`, owner mobile, 0600). Applied
  2026-11-15; original kept at `logs/phone/prefs/com.apple.backboardd.orig.plist` and on the phone
  at `/var/root/gpu/com.apple.backboardd.orig.plist`. Effect on the GL path: UNVERIFIED until the
  bundle is reinstalled.
