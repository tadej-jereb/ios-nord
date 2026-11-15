# F — the libdrm stand-in and the freedreno-darwin draft patches, against 0126

Lane 3, round 3. Owns this file and `tooling/gpu/mesa-patches/*.patch` (new; plain patches against
Mesa 25.0.7, applied nowhere in the repo). Everything below was run on this host; nothing touched the
phone, the kernel tree or CI. Scratch: `~/.hermes/cache/scratch/lane-3/` (pristine 25.0.7 copy,
patched copy, `out/`, an overlay of the SDK headers lane 1's sysroot is missing for the compile
check). Guesses are marked **inferred**.

## Summary

- The whole libdrm surface freedreno uses is 14 functions (plus two more that only unbuilt paths
  reference); all of it is in one stand-in header and one source file
  (`src/freedreno/drm/darwin/`), calling `ioctl(2)` on `/dev/dri/renderD128`. Nothing modesets, no
  `drmMode*`, no event loop, no fence or buffer descriptors.
- The direction gotcha is the core of it: every request is re-encoded with XNU's `ioccom` bits, and
  the five pure-`_IOW` requests (`GEM_CLOSE`, `GEM_CPU_PREP`, `WAIT_FENCE`, `SUBMITQUEUE_CLOSE`,
  `SUBMITQUEUE_QUERY`) go out as XNU `_IOW` (IOC_IN) so XNU copies them in. §1 has the table.
- Buffers are mapped by the kernel (`MSM_INFO_IOS_MMAP`, 0x80) and unmapped with
  `mach_vm_deallocate`; an imported IOSurface is never mapped twice — its own mapping serves the CPU
  side (§2).
- An IOSurface becomes an `fd_bo` through `MSM_INFO_IOS_IMPORT` (0x85) and a `pipe_resource` through
  `resource_from_handle` with `WINSYS_HANDLE_TYPE_FD`, the ID as the handle, `'BGRA'` only (§3).
- Six patches, 18 files (2 new), +726/−9: the build wiring, the stand-in, the drm-layer changes,
  the remaining Linux-isms, the OSMesa screen/texture glue, and HackiOS's a6xx fb-read barrier.
- All six apply cleanly to a pristine 25.0.7 (`patch -p1 --dry-run`, then a real apply that
  reproduces the patched tree byte-identically).
- With lane 1's sysroot: **13/13** files of `src/freedreno/drm/` compile `-fsyntax-only` for
  `arm64-apple-ios16.0`, `__APPLE__` defined, no diagnostics.
- Untested: a real compile of the Gallium driver files (blocked on generated NIR/glsl headers),
  linking, meson configure, and every run-time path — nothing here has ever executed on the phone.

## 1. What the kernel answers, and what the shim must therefore do

The contract is `xnu-avicii/patches/0126-avicii-gpu-kgsl-drm-uapi.patch`. Read as a uAPI:

