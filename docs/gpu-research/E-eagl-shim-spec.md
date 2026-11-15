# E — The exact EAGL / OpenGL ES surface QuartzCore's GLES renderer requires, as a shim spec

Lane 2 report (round 3). Everything below was read on this host out of the SystemOS cryptex dyld
shared cache (`build/ipsw-x/087-86593-047.dmg`) and the kernel contract patch; raw tool output is in
`~/.hermes/cache/scratch/lane-2/`. Nothing disassembled is copied into the repo. Read lane A
(`A-quartzcore-compositing.md`) for the compositor as a whole; this file is only the seam.

## Summary

1. QuartzCore reaches OpenGL ES through **one object and one function table**: an `EAGLContext`
   (`initWithAPI:3 properties:` with two `kEAGLContextProperty*` keys) whose
   `-getMacroContextPrivate` returns a **jump table** of 0x2000-odd bytes. QuartzCore imports **no
   `gl*` symbol at all** (`llvm-nm -u QuartzCore` → only `_OBJC_CLASS_$_EAGLContext`, `kEAGLContextPropertyAccelerated`,
   `kEAGLContextPropertyClientRetainRelease`); every GL call is `table[offset]` with the table's
   first word as the context argument. A shim therefore does **not** export `gl*`; it fills a table.
2. 58 distinct table offsets are called from QuartzCore (229 call sites, listed below), including
   `glFenceSync`/`glClientWaitSync`, `glFinishObjectAPPLE`, `glFramebufferTexture2D` and
   `glFramebufferParameteriAPPLE`. One `NULL` slot is a jump to 0.
