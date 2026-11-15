# Lane B — the public HackiOS / raphael GPU userland: inventory, exact kernel ABI, A640→A620 delta

Scope: what is public in the iOS-on-Qualcomm GPU userland, exactly what kernel interface it
expects, what of that changes for an Adreno 620 (SM7250 `lito`, `avicii`) and what does not exist
anywhere and would have to be written. Layer 6–7 of `.hermes-lanes/gpu-shared.md`; the kernel side
(layers 1–5) is another lane's work in `xnu-avicii/patches/`.

Read-only work. Nothing was built, flashed or booted. All tool output of this lane lives in
`~/.hermes/cache/scratch/lane-b-hackios/`. Every `file:line` below was read with `read_file`,
`sed -n` or `grep -n` against the clones named here.

**Sources read (pinned commits, `git rev-parse HEAD`):**

| Tree | Commit | Note |
|---|---|---|
| `refs/gsjsjzhznsz-hackios-xnu-userland` | `ea65b1ddeaf21545e08456d9d970b04de146aad6` | fork of OOSEX GANG's `hackios-xnu-userland`; `redwood-*` names. The userland this lane was asked about. |
| `refs/heliumstudio-hackios-xnu-kernel` (`raphael-bringup`) | `57722468a3774e2ec60017705ec356ae9b31f40e` | same code renamed `hakios-*`, **plus** the kernel user client `xnu/files/iokit/Kernel/hakios.gpu.cpp` and the A640 driver `xnu/files/bsd/dev/hakios.adreno.c`. |
| `refs/marnov999-raphael-ios-gpu` (already in the repo) | `69dac1c42b971565595cc535bfdf3e5c549ab2ea` | our own lineage. Same ABI, but reached through a **BSD cdev** in `bsd/dev/sweet_gpu.c` (`xnu/patches/0113-raphael-gpu-kgsl-drm.patch`), not through IOKit. |
| Mesa 25.0.7 (lane C's unpacked source, read-only) | n/a | `~/.hermes/cache/scratch/lane-c-mesa/src/mesa-25.0.7` — for what freedreno actually asks for, and for `freedreno_devices.py`'s A620 entry. |

Both clones succeeded on the first attempt; no network problem to report.

---

## Summary

### Components × (public? / A620 change / effort)

`S` ≈ under a day, `M` ≈ days, `L` ≈ a week or more, of one person who has the toolchain. Effort is
for *our* port, not for what the reference projects did.

| # | Component | Exists publicly | A620 change needed | Effort |
|---|---|---|---|---|
| 1 | `libredwood-gl.dylib` — EAGL replacement, 409 slots of which 30 hand-written (`userland/src/eagl.c`, 4205 lines; `userland/src/eagl_slots.txt`, 409 slots; `userland/mkeagl.py`) | yes (source) | none in the interface: it is parameterised entirely by `GET_PARAM` and by Mesa's own device table. Nothing in `eagl.c` mentions a GPU type. Verified: `diff` of the gsjsjzhznsz and heliumstudio `eagl.c` shows **only** `redwood→hakios` renames, zero logic lines. | M (port + debug on our panels) |
| 2 | `gl_osmesa.c` (33 lines) — the only file that knows which library draws; `redwood_gl*` four-function API (`userland/src/redwood_gl.h:9-12`) | yes | none | S |
| 3 | Mesa `freedreno-darwin.patch` (365 lines) — makes freedreno build without libdrm, `#ifdef __APPLE__` arms in `freedreno_bo.c`/`msm_bo.c`/`osmesa.c`, GET_IOVA instead of `lseek`, `fd6_draw.cc` UCHE flush fix | yes | none; it is genotype-agnostic (written for an A642L) | S |
| 4 | libdrm stand-in `redwood-drm/redwood_drm.c` (226 lines) + `xf86drm.h` (76) | yes | service name only (`RedwoodGPU`/`HakiosGPU` → ours), and only if we keep the IOKit shape | S |
| 5 | Kernel GPU user client, ~1190 lines (`hakios.gpu.cpp`) — **the entire layer-5 uAPI**: 15 selectors, buffer table, submit ring feed, surface import | yes (source, in the *kernel* repo) | all of the value semantics (chip id, GMEM, bank bit, macrotile), and it is IOKit-shaped where our tree wants a cdev | **L** |
| 6 | `MiniIOSurface` (kernel, 174 + 1814 lines) — the IOSurface the surface request reads | yes | our tree already has a different stand-in, `SweetSurface` (`xnu-avicii/patches/0046-sweet-iosurface-iomfb.patch`) — the surface request must be built on **that**, not ported | M |
| 7 | `MiniIOMobileFramebufferShow()` + `Redwood/HakiosWaitsForGPU` property — the "the display waits for the fence" contract | yes | nothing in `xnu-avicii/patches/` calls `setProperty` at all; our framebuffer is `SweetFramebuffer.cpp` (patch 0114) and the property must be added there | M |
| 8 | `init`/`launchd` job lists, `/redwood` root layout, `build.sh` GL=1 pipeline | yes | paths and the 64 MB loader budget are ours to re-cut (`userland/build.sh:43-54,326-372,472-477`) | S |
| 9 | Metal front-end (`tools/mesa/air/`, 20 files, `docs/air.md` 4990 lines) | yes | none | M, **but** the project's own verdict is GLES-only (commit message of `ea65b1d`, the `rc.jobs.r39quiet` says Metal is off the boot path) — deferred |
| 10 | Cross toolchain + iPhoneOS SDK for `GL=1` | **no** — `prebuilt/userland/SHA256SUMS` has 19 entries and not one `-gl` or `libOSMesa`; `build.sh` requires theos + `iPhoneOS16.5.sdk` | our own SDK/clang (`tooling/opt/llvm` is host-only, no `iPhoneOS*.sdk` anywhere on this machine) | M, blocking |
| 11 | GMEM size end-to-end: `GET_PARAM` → `screen->gmemsize_bytes` → bin/tile sizing | mechanism is upstream | **512 KiB** must reach `fd6_screen_init()` or the colour-CCU offset at the top of GMEM is computed outside the aperture (`fd6_screen.cc:180`) — see §3.2 | S |

### The ordered list of ioctls our layer-5 uAPI must provide

This is the sequence freedreno actually performs, read out of Mesa; the uAPI has to answer all of it
in this order, not merely exist. Selector numbers are the low byte of the Linux ioctl code, which is
what `drmIoctl()` sends (`redwood_drm.c:81`).

| # | When | Request | Selector | Struct / answer |
|---|---|---|---|---|
| 1 | `fd_device_new()` → `drmGetVersion` (`freedreno_device.c:39`) | not an ioctl in the Darwin shim: `redwood_drm.c:109-125` fabricates `1.7`, name `msm` | — | major 1 ⇒ `msm_device_new()`; minor 7 ⇒ `SOFTPIN`, `GMEM_BASE`, `ROBUSTNESS`, `SUSPENDS` paths all taken |
| 2 | `drmGetCap(DRM_CAP_SYNCOBJ)` (`freedreno_device.c:237`) | fabricated 0 in the shim (`redwood_drm.c:138-145`) | — | 0 ⇒ no syncobj |
| 3 | `msm_pipe_new`: GPU_ID | `MSM_GET_PARAM` 0x01 | `0x40` | 0 (the chip id carries it) |
| 4 | GMEM_SIZE | `MSM_GET_PARAM` 0x02 | `0x40` | **524288**, not 1048576 |
| 5 | CHIP_ID | `MSM_GET_PARAM` 0x03 | `0x40` | **`0x06020000`**, speed bin in the upper 32 bits |
| 6 | GMEM_BASE (minor ≥ 3) | `MSM_GET_PARAM` 0x06 | `0x40` | **an IOVA we choose**, must equal `UCHE_GMEM_RANGE` base |
| 7 | `open_submitqueue` | `SUBMITQUEUE_NEW` 0x0a | `0x4a` | `{flags,prio,id}` → `id` |
| 8 | `fd_screen_create`: GMEM_SIZE, GMEM_BASE, MAX_FREQ 0x04, TIMESTAMP 0x05, GPU_ID, CHIP_ID, PRIORITIES 0x07 (`freedreno_screen.c:923-985`) | `MSM_GET_PARAM` ×7 | `0x40` | 625 000 000 Hz, `mach_absolute_time()`, 1 |
| 9 | robustness (minor ≥ 5): GLOBAL_FAULTS 0x09, SUSPENDS 0x0a, and PP_PGTABLE 0x08 on the old path | `MSM_GET_PARAM` | `0x40` | 0, 0, 0 — must *succeed*, not `EINVAL` |
| 10 | optional: HIGHEST_BANK_BIT 0x10, UBWC_SWIZZLE 0x12, MACROTILE_MODE 0x13 (Vulkan only today) | `MSM_GET_PARAM` | `0x40` | **14**, 6, **1** |
| 11 | VA_START 0x0e / VA_SIZE 0x0f | `MSM_GET_PARAM` | `0x40` | our IOVA window (the HackiOS tree answers `EINVAL` here; the davinci tree answers both — see §2.6) |
| 12 | every buffer: `msm_bo_new` → `GEM_NEW` | 0x02 | `0x42` | `{size,flags,handle}`, zeroed, **write-combined** |
| 13 | `msm_bo` import of an IOSurface (the EGLImage path) | private `MSM_INFO_IOS_IMPORT` | `0x85` (davinci) / the surface request `0x7e` (HackiOS) | `{surface,handle,…}` → a handle whose memory is the surface's |
| 14 | `fd_bo` info: MSM_INFO_GET_IOVA | `GEM_INFO` 0x03 | `0x43` | `value` = the buffer's IOVA |
| 15 | `mmap` of a buffer (`freedreno_bo.c`, patched) | private `MSM_INFO_IOS_MMAP` 0x80, or `IOConnectMapMemory64(handle)` | `0x43` / — | a VA-aliasing write-combined mapping; a 64 KiB page past the end must still be mapped |
| 16 | `fd_bo_cpu_prep` | `GEM_CPU_PREP` 0x04 | `0x44` | wait for `last`, `MSM_PREP_NOSYNC` honoured |
| 17 | frame: `fd_ringbuffer_flush` → `GEM_SUBMIT` | 0x06 | `0x46` | the struct in §2.1; fence raises atomically; no fd path (`fence_fd` = -1) |
| 18 | fence wait (`fd_pipe_wait`) | `WAIT_FENCE` 0x07 | `0x47` | wait to `timeout`, `queueid` |
| 19 | buffer given back: `GEM_CLOSE` | 0x09 | `0x09` | free, or keep until its fence is done |
| 20 | `GEM_CPU_FINI` 0x05, `SET_PARAM` 0x01 (task name), `GEM_MADVISE` 0x08, `SUBMITQUEUE_CLOSE` 0x0b, `SUBMITQUEUE_QUERY` 0x0c | 0x45/0x41/0x48/0x4b/0x4c | — | may be no-ops, but must return success: `SET_PARAM`, `CPU_FINI`, `SUBMITQUEUE_CLOSE` are called unconditionally |
| 21 | present (ours): hand a fence to the framebuffer | HackiOS `0x7f` (`hakios_show`), davinci `MSM_INFO_IOS_PRESENT{,_IMG,_BO}` 0x81-0x83 | — | not a DRM request at all; whoever shows a surface waits on its fence |

Nothing may be answered `EINVAL` from rows 3-11: a failed `GMEM_SIZE`, `CHIP_ID` or `MAX_FREQ` query
aborts `fd_screen_create` (`freedreno_screen.c:923,955`).

### What I could not get

No A620 hardware read (phone is the other agent's), so every A620 value below is from
`avicii/CONSTANTS.md` or Mesa's table, never from this GPU; no iPhoneOS SDK on this machine, so
nothing was cross-built; and neither public tree contains an A620 target, so `a620_zap`'s load
address, the A620 GMEM IOVA base and the A620 ucode-version gates have **no** public number.

---

## 1 Components and how they connect

### 1.1 Where the pieces sit

```
CoreAnimation (QuartzCore, stock, GLES renderer)
  │  EAGLContext / EAGLSharegroup / CAOpenGLLayer — Apple's API, unchanged
  ├── userland/src/inject.c:1203        dlopen("/redwood/lib/libredwood-gl.dylib") if "RedwoodGPU"
  │                                     (resp. HakiosGPU) matches and boot-arg gl≠0 (inject.c:1178-1206)
  ▼
libredwood-gl.dylib   = eagl.c + gl_osmesa.c + eagl_gen.h, install name /redwood/lib/… (build.sh:344-346)
  │  eagl.c replaces 8 EAGLContext methods by IMP (eagl.c:4055-4064), hands each GL call to the
  │  entry points the table of slots names (eagl_slots.txt), keeps IOSurfaces as textures
  ▼
libOSMesa.8.dylib (15 MB, Mesa 25.0.7, freedreno + softpipe, OSMesa ES profile patch)
  │  glEGLImageTargetTexture2DOES(img = an IOSurface **ID**)   (gl_osmesa.c:100-117)
  │  drm* calls of the libdrm stand-in
  ▼
redwood_drm.c: IOServiceGetMatchingService("RedwoodGPU") → IOServiceOpen → IOConnectCallStructMethod
  │  selector = ioctl number & 0xff, struct in and out, buffers by IOConnectMapMemory64
  ▼
kernel: HakiosGPUUserClient::externalMethod (hakios.gpu.cpp:1078) → bsd/dev/hakios.adreno.c
  │  hakios_gpu_submit / hakios_gpu_map / hakios_gpu_parameter
  ▼
A640: GMU, SMMU context, CP ring, a640_zap, cmdstream from userspace
```

The connection that matters for our port: **the only thing the userland knows about the GPU is what
`GET_PARAM` tells it.** There is no A640 constant in `eagl.c`, `gl_osmesa.c`, the Mesa patch or the
drm shim (`grep` for `640`, `a640`, `0x0604`: none). Device behaviour comes from Mesa's
`freedreno_devices.py`, keyed by the chip id the kernel reports.

### 1.2 The components, one by one

1. **`userland/src/eagl.c`** (4205 lines) — EAGL on Mesa. Replaces `initWithAPI:properties:`,
   `API`, `sharegroup`, `setParameter:to:`, `getMacroContextPrivate`,
   `texImageIOSurface:target:…:invert:`, `attachImage:toCoreSurface:invertedRender:`, `dealloc`
   (`eagl.c:4055-4064`), builds the 409-slot function table (`mkeagl.py` from `eagl_slots.txt`,
   30 of the entries written by hand), and keeps a table of `struct image` (IOSurface, plane, seed,
   `shared`, `mirror`, `out_seed` — `eagl.c:224-253`).
   Deliberate policies, each with a boot-arg to turn it off: draw into a texture of Mesa's own and
   `glBlitFramebuffer` it into the surface at frame end (`glblit`, default on, because
   `EXT_shader_framebuffer_fetch` over surface memory lost parts of frames — `eagl.c:340-347`);
   `IOSurface` memory only when the library can share it *and* the format is plain BGRA at the
   surface's own size (`surface_shared()`, `eagl.c:625-637`); seed compare instead of a copy when
   the surface did not change (`surface_changed()`, `eagl.c:650-672`); `IOSurfaceLock` around CPU
   read/write; the seed bumped by lock/unlock so the display sees a change (`eagl.c:789-792`);
   `glFinish` at frame end unless the display says it waits (`display_waits()`, `eagl.c:4036-4052`,
   read once into `wait_for_frames`, `eagl.c:357`).
2. **`userland/src/gl_osmesa.c`** (33 lines) — the whole "which library" boundary: `redwood_gl_create`
   with an ES2/ES3 OSMesa profile, `make_current`, `destroy`, `library`, and
   `redwood_gl_surface_texture()` which refuses on `softpipe`/`llvmpipe` so the software path falls
   back to copies (`gl_osmesa.c:100-117`).
3. **`userland/src/redwood_gl.h`** (33) — contract only; also the 90 four-character names of
   CoreAnimation's fragment functions (`redwood_gl.h:24-28`).
4. **`tools/mesa/freedreno-darwin.patch`** (365) — meson: if `darwin` and gallium freedreno, use
   `src/redwood-drm` as libdrm and link `-framework IOKit -framework CoreFoundation`
   (patch lines 5-16). `freedreno_bo.c`: no `lseek`, size from the surface descriptor
   (lines 25-31), `redwood_drm_map/unmap` instead of `mmap` (40-60). `msm_bo.c` likewise. `osmesa.c`:
   `osmesa_surface_resource()` builds a `B8G8R8A8_UNORM` 2D resource over the surface and refuses
   anything but `'BGRA'` with 0 planes (lines 320-345). `fd6_draw.cc`: `FD6_WAIT_FOR_ME` flush
   before the first UCHE-reading draw of an overlapping batch (lines 140-160).
5. **`tools/mesa/redwood-drm/xf86drm.h` + `redwood_drm.c`** (76 + 226) — see §2. `drmGetVersion`
   claims `1.7`, `drmGetCap` returns 0, prime/syncobj are `ENOSYS`, `drmPrimeFDToHandle` treats its
   `fd` as an IOSurface ID.
6. **`userland/src/inject.c`** (1273) — the loader/decision side: only loads the GL library when a
   `RedwoodGPU` service exists and `gl≠0`, and feeds the table values into CoreAnimation.
7. **`userland/build.sh`** (830) — `GL=1` runs `tools/mk-mesa.sh`, runs `mkeagl.py`, links
   `libredwood-gl.dylib` against `libOSMesa.8.dylib` with `-framework IOKit -framework IOSurface`
   (lines 326-350) and installs `/redwood/lib/` (472-477); `GL=test` exists because 15 MB + the rest
   does not fit the 64 MB the loader takes (line 54).
8. **`tools/mk-mesa.sh`** (163) — fetches Mesa 25.0.7 (sha256 `592272df…f8a6`), applies
   `tools/mesa/*.patch`, builds `DRIVERS="softpipe,freedreno"` into `libOSMesa.8.dylib` with
   `xnu-deps/host/bin/xnu-clang` and `iPhoneOS16.5.sdk` (lines 1-20, 36-37). Documents that its
   output is not reproducible, only patch-presence in the source tree is.
9. **Kernel side, HackiOS shape**: `hakios.gpu.cpp` (1192) is the user client; every request is a
   `switch` case in `externalMethod` (`:1092-1180`). The A640 hardware work is
   `bsd/dev/hakios.adreno.c` (4188). `MiniIOSurface.{h,cpp}` back the surface request; the
   `HakiosWaitsForGPU` property is set at `MiniIOMobileFramebuffer.cpp:497`.
10. **Kernel side, our own lineage**: `xnu/patches/0113-raphael-gpu-kgsl-drm.patch` (2687) adds the
    same ABI as **`/dev/kgsl-3d0` and `/dev/dri/renderD128` cdevs** with `d_ioctl = drm_ioctl`
    (`0113:2417-2422`), `MSM_PARAM_*` structs declared at `0113:1643-1700`, and it names the
    HackiOS functions it ports ("port of HackiOS RedwoodGPU::submit", `0113:1720`). Our tree already
    has `bsd/dev/sweet_gpu.c` as the file these would live in (`xnu-avicii/patches/0119,0122,0123`),
    so 0113 is the closer template than `hakios.gpu.cpp`.
11. **Metal** — `tools/mesa/air/` (AIR→NIR frontend, 20 files), `userland/src/redwoodmetal.m`,
    `redwooddrawable.m`, `docs/air.md` (4990), `docs/air-report.md`. Not on the boot path in the
    newest job list (`rc.jobs.r39quiet`); out of scope here.

### 1.3 What one composited frame does

`CAOpenGLLayer` → `-[EAGLContext attachImage:toCoreSurface:]` (`eagl.c` `my_attachImage`) → make or
reuse an `image`, `surface_mirrored()` makes a second texture *of the surface's memory* and the frame
is drawn into a private colour texture → draws through the generated table → `glFlush`/
`glBlitFramebuffer` (`frame_end()`, `eagl.c:1027-1060`) pushes the texture into the surface
(`target_to_surface()`), bumps the seed, and either waits (`glFinish`) or trusts the framebuffer to
wait for the submission → the framebuffer driver shows the surface. Every GPU call in that path ends
in `GEM_SUBMIT` (selector 0x46) with the surface's buffer in the BO list, and the display's wait is
`WAIT_FENCE`-equivalent on the returned fence.

---

## 2 The kernel ABI, exactly

### 2.1 The structures (as the kernel declares and accepts them)

`hakios.gpu.cpp:89-154` and `0113:1669-1699`, identical field for field; sizes as the davinci tree
comments them.

```c
struct msm_timespec      { int64_t seconds, nanoseconds; };                          /* 16 */
struct msm_param         { u32 pipe, param; u64 value; u32 len, pad; };              /* 24 */
struct msm_gem_new       { u64 size; u32 flags, handle; };                           /* 16 */
struct msm_gem_info      { u32 handle, info; u64 value; u32 len, pad; };             /* 24 */
struct msm_gem_cpu_prep  { u32 handle, op; struct msm_timespec timeout; };           /* 24 */
struct msm_gem_submit    { u32 flags, fence, nr_bos, nr_cmds; u64 bos, cmds;
                           int32_t fence_fd; u32 queueid; u64 in_syncobjs, out_syncobjs;
                           u32 nr_in_syncobjs, nr_out_syncobjs, syncobj_stride, pad; }/* 72 */
struct msm_gem_submit_bo { u32 flags, handle; u64 presumed; };                       /* 16 */
struct msm_gem_submit_cmd{ u32 type, submit_idx, submit_offset, size, pad, nr_relocs;
                           u64 relocs; };                                            /* 40 */
struct msm_wait_fence    { u32 fence, flags; struct msm_timespec timeout;
                           u32 queueid; };                                           /* 32 */
struct msm_gem_madvise   { u32 handle, madv, retained; };                            /* 12 */
struct msm_submitqueue   { u32 flags, prio, id; };                                   /* 12 */
struct msm_submitqueue_query { u64 data; u32 id, param, len, pad; };                 /* 24 */
struct drm_gem_close     { u32 handle, pad; };                                       /* 8  */
struct redwood/hakios_drm_surface { u32 surface, handle; u64 size;
                           u32 offset, row_bytes, width, height, pixel_format, planes; }/* 40 */
struct hakios_show       { u64 pixels; u32 width, height, rowBytes, pad; };          /* 24 */
```

`msm_submitqueue_query`/`_madvise`/`_bo`/`_cmd` are consumed **by kernel copyin of pointer fields**
(`bos`, `cmds`, `data`, `pixels`), so `IOCPARM_LEN` is whatever Mesa passes, not `sizeof`.

### 2.2 Transport, selector derivation, return mapping

* HackiOS: `IOConnectCallStructMethod(connection, number, data, size, data, &returned)`
  (`redwood_drm.c:56`); `number = request & 0xff` (`:81`); `size = IOCPARM_LEN(request)` — the
  struct `drmCommandWriteRead`/`drmIoctl` were handed. Reply in the same buffer, truncated to the
  input size (`hakios.gpu.cpp:1181-1189`).
* davinci: `d_ioctl(dev, cmd, data)`, `nr = cmd & 0xff`, `typ = (cmd>>8)&0xff` must be the DRM IOC
  type, then `drm_ioctl_locked(nr, data)` (`0113:2400-2410`).
* Shell errors: `kIOReturnNoMemory→ENOMEM`, `BadArgument→EINVAL`, `Timeout→ETIMEDOUT`,
  `Busy→EBUSY`, `NotFound→ENOENT`, `Unsupported→ENOSYS`, else `EIO` (`redwood_drm.c:58-75`).
  `drmIoctl` sets `errno` (`:81-89`). davinci returns `errno` directly.
* No fd is real: one `IOServiceOpen` per process, `drmOpenWithType` hands back `dup(/dev/null)`
  (`redwood_drm.c:26-50`). One GPU, one connection.
* Like-structs are `bzero`d and only `structureInputSize` bytes are taken, so shorter
  (Linux-sized) structs are safe (`hakios.gpu.cpp:1100-1106`); anything larger than the biggest
   member is refused.

### 2.3 The selectors

`hakios.gpu.cpp:71-87`, `0113:1640-1651`. Numbers are Linux's `msm_drm.h`/`drm.h` values through
`DRM_COMMAND_BASE 0x40` (`include/drm-uapi/drm.h:1293`).

| Name | Sel | Handled at | Semantics |
|---|---|---|---|
| `kDrmGemClose` | `0x09` | `hakios.gpu.cpp:1163-1172` / `0113:2272` | free a handle; HackiOS keeps the memory if its fence is not done |
| `kMsmGetParam` | `0x40` | `:1110` / `:2276` | `hakios_gpu_parameter()`; unknown param ⇒ `kIOReturnBadArgument` |
| `kMsmSetParam` | `0x41` | no-op `:1113` | task name |
| `kMsmGemNew` | `0x42` | `gemNew()` `:692-778` | zeroed **write-combined** `IOBufferMemoryDescriptor` (unless boot-arg `gpu_cached=1`), address from the IOVA allocator; one kept buffer of the same size/flags may be handed back instead of making one (`:700-745`) |
| `kMsmGemInfo` | `0x43` | `gemInfo()` `:844-864` | `GET_OFFSET`→`handle<<32`; `GET_IOVA`→`b->address`; `GET_FLAGS`→`b->flags`; `SET_NAME` no-op; anything else unsupported |
| `kMsmGemCpuPrep` | `0x44` | `:1123-1135` | wait until `hakios_gpu_last()` ≤ the client's last submission; `MSM_PREP_NOSYNC` ⇒ patience 0 ⇒ `EBUSY` |
| `kMsmGemCpuFini` | `0x45` | no-op `:1114` | |
| `kMsmGemSubmit` | `0x46` | `submit()` `:867-1031` | see 2.4 |
| `kMsmWaitFence` | `0x47` | `:1139-1151` | `gpuWait(fence, patience)`; 0 timeout ⇒ ETIMEDOUT |
| `kMsmGemMadvise` | `0x48` | `:1152-1154` | `retained = 1` |
| `kMsmSubmitQueueNew` | `0x4a` | `:1155-1157` | `id = ++fNextQueue` |
| `kMsmSubmitQueueClose` | `0x4b` | no-op `:1115` | |
| `kMsmSubmitQueueQuery` | `0x4c` | `:1158-1162` | `copyout` a zero count |
| `kHakiosSurface` | `0x7e` | `surfaceBuffer()` `:780-842` | the surface request, 2.5 |
| `kHakiosShow` | `0x7f` | `show()` `:1034-1056` | `copyin` BGRA pixels, `MiniIOMobileFramebufferShow()` |

`0x80`-`0x85` exist only in the davinci variant, as `MSM_INFO_*` operations: `IOS_MMAP 0x80`
(returns a WC user VA), `IOS_PRESENT 0x81`, `IOS_PRESENT_IMG 0x82`, `IOS_PRESENT_BO 0x83`,
`IOS_IMPORT 0x85` (`0113:1865,2093-2094,2182,1928`).

### 2.4 `GEM_SUBMIT` — the one request with real work

`hakios.gpu.cpp:866-1031`; invariants it enforces:

* `nr_cmds ∈ [1,128]`, `nr_bos ∈ [1,8192]`, `nr_bos == 0` counted from the BO list;
* every `CMD_BUF`'s BO is in the BO list, offset+size inside the buffer, size a multiple of 4;
  the IB words are `copyin`ed into kernel pages and the BO's IOVA is patched in as a qword per
  command so the ring carries `CP_INDIRECT_BUFFER`-style hrefs;
* a BO named `WRITE` gets the submission's fence; a buffer given back before its fence is kept;
* a surface named in the submission whose seed moved (or whose push is older than 4 ms,
  `GPU_PUSH_AGAIN_MS`) is written out of the CPU cache first (`flush`, `:930-1000`);
* relocations are **not** supported: `nr_relocs != 0` is refused (softpin only);
* `MSM_SUBMIT_NO_IMPLICIT` is not inspected (the BO flags are stored on the buffer and honoured for
  `GET_FLAGS`/`GPU_READONLY` only); there is no fence-fd path — `fence_fd` is written **-1**
  (`:962`) and the fence comes back in `request->fence` (`:944`);
* returns `EBUSY` when the ring is full (`hakios_gpu_submit() == 0`).

### 2.5 The surface request (ours; the reason any of this is being ported)

`surfaceBuffer()` (`:780-842`, ported at `0113:1928-2000`):

* input: `surface` = an IOSurface **ID** in the caller's namespace, `handle` = `0xffffffff`
  (`kHakiosDescribe`) to only ask, else 0;
* answer: `size` (rounded to pages, from `allocSize`), `offset`, `rowBytes`, `width`, `height`,
  `pixelFormat`, `planes`, and `handle` — 0 when only describing;
* the buffer's memory starts at **page 1** of the surface (`IOSubMemoryDescriptor::withSubRange(s->memory, PAGE_SIZE, …)`),
  i.e. the surface's shared header is skipped;
* a surface already in this client's table is that buffer again (`:825-833`); the surface is
  retained while the buffer exists;
* surfaces made *around* our own memory (`s->client != NULL`) are refused (`Unsupported`);
* the pixel format must be `'BGRA'` (`0x42475241`) with 0 planes, else `osmesa_surface_resource()`
  refuses (`freedreno-darwin.patch:335`);
* the davinci port adds two hard-won details: the mapping is padded with **128 aliased scratch
  pages** because a GMEM resolve of a 1125-row surface wrote 1 KiB past the last page and SMMU-faulted
  the core for the rest of the boot (`0113:1932-1937`), and the "already imported" lookup is per-PID
  because a handle has no reference count and the window server closing a shared surface unmapped it
  under the application still drawing (`0113:1949-1958`).

### 2.6 `GET_PARAM` — the values, and the whole A620 question

`hakios_gpu_parameter()` (`hakios.adreno.c:3391-3432`), `drm_do_get_param()` (`0113:1700-1712`);
Mesa's enum order is `freedreno_drmif.h:38-50`.

| Param | HackiOS | davinci | A620 must be |
|---|---|---|---|
| 0x01 GPU_ID | 0 | 640 | 0 (chip id says it) |
| 0x02 GMEM_SIZE | `a640 ? 1 MiB : 512 KiB` | `0x100000` | **`0x80000`** |
| 0x03 CHIP_ID | `0x06040001 \| bin<<32` | `0x06040001` | **`0x06020000`** |
| 0x04 MAX_FREQ | `core_khz*1000` | `585000000` | **`625000000`** (`CONSTANTS.md:315`) |
| 0x05 TIMESTAMP | `mach_absolute_time()` | same | same |
| 0x06 GMEM_BASE | `a640 ? 0x100000 : 0` | `0x100000` | **an IOVA, = `UCHE_GMEM_RANGE` base**; must match `KGSL_PROP_UCHE_GMEM_VADDR` |
| 0x07 PRIORITIES | 1 | 1 | 1 |
| 0x08/0x09/0x0a/0x11 | 0 | absent (EINVAL) | 0, must succeed |
| 0x0e/0x0f VA_START/SIZE | absent | the allocator's window | the allocator's window |
| 0x10 HIGHEST_BANK_BIT | `a640 ? 15 : 14` | absent | **14** |
| 0x12 UBWC_SWIZZLE | 6 | absent | 6 |
| 0x13 MACROTILE_MODE | `a640 ? 0 : 1` | absent | 1 |

Mesa asks 0x01→0x02→0x03→0x06 first, then 0x02/0x06/0x04/0x05/0x01/0x03/0x07, then 0x09/0x0a — the
order in the summary table. `GMEM_BASE` and `SUSPENDS` are only asked because the Darwin shim
answers version 1.7; dropping the shim's minor below 3 would remove 0x06 but also softpin.

### 2.7 The mapping

HackiOS: `IOConnectMapMemory64(connection, handle, …)` where the type **is the handle**
(`clientMemoryForType()` `:1058-1075` returns that buffer's descriptor and marks it seen), unmapped
with `IOConnectUnmapMemory64` (`redwood_drm.c:147-171`). The descriptor is already write-combined,
so the mapping needs no cache call. davinci: `mach_make_memory_entry_64` +
`mach_vm_map_external` with `MAP_MEM_WCOMB<<24` over the BO's kernel range (`0113:1875-1912`).

---

## 3 A640 → A620 delta

Grouped by what has to change; every row names where the A640 assumption is and what the A620 value
is. "Same" rows are listed so nobody re-derives them.

### 3.1 Identity and Mesa's table

| Item | A640 (raphael) | A620 (avicii) | Where |
|---|---|---|---|
| Chip id reported | `0x06040001` | **`0x06020000`** | `hakios.adreno.c:3305`, `0113:98`; `avicii/CONSTANTS.md:311` (`lito-gpu.dtsi:67-82`) |
| `gpu_id` | 640 | **620** | `0113:1706`; Mesa `freedreno_devices.py:507` |
| Mesa gen | `a6xx_gen2` (line 608) | **`a6xx_gen1`** (line 511) — gen-dependent cmdstream encoding | `freedreno_devices.py:507-531` vs `605-633` |
| CCU | `num_ccu = 2` (`:609`) | **1** (`:519`) | drives `RB_CCU_CNTL`, `sysmem_per_ccu_*` sums in `fd6_screen.cc:151-155` |
| Tile align | 32×16 (`:610-611`) | same (`:513-514`, 620 does not override the class) | |
| Sysmem CCU cache | 8 KiB/CCU depth, 8 KiB/CCU colour, fraction HALF (`:363-365`) | same — 620 inherits, no override | |
| Magic regs | 640's own set (`:618-632`) | **620's set** (`:520-531`): `TPL1_DBG_ECO_CNTL 0x01008000`, `SP_CHICKEN_BITS 0x400`, `SP_DBG_ECO_CNTL 0x01000000`, `VPC_DBG_ECO_CNTL 0x02000000`, `RB_UNKNOWN_8E01 0x0`, `HLSQ 0x0` | see 3.4 |
| `gmem_base` in the device table | — | — | Mesa takes it from `GET_PARAM`, not the table (`freedreno_screen.c:931`) |

Consequence if the chip id is wrong: `fd_dev_id()` finds no entry, or the wrong one, and every
gen-dependent command is encoded for another GPU. **This is the single highest-risk number in the
port.**

### 3.2 GMEM

| Item | A640 | A620 | Where |
|---|---|---|---|
| GMEM size | 1 MiB | **512 KiB** | `hakios.adreno.c:3404-3406`, `0113:1709`; `CONSTANTS.md:311` + shared brief |
| GMEM base (phys/IOVA) | `0x100000`, `UCHE_GMEM_RANGE 0x100000..0x1fffff` | **`0`..`0x7ffff`** (inferred: same rule, half the range) | `hakios.adreno.c:3401-3403`, `0113:1710,1366` |
| `gmem_sizebytes` in the driver | `0x100000u` | `0x80000u` | `0113:1366` |
| `UCHE_GMEM_VADDR` for Vulkan's KGSL path | `0x100000000` | same VA is a fine choice (gmem VA ≠ gmem phys) — **inferred** | `0113:1418` |
| Bins a frame takes | 66+ command buffers at 512 KiB per the comment | our 512 KiB ceiling is what that comment was measured at; `GPU_SUBMIT_CMDS 128` already covers it | `0113:674` |
| `screen->gmemsize_bytes` | — | 512 KiB feeds `gmem->color_ccu_offset = size - color_cache` (`fd6_screen.cc:180`); a stale 1 MiB overruns the top of GMEM | |

### 3.3 UBWC, bank bit, macrotile

| Item | A640 | A620 | Where |
|---|---|---|---|
| dts `ubwc-mode` | 3 | **3** (same) | `CONSTANTS.md:311` |
| Mesa `ubwc_swizzle` | 6 (class default, not overridden) | **6** (same) | `freedreno_devices.py:137` |
| `highest_bank_bit` | **15** (`:616`) — also the class default `:136` | **14** per the dts, but Mesa's 620 block does **not** override it and so carries **15** | `CONSTANTS.md:311`; `freedreno_devices.py:507-531` |
| `macrotile_mode` | 0 (`:617`) | **1** (class default `:137`, not overridden) | |

⚠ **Conflict.** `CONSTANTS.md:311` records `highest-bank-bit 14` for `lito`; Mesa 25.0.7 gives
GPUId(620) the inherited 15. Gallium never reads `MSM_PARAM_HIGHEST_BANK_BIT` (Vulkan's
`tu_drm_get_highest_bank_bit()` does, `tu_knl_drm_msm.cc:140`), so for the GLES path the value that
wins is Mesa's **15**, and the kernel param is decorative. On Linux+kgsl the same 620 would get the
dts 14 unless `ADRENO_QUIRK_...` says otherwise. If UBWC tiles come out with vertical stripes, this
is the first thing to try both ways — **UNVERIFIED** which is right for this silicon.

### 3.4 Register init the kernel performs (a660-shaped fallbacks)

The raphael driver is written as `a640 ? A640 : <other>` and the "other" side is **a650/a660**, not
A620 — the comment says `-sc7280.c` (`hakios.adreno.c:287`) and the fw names are `a660_*`. A620 is
`a6xx_gen1`; several of these values belong to gen3. From `hakios.adreno.c`:

| Line | Register / item | written on `!a640` | A620/gen1 wants |
|---|---|---|---|
| 2870-2871 | `rb_nc_mode_cntl` | `1<<11\|1<<4\|1<<1` | check |
| 2872 | `tpl1_nc_mode_cntl` | `1<<1` | check |
| 2873 | `sp_nc_mode_cntl` | `2<<4\|1<<1` | check |
| 2874 | `uche_mode_cntl` | `1<<21` | check |
| 2878 | `uche_client_pf` | `1<<7\|1` | Mesa 620 `UCHE_CLIENT_PF 0x4` (`:526`) |
| 2881-2883 | `cp_apriv_cntl` | written | gen3+ register; harmless or wrong on gen1 — check |
| 2884 | `rb_dbg_eco_cntl` | `0x04100000` | **matches** Mesa 620 (`:529`) |
| 3394-3399, 3419-3427 | param values | see 2.6 | 14 / 1 |

Read the Mesa table for 620 (`freedreno_devices.py:520-531`) as the authority on the magic set;
`RB_DBG_ECO_CNTL` for 620 and 640 are *both* `0x04100000`, so the `a640 ? 0 : 0x04100000` split on
that one register is a coincidence of the 640 entry, not a gen fact.

### 3.5 Firmware, GMU, clocks

| Item | A640 | A620 | Where |
|---|---|---|---|
| zap | `a640_zap.mdt/.b02` | **`a620_zap.*`**, PAS id 13, TZ-loaded | `hakios.adreno.c:1677,2778`; `CONSTANTS.md:314,321` |
| GMU fw | `a640_gmu.bin` | **`a650_gmu.bin`** (41548 B) — A650-family, core version `0x20010008` | `hakios.adreno.c:1789`; `CONSTANTS.md:321-323` |
| SQE fw | `a630_sqe.fw` | **`a650_sqe.fw`** (31632 B) | `hakios.adreno.c:2692`; `CONSTANTS.md:321` |
| GMU DTCM | `0x00040000` | **`0x10004000`** | `hakios.adreno.c:1738`; `CONSTANTS.md:323` |
| GMU chip id (register the firmware reads) | `0x06040100` | `0x06030500` in the code, comment "dt qcom,chipid 0x06030500 the way the firmware wants it", while our dts and Mesa say GPU chip id `0x06020000` — **which `a650_gmu.bin` accepts is UNVERIFIED** | `hakios.adreno.c:1927` |
| GMU up test | `== 0xbabeface` | `FW_INIT_RESULT[8:0] == 0x100` | `hakios.adreno.c:1936,1964-2036`; `CONSTANTS.md:323` |
| RSCC | GMU+0x23000 | own block `0x3de0000`, sequencer program in CONSTANTS | `CONSTANTS.md:322` |
| PDC | in AOP | host-programmed, TCS3 cx vote 2 | `CONSTANTS.md:323` |
| Speed table | 257/345/427/585/765 MHz | **275/400/500/625** (bin 0) | `hakios.adreno.c:2393-2397` vs `CONSTANTS.md:315,327`; the `!a640` arm uses 315/450/550 — **not** lito's set |
| `perf.gpu_levels` | array size | 4 (`:2411`) — cuts the 625/765 entries off | |
| GPUCC/GCC offsets, debug muxes, cmd-db, SMMU stream mask, ACTLR | sm8150 values (`:290,300,490,714-734,1451`) | lito values in `CONSTANTS.md:316-319,325-326` | see 3.4 note: the `a640?` split exists but the `!a640` side is sc7280 for several of these |

### 3.6 Userland-visible names and paths

| Item | Value in both public trees | Our choice |
|---|---|---|
| IOKit service | `RedwoodGPU` (`redwood_drm.c:19`) / `HakiosGPU` (`hakios.gpu.cpp:71` driver name, `hakios.drm.c`) | e.g. `AviciiGPU`, and `inject.c:1192` must match (`IOServiceMatching`) |
| Registry property the display sets | `RedwoodWaitsForGPU` / `HakiosWaitsForGPU` (`eagl.c:4045`) | ours, published by `SweetFramebuffer.cpp` |
| Install names | `/redwood/lib/libredwood-gl.dylib`, `/redwood/lib/libOSMesa.8.dylib`, `/redwood/bin/*` | ours; `inject.c:56` has the path |
| Boot-args | `gl`, `glcopy`, `glblit`, `glwait`, `glsync`, `glfetch`, `glskip`, `gpu_keep`, `gpu_cached` | keep the names, or the diagnostics in `eagl.c` become useless |

Nothing else in the userland is A640-specific: `eagl.c`, `gl_osmesa.c`, the Mesa patch and the drm
shim contain no 640 constant.

---

## 4 Licences and Apple-derived provenance

### 4.1 Licences that apply

| Material | Licence | Citation |
|---|---|---|
| `hackios-xnu-userland` (all of it, including `eagl.c`, `redwood_drm.c`, `xf86drm.h`, `mkeagl.py`, `build.sh`) | **MIT**, © 2026 OOSEX GANG; third-party parts keep their own | `LICENSE:1-26` (`:22-25` says Mesa/apfsprogs/Procursus are fetched, not in the repo) |
| `hackios-xnu-kernel` split | **APSL 2.0** for `xnu/hakios.patch` + `xnu/files/**` (a derivative of XNU), **MIT** for `userland/src/**`, `tools/`, `devices/` | `LICENSE:1-13`; `COMPLIANCE.md:7-27`; `LEGAL.md:16-18` |
| The drm shim specifically | MIT (Linux / X.Org), listed as a build-time shim | `THIRD_PARTY_LICENSES.md:17` |
| Mesa (not in either repo) | MIT and others; fetched by `tools/mk-mesa.sh:37` from a pinned sha256 | `THIRD_PARTY_LICENSES.md:36`; `README.md:53-55` |
| apfsprogs, Procursus/Sileo, lzfse, ath11k/LinuxKPI, Mu-Silicium, vendor UEFI blobs | GPL-2.0 / various / BSD / BSD-2-Clause-Patent / vendor | `NOTICE`, `THIRD_PARTY_LICENSES.md:13-36` |
| `marnov999-raphael-ios-gpu` (our lineage) | base MIT (dipa-studio/ios-sweet), their own patches; `CREDITS.md` + `LICENSE` present | ref root |

Practical reading: **everything we would take is MIT or APSL-compatible**, and MIT obliges only
notice retention. The kernel user client, if written into `bsd/dev/*` next to our APSL-licensed XNU
patches, should keep the file's MIT notice to stay separable (`COMPLIANCE.md:20` says added files
carry their own notices).

### 4.2 Apple-derived material, and how far it is "code"

| Item | What it is | Fits our no-decompiled-code rule? |
|---|---|---|
| `eagl_slots.txt` (409 offsets) | offsets into a table Apple's `OpenGLES.framework` hands out via `-[EAGLContext getMacroContextPrivate]`, each with the calling function read off the binary (`eagl_slots.txt:1-4`) | **as data, yes** — it is a table of integers and symbol names, not disassembly. Says so itself: "read off their code". |
| Selector names `texImageIOSurface:target:internalFormat:width:height:format:type:plane:invert:`, `attachImage:toCoreSurface:invertedRender:`, `initWithAPI:properties:` | Objective-C selector strings, visible in any Objective-C runtime | yes — strings |
| `EAGLContext`/`EAGLSharegroup` semantics, `CAOpenGLLayer` interaction | interface behaviour | yes — described in our own words |
| `IOSurface` API used (`IOSurfaceLock`, `IOSurfaceGetSeed`, `IOSurfaceGetID`, `…GetBaseAddress`) | Apple's public framework headers | yes — public API |
| Apple's `IOGLBundle`/`OpenGLES.framework` code itself | never vendored; replaced wholesale by Mesa | — |
| `MiniIOSurface` / `SweetSurface` | our own stand-ins for the closed `IOSurface` kext | yes — written, not extracted |
| The 90 four-character CA function names | CoreAnimation's shader names, from the binary or from public dumps | yes — strings |

So the report and the port stay on the right side of the rule as long as the offset table is carried
as a data file and no XNU/Apple `.c` is pasted in.

---

## 5 Gaps — what does not exist anywhere and must be written

Ordered by what blocks the most.

1. **The layer-5 uAPI does not exist in `ios-nord` at all.** `xnu-avicii/patches/0119,0122,0123` are
   probe/GMU/CP only, all in `bsd/dev/sweet_gpu.c`, with no user client and no `IOUserClient`
   anywhere (`grep IOUserClient xnu-avicii/patches`: none). ~1200 lines equivalent
   (`hakios.gpu.cpp`) or ~800 (`0113:1640-2430`) of new kernel code. **L**
2. **Decision, then work: cdev or IOKit.** Our tree's file is `sweet_gpu.c` and the in-repo
   reference does it as `/dev/dri/renderD128` + `/dev/kgsl-3d0` cdevsw (`0113:2417`), which needs no
   IOKit class, no `clientMemoryForType`, and keeps `redwood_drm.c`'s `drmIoctl` shape nearly
   intact (it becomes a real `ioctl(2)` instead of `IOConnectCallStructMethod`). Choosing the
   IOKit shape instead means porting the class, a plist match, and the mapping path. **S** to decide,
   then 1 is cheaper the cdev way.
3. **The A620 never appears in either tree.** Every `a640 ?` (79 matches of `grep -c a640` in
   `hakios.adreno.c`, 11 in `0113`) needs an A620 arm, and the `!a640` arms are a660/sc7280 values (§3.4-3.5). Also
   `GPU_CHIP_ID`, `gmem_sizebytes`, the kmsg strings. **L**
4. **A620 numbers with no public source:** `a620_zap`'s load address (A640 `0x98f15000`,
   `hakios.adreno.c:2748`; the `!a640` `0x8b71a000` is a660's), the A620 GMEM IOVA base (must match
   `UCHE_GMEM_RANGE` and `KGSL_PROP_UCHE_GMEM_VADDR`), and whether `GMPU`/APRIV/`pc_power_cntl`
   needs the gen1 treatment. Must be measured on the phone. **M**
5. **The surface import in *our* kernel.** HackiOS reads `MiniIOSurface` structs directly
   (`surfaceBuffer()` `:780-842`); our stand-in is `SweetSurface.cpp` with a different shape, and our
   `SweetFramebuffer` publishes the panel as a surface. The request, the per-PID "already imported"
   lookup and the 128-page scratch pad (§2.5) have to be rebuilt on our structures. **M**
6. **Present + the wait contract.** `MiniIOMobileFramebufferShow()` and the
   `HakiosWaitsForGPU` property (`MiniIOMobileFramebuffer.cpp:497`) have no counterpart: nothing in
   `avicii/` publishes a property, and `SweetFramebuffer.cpp` needs to (a) set it, (b) wait on the
   surface's last fence on its own thread before scanning out. Without (b) `eagl.c` falls back to
   `glFinish` per frame — correct but serialised, which is the 24 fps problem again. **M**
7. **Toolchain and SDK.** `GL=1` needs theos + `iPhoneOS16.5.sdk` and `xnu-deps/host/bin/xnu-clang`
   (`mk-mesa.sh:36-37`); this machine has `tooling/opt/llvm` (host) and no `iPhoneOS*.sdk`
   (`find / -name 'iPhoneOS1*.sdk'`: none), and `prebuilt/userland/SHA256SUMS` carries no `-gl`
   library, so nothing prebuilt can stand in. 15 MB library + 64 MB loader budget
   (`build.sh:54`) is a sizing constraint too. **M, blocking anything userland**
8. **Mesa's 620 entry has the `highest_bank_bit` conflict** of §3.3 and no `ubwc_swizzle`/
   `macrotile_mode` override. If the fields turn out wrong for this silicon, it is a one-line local
   Mesa patch (`tools/mesa/ir3-*` style) — but nothing in the public trees says which way. **S**
9. **`EXT_shader_framebuffer_fetch` on gen1.** `eagl.c`'s whole blit strategy exists because
   framebuffer fetch over surface memory lost frame content (`eagl.c:340-347`); whether a620 supports
   the extension the same way is **UNVERIFIED**. Ship with `blit_targets = 1` (default) and only then
   measure. **S**
10. **Panel vs render geometry.** iOS draws 1125×2436, the panel is 1080×2400; `surface_shared()`
    requires the texture and surface to be the same size (`eagl.c:629-631`), so the stand-in
    framebuffer has to scale or the surfaces have to be the drawn size. Nothing in either tree
    handles a mismatch. **M**
11. **`IOSurface` semantics we do not have.** `IOSurfaceGetSeed`, `IOSurfaceLock` bumping the seed,
    `IOSurfaceGetID` stability across processes and `IOSurfaceLookup` by id: `SweetSurface` must give
    all four or `surface_changed()`/`surface_to_texture()` see no change and frames freeze. **S/M**
12. **Licence bookkeeping.** MIT notices for `eagl.c`, `redwood_drm.c`, `xf86drm.h`, `mkeagl.py`,
    the slot table; a `THIRD_PARTY` line for Mesa; keep APSL files separable. **S**
13. **Not needed now:** Metal/AIR (`tools/mesa/air/`, `redwoodmetal.m`) — the project itself moved it
    off the boot path; and Vulkan/turnip, which the KGSL half of `0113` serves but nothing in our
    plan uses.

---

### Appendix — commands used, and where the raw output is

`git clone --depth 50 …` ×2 (both `rc=0`), `git rev-parse HEAD` (hashes in the header and in
`~/.hermes/cache/scratch/lane-b-hackios/commits.txt`), `git show --stat 8a3135e`, `find`,
`grep -n`/`wc -l` over both clones, `diff -u` of the two `eagl.c`/`redwood_drm.c`/`freedreno-darwin.patch`
(rename-only, counts recorded: 178 lines of `eagl.c` diff, all `redwood→hakios`), and `sed -n` reads
of the Mesa 25.0.7 tree that lane C unpacked. No build, no phone, no `git add`.
