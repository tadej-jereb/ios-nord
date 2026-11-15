# A — How iOS 16.7.16 QuartzCore/backboardd composites, and where a Mesa/Adreno backend can attach

Lane A report (GPU userland seam). Read `../../.hermes-lanes/gpu-shared.md` for the framing.
Everything below was read out of the two iOS images on this host; the raw tool output lives in
`~/.hermes/cache/scratch/lane-a-quartzcore/` (`bin/`, `out/*.dis`, `out/*.nm`, `out/*.strings`)
and nothing disassembled is copied into the repo.

## Summary

1. A CA commit ends in one function, `IOMFBDisplay::finish_update`: render → SwapWait → SwapBegin(4) →
   SwapSetLayer(0x37) with a surface ID → SwapEnd(5, 0x46C struct) → SwapWait(6).
2. The renderer is picked in `EAGLServer::renderer()`, in this order: Metal (`MTLCreateSystemDefaultDevice`
   + `new_metal_context`) → OpenGL ES 3 (`EAGLContext initWithAPI:3` → `GLESContext`) → `sw_renderer()`,
   a bare `CA::OGL::Context`, i.e. the CPU rasterizer.
3. Metal only sees a device if an IOService of class `IOAcceleratorES` exists *and* carries
   `MetalPluginName`/`MetalPluginClassName`; `CAMetalContextCreate` polls that class 300 × 100 ms.
4. On the Nord `0107` publishes `IOAcceleratorES` **empty** — enumerated, then skipped — and nothing
   answers `EAGLContext`, so every frame falls through to the CPU context: the ~24 fps.
5. **Recommended seam: the OpenGL ES step** — an `EAGLContext` over `libEGL`/`libGLESv2` (Mesa
   freedreno, `GPUId(620)`) as an inserted dylib plus the `IOGLESBundleName` property on
   `IOAcceleratorES`, exactly as raphael did. No Apple Metal/IOGPU ABI needed.
6. Surfaces already come from `CAIOSurfaceCreate` and already reach the scanout path; the only new
   kernel-side need is a GPU SMMU mapping when a renderer binds one (`IOSurfaceClientBindAccel`, 0xc).

## Provenance and how the images were read

| Item | Value |
|---|---|
| OS image | `build/ipsw-x/087-86698-044.dmg`, 4 730 814 044 B, sha256 `80f426d5b8fca855…` |
| SystemOS cryptex (dyld shared cache) | `build/ipsw-x/087-86593-047.dmg`, 2 743 074 816 B, sha256 `9cd738f3b0169055…` |
| QuartzCore | `/System/Library/Frameworks/QuartzCore.framework/QuartzCore`, 5 391 582 B, sha256 `d1fe6d891fccac80…`, LC_ID_DYLIB version 1.11.0, `LC_BUILD_VERSION` platform ios sdk 16.7.3 minos 16.7 |
| backboardd | `/usr/libexec/backboardd` from the OS image, 1 184 848 B, sha256 `7aa6f8bf5ea2c363…` |
| Other binaries used | `IOSurface` `8b5c20198b7d0bc3…`, `IOMobileFramebuffer` `18511ca48fefc812…`, `IOGPU` `018eec2f4c58c799…`, `Metal` `90d280fa5adfbf33…`, `AGXMetalA11` `983f6b05e08dbf2c…`, `libGFXShared` `48a9656f7da861dd…`, `OpenGLES` `8378139226c88ce7…` |

Mount (unprivileged, the invocation `tooling/61-mkrd-root.sh` uses — the path handed to apfs-fuse
must end in `.dmg`, so the repo path is given verbatim):

```
tooling/opt/apfs-fuse/bin/apfs-fuse -l -o ro build/ipsw-x/087-86593-047.dmg  ~/.hermes/cache/scratch/lane-a-quartzcore/mnt/sys
tooling/opt/apfs-fuse/bin/apfs-fuse -l -o ro build/ipsw-x/087-86698-044.dmg  ~/.hermes/cache/scratch/lane-a-quartzcore/mnt/os
```