| nr | request | struct (0126 size) | Linux direction | 0126 | shim must encode |
|---|---|---|---|---|---|
| 0x00 | VERSION | `drm_version` 64 (`:1537`) | `_IOWR` | `:1961` | `_IOWR` |
| 0x0c | GET_CAP | `drm_get_cap` 16 | `_IOWR` | `:1973-1976`, value 0 for all | `_IOWR` |
| 0x09 | GEM_CLOSE | `drm_gem_close` 8 | `_IOW` | `:1978` | **`_IOW` → IOC_IN** |
| 0x40 | GET_PARAM | `drm_msm_param` 24 | `_IOWR` | `:1982` (params `:1573-1599`) | `_IOWR` |
| 0x41 | SET_PARAM | `drm_msm_param` 24 | `_IOW` | **not implemented** → ENOTTY | `_IOW` |
| 0x42 | GEM_NEW | `drm_msm_gem_new` 16 | `_IOWR` | `:1990` | `_IOWR` |
| 0x43 | GEM_INFO | `drm_msm_gem_info` 24 | `_IOWR` | `:1997`, private ops `:2000/:2006/:2018` | `_IOWR` |
| 0x44 | GEM_CPU_PREP | `drm_msm_gem_cpu_prep` 24 | `_IOW` | `:2028` | **`_IOW` → IOC_IN** |
| 0x46 | GEM_SUBMIT | `drm_msm_gem_submit` 72 | `_IOWR` | `:2046` | `_IOWR` |
| 0x47 | WAIT_FENCE | `drm_msm_wait_fence` 32 | `_IOW` | `:2054` | **`_IOW` → IOC_IN** |
| 0x48 | GEM_MADVISE | `drm_msm_gem_madvise` 12 | `_IOWR` | `:2062`, retained=1 | `_IOWR` |
| 0x4a | SUBMITQUEUE_NEW | `drm_msm_submitqueue` 12 | `_IOWR` | `:2071` | `_IOWR` |
| 0x4b | SUBMITQUEUE_CLOSE | `__u32` 4 | `_IOW` | `:2076` returns 0 | **`_IOW` → IOC_IN** |
| 0x4c | SUBMITQUEUE_QUERY | `drm_msm_submitqueue_query` 32 | `_IOW` | `:2077` returns 0 | **`_IOW` → IOC_IN** |
| 0x0a / 0x0b | GEM_FLINK / GEM_OPEN | — / 32 | `_IOWR` | **not implemented** → ENOTTY | `_IOWR` |

Anything else returns ENOTTY (`:2079-2080`) and prints a line. The kernel dispatches on the number
byte alone (`drm_ioctl()`, `:2085-2088`), so the length and direction fields are the caller's
business — which is exactly what the banner at `:1500-1505` and the note at `:2029-2033` hand to this lane.

Why it matters, from XNU itself: `_IOW` is `_IOC(IOC_IN,…)` and IOC_IN is `0x80000000`
(`~/xnu-8796.141.3/bsd/sys/ioccom.h:83,85,95`); Linux's `_IOW` is `0x40000000` = XNU IOC_OUT; and
`ioctl()` copies in only for IOC_IN, **zeroing** the buffer for IOC_OUT
(`~/xnu-8796.141.3/bsd/kern/sys_generic.c:888-907`). Sent as Linux's, `GEM_CLOSE` would close handle
0, `WAIT_FENCE` would wait for the last submission instead of the asked one. The kernel compensates
for the zeroing (`:2029-2035`, `:2056`) but only by waiting for everything.

`IOCPARM_MAX` is `0x2000` (`ioccom.h:79`); the largest struct here is 72 bytes, and XNU keeps the
argument on the stack below its 8 KiB `stkbuf`, so no kalloc path is involved.

### Function table

All call sites are in Mesa 25.0.7; "built" means the file is compiled in lane C's configuration
(`-Dgallium-drivers=softpipe,freedreno -Dfreedreno-kmds=msm`, no EGL/GLX/GBM/DRI, no Vulkan).