3. Seven `-EAGLContext` methods can be replaced via `class_addMethod` so that Apple's
   `libGFXShared`/`GLEngine` GLI plugin never has to exist (HackiOS's route, `refs/gsjsjzhznsz-hackios-xnu-userland/userland/src/eagl.c:4052`).
   `-initWithAPI:properties:`, `-API`, `-getMacroContextPrivate`, `-dealloc`, `-attachImage:…`,
   `-texImageIOSurface:…` and `-setParameter:to:` are the whole required set.
4. IOSurfaces arrive as **render targets** (`-attachImage:target:toCoreSurface:invertedRender:NO`
   from the texture that the FBO will use) and as **textures to sample** (`-texImageIOSurface:…
   plane:0 invert:`). Both act on the *currently bound* texture. They must be backed by the
   surface's own memory: `MSM_INFO_IOS_IMPORT` (0x85) → GEM handle → EGLImage, else a CPU copy.
5. Presentation is not the renderer's business: QuartzCore hands finished surfaces to
   `IOMobileFramebufferSwap*` itself (lane A §3), so `-presentRenderbuffer:` has no call site in
   QuartzCore. It is only needed for applications that present themselves.
6. Divergences from HackiOS and raphael, and from `0126`, are in §7; the important one is that
   `0126`'s import returns a handle only, so stride/format must come from `IOSurface` in userland and
   the image offset is 0.

## Evidence

| What | Where |
|---|---|
| Renderer selection, dict, `initWithAPI:3 properties:`, `setParameter:0x260`, `[ctx API]==3`, `new CA::OGL::GLESContext` | `QuartzCore` 0x1882eb040–0x1882eb168 (`EAGLServer::renderer()`) |
| Property keys set on the dict (both to `kCFBooleanTrue`) | 0x1882eb068–0x1882eb09c; symbols `_kEAGLContextPropertyAccelerated` `_…ClientRetainRelease` (`llvm-nm -m`) |
| `GLESContext` ctor: `[eagl getMacroContextPrivate]` → `this+0x7f8`, then `glGetString` ×3, 4 × `glGetIntegerv`, 16 `check_extension` calls | 0x18840960c–0x188409c14 |
| `check_extension` = substring search of the `GL_EXTENSIONS` string, `CA_DISABLED_EXTENSIONS` env honoured | 0x1884b6664–0x1884b6794 |
| Table slot call shape (`ldr xN,[tbl,#off]` / `ldr x0,[tbl]` / `blr xN`) | e.g. 0x188407a30–0x188407a44, 0x1884058d8–0x188405900 |
| `_EAGLContextPrivate` layout + dispatch record | `-getMacroContextPrivate` 0x1d3f5211c = `return _private+0x20`; `+setCurrentContext:` 0x1d3f517ec stores `ctx->_private` in TLS slot 0xf0; stubs read `[rec+0x20]` as arg0 and `[rec+0x20+T]` as the function |
| Table size | `-[EAGLContext dealloc]` bzeroes 0x2060 bytes at `_private+0x28` (0x1d3f51770) |
| IOSurface → render texture → FBO order | `make_buffer_current` 0x188407980: gen 0x318, bind 0x30, texparam 0x988 ×4, `attachImage` 0x188407ac8, genFBO 0x1518, bindFBO 0x1508, `glFramebufferTexture2D` 0x1530, unbind |
| IOSurface → sampled texture | `attach_surface_texture` 0x188408e58 (`texImageIOSurface…invert:`) and 0x188409048 (`attachImage…invertedRender:NO`), `glLabelObjectEXT` 0x1978 at 0x188408e68 |
| Teardown order (textures, then FBOs) | `finalize_surface` 0x188407408: 0x1e0 then 0x1510 |
| Fences are real `GLsync` objects | `set_fence` 0x1884058b8 = `glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE,0)`; `test_fence` 0x1884058d0 = `glClientWaitSync(s, GL_SYNC_FLUSH_COMMANDS_BIT, 0)`; `delete_fence` = `glDeleteSync` |
| Discovery outside QuartzCore: `IOGLESBundleName`, `IOGLESMetalBundleName`, `UseMetal`/`com.apple.opengl`, `/System/Library/Extensions/%s.bundle`, `gldInitializeLibrary`, `gldGetVersion`, `gliInitializeLibrary`, `GL_BORON`, `IOAcceleratorES(Legacy)` | `libGFXShared` `_gfxInitializeLibrary` 0x1d3f6e2f0–0x1d3f6e970; `OpenGLES` `commonInitWithAPI:` 0x1d3f52550–0x1d3f52670 |
| `CA_ENABLE_OGL` default 1, Metal step first, GLES second, `sw_renderer()` third | lane A §Summary/§2 (A:12–13, A:84–86) |
| Kernel contract | `xnu-avicii/patches/0126-avicii-gpu-kgsl-drm-uapi.patch`: `struct drm_msm_gem_info` :1552, `MSM_INFO_IOS_IMPORT 0x85` :1799, handler :2006–2012, `drm_ioctl` nr/type :2085–2092, `MSM_INFO_IOS_MMAP 0x80` :1736, `MSM_INFO_GET_IOVA` :2016, pad pages :1804–1808, per-process dedupe :1820–1830 |
| Import refuses program-owned memory (`s->wrapped`), pages start at offset 0 | `refs/marnov999-ios26-sweet/xnu/patches/0100-sweet-new-files.patch:35580–35603` |
| HackiOS's kernel returns offset/rowBytes/format *with* the handle | `refs/heliumstudio-hackios-xnu-kernel/xnu/files/iokit/Kernel/hakios.gpu.cpp:144–150, 780` |
| raphael: `IOGLESBundleName = "SweetGLES"`, `IOGLESDefaultUseMetal = false`, bundle installed at `System/Library/Extensions/SweetGLES.bundle/SweetGLES` | `refs/marnov999-raphael-ios-gpu/xnu/patches/0112-…:950–952`, `tools/sweet-root-overlay.py:72` |

Versions: `QuartzCore` sha256 `d1fe6d891fccac80…` (lane A provenance table, A:33), `OpenGLES`
`8378139226c88ce7…`, `libGFXShared` `48a9656f7da861dd…`, both iOS 16.7.16 (20H392) from the cryptex.
`eagl_slots.txt` (the offset→name map) is HackiOS's, read from iOS 16.5 (20F66); I re-derived every
name used here from the 16.7.16 `OpenGLES` stubs themselves (`scratch/lane-2/out/offmap.txt`), and
the two agree, so the offsets are stable across those versions.

## 1. How the window server decides OpenGL ES is available

`CA::WindowServer::EAGLServer::renderer()` is the only gate, and it runs on the render thread when the
first commit needs a renderer:

1. `getenv("CA_ENABLE_OGL")` must not be `"0"` (A:84).
2. Metal is tried first and fails here (no `MetalPluginClassName` on `IOAcceleratorES`, A:17/§2).
3. `[NSMutableDictionary alloc] init`; `setObject:kCFBooleanTrue forKey:kEAGLContextPropertyAccelerated`;
   same for `kEAGLContextPropertyClientRetainRelease` (0x1882eb058–0x1882eb09c). Those two keys are the
   only ones QuartzCore uses; `Sharegroup`, `SharedWithCompute`, `ClientLabel`,
   `VisibleInDebugTools` exist in `OpenGLES` but are not passed.
4. `[[EAGLContext alloc] initWithAPI:3 properties:dict]`; if `nil`,
   `initWithAPI:2 properties:` (0x1882eb0a4–0x1882eb0f8).
5. `[ctx setParameter:0x260 to:&(int){0}]` (0x1882eb0fc–0x1882eb10c). Return value ignored.
6. `if ([ctx API] != 3) give up` (0x1882eb118–0x1882eb124) — so an API-2-only shim buys nothing.
7. `new CA::OGL::GLESContext(ctx)` (0x1882eb128–0x1882eb140) and `new CA::OGL::Renderer(context)`.

The bundle-name properties (`IOGLESBundleName` etc.) only matter for *Apple's* `EAGLContext`
implementation, which `-commonInitWithAPI:` loads through `libGFXShared`. If the shim replaces
`-initWithAPI:properties:` wholesale, no bundle is consulted for the window server — but publishing
`IOGLESBundleName` is still worth doing because applications load their own `EAGLContext` through the
same path and Apple's implementation is what they get unless the shim is inserted into them too.
`libGFXShared` builds `/System/Library/Extensions/%s.bundle` from that property and `dlopen`s
`%s/%s`; `OpenGLES` appends `/GLEngine.bundle/GLEngine` and `dlsym`s `gliInitializeLibrary`, then
resolves 19 further entry points by inline 8-byte name (`gliChoose…`, `gliDestr…`, `gliQuery…`,
`gliAttac…`, `gliPrese…`) and stores them at `gfx_shared+8…+0x98`. That is the deeper (GLD/GLEngine)
plugin ABI; the shim does not have to implement it and neither HackiOS nor raphael do.

## 2. The ABI the shim has to satisfy

Apple's `EAGLContext` keeps a `_private` (`ivar` at `+8`, type
`^{_EAGLContextPrivate=@@QI^{__GLIContextRec}{__GLIFunctionDispatchRec=…}{__GLIFunctionDispatchRec=…}}`):