The shared cache is `/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64` (+`.01`… in the
cryptex). Extracted with `dyldextractor` in a throwaway venv (`/usr/bin/python3.12 -m venv venv`,
`pip install dyldextractor 'setuptools<70'`; py3.14 lacks `distutils`, which capstone imports):

```
./venv/bin/dyldex -l -a <cache>                                   # image list -> out/cache-list.txt
./venv/bin/dyldex -e QuartzCore.framework/QuartzCore -o bin/QuartzCore <cache>
```

Analysis only with `tooling/opt/llvm/bin/llvm-nm`, `llvm-objdump -d --macho --symbolize-operands`,
`strings`. Addresses below are the unslid vmaddrs the disassembler prints (base 0x180000000 at
runtime on device).

---

## 1. Renderer selection: the order, and what makes each step fail

**Choice point** — `CA::WindowServer::EAGLServer::renderer()` at 0x1882eaf3c (cached at `this+0x320`;
the chosen renderer is also stored in `server+0x118`):

1. `if (this->server->metal_context /* +0x108 */ == NULL) metal_context = CAMetalContextCreate();`
2. on success: `ctx = CA::OGL::new_metal_context(metal_context, NULL, NULL, 0, 0, /*MetalPriority*/ 4,
   CFSTR("com.apple.coreanimation.EAGLServer"))`, `renderer = new CA::OGL::Renderer(ctx)` — done, Metal.
   (The metal context is the only real argument; the 4 is a priority enum value, not a count.)
3. `CAMetalContextCreate()` returned NULL → if the global set from **`CA_ENABLE_OGL`** (0x1dcdf81b9) is
   non-zero, build `EAGLContext`: an `NSMutableDictionary` with two `EAGLContextProperty*` keys, both
   set to one global value (`kCFBooleanTrue`-like; the keys are imported constants and **inferred**
   to be `Sharegroup`/`Accelerated`), then `[EAGLContext alloc] initWithAPI:3 properties:dict`; on
   failure the same again with API 2 (ES 2).
   Only `[ctx API] == 3` is accepted: `ctx = new CA::OGL::GLESContext(eagl_ctx)` (+0x318),
   `renderer = new CA::OGL::Renderer(ctx)`.
4. both failed → `renderer` stays NULL, and `EAGLServer::render_update` (0x1883601dc: `vtable[0x1a0]()`,
   `render_display` if non-NULL, else a tail-call to `Server::render_update` at 0x18836026c) falls
   back to the base `CA::WindowServer::Server::render_update`, which uses `sw_renderer()`.

**The software renderer is a distinct object, not a mode flag**: `Server::sw_renderer()` (0x1884f4c54)
`malloc_zone_calloc(0x4fe0)` + `CA::OGL::Context::Context()` (the *base* class, its own vtable) +
`new CA::OGL::Renderer`. It is the CPU rasterizer, and it is what composites every frame on the Nord.

How each step fails, sourced:

* **`CA_ENABLE_OGL` defaults to 1** — `EAGLServer::EAGLServer()` reads `getenv("CA_ENABLE_OGL")`,
  `atoi`, and stores `ne` — but with `getenv` returning NULL it stores **1** (0x1883da844–0x1883da874).
  So the GLES step is on unless explicitly set to 0; the step that is really blocked is `EAGLContext`.
* **Metal step.** `CAMetalContextCreate` (0x18838421c) is `MTLCreateSystemDefaultDevice()` inside an
  autorelease pool, and when that returns nil the caller's NULL check falls through to step 3. The
  poll raphael reported is real and is *here*: `___CAMetalContextCreate_block_invoke` loops
  `IOServiceGetMatchingServices` on class `IOAcceleratorES` + `IOIteratorNext`, 0x12b (299)
  iterations, `usleep(0x186a0)` (100 ms) between — ~30 s at every backboardd start. The loop only
  tests whether *any* service matched, so the empty service of `0107` ends it on the first iteration;
  what it cannot fix is the resulting empty device list, so Metal still yields no device.