| function | call site(s) | verdict | how |
|---|---|---|---|
| `drmOpenWithType` | `freedreno_device.c:148` (built) | implement | `open("/dev/dri/renderD128", O_RDWR\|O_CLOEXEC)`; `name` must be `"msm"` else ENODEV |
| `drmIoctl` | `freedreno_bo.c:108`, `msm_device.c:63` (built) | implement | `ioctl(2)`, retried on EINTR; `-1`/errno. Also the one place GEM_CLOSE drops an import's surface |
| `drmCommandWrite` | `msm_bo.c:60,118,131,148`, `msm_pipe.c:131,194` (built) | implement | builds `_IOC(IOC_IN,'d',0x40+nr,len)`; returns `-errno` (libdrm's convention, which `msm_pipe_wait` compares against `-ETIMEDOUT`) |
| `drmCommandWriteRead` | `msm_bo.c:27,77,93,190`, `msm_pipe.c:25,46,158`, `msm_ringbuffer_sp.c:132`, `msm_device.c:58` (built) | implement | `_IOC(IOC_INOUT,…)`; same return convention |
| `drmGetVersion` | `freedreno_device.c:39` (built) | implement, with a fake fallback | VERSION ioctl against the 64-byte `drm_version`; if it fails (older image) says `msm 1.7`. **Minor clamped to 7**: 8 would claim cached-coherent memory that 0126 only carries as a flag, 9+ the suspend/VA counters |
| `drmFreeVersion` | `freedreno_device.c:76` | implement | free the three strings and the struct |
| `drmGetCap` | `freedreno_device.c:237` (built) | implement | GET_CAP; the kernel answers 0 for every capability (`:1973-1976`), so `fd_has_syncobj()` is false (`freedreno_device.c:237-240`) and the whole syncobj path stays off |
| `drmPrimeFDToHandle` | `freedreno_bo.c:223` (built) | implement | GEM_INFO + `MSM_INFO_IOS_IMPORT`, the argument is an **IOSurface ID**, not an fd |
| `drmPrimeHandleToFD` | `freedreno_bo.c:555` (built) | implement for imports, `ENOSYS` otherwise | an imported buffer answers with its surface ID again; a buffer of Mesa's own has no descriptor to give |
| `drmSyncobjCreate/Destroy/Reset/FDToHandle/HandleToFD/ImportSyncFile/ExportSyncFile` | `freedreno_fence.c:108,199,244,256,372` (all built, all under `fence->syncobj`) | fake `ENOSYS` | never reached while `has_syncobj` is false; they exist for the linker. `PIPE_FD_TYPE_NATIVE_SYNC` (`:191`) uses `os_dupfd_cloexec`, no drm call |
| `drmGetVersion`/`drmGetCap` in `src/gallium/auxiliary/util/u_screen.c:139` | guarded by `HAVE_LIBDRM && (LINUX\|BSD\|MANAGARM)` | out of scope | `HAVE_LIBDRM` is left **undefined** on Darwin, as HackiOS does, so `DRM_CAP_PRIME`/`caps->dmabuf` is never asked (only VDPAU interop reads that cap: `st_vdpau.c:219`) |
| `src/loader/loader.c` | built (`src/meson.build:50`) | none needed | it includes `util/libdrm.h`, which *without* `HAVE_LIBDRM` is Mesa's own no-op inline shim (`util/libdrm.h:30-…`), so `drmGetDevices2`/`drmGetDevice2`/`drmGetDeviceNameFromFd2`/`drmFreeDevices`/`drmFreeDevice` never reach us |
| `drmMode*`, `drmHandleEvent`, `drmAuthMagic`, `drmGetMagic`, `drmIsKMS`, `drmDevicesEqual` | KMS/Vulkan-WSI only | not needed | scanout is `IOMobileFramebuffer`; no Vulkan, no DRI3 |
| `src/freedreno/decode/replay.c:424` | `-Dtools=` empty | not needed | — |

Headers: the only DRM header the built path needs is `<xf86drm.h>` (`freedreno_priv.h:21`); the
structs and `DRM_FORMAT_MOD_*` come from the in-tree `drm-uapi/{drm,msm_drm,drm_fourcc}.h`, which
Mesa ships under MIT. The stand-in supplies `xf86drm.h` and nothing else; `drm-uapi/drm.h:39-48`
already has a non-Linux branch that includes `<sys/ioccom.h>` and typedefs `__u32` &co., so the BSD
path is the one taken and no Apple header is included by the stand-in.

## 2. Mapping a buffer: `MSM_INFO_IOS_MMAP`

`fd_bo_map_os_mmap` (`freedreno_bo.c:613`) is `os_mmap(0, size, …, MAP_SHARED, dev->fd, offset)`.
XNU's `d_mmap` on the render node exists (`0126:2112`) but the offset token route is not what 0126
offers as the interface; `MSM_INFO_IOS_MMAP` is (`:1731-1735`, `:2018-2024`): GEM_INFO with
`handle` in, and the user address of a write-combined mapping made with
`mach_make_memory_entry_64`+`mach_vm_map_external` in `gi->value` out. Imported surface buffers have
`cva == 0` (`:1877`) and therefore cannot be mapped this way (`drm_do_gem_mmap` returns EINVAL,
`:1759`) — their mapping is the surface's own.

The change (patch 0003): `msm_bo.c` gets its own `.map`, which returns
`drm_msm_ios_surface_base()` for a buffer with `from_surface`, else calls `drm_msm_ios_mmap()`
(GEM_INFO 0x80) and sets `fd_bo.map_owned` when that worked. `fd_bo_fini_common` (`freedreno_bo.c:477`)
then unmaps only what is ours:

```c
   if (bo->map) {
#if defined(__APPLE__)
      if (bo->map_owned)                       /* not a block's, not a surface's */
         drm_msm_ios_munmap(bo->map, bo->size);
#else
      os_munmap(bo->map, bo->size);
#endif
   }
```

`map_owned` also fixes the Linux side's silent no-op: a suballocated buffer's `bo->map` is its
block's base plus an unaligned offset (`freedreno_bo_heap.c:251`) and `munmap` of that fails, while
`mach_vm_deallocate` of it would fail too and, worse, must not take the block's pages.
`drm_msm_ios_munmap` rounds up to 4 KiB (the kernel's `PAGE_SIZE`) and drives
`mach_vm_deallocate(mach_task_self(), …)`; suballocated and imported buffers keep `map_owned == false`.

`offset` (`msm_bo.c:12-37`, GEM_INFO 0x00 → `id << 12`, `:2017`) stays as it is: it is still what
`fd_bo_offset()` answers for softpin, just no longer a slice into an `mmap` of the device.

## 3. IOSurface → `fd_bo` → `pipe_resource`

Kernel side (`:1812-1897`): GEM_INFO, `info = MSM_INFO_IOS_IMPORT` (0x85), the surface **ID** in
`value`, a GEM handle back in `handle`; pages are imported once per (surface, pid) — a repeat import
of the same surface by the same process gives the same handle back (`:1826-1834`); a wrapped surface
must sit on a 4 KiB boundary (`:2400`), and 128 scratch pages follow the buffer so a GMEM resolve
overshooting the last row lands somewhere (`:1805-1811`).

Mesa side, and where each number comes from:

1. `fd_resource_from_handle()` (`freedreno_resource.c:1505`) reads `handle->stride` (`:1535`),
   `handle->offset` (`:1536`) and `handle->modifier`, then `fd_screen_bo_from_handle()`
   (`freedreno_screen.c:843`) → `fd_bo_from_dmabuf()` → `drmPrimeFDToHandle()`.
2. `freedreno_bo.c:243-256` cannot `lseek()` an ID, so the size is asked of the surface:
   `drm_msm_ios_surface_info()` returns `IOSurfaceGetAllocSize` and the row length; the platform
   holds the surface for the buffer (`fd_msm_surface_attach`), `drmPrimeFDToHandle` takes its own
   lookup reference and `GEM_CLOSE` drops it.
3. The winsys handle is filled by the front end that has the surface at hand (OSMesa,
   patch 0005): `type = WINSYS_HANDLE_TYPE_FD`, `handle = surface`, `stride = IOSurfaceGetBytesPerRow`,
   `offset = 0` (the kernel imports from page 0 of the surface's memory), `size = allocSize`,
   `modifier = DRM_FORMAT_MOD_LINEAR` (set by `fd_resource_modifier()` from a tile_mode of 0 —
   CA surfaces are linear, `A-quartzcore` §“fmt 0x42475241 bpr 4608 1125x2436”).
4. Template: `PIPE_TEXTURE_2D`, `PIPE_FORMAT_B8G8R8A8_UNORM`, `bind = SAMPLER_VIEW | RENDER_TARGET`.
   `'BGRA'` = `0x42475241`, the only format iOS surfaces arrive in; anything else is refused rather
   than guessed.
5. Nothing is copied: the import maps the same pages the surface owns, so presenting the surface and
   drawing into it are the same memory. Whether the compositor's own `IOSurfaceClientBindAccel`
   (selector 0xc, `A-quartzcore` §2) is still needed *in addition* is open (question 2).

## 4. The 14 Linux-isms

Item numbers are lane C's (`docs/gpu-research/C-mesa-darwin-build.md` §3). "HackiOS" is the same hunk
in their patch (`refs/gsjsjzhznsz-hackios-xnu-userland/tools/mesa/freedreno-darwin.patch`).

| # | where | Darwin replacement | patch |
|---|---|---|---|
| 1 | `meson.build:1717` (`dep_libdrm = null_dep`, no `-I`, no `-l`) | on darwin+gallium_freedreno a `declare_dependency` with `-Isrc/freedreno/drm/darwin` and `-framework IOSurface -framework CoreFoundation`; `HAVE_LIBDRM` stays undefined | 0001 |
| 2 | `src/freedreno/meson.build:25` (`subdir('drm')` under `system_has_kms_drm`) | `or host_machine.system() == 'darwin'` | 0001 |
| 3 | `src/freedreno/drm/meson.build:76` (`link_with : [libvdrm]`) | `freedreno_kmds.contains('virtio') ? [libvdrm] : []`; the stand-in's source is added on darwin | 0001 |
| 4 | `freedreno_bo.c:249` (`lseek` for the import size) | `drm_msm_ios_surface_info()`/`fd_msm_surface_size()` | 0003 |
| 5 | `freedreno_bo.c:613,621` (`os_mmap` of the device) | `msm_bo_map()` → GEM_INFO `MSM_INFO_IOS_MMAP` / the surface's own base | 0003 |
| 6 | `freedreno_bo.c:477` (`os_munmap`) | `drm_msm_ios_munmap()` behind `map_owned`, as in §2 | 0003 |
| 7 | `msm_priv.h:176` (`CLOCK_MONOTONIC` for the waits) | `CLOCK_MONOTONIC_RAW` — the clock `mach_continuous_time()` is, which the kernel reads against (`:1714-1716`) | 0003 |
| 8 | `freedreno_screen.c:28,1007-1008` (`<sys/sysinfo.h>`, `sysinfo()`) | the include guarded out; `os_get_total_physical_memory()` clamped to `UINT32_MAX` (util has an Apple branch, `os_misc.c:432`) | 0004 |
| 9 | `ir3_disk_cache.c:33-56` (ELF build-id note) | return early: `util/build_id.h` is entirely inside `HAVE_DL_ITERATE_PHDR`, so the note is an incomplete type here | 0004 |
| 10 | `frontends/osmesa/osmesa.c:165` (`get_egl_image = NULL`) | `get_egl_image`/`validate_egl_image` callbacks, the "image" being a surface ID | 0005 |
| 11 | `targets/osmesa/meson.build:41` (links swrast only) | `driver_freedreno, idep_xmlconfig, dep_libdrm` added | 0005 |
| 12 | `targets/osmesa/osmesa_target.c:37-40` (null winsys only) | `osmesa_create_gpu_screen()` → `drmOpenWithType("msm", NULL, DRM_NODE_RENDER)` → `fd_drm_screen_create_renderonly()` with `OSMESA_SOFTWARE` opt-out, softpipe fallback | 0005 |
| 13 | `a6xx/fd6_draw.cc:445` (fb-read needs a CCU/UCHE flush) | `FD6_FLUSH_CCU_COLOR \| FD6_INVALIDATE_CACHE` on the first fb-reading draw after a non-reading one (`freedreno_batch.h` gains `prev_draw_read_fb`) | 0006 |
| 14 | the stand-in itself must not need libdrm | it needs only `<xf86drm.h>`; the IOSurface functions are declared in that header by hand, so no Apple header is included for them (only `<mach/mach_init.h>`/`<mach/mach_vm.h>`, for the unmap) | 0002 |

Also present, and not in either public patch: `freedreno_util.h:98` takes `<sys/syscall.h>` and
`SYS_gettid` for the debug log — on Apple the thread port is the same information, so `FD_THREAD_ID`
becomes `pthread_mach_thread_np(pthread_self())` (patch 0004). `sys/syscall.h` is in the SDK but lane
1's sysroot extract has neither it nor `SYS_gettid` (inferred that the SDK's has the macro).

`eventfd`, `futex`, `memfd`, `sync_file`, `linux/*.h` appear nowhere in the compiled path — the grep
of lane C is confirmed: the only hits in 25.0.7 are under `src/freedreno/vulkan/` (not built).

Not changed, deliberately: `MSM_INFO_SET_NAME`/`SET_METADATA`/`GET_METADATA` (`msm_bo.c:101-155`) are
EINVAL on 0126 (`:2025`). `set_name` ignores it, `set_metadata` logs once per call site, and `fd_bo`
metadata is only the modifier hint for a scanout consumer. Skipping them would mean reporting a
version below `FD_VERSION_SOFTPIN`, i.e. losing softpin.

## 5. Where HackiOS assumes their kernel, and what is taken as is

Their stand-in is `redwood-drm/{redwood_drm.c,xf86drm.h}`: an IOKit user client `RedwoodGPU`, the
request number as `IOConnectCallStructMethod` selector, the argument size from `IOCPARM_LEN`, one
connection per process on a fake `/dev/null` fd. Ours is a cdev, so:

| theirs | ours |
|---|---|
| `IOServiceOpen`/`IOConnectCallStructMethod`, `REDWOOD_GPU_SURFACE 0x7e` | `open()` + `ioctl(2)`; the surface op is `MSM_INFO_IOS_IMPORT` 0x85 through GEM_INFO (no describe op exists in 0126) |
| selector = `request & 0xff`, no direction handling | per-request XNU macros, length = `sizeof(struct)` |
| `drmGetVersion` fabricates 1.7 locally, `drmVersion.name_len` is `int` (56-byte struct) | VERSION ioctl against 0126's 64-byte layout (`:1537-1549`), `size_t` lengths as libdrm has them, `_Static_assert` on the size, fake fallback, minor clamped to 7 |
| `drmGetCap` always 0 | GET_CAP ioctl, 0 for everything, same net effect but from the driver |
| `IOConnectMapMemory64`/`UnmapMemory64` per handle | GEM_INFO `MSM_INFO_IOS_MMAP` + `mach_vm_deallocate`; the surface's own mapping for imports |
| `redwood_drm_surface()` describe struct | `IOSurfaceGetAllocSize/…/GetBaseAddress` over `IOSurface.framework` (the kernel takes the same values from the same surface) |
| `drmPrimeFDToHandle(fd, surfaceID)` | same signature and meaning — adopted |
| no `map_owned`, unmap by `bo->handle` | `map_owned`: an unaligned/interior `munmap` cannot work on Darwin either |
| `drmPrimeHandleToFD` `ENOSYS` | adopted for Mesa-owned buffers; an import answers its surface ID |
| `-framework IOKit -framework CoreFoundation` | `-framework IOSurface -framework CoreFoundation` |

Adopted verbatim in intent: the meson stand-in pattern, `subdir` guard, `link_with` fix, the
`__APPLE__` clock, the sysinfo replacement, the build-id early return, the OSMesa EGL-image callbacks
and GPU screen (with the surface describe replaced), and the fb-read barrier including its comment.

## 6. Verification, and what is not verified

Run, all in `~/.hermes/cache/scratch/lane-3/`:

- `patch -p1 --dry-run` of each patch in order against a pristine `mesa-25.0.7` copy: 6/6 clean, no
  fuzz. Then a real apply of all six, `diff -r` against the tree the patches were cut from:
  identical.
- `clang -target arm64-apple-ios16.0 -isysroot ~/.hermes/cache/scratch/sysroot-ios16 -fsyntax-only
  -D__APPLE__ -DHAVE_STRUCT_TIMESPEC -DHAVE_PTHREAD …`: **13/13** files of `src/freedreno/drm/`
  (all of `drm/`, `drm/msm/`, `drm/darwin/`) with no diagnostics. This exercises the new struct
  fields, the `map_owned`/`from_surface` logic and every stand-in prototype.
- Blocked, not by these patches: `freedreno_screen.c`, `ir3_disk_cache.c` and `osmesa*.c` stop in
  generated headers (`followed by nir_intrinsics_indices.h`, `nir_intrinsic_set_align*`). Nothing
  links: no `.tbd` in the sysroot yet (0 found).
- Gaps in the sysroot lane 1 is building, hit head-on (all worth fixing there):
  `<arm/arch.h>`, `<math.h>`, `<zlib.h>`, `<malloc/_malloc.h>`, `<sys/syscall.h>`,
  `mach/mach_vm.h`, `mach/mach_init.h`, `mach/vm_page_size.h`, `mach_debug/ipc_info.h`,
  `mach/clock.h`, `mach/clock_priv.h`, `mach/mach_port.h`, `mach/task.h`, `mach/thread_act.h`,
  `mach/vm_map.h`, `mach/exc_server.h`, `mach/mach_exc_server.h`, `mach/notify_server.h`,
  `mach/host_priv.h`, `mach/host_security.h`, `mach/processor.h`, `mach/processor_set.h`,
  `mach/clock_reply_server.h`, `mach/machine/thread_status.h`, and **`Availability.h` is the 2016
  one**, whose `__API_UNAVAILABLE()` expands without its attribute and breaks every SDK header that
  uses it. The check above got past these with `~/.hermes/cache/scratch/lane-3/overlay/`.
- The sysroot changed while this lane ran (a second copy of `pthread/*.h` appeared under
  `usr/local/include`, half-filled: `qos_private.h` there refers to types its `qos.h` does not
  define). The 13/13 was re-run against the repo copies of the patches after stubbing those too, so
  the count is not an artefact of an older sysroot.
- Never run: meson configure, any link, any execution. The whole of §2/§3 is design until the first
  `libOSMesa` loads and a quad lands in a surface.

## 7. Plan

1. Apply the six patches to a clean 25.0.7 in build scratch (`patch -p1 -i` each, in order); verify
   with `diff -r` against `lane-3/patched` (identical), then `meson setup` with lane C's cross file
   once lane 1's sysroot has the headers in §6. Gate: configure finishes; today it does not.
2. Build `libfreedreno_drm` alone first (`ninja src/freedreno/libfreedreno_drm.a`), then the whole
   `libOSMesa.8.dylib`. Gate: no compile errors in `drm/darwin/*` and `drm/msm/*`; the check in §6
   is the predictor.
3. Code-sign as `tooling` already does (`ld64.lld -adhoc_codesign`) and place it in the iOS root with
   the rest of the userland; nothing runs before `open("/dev/dri/renderD128")` succeeds in a
   test process.
4. First run-time gate, no compositor involved: a 40-line OSMesa program that makes a context,
   clears to a colour on a `OSMesaCreateContextExt` buffer, and reads it back. That exercises open,
   VERSION/GET_PARAM, GEM_NEW, GEM_INFO 0x80/0x00, GEM_SUBMIT, WAIT_FENCE, GEM_CLOSE — every ioctl in
   §1 — and would show the direction bug immediately. Device-side log to read (read-only, for the
   main agent):
   `dmesg | grep -E 'SWEET (DRM|KGSL)' | tail -60` and `ls -l /dev/dri/renderD128`.
5. Then the IOSurface path: a surface from `IOSurfaceCreate`, `glEGLImageTargetTexture2DOES`, draw,
   read back, present. Gate: `SWEET DRM: ios_import surf N -> handle …` in the log and correct pixels.
6. Then the EAGL shim (lane 2) on top.

## 8. Open questions

1. **Version clamp.** 7 keeps cached-coherent off, but `GEM_NEW` accepts `MSM_BO_CACHED_COHERENT`
   anyway (`:1993` takes any flags; `kgsl_do_gpumem_alloc` only keeps them in `kflags`, `:1115`), so
   if the kernel later implements the flag the clamp hides a feature. If the mapping stays
   write-combined the flag is harmless either way (inferred). Confirmation needs a run with a mapped
   buffer written by the CPU and read by the GPU after a submit.
2. **`ContentBuffer` surfaces.** `A-quartzcore` says QuartzCore already binds surfaces for the GPU
   (`IOSurfaceClientBindAccel`, selector 0xc). If one surface then has two SMMU mappings (theirs and
   ours, per pid), which one does the GMEM resolve write through? Ours is per-process (`:1826-1834`)
   and used `pid`-checked reuse, so a second process's import maps the same pages again. A run with
   both mapped is the test.
3. **Planar and 10-bit surfaces.** Only `'BGRA'` is accepted (§3.4). `IOSurfaceGetPlaneCount` is not
   consulted; a `'420f'`/`'x444'` surface would be refused rather than mishandled. Does QuartzCore on
   this build ever hand a planar surface to the renderer?
4. **`drmPrimeHandleToFD` for Mesa-owned buffers.** Returning `ENOSYS` means an app that exports an
   EGLImage from a Mesa renderbuffer gets nothing. Is an export path needed before the first present,
   or does everything go surface → import only?
5. **Hardware claim in patch 0006.** The CCU/UCHE flush is HackiOS's, seen on a642l. Our GPU is an
   a620 with the same A6xx CCU; unverified here. If a colour is wrong on the first frame after a
   non-reading draw, this is the patch to look at — and if it never shows, dropping it is cleaner.

## Patch list

`tooling/gpu/mesa-patches/`, against Mesa 25.0.7 (`VERSION` = 25.0.7), apply in order with `patch -p1`.

| file | purpose | lines (+/−) | files touched |
|---|---|---|---|
| `0001-meson-darwin-libdrm-stand-in.patch` | build the stand-in, enter `drm/`, drop `libvdrm` | +18/−4 | `meson.build`, `src/freedreno/meson.build`, `src/freedreno/drm/meson.build` |
| `0002-darwin-libdrm-shim.patch` | the function set, the XNU direction encoding, mmap/unmap, surface import | +470/−0 | new `src/freedreno/drm/darwin/{xf86drm.h,drm_darwin.c}` |
| `0003-drm-layer-darwin-mmap-import-and-clock.patch` | `map_owned`, `from_surface`, import size, `CLOCK_MONOTONIC_RAW` | +91/−3 | `freedreno_drmif.h`, `freedreno_priv.h`, `freedreno_bo.c`, `msm/msm_priv.h`, `msm/msm_bo.c` |
| `0004-darwin-without-sysinfo-and-build-id.patch` | RAM size, no shader disk cache, thread id for the log | +26/−1 | `freedreno_screen.c`, `ir3/ir3_disk_cache.c`, `freedreno_util.h` |
| `0005-osmesa-gpu-screen-and-surface-textures.patch` | GPU screen, EGL-image callbacks, surface → `pipe_resource` | +109/−1 | `frontends/osmesa/osmesa.c`, `targets/osmesa/{meson.build,osmesa_target.c}` |
| `0006-a6xx-fb-read-barrier.patch` | CCU flush before the first fb-reading draw (from HackiOS) | +12/−0 | `a6xx/fd6_draw.cc`, `freedreno_batch.h` |

Total: 6 patches, 18 files (2 new), +726/−9, by `grep -c '^+[^+]'` / `'^-[^-]'`.