```
+0x00  id        a value returned by +currentContext            (set it to the EAGLContext)
+0x08  id        sharegroup  (only used by -dealloc, -attachImage…, -setParameter:to:)
+0x10  uint64_t  api
+0x18  uint32_t  flags
+0x20  void     *context  == table[0], passed as arg0 to every slot function
+0x28  void     *table[1]  == slot offset 0x08
+0x30  void     *table[2]  == slot offset 0x10
+…               (table 0x2068 bytes long, header + table = the 0x2088 the dealloc bzeroes)
```

`-[EAGLContext getMacroContextPrivate]` is literally `return _private + 0x20` (0x1d3f5211c). Every
`gl*` in `OpenGLES.framework` is a six-instruction stub:

```
mrs x8, TPIDRRO_EL0 ; ldr x8,[x8,#0xf0] ; cbz x8,ret
ldr x3,[x8,#0x20+T] ; ldr x0,[x8,#0x20] ; (args shifted) ; br x3
```

with `T` the offsets in the table below — so **the table is the API**. `+[EAGLContext setCurrentContext:]`
only does `TLS[0xf0] = ctx->_private` (plus retain/release), so once `_private` points at our table the
stock `OpenGLES.framework` stubs work for application code too. QuartzCore itself never goes through
TLS: it calls `getMacroContextPrivate` once (ctor) and then `table[T]` directly.

Notes that cost time if missed:

* `table[0]` is the argument, `table[1]` (offset 0x08) is called by nothing and may be `NULL`.
* Slot `T` lives at `table[T/8]`, so `glAlphaFunc` (`T = 0x10`) is `table[2]`; the numbering is the
  `eagl_slots.txt` one (offset from the start of the *table*), not from `_private`.
* A `NULL` slot is executed as `br x0` to address 0, so **every offset in §4 must be non-NULL even if
  it only logs and returns**.
* With `_private` set, `-[EAGLContext dealloc]` calls `gliDestroyContext` through
  `_private->sharegroup` — either replace `dealloc` or build a sharegroup stub.

Recommended construction: `calloc(0x2088)`, `table = p + 0x20`, `table[0] = ctx`, fill
`table[T/8]` for every `T` in §4, `object_setIvar(ctx, ivar_(EAGLContext,_private), table - 0x20)`.

## 3. Required Objective-C surface