* **What Metal requires from the service.** `MTLRegisterDevices` (0x181b144c8) does
  `IOServiceMatching("IOAcceleratorES")`, and for each service `getMetalPluginClassForService`
  (0x181a3c7c8) reads registry property **`MetalPluginName`** (bundle name), builds
  `/System/Library/Extensions/<name>.bundle`, then reads **`MetalPluginClassName`** and
  `[bundle classNamed:]`, and requires the class to be a subclass of `MTLIOAccelDevice`. It then
  `[[cls alloc] initWithAcceleratorPort:service]` and adds it to the device list. A service without
  those two properties is enumerated and silently skipped — which is exactly what the empty
  `IOAcceleratorES` of `0107` gets, and why no Metal device appears.
* **Alignment values are read off the same service.** `CADeviceInfo.cpp`'s static
  `init_alignment` (0x1883713b4) does `IOServiceMatching("AGXAccelerator")` +
  `IOServiceGetMatchingService`, reads CFNumber property **`PurpleGfxMem`**, and stores it into
  `alignment_values[]` (both the `…ImageBytes` and `…NeededImageBytes` slots), then asserts
  `image >= needed` and `rowBytes >= neededRowBytes`. **`AGXAccelerator` is the kext class name, not
  `IOAcceleratorES`** — with no such service the array stays all-zero, `0 >= 0` passes, and every
  surface alignment is 0 (unpadded rows).
* **GLES step.** `EAGLContext` lives in `OpenGLES.framework` and pulls its renderer through
  `libGFXShared`; `-[EAGLContext commonInitWithAPI:properties:]` is the entry. `libGFXShared`
  (`_gfxInitializeLibrary`) reads **`IOGLESBundleName`**, `IOGLESMetalBundleName`,
  `IOGLESDefaultUseMetal` off the accelerator service and dlopens
  `/System/Library/Extensions/%s.bundle` — with no service publishing them there is no renderer and
  `initWithAPI:` fails for both 3 and 2. (raphael's note, reproduced in §5: "Without them EAGLContext
  found no renderer at all and gave applications no context".)

Commands:

```
llvm-objdump -d --macho --symbolize-operands bin/QuartzCore > out/qc.dis
grep -n 'EAGLServer8rendererEv\|CAMetalContextCreate\|MetalContextC1' out/qc.dis
sed -n '/^_CAMetalContextCreate:/,/^____CAMetalContextCreate_block_invoke:/p' out/qc.dis
grep -n 'EAGLServer8rendererEv' out/qc.dis ; sed -n '<caller lines>' out/qc.dis     # EAGLServer::render_update, vtable+0x1a0, tail-call to Server::render_update
grep -n 'IOServiceMatching' out/metal.dis ; sed -n '267660,267860p' out/metal.dis  # MTLRegisterDevices
strings -a bin/libGFXShared | grep IOGLES                                           # IOGLES* property names + "Extensions/%s.bundle"
python3 -I resolve2.py out/metal.sections.json bin/Metal 0x1d59dcd10 0x1d59dcd70     # "MetalPluginName", "MetalPluginClassName"
```

Live confirmation that this is the state on the phone: `logs/phone/live-20261115-0118.txt`
shows backboardd in `IOServiceMatching({"IOProviderClass": "IOAcceleratorES"})` over and over
(`IOK backboardd: matching1 … -> IOAcceleratorES`) — it is polling the empty service — and
`0107-sweet-empty-ioacceleratores.patch` publishes it empty on purpose, with the comment that a
service without `MetalPluginName`/`MetalPluginClassName` is "found and then passed over by
MTLRegisterDevices".

## 2. Surfaces: allocation path, user-client selectors, properties

**Where.** `CA::WindowServer::Display::allocate_surface(w, h, fmt, flags, primaries, …, name)` first
walks a CA-side free list of pooled `CA::WindowServer::Surface` objects with matching geometry and
format (`w8` compares at struct offsets 0x18/0x1c/0x20, then a virtual equality test), and otherwise
creates one through **`CA::SurfaceUtil::CAIOSurfaceCreate`** (0x188320750). The new surface is wrapped
by `CA::WindowServer::IOSurface::wrap_buffer`. On the scanout side `finish_update` calls
`allocate_surface` for the next frame's buffer and `copy_surface` when a surface has to be carried
over — both are in the per-frame path.

**Property dictionary.** `CAIOSurfaceCreate` builds a mutable CFDictionary (2 `CFDictionaryCreateMutable`,
**17** `CFDictionarySetValue`) and calls `IOSurfaceCreate` once; the keys are the framework's exported
constants, imported by QuartzCore: `_kIOSurfaceWidth`, `_kIOSurfaceHeight`, `_kIOSurfaceBytesPerRow`,
`_kIOSurfaceBytesPerElement`, `_kIOSurfaceAllocSize`, `_kIOSurfacePixelFormat`, `_kIOSurfaceCacheMode`,
`_kIOSurfaceIsGlobal` (full list: `grep 'U _kIOSurface' out/QuartzCore.nm`). Row padding is the
`alignment_values[]` from §1 (`CA::SurfaceUtil::SurfaceAlignment`, parameter 8), i.e. today 0.
After creation it also calls `IOSurfaceSetValue(surface, kIOSurfaceName…)` when a name was passed, and
`IOSurfaceSetBulkAttachments2(surface, &attachments, 0x70, 0xc0)` with a 0x70-byte colour/attachment
block (literal dict key `IOSurfaceBulkAttachments`, the only `IOSurface*` CFString QuartzCore embeds).
The live log shows the numbers actually in use: `fmt 0x42475241 bpr 4608 1125x2436` — BGRA, row
4608 = 1152 px, i.e. already 64-byte aligned by CA even with alignment 0.

**User-client selectors** (`IOSurface.framework`, connection opened by `__iosConnectInitalize` on the
`IOSurfaceRoot` service; `nm`-visible function → selector):

| Selector | Function | Notes |
|---|---|---|
| 0x0 | `IOSurfaceClientCreate` → `IOSurfaceClientCreateChild(plane=0)` | **surface create**; props dict is the input struct |
| 0x4 | `IOSurfaceClientLookup` | by ID |
| 0x22 | `IOSurfaceClientLookupFromMachPort` | by mach port |
| 0x23 | `IOSurfaceClientCreateMachPortWithOptions` | publish a port for another task |
| 0x6 | `IOSurfaceClientWrapClientImage` | wrap an existing image |
| 0x7 | `IOSurfaceClientWrapClientMemory` | wrap client memory (SweetSurface's ancestor) |
| 0xc | `IOSurfaceClientBindAccel` | **bind to an accelerator ID (GPU SMMU mapping)** |
| 0x9 / 0xa / 0xb | `SetValue` / `UpdateNonBulkValueCache` / `RemoveValue` | property accessors |
| 0x15 / 0x2c | `SetOwnership` / `SetOwnershipIdentity` | |
| 0x14 | `SetPurgeable` | |
| 0x16 / 0x19 | `SetTiled` / `GetTileFormat` | |
| 0x18 / 0x21 | `SetTimestamp` / `SetIndexedTimestamp` | |
| 0x11 | `SetSurfaceNotify` (`IOConnectCallAsyncMethod`) | notification port |
| 0x32 / 0x33 / 0x34 | `SetDataProperty` / `GetDataProperty` / `ClearDataProperties` | |
| 0x2f–0x31 | `IOSurfaceMemoryPool ensure/flush/debugInfo` | |

**Lock/unlock and use-count need no kernel call at all**: `IOSurfaceLock` (0x1a3980cb8) tail-calls
`IOSurfaceClientLock`, which only touches the client struct; use-count is an in-process counter
(`IOSurfaceIncrementUseCount` / `IOSurfaceGetUseCount` are plain functions), and the base address is a
field of the client object (`__IOSurfaceClientGetUnadjustedBaseAddress` = `ldr x0,[x0,#0x68]`,
buffer offset at `+0x94`). So a surface has CPU access the moment `IOSurfaceLookup`/`Create` returns —
no extra call.

**What must be GPU-visible.** Only the *memory*: everything handed to a GPU has to be addressable
through the GPU SMMU (streams 0x4 user / 0x5 kernel, `avicii/CONSTANTS.md` GPU SMMU row), which is
what `IOSurfaceClientBindAccel` arranges for a surface and what the freedreno winsys has to do for
its own buffers. The selector set above is otherwise format/metadata only; nothing in the CPU path
depends on the surface being reachable by a device.

Commands:

```
grep -n 'kIOSurface' out/QuartzCore.nm | head -25                       # imported key constants
python3 -I body.py      # per-function stub census of CAIOSurfaceCreate: 17x CFDictionarySetValue, 1x IOSurfaceCreate, 1x IOSurfaceSetBulkAttachments2
python3 -I sels2.py     # stub + nearest "mov w1, #N" -> selector table (IOSurface, IOMobileFramebuffer, IOGPU)
sed -n '/^_IOSurfaceLock:/,/^_IOSurfaceAcceleratorBlitSurface:/p' out/ios.dis
grep -n 'SWEET FB: swap' logs/phone/live-20261115-0118.txt
```

## 3. Scanout: the per-frame IOMobileFramebuffer calls

All of it is in `CA::WindowServer::IOMFBDisplay::finish_update(Render::Update*, uint32)` (0x1882d0f88).
Order of the stub calls in that function, as disassembled:

```
IOMobileFramebufferSwapWait            (previous swap)
IOMobileFramebufferSwapBegin
IOMobileFramebufferSwapSetTimestamps ×3, SwapSetBackgroundColor, SwapSetColorRemapMode
update_blend_display_color_spaces / update_system_gamma / update_blackpoint_adaptation /
update_gamma_adjustment / update_user_adjustment / set_framebuffer_ax_matrix
[per layer]  swap_set_layer(layer, surface, src, dst)  ->  IOSurfaceGetID  ->  IOMobileFramebufferSwapSetLayer
Display::allocate_surface (next buffer), IOMFBDisplay::copy_surface, current_page_surface,
  IOMobileFramebuffer::get_wireless_surface_options, IOSurface::wrap_buffer, swap_set_layer again
IOSurfaceGetID ×3, kdebug_trace, SwapDirtyRegion, SwapWorkaroundSettings
SwapSetTimestamps ×2, swap_brightness, swap_display_edr_factor, swap_display_headroom_used,
  swap_hdr_metadata, SwapSetGainMap (+ IOMFBGainEncoder*), IOMobileFramebufferSwapEnd
IOMobileFramebufferSwapWait            (this swap)
```

The `IOMobileFramebuffer*` functions are thin: each dispatches through a function pointer in the
client object's table (`IOMobileFramebufferSwapSetLayer` = `ldr x4,[x0,#0x6b8]; br x4`, returning
`kIOReturnUnsupported` 0xe00002c2 when absent), and the `_kern_*` implementations hold the user-client
selectors:

| Selector | Call | Argument shape |
|---|---|---|
| 0x4 | `_kern_SwapBegin` | `IOConnectCallScalarMethod(conn, 4, NULL, 0, &swapid, &count=1)`; swap id is stored at client `+0x68`; the swap record at client `+0x18` is `bzero`ed (0x46C bytes) |
| 0x37 | `_kern_SwapSetLayer(layer, surface, src, dst, flags)` | no user-client call: fills the layer entry in the 0x46C record in place; layer index must be **< 4** (`cmp w1,#4`) or `kIOReturnUnsupported` |
| 0x5 | `_kern_SwapEnd` | `IOConnectCallStructMethod(conn, 5, client+0x18, 0x46C, NULL, NULL)` — the whole frame goes over in one 0x46C struct |
| 0x6 | `_kern_SwapWait` / `SwapWaitWithTimeout` | scalar; waits on the swap id |
| 0x14 / 0x34 / 0x51 | `SwapSignal` / `SwapCancel` / `SwapCancelAll` | scalar |
| 0x45 | `SwapSetColorMatrix` | struct |
| 0x3 / 0x31 / 0x53 | `GetLayerDefaultSurface` / `SurfaceIsReplaceable` / `CopyLayerDisplayedSurface` | scalar |

Today's live sequence, straight from `logs/phone/live-20261115-0118.txt` — the kernel stub prints the
selector as decimal, and each frame is: `sel 4` (begin), `sel 55` (= 0x37, one layer), `sel 5 in
0/1132` (end, 1132 = 0x46C), then `sel 3`; the stub's own decode line reads
`SWEET FB: swap 2 layer 0 surface 2 1125x2436 fmt 0x42475241 bpr 4608 a 0,0 1125x2436 b 0,0 1125x2436`.
Other selectors backboardd actually uses on this boot: 3, 6, 0xc, 0xf, 0x11, 0x16, 0x1b, 0x1d, 0x21,
0x32, 0x37, 0x39, 0x44, 0x4a, 0x4f, 0x54. So `SweetFramebuffer.cpp` today already answers the
frame-bearing ones (begin/end/layer/wait) well enough for the CPU path, and a GPU-rendered surface
needs no new selector — the layer already carries nothing but a **surface ID**.

Commands:

```
python3 -I seq.py                       # ordered stub calls inside IOMFBDisplay::finish_update
python3 -I sels2.py                     # IOMobileFramebuffer selector table (uses out/iomfb.dis)
sed -n '/^_kern_SwapEnd:/,/^_IOMobileFramebufferSetBrightnessCorrection:/p' out/iomfb.dis
sed -n '/^_kern_SwapBegin:/,/^_kern_[A-Za-z]+:/p' out/iomfb.dis
grep -o 'SWEET FB: backboardd sel [0-9]*' logs/phone/live-20261115-0118.txt | sort -u
```

## 4. GPU submission: IOGPU user-client selectors and the seam recommendation

`IOGPU.framework` is the client library for the accelerator device; every selector below is
`IOConnectCallMethod`/`…StructMethod`/`…ScalarMethod` with `conn` from `IOServiceOpen` on the service
the AGX device class opened:

| Selector | Function |
|---|---|
| 0x0, 0x2, 0x4, 0x6 | `IOGPUDeviceCreateWithAPIProperty` (staged, largest last) |
| 0x1 | `IOGPUDeviceGetName` |
| 0x3 / 0x5 / 0x16 | `GetCurrentTraceFilter` / `GetNextGlobalTraceID` / `GetMemoryData` |
| 0x7 / 0x19 | `IOGPUCommandQueueCreateWithQoS` (device ↔ queue variants) |
| 0x8 | command-queue finalize |
| 0x9 | **`IOGPUResourceCreate`** |
| 0xa / 0xb / 0xc | resource finalize / `FinishEvent` / `SetPurgeable` |
| 0x25 | **`IOGPUResourceCreateIOSurface`** (wrap an IOSurface as a GPU resource) |
| 0x24 | `IOGPUResourceSetOwnerIdentity` |
| 0xd / 0xe | `CreateDeviceShmem` / `DestroyDeviceShmem` |
| 0xf / 0x10 | **`IOGPUNotificationQueueCreate`** / finalize — completion channel |
| 0x12 / 0x13, 0x14 / 0x15, 0x1d–0x20 | fence / event / late-eval-event create+destroy+signal |
| 0x1a | **`IOGPUCommandQueueSubmitCommandBuffers`** |
| 0x1b / 0x1c | `SetPriorityAndBackground` / `SetQualityOfService` |
| 0x21 / 0x22 / 0x23 | `SetDisplayParams` / `SetAppGPURole` / `GetAppGPURole` |
| 0x28–0x31 | IO-command-queue create/submit/complete/cancel |

Submit, in full (0x1ece1d48c): `IOConnectCallMethod(conn, 0x1a, input[4] = {queue shmem base, count,
count, argsSize}, 4, args, count*argsSize, NULL, NULL, NULL, NULL)` — the command-buffer args array is
passed as the *struct* argument, four scalars carry the shmem pointer and lengths. Asynchrony: the
queue's notification port comes from `IODataQueueAllocateNotificationPort` +
`IOConnectSetNotificationPort(conn, 0, port, ref)`, and completion is a queue entry of two words per
command buffer (`WillSubmit` sizes it `count*2`). Nothing here is Apple-secret beyond the numbering;
implementing it means implementing IOGPU, then a Metal driver on top.

**Recommendation — take the GLES step (Option a), not Metal/IOGPU.** Evidence:

* QuartzCore's own fallback is the GLES path, on by default (`CA_ENABLE_OGL` default 1), and it needs
  exactly one foreign object: an `EAGLContext` (selector `initWithAPI:3` + `properties:` dict of
  `EAGLContextProperty*` keys: `Sharegroup`, `Accelerated`, `ClientRetainRelease`,
  `SharedWithCompute`, `ClientLabel`, `VisibleInDebugTools`). Everything above it — `CA::OGL::Renderer`,
  `GLESContext`, the shader cache, the layer tree — is QuartzCore's own GL code and runs unchanged;
  `GLESContext` calls plain `gl*` entry points.
* The Metal path costs a whole second ABI: IOGPU device/queue/resource/submit selectors above, plus
  `MTLIOAccelDevice`-subclass plugin class, plus Metal's plugin discovery from registry properties.
  raphael built a shim Metal (`RedwoodMetal`) and then still kept the window server on GLES: their
  `0112` comment is "a process handed a half-made device aborts rather than falls back, so … the
  window server stays on OpenGL ES".
* The scanout handoff is renderer-agnostic (§3): `finish_update` submits surface **IDs**. A GLES
  renderer writing into the same surface is indistinguishable to the display path from the CPU one.
* What the GLES seam does need from the kernel is small and already half-present: the surfaces must be
  GPU-addressable (`IOSurfaceClientBindAccel`, selector 0xc, → GPU SMMU mapping) and the surface memory
  is the client-mapped buffer SweetSurface already produces.

So: keep `SweetFramebuffer`, keep `IOAcceleratorES` published (it stops the 300 × 100 ms poll either
way), and add the `IOGLESBundleName`/`IOGLESMetalBundleName`/`IOGLESDefaultUseMetal` properties so
`libGFXShared` finds a renderer; supply that renderer as a `libredwood-gl`-style dylib over Mesa.

Commands: `python3 -I sels2.py` (after `llvm-objdump -d --macho --symbolize-operands bin/IOGPU >
out/iogpu.dis`), `sed -n '/^_IOGPUCommandQueueSubmitCommandBuffers:/,/^_IOGPUCommandQueueSetPriority/p'
out/iogpu.dis`, `grep -n 'IODataQueue\|IOConnectSetNotificationPort' out/iogpu.dis`,
`strings -a bin/OpenGLES | grep EAGLContextProperty`.

## 5. What raphael-ios-gpu intercepts (cross-check)

`refs/marnov999-raphael-ios-gpu/` (A640, davinci lineage) resolves the same fork the same way and
documents it:

* **Never a Metal device, the GLES step instead.** `xnu/patches/0112` publishes `IOAcceleratorES`
  with `MetalPluginName`/`MetalPluginClassName` pointing at **their own** `RedwoodMetal` bundle, and
  `IOGLESBundleName = "SweetGLES"`, `IOGLESMetalBundleName = "AppleMetalGLRenderer"`,
  `IOGLESDefaultUseMetal = false`; only under boot-arg `sweetmetal=1`. Their comment states the reason
  and the consequence: with the IOGLES properties "an application's own EAGLContext" runs on
  RedwoodMetal, and "without them EAGLContext found no renderer at all and gave applications no
  context"; the window server stays on OpenGL ES regardless.
* **The GL bridge is an EAGL reimplementation over Mesa.** `tools/build-redwood-gl.sh` compiles
  `eagl.c` + `redwood_gl_egl.c` (from davinci's `hackios-port`) against Mesa's `libEGL.1.dylib` /
  `libGLESv2.2.dylib`, generating the exported `gl*` set with `mkeagl.py` from `gl.xml` +
  `eagl_slots.txt`, links `-install_name /usr/local/lib/libredwood-gl.dylib`, and ad-hoc signs with
  `ldid -Hsha256 -Cadhoc`. It is loaded as an insert library, not linked by QuartzCore.
* **They intercept the frame, not the API**: `userland/redwood-gl/eagl-raphael.patch` makes a fresh
  full-screen target (`seed 0`) get its clear done by the GPU instead of a `surface_to_texture()` CPU
  copy of 10.8 MB/frame (~5 ms), and `userland/surfuse.c` dumps `IOSurfaceIsInUse`/use-count/seed per
  surface to explain why CA does not re-take its display surfaces. Their remaining open item is
  zero-copy IOSurface import (note at line 381: "zero-copy IOSurface import (10.8 MB/frame)"), i.e.
  exactly the `IOSurfaceClientBindAccel`/SMMU work named in §2.
* **Kernel-side property they added for pacing**: `setProperty("RedwoodWaitsForGPU", kOSBooleanTrue)`
  so `present()` waits for the GPU on the vsync thread and the bridge can drop its per-frame
  `glFinish()` (3–14 ms/frame). Same shape as `SweetFramebuffer`'s present path here.
* `userland/redwood-gl/cahook.c` is instrumentation only (12 inline hooks on shared-cache addresses
  such as `IOMFBServer::vsync_callback`, `Render::Context::will_commit`, `Transaction::commit`) — it
  documents the commit→vsync→render call order but changes nothing.
* Boot-args/entitlements: `sweetmetal` gates the accelerator publish; the Metal plugin is only
  offered to processes named in `/usr/local/gltest/metal_allow`. No entitlement is needed for the
  GLES route — their bridge is an inserted dylib.

Nothing of the above is a *different* seam than §4 recommends; it is the same one, already proven on
an A6xx phone, with the A640→A620 delta confined to Mesa's device table (`GPUId(620)`).

## What could not be determined

* Which of the 17 `CFDictionarySetValue` keys in `CAIOSurfaceCreate` maps to which value: the keys are
  loaded through `__DATA_CONST` auth-pointer slots that sit at 0 in the extracted file (bind opcodes
  were not decodable by `llvm-objdump --chained-fixups` on the rebuilt dylib), so the key *set* is
  sourced from the import list and the values/numbers from the code, but the pairing is **inferred**.
* The `IOSurface` user-client *return* struct layout for selector 0 — the surface record is filled by
  the kernel and the client parses it at fixed offsets (`+0x68` base address, `+0x94` buffer offset,
  `+0x70`→`+0xc` seed, `+0xaa`/`+0xab` element size, `+0xa0` plane count); only those offsets are
  read, the full struct size is **inferred**.
* The exact layer-entry layout inside the 0x46C swap record (order of surface id / rects / flags):
  `SwapSetLayer` writes it, but the field offsets were not traced field by field.
* Whether `CA_ENABLE_OGL` is the only gate on the GLES step (a second check was seen on
  `server+0x240 & 0x1c00` in the `EAGLServer` constructor that only decides whether the renderer is
  built eagerly); it is **inferred** that no other condition can veto an ES3 context.
* Nothing was run on the phone — all of the live material above is from the existing logs.