| Selector / symbol | Required? | Implemented by | Notes |
|---|---|---|---|
| `+[EAGLContext alloc]` | yes | stock (NSObject) | instance size 24, ivars `_private` only |
| `-initWithAPI:properties:` (`@32@0:8Q16@24`) | **yes** | `eglGetPlatformDisplay`+`eglCreateContext` (ES3) or `redwood_gl_create()` as HackiOS | must return a non-nil object for api 3 and set `_private`; api 2 may return an ES2 context and the callers will drop it |
| `-API` (`Q16@0:8`) | **yes** | return 3 | checked at 0x1882eb120 |
| `-getMacroContextPrivate` (`^{EAGLMacroContext=}16@0:8`) | **yes** | return the table | `_private+0x20` if you follow Apple's layout |
| `-setParameter:to:` (`Q28@0:8I16^i20`) | **yes** | log + return 0 is enough for 0x260 | only call site is `setParameter:0x260`, return ignored |
| `+currentContext` / `+setCurrentContext:` | **yes** | stock (works once `_private` is sane) | QC saves + restores the current context around work (0x188549b20–0x188549b48) |
| `-attachImage:toCoreSurface:invertedRender:` (`B36@0:8Q16^{__IOSurface=}24B32`) | **yes** | import surface → EGLImage → `glEGLImageTargetTexture2DOES` on the bound texture, else CPU copy | called with `target=GL_TEXTURE_2D`, `invertedRender=NO`, from `make_buffer_current` and `attach_surface_texture` |
| `-texImageIOSurface:target:internalFormat:width:height:format:type:plane:invert:` (`B72@0:8^{__IOSurface=}16Q24Q32I40I44Q48Q56I64B68`) | **yes** | same, for sampled textures | `format` is `GL_BGRA`, `type` `GL_UNSIGNED_BYTE`, `plane` 0; `invert` says the picture is upside down |
| `-dealloc` (`v16@0:8`) | **yes** (if `_private` set) | release GL objects, free table, call super | Apple's version needs a GLI plugin |
| `-renderbufferStorage:fromDrawable:` (`B32@0:8Q16@24`) | no for the window server | — | no call site in QuartzCore; needed only for `CAEAGLLayer` app drawing. It reads `EAGLDrawablePropertyColorFormat`/`…Retained` off the drawable and maps `EAGLColorFormat8888`→`GL_RGBA8`, `565`→`GL_RGB565`, `S8888`/`SRGB_XR10`/`…_64BPP` to their formats (0x1d3f518f4–0x1d3f51b20) |
| `-presentRenderbuffer:` (`B24@0:8Q16`), `…:atTime:` / `…:afterMinimumDuration:` (`B32@0:8Q16d24`) | no | `eglSwapBuffers` or nothing | present is done by `IOMobileFramebufferSwap*` in the window server (A §3); app-side only |
| `-sharegroup` (`@16@0:8`) | no | return `nil` (HackiOS) or a stub `EAGLSharegroup` | CoreImage asks for it and crashes on Apple's accessor with an unset `_private` (eagl.c:3855–3874) |
| `-setBlockFence:onQueue:` (`B32@0:8@?16@24`) | no | ignore, return YES | no call site found |
| `-nativeWindow` | no | return a zeroed `_EAGLNativeWindowObject` | 9 fields, `{int, uint, ptr×7}` |
| `-drawableProperties`, `-getGLIShared`, `-GetMacroContextPrivate`, `-init`, `-initWithAPI:`, `-initWithAPI:sharegroup:`, `-initWithAPI:sharedWithCompute:`, `-commonInitWithAPI:properties:`, `-loadGLIPlugin:sharedWithCompute:`, `-debugLabel`/`-setDebugLabel:`, `-multiThreaded`/`-isMultiThreaded`/`-setMultiThreaded:` | no | stock or one-liners | `commonInit…`/`loadGLIPlugin…` are only reached if you *don't* replace `initWithAPI:properties:` |

`EAGLSharegroup` (added if you ever do implement it): `_private` is
`^{_EAGLSharegroupPrivate=QiB^{__GLDPixelFormatRec}^{__GLISharedRec}}`, 9 methods, `initWithAPI:`.

## 4. Required C surface

All 58 offsets below have at least one call site in QuartzCore and must be non-NULL. They are plain
`libGLESv2` entry points under a different name; the "implemented by" column says what the shim body
does. The `n=` column is the site count, the address is the first site — the whole site list is
`scratch/lane-2/out/slots.json` and can be regenerated with `scratch/lane-2/slots.py`.

Groups, for reading: ES1 leftovers 0x10, drawing/clear 0x58/0x68/0x210/0x220/0x2d0/0x2d8, state
0x200/0x248/0x620/0x7e0/0x7f8/0xa80–0x0ab8, textures 0x30/0x1c8/0x318/0x970/0x978/0x988/0x9a0/0xbe8,
vertex arrays 0x1000–0x1010, shaders and uniforms 0x1280–0x1390, framebuffers
0x1508/0x1510/0x1518/0x1530/0x1550/0x2008, sync 0x1878/0x1870/0x1860/0x0eb8, debug 0x1978–0x1998,
queries 0x338/0x348.

| Symbol (offset) | Required? | Implemented by | Notes |
|---|---|---|---|
| `glAlphaFunc` 0x0010 (n=1) | yes | `glAlphaFunc` | ES1 leftover, called in `GLESContext::update` |
| `glBindTexture` 0x0030 (n=6) | yes | pass through | always `GL_TEXTURE_2D` |
| `glBlendFunc` 0x0040 (n=1) | yes | pass through | `load_blend_func` |
| `glClear` 0x0058 (n=2) | yes | pass through | |
| `glClearColor` 0x0068 (n=3) | yes | pass through | |
| `glCopyTexSubImage2D` 0x01c8 (n=1) | yes | pass through | `copy_destination` |
| `glDeleteTextures` 0x01e0 (n=7) | yes | pass through + drop the image cache entry | `purge`, `finalize_surface` |
| `glDisable` 0x0200 (n=5) | yes | pass through | |
| `glDrawArrays` 0x0210 (n=3) | yes | pass through | |
| `glDrawElements` 0x0220 (n=1) | yes | pass through | |
| `glEnable` 0x0248 (n=2) | yes | pass through | |
| `glFinish` 0x02d0 (n=3) | yes | pass through | `finish_image`, `finish` |
| `glFlush` 0x02d8 (n=2) | yes | pass through | `flush_texture_cache` |
| `glGenTextures` 0x0318 (n=6) | yes | pass through | |
| `glGetError` 0x0338 (n=1) | yes | pass through | polled by `GLContext::get`, must stay cheap |
| `glGetIntegerv` 0x0348 (n=2) | yes | pass through | `GL_DRAW_FRAMEBUFFER_BINDING` in `update` (0x8ca6, 0x188405744) and `GL_VIEWPORT` in `init_state` (0xba2, 0x1884b1270); the ctor also reads `GL_MAX_TEXTURE_IMAGE_UNITS`, `GL_MAX_TEXTURE_SIZE`, `GL_MAX_CUBE_MAP_TEXTURE_SIZE`, `GL_MAX_3D_TEXTURE_SIZE` (0x8872/0xd33/0xd3a/0xd50, 0x188409aa4–0x188409c14) — do not clamp, the limits drive CA's tiling decisions |
| `glPixelStorei` 0x0620 (n=7) | yes | pass through | `init_state` |
| `glScissor` 0x07e0 (n=3) | yes | pass through | |
| `glStencilFunc` 0x07f8 (n=2) | yes | pass through | |
| `glTexImage2D` 0x0970 (n=5) | yes | pass through; `internalFormat` may be `GL_BGRA` (Apple's `GL_RGBA`+`format=GL_BGRA` means BGRA8) | `create_surface`, `update_image`, `attach_surface_texture` fallback copy |
| `glTexParameterf` 0x0978 (n=2) | yes | pass through | |
| `glTexParameteri` 0x0988 (n=37) | yes | pass through | most frequent slot; filters/wrap modes incl. `GL_TEXTURE_RECTANGLE_APPLE` targets |
| `glTexSubImage2D` 0x09a0 (n=3) | yes | pass through | `modify_subimage_impl` |
| `glViewport` 0x0a80 (n=2) | yes | pass through | |
| `glBlendFuncSeparate` 0x0a88 (n=1) | yes | pass through | |
| `glBlendEquation` 0x0a98 (n=1) | yes | pass through | |
| `glActiveTexture` 0x0ab8 (n=6) | yes | pass through | |
| `glCompressedTexImage2D` 0x0be8 (n=1) | yes | pass through (ASTC/PVRTC must be in `GL_EXTENSIONS`) | `update_compressed_image` |
| `glFinishObjectAPPLE` 0x0eb8 (n=1) | yes | `glFinishObjectAPPLE` if Mesa has it, else `glFinish` | `finish_image` names the texture it finished; fences themselves are real `GLsync` objects (§Evidence: `set_fence`) |
| `glVertexAttribPointer` 0x1000 (n=12) | yes | pass through | |
| `glEnableVertexAttribArray` 0x1008 (n=8) | yes | pass through | |
| `glDisableVertexAttribArray` 0x1010 (n=10) | yes | pass through | |
| `glDeleteProgram` 0x1280 (n=1) | yes | pass through | `purge` |
| `glCreateShader` 0x1298 (n=2) / `glShaderSource` 0x12a0 (n=2) / `glCompileShader` 0x12a8 (n=1) | yes | pass through | the shader cache compiles at supervisor start |
| `glUseProgram` 0x12c8 (n=5) | yes | pass through | |
| `glUniform1f` 0x12d8 / `glUniform4f` 0x12f0 / `glUniform1i` 0x12f8 / `glUniform3fv` 0x1328 / `glUniform4fv` 0x1330 (n=8) / `glUniformMatrix3fv` 0x1360 / `glUniformMatrix4fv` 0x1368 | yes | pass through | |
| `glGetUniformLocation` 0x1390 (n=36) | yes | pass through | must be cheap: called per shader binding |
| `glBindFramebuffer` 0x1508 (n=5) | yes | pass through | `set_surface` |
| `glDeleteFramebuffers` 0x1510 (n=1) | yes | pass through | `finalize_surface` |
| `glGenFramebuffers` 0x1518 (n=2) | yes | pass through | |
| `glFramebufferTexture2D` 0x1530 (n=2) | yes | pass through | `GL_COLOR_ATTACHMENT0` ← the attached surface texture |
| `glGenerateMipmap` 0x1550 (n=3) | yes | pass through | |
| `glFenceSync` 0x1860 (n=1) | yes | pass through, real `GLsync` | `set_fence`: `(GL_SYNC_GPU_COMMANDS_COMPLETE, 0)` |
| `glClientWaitSync` 0x1878 (n=1) | yes | pass through | `(s, GL_SYNC_FLUSH_COMMANDS_BIT, 0)`; caller treats `0x911A…0x911D` as poll answers |
| `glDeleteSync` 0x1870 (n=1) | yes | pass through | |
| `glLabelObjectEXT` 0x1978 (n=1) | yes | `glObjectLabel`-style stub or no-op | `EXT_debug_label` |
| `glInsertEventMarkerEXT` 0x1988 / `glPushGroupMarkerEXT` 0x1990 / `glPopGroupMarkerEXT` 0x1998 (n=1 each) | yes | no-ops are fine | `EXT_debug_marker` |
| `glFramebufferParameteriAPPLE` 0x2008 (n=1) | yes | wrapper: Apple calls it `(GL_FRAMEBUFFER, 0x8A79, GLint *out)` and reads the written int back (0x18840773c–0x188407758) — pass `*out` to Mesa's by-value version or keep an own sample-count | **the only slot past the last exported `gl*` stub; pname 0x8A79 is Apple-private (inferred: MSAA sample count)** |

`GL_EXTENSIONS` must contain, or `GLESContext` takes a cheaper path or errors out (all 16 checked in
the ctor, 0x188409764–0x188409b10): `GL_APPLE_fence`, `GL_APPLE_texture_filter_cubic`,
`GL_APPLE_texture_ycbcr_basic_formats`, `GL_APPLE_texture_ycbcr_extended_formats`, `GL_APPLE_texture_xr`,
`GL_APPLE_tile_order_rot`, `GL_EXT_shader_framebuffer_fetch`, `GL_EXT_texture_filter_anisotropic`,
`GL_EXT_texture_lod_bias`, `GL_IMG_texture_compression_pvrtc`, `GL_KHR_texture_compression_astc_ldr`,
`GL_OES_standard_derivatives`, `GL_OES_texture_float`, `GL_OES_texture_float_linear`,
`GL_OES_texture_half_float`, `GL_OES_texture_half_float_linear`. `check_extension` only does a substring search of the string QuartzCore got from
`glGetString(GL_EXTENSIONS)` (no per-renderer tables, no version parsing), so what Mesa reports
decides; `CA_DISABLED_EXTENSIONS=<name>…` turns any one off without a rebuild (same ctor also caches
`CA_DISABLE_WORKAROUNDS`, `CA_MAX_TEXTURE_UNITS`, `CA_MAX_TEXTURE_SIZE` from the environment,
0x1884096c4–0x188409710). The ctor's three `glGetString` calls are `GL_EXTENSIONS` (0x1f03),
`0x8a1e` (fetched, not used by `check_extension`) and `GL_RENDERER` (0x1f01, also unused by it);
`GL_VERSION`/`GL_SHADING_LANGUAGE_VERSION` are not queried at all at this point. Advertise an ES 3.x
version string anyway (`OpenGL ES 3.2 …`), because Mesa's own and any app's behaviour depends on it.

## 5. IOSurface ↔ texture/renderbuffer path

Order, as executed (all under `set_surface`/`make_buffer_current`, 0x188407980):

1. `glGenTextures(1,&tex)` (0x318), `glBindTexture(GL_TEXTURE_2D,tex)` (0x30);
2. `glTexParameteri` MIN/MAG `GL_NEAREST`, WRAP_S/T `GL_CLAMP_TO_EDGE` (0x988);
3. `[eaglContext attachImage:GL_TEXTURE_2D toCoreSurface:surfaceIOSurface invertedRender:NO]`;
4. `glGenFramebuffers` (0x1518), `glBindFramebuffer(GL_FRAMEBUFFER,…)` (0x1508),
   `glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0)` (0x1530),
   `glBindFramebuffer(GL_FRAMEBUFFER,0)`;
5. `glFramebufferParameteriAPPLE(GL_FRAMEBUFFER, 0x8A79, &samples)` for MSAA surfaces.

Surfaces that are only *sampled* go through `attach_surface_texture` → `-texImageIOSurface:…` with the
format triple Apple derived (`'BGRA'` → internal `GL_RGBA`/`GL_RGBA8`, format `GL_BGRA`, type
`GL_UNSIGNED_BYTE`; `'BGRA10_XR'`-class formats map to 10-bit/`GL_HALF_FLOAT`-style triples,
0x1d3f51d24–0x1d3f51e44). A surface with **pixel format 0** is memory CoreAnimation made a surface
around; it is opacity-first in memory (HackiOS reads it as `GL_BGRA` + an alpha-first swizzle,
eagl.c:3977–3988).

Mapping onto the kernel (contract `0126`):

* `IOSurfaceGetID(surface)` → `struct drm_msm_gem_info{ .info = MSM_INFO_IOS_IMPORT(0x85), .value = id }`
  via `_IOWR('d', 0x43, struct drm_msm_gem_info)` = `0xc0186443` on `/dev/dri/renderD128` → `.handle`.
  The kernel holds the surface for the buffer's life, appends 128 scratch pages behind it, and gives
  the same handle back for the same surface *in the same process* (0126:1820–1830) — so cache
  id→handle per process and close with `DRM_NR_GEM_CLOSE`.
* `eglCreateImageKHR(dpy, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, NULL, {fourcc, w, h, stride, offset 0})`
  with the *handle used as the fd* (the `fd==handle` convention is 0126's own, 0126:1795);
  the libdrm shim must therefore answer `PRIME_FD_TO_HANDLE` locally (0126 has no PRIME ioctl,
  0126:1975). `fourcc` from `IOSurfaceGetPixelFormat` (`'BGRA'`→`DRM_FORMAT_ARGB8888`), `stride`
  from `IOSurfaceGetBytesPerRow`, `offset` 0 (0126 maps from the allocation's first page,
  `sweet_surface_gpu_pages` starts at `off = 0`, sweet:35590).
* No MSAA/modifier: `EGL_LINUX_DMA_BUF_EXT` needs `EGL_EXT_image_dma_buf_import`; linear only.
* CPU fallback when the import fails (`ENOENT`/`EINVAL`, e.g. a `wrapped` surface, sweet:35594–35596):
  `IOSurfaceLock` + `glTexImage2D`/`glTexSubImage2D` copy per change.
* `MSM_INFO_IOS_MMAP` (0x80) and `MSM_INFO_GET_IOVA` (0x01) exist for CPU access and debugging.

Who presents: nobody in the renderer. `finish_image` only ends with `glFinishObjectAPPLE` (0x0eb8) or
`glFinish` (0x2d0), and the surface then goes to `IOMFBDisplay::finish_update` →
`IOMobileFramebufferSwapBegin/SetLayer/SwapEnd` (A §Summary 1, A §3). `QuartzCore` imports the whole
`IOMobileFramebufferSwap*` set; `presentRenderbuffer:` has **no** call site in it.

## 6. Cross-check with HackiOS `eagl.c`

Implements: `initWithAPI:properties:` (creates the context in a real GL library, builds the table with
`mkeagl.py` from `gl.xml` against that library's exports, eagl.c:3815–3843), `API`, `sharegroup`
(`nil`), `setParameter:to:` (logs), `getMacroContextPrivate` (returns the table),
`texImageIOSurface:…` and `attachImage:…` (both take the *currently bound* texture, reject anything but
`GL_TEXTURE_2D`/`'BGRA'`, and fall back to CPU copies with a summed-hash change check,
eagl.c:3897–4008), `dealloc`. Stubs: everything else in §3. Loads via `DYLD_INSERT_LIBRARIES`
(`userland/src/inject.c:5`, kernel `sweetinsert=` boot-arg in docs/anonbeat1-NOTES.md:1322–1328).

Gaps against §3–§5: no `renderbufferStorage:fromDrawable:` (so `CAEAGLLayer` app drawing is dead), no
`presentRenderbuffer:`, no `sharegroup` (CoreImage breaks), no `_private` (so app-side `gl*` through
`OpenGLES.framework` no-ops: `_private` stays 0 → TLS 0 → stubs return immediately), only ES2 API
accepted, its import path is its own kernel client (`RedwoodGPUUserClient::surfaceBuffer`) rather than
`0126`, and offset 0x2008 (`glFramebufferParameteriAPPLE`) is generated by `mkeagl.py` only if the
library exports it. raphael is the same file with performance work in `attachImage`
(`eagl-raphael.patch:75,124`: never-written surfaces are cleared by the GPU instead of copied).

## 7. What must not be copied from HackiOS

* `surfaceBuffer` takes a `struct hakios_surface *` and fills `offset/rowBytes/pixelFormat/w/h/planes`
  (hakios.gpu.cpp:144–150). `0126` returns only `gi->handle`, and expects `value` = the **surface id**,
  not a pointer. Follow `0126`; get geometry from `IOSurface`.
* `IOGLESBundleName` on raphael points at a `SweetGLES.bundle` whose binary is a `gld*`/`gli*` plugin.
  Our shim can be shipped as that bundle *and* as the inserted dylib, but the dylib is the part that
  matters for backboardd on day one.
* HackiOS leaves `table[1]` (0x08) unfilled; harmless, keep it `NULL` with a logging stub if you prefer.

## 8. Plan

1. **Table skeleton first, no Mesa.** Insert a dylib into backboardd (`sweetinsert=backboardd`
   boot-arg) whose constructor `dlopen`s `OpenGLES`, `class_addMethod`s the eight methods of §3's
   required set, allocates a table of 0x2088 and fills every offset in §4 with one stub that logs `offset, arg0..arg5` once and
   returns 0. Verify: `/var/log` console or serial-less log ring shows the offsets in call order and
   `CA::OGL::GLESContext` being constructed (`-initWithAPI:properties:`, `-API` → 3). A missing
   offset shows up as a crash with a `br` target of 0.
2. **Wire the table to Mesa.** Load `libGLESv2.2.dylib` (lane C) with `dlopen`, fill each slot from
   `dlsym` of the same `gl*` name, with `-1`-to-`GLES2` fallbacks for ES1-only names as `mkeagl.py`
   does (`mkeagl.py:74–81`). Verify: `glGetString(GL_VERSION)`/`(GL_RENDERER)`/`(GL_EXTENSIONS)` in the
   log, `GLESContext` ctor returning instead of erroring.
3. **Surface import.** Implement the id→handle→EGLImage path of §5 plus the copy fallback, driven by
   `attachImage`/`texImageIOSurface`. Verify: kernel console lines `SWEET DRM: ios_import surf N ->
   handle H …` (0126:1894) once per surface, no repeat per frame (the per-process dedupe must hit).
4. **Fences and finish.** Real `GLsync`, `GL_APPLE_fence` in the extension string. Verify:
   `test_fence` returns without `GL_TIMEOUT_EXPIRED` storms; no `SWEET DRM: fence … waited`.
5. **Present.** Only for app processes: `presentRenderbuffer:` → `eglSwapBuffers` on a surface-backed
   default framebuffer, or `IOSurface` handover to `IOMobileFramebuffer`. Verify with the test program.
6. **Rendering smoke test in the window server.** Run the §9 test program first standalone, then look at
   the screen: a correctly coloured, correctly oriented first frame; `CA_ENABLE_OGL=0` must still fall
   back to the CPU renderer.

## 9. Minimal test program (§outline)

`eagl_test.m`, in scratch, run over ssh; makes and uses one context, no CA, no app bundle.

```
install:  dlopen("/System/Library/Frameworks/OpenGLES.framework/OpenGLES", RTLD_NOW)
          (and dlopen the shim itself if not injected)
setup:    dict = {kEAGLContextPropertyAccelerated:@YES, kEAGLContextPropertyClientRetainRelease:@YES}
          ctx  = [[EAGLContext alloc] initWithAPI:3 properties:dict];   assert ctx, [ctx API]==3
          assert +[EAGLContext setCurrentContext:ctx]
          tbl  = [ctx getMacroContextPrivate];  assert tbl && tbl[0]
          for each offset of §4: assert tbl[off/8] != NULL     (a NULL is a jump to 0 later)
surface:  IOSurfaceCreate({w:64,h:64,'BGRA',bytesPerRow:256}) → s   assert s
          glGenTextures(0x318), glBindTexture(0x30, tex)
          assert [ctx attachImage:GL_TEXTURE_2D toCoreSurface:s invertedRender:NO]
framebuffer: glGenFramebuffers(0x1518)/glBindFramebuffer(0x1508)/glFramebufferTexture2D(0x1530)
             assert dlsym(libGLESv2,"glCheckFramebufferStatus")(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE
             (glCheckFramebufferStatus is not a table slot — QuartzCore never checks, the test should)
draw:     glViewport(0xa80,0,0,64,64); glClearColor(0x68,1,0,0,1); glClear(0x58); glFinish(0x2d0)
check:    assert glGetError()==0
          IOSurfaceLock(s, kIOSurfaceLockReadOnly); assert base[32*256+32*4..+4] == 00 00 ff ff
          (BGRA in memory: red = bytes 00 00 ff ff); IOSurfaceUnlock
fence:    sync = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE,0); glFinish;
          assert glClientWaitSync(sync, GL_SYNC_FLUSH_COMMANDS_BIT, 0) in {0x911A,0x911C}
teardown: glDeleteSync, glDeleteFramebuffers, glDeleteTextures, [EAGLContext setCurrentContext:nil],
          release ctx, IOSurfaceRelease
```

Negative cases worth keeping: a `wrapped` surface (must fall through to the copy path), an API-2
context (must be non-nil and then rejected by `[ctx API]!=3`), and `attachImage` with target ≠
`GL_TEXTURE_2D`.

## 10. Open questions

* **`glFramebufferParameteriAPPLE` 0x2008**: signature and pname 0x8A79 are inferred from the single
  call site (an out-pointer is written). Needs one run with the offset traced to confirm whether it is
  the MSAA sample count and what `GLESContext` does with the answer.
* Whether the four limits the ctor reads (`GL_MAX_TEXTURE_SIZE`, `GL_MAX_TEXTURE_IMAGE_UNITS`,
  `GL_MAX_CUBE_MAP_TEXTURE_SIZE`, `GL_MAX_3D_TEXTURE_SIZE`) are used to size CA's tiling; Mesa's
  numbers should be passed through unchanged, but a value that disagrees with what CA assumes (e.g.
  `CA_MAX_TEXTURE_SIZE`) has to be found by running.
* Nothing in this lane needed the phone. When the shim exists, the only phone-side prerequisite is a
  boot-arg carrying the insert list (`sweetinsert=backboardd[,app…]`, docs/anonbeat1-NOTES.md:1322–1328)
  — a kernel-side change for the main agent — plus `CA_ENABLE_OGL` left unset (default 1).
* Does Mesa's freedreno accept an `EGLImage` whose only backing is a GEM handle, or does it need
  `fd_bo_from_dmabuf` to see a real `DRM_IOCTL_PRIME_FD_TO_HANDLE`? Lane C owns the shim answer.
* `GL_TEXTURE_RECTANGLE_APPLE` (0x8D41) appears in the format mapping; ES3 has no such target, so its
  use has to be translated or the extension string must hide it (untested which `GLESContext` path
  takes it).
* Alias of `IOSurfaceGetBytesPerRow` vs the kernel's `allocSize` pages: a surface whose rows are
  padded is fine for a texture but the import maps whole pages, so `GL_UNPACK_ROW_LENGTH`-style stride
  handling must match exactly.
* Whether backboardd's `_dyld_register_func_for_add_image` timing is needed before `objc_getClass`
  on `OpenGLES` (HackiOS needed it for a CoreImage swizzle, docs/anonbeat1-NOTES.md:1317).

## 11. Scratch

`~/.hermes/cache/scratch/lane-2/out/`: `opengles.dis`, `opengles.exports.txt`, `offmap.txt`
(offset→`gl*` name read off the 16.7.16 stubs), `qc.methname.txt`, `qc.classname.txt`,
`slots.json` (58 offsets, 229 sites). `sect.py`, `strsec.py`, `range.py`, `offmap.py`, `slots.py`,
`selref.py` are the extractors. No repo file other than this one was touched.
