# Codex task A: SweetEAGL, the EAGL shim QuartzCore renders through

**Repo:** `/home/tadej/ios-nord`.
**Branch:** create `codex/eagl-shim` from `kern-0122` (HEAD `71c39d0` or later).
**Work only in:** `tooling/gpu/sweeteagl/` (new).
**Output:** host-built, ad-hoc signed arm64 iOS 16 Mach-O files. The main agent (Claude) runs them on the phone; you do not.

## Why this exists

The iOS port on the OnePlus Nord renders its UI on the CPU at about 24 fps. The GPU stack is now
proven from userland. Mesa 25.0.7 freedreno, built as `libOSMesa.8.dylib`, renders on the A620
through our own kernel driver: `GL_RENDERER FD620`, clear and triangle pass. You can see this in
`tooling/gpu/osmesatest/osmesatest.c`.

QuartzCore (backboardd's compositor) will use OpenGL ES if `EAGLContext` gives it a working
context. Your job is the piece in between: a dylib that makes Apple's `EAGLContext` class produce
contexts backed by our OSMesa.

## Read first, in this order

1. `docs/gpu-research/E-eagl-shim-spec.md` is **the spec**. §2 covers the ABI and table layout,
   §3 the ObjC methods, §4 the 58 slots, §5 the IOSurface path and §9 the test outline.
2. `docs/gpu-research/data/eagl-slots.json` lists the 58 offsets and call sites.
   `docs/gpu-research/data/eagl-offmap.txt` maps every offset to its `gl*` name from iOS 16.7.16.
3. `tooling/gpu/mesa-patches/0005-osmesa-gpu-screen-and-surface-textures.patch` shows that
   `glEGLImageTargetTexture2DOES(target, (GLeglImageOES)(uintptr_t)iosurface_id)` makes an
   IOSurface's memory the bound texture's storage. That is the import path. There is no EGL, and
   you do not do the DRM ioctls yourself.
4. `tooling/gpu/osmesatest/` is the working pattern for building, `dlopen`ing and dlsym-ing the
   library.
5. `refs/gsjsjzhznsz-hackios-xnu-userland/userland/src/eagl.c` is a read-only reference for an
   earlier shim. See spec E §6/§7 for what differs. Do **not** copy its kernel-client code.

## Hard rules

- No Apple SDK, and no Apple headers or code copied in. Declare the few Objective-C runtime,
  CoreFoundation and IOSurface prototypes yourself, in your own header.
  - The sysroot has **no** `objc/` headers and **no** `libobjc` stub. Resolve the ObjC runtime
    with `dlopen("/usr/lib/libobjc.A.dylib")` + `dlsym`: `objc_getClass`, `sel_registerName`,
    `class_replaceMethod`, `class_addMethod`, `class_getInstanceVariable`, `object_setIvar`,
    `object_getIvar`, `objc_msgSend`, `objc_msgSendSuper2` or `class_getSuperclass` +
    `method_getImplementation`.
  - IOSurface and CoreFoundation may link against the stubs in
    `build/gpu/sysroot/System/Library/Frameworks/*.framework/*.tbd`, or be resolved by `dlsym`.
- Build with `tooling/opt/llvm/bin/clang`, using the flags in `tooling/gpu/osmesatest/build.sh`:
  - `-target arm64-apple-ios16.0 -isysroot build/gpu/sysroot -DXNU_PLATFORM_iPhoneOS`
  - `-fuse-ld=lld -Wl,-adhoc_codesign`
  - plus `-shared` for the dylib.
- Write it in C. Objective-C would need headers we don't have.
- **Never use `@rpath`/`@loader_path`/`@executable_path`.** dyld refuses them on this phone with
  "security policy does not allow @ path expansion". Load `libOSMesa.8.dylib` by absolute path:
  - default `/System/Library/Extensions/SweetGLES.bundle/libOSMesa.8.dylib`, then
    `/private/var/root/gpu/libOSMesa.8.dylib`;
  - the environment variable `SWEETEAGL_MESA` overrides both.
- Do not touch `xnu-avicii/`, `avicii/`, `build/gpu/mesa-*`, the phone, or any git remote. No
  pushes. Commit only on your branch.
- No mystery numbers. Every offset, selector and type encoding you use must come from spec E or
  the data files, with a comment citing `E §n` or the offset.

## Deliverables (all in `tooling/gpu/sweeteagl/`)

### 1. `slots.h` / `slots.c`, generated

Generate them with `gen_slots.py` (Python 3, stdlib only) from the two data files. The result is a
table of `{offset, "glName"}` for **all 58 offsets** that have call sites, plus how each slot is
filled:
- `direct`: `OSMesaGetProcAddress(name)`, falling back to `dlsym`.
- `wrap`: your own function.

Commit the generator and its output.

### 2. `sweeteagl.c` → `SweetEAGL.dylib`

When the dylib loads (a `constructor`, or an explicit `sweeteagl_install()` export that the
constructor calls):
- `dlopen` `/System/Library/Frameworks/OpenGLES.framework/OpenGLES`, find class `EAGLContext`, and
  `class_replaceMethod` the required set from E §3:
  - `-initWithAPI:properties:`
  - `-API`
  - `-getMacroContextPrivate`
  - `-setParameter:to:`
  - `-attachImage:toCoreSurface:invertedRender:`
  - `-texImageIOSurface:target:internalFormat:width:height:format:type:plane:invert:`
  - `-dealloc`
  - `-sharegroup` (returns nil)
- Use the exact type encodings from E §3.

`initWithAPI:properties:`:
- Accept API 2 and 3, and report `API` = 3 for an API-3 request.
- Create an `OSMesaCreateContextAttribs` context (or `…Ext`), on its own small private colour
  buffer (QuartzCore always renders into FBOs).
- Lay `_private` out as E §2 describes: `calloc(0x2088)`, table at `+0x20`, `table[0]` = an
  opaque per-context pointer that every slot receives as arg0.
- Fill **every** one of the 58 slots. A NULL slot is a jump to address 0.
- Set the `_private` ivar.
- Leave `table[1]` NULL, or point it at a logging stub.

Slot calling convention (E §2): every slot function gets `table[0]` as arg0, followed by the normal
GL arguments. So every slot is a thin wrapper `ret w_glX(void *ctx, args…)`. The wrapper makes
`ctx`'s OSMesa context current if it isn't already, then calls Mesa's `glX(args…)`. Keep the
"already current" check cheap: `glGetError` and `glGetUniformLocation` are hot paths.

Special slots:
- **0x0eb8** `glFinishObjectAPPLE`: calls `glFinish`.
- **0x2008** `glFramebufferParameteriAPPLE(GL_FRAMEBUFFER, 0x8A79, GLint *out)`: writes `*out = 0`
  (the sample count, E §4/§10).
- **0x1978–0x1998** (debug labels and markers): no-ops.
- **0x0010** `glAlphaFunc`: pass through if OSMesa exports it, else a no-op.
- **`glGetString(GL_EXTENSIONS)`**: QuartzCore calls `glGetString` before anything else, so wrap
  it. Append the extension names from E §4 that Mesa doesn't report but that are safe to claim
  (`GL_APPLE_fence`, `GL_EXT_debug_label` …). Leave out the ones you cannot honour (PVRTC, YCbCr,
  `texture_xr`), and comment the choice. Also check whether `glGetString` is one of the 58
  offsets in the data files; the ctor's three calls (E §4) suggest it must be.

`attachImage:` and `texImageIOSurface:` (E §5):
- Act on the currently bound `GL_TEXTURE_2D`.
- Fast path: `glEGLImageTargetTexture2DOES(GL_TEXTURE_2D, (void *)(uintptr_t)IOSurfaceGetID(s))`.
- If `glGetError` reports a failure, take the **CPU fallback**: `IOSurfaceLock` read-only,
  `glTexImage2D` with BGRA from `IOSurfaceGetBaseAddress`/`BytesPerRow` (watch the row stride),
  then unlock. Remember per texture that it is a copy, so later frames re-upload. That is
  acceptable for now.
- Handle only target `GL_TEXTURE_2D` and pixel format `'BGRA'` or 0. Return NO for anything else.

Logging:
- Append to `/private/var/root/gpu/sweeteagl.log` (open with `O_APPEND`, no stdio buffering),
  once per event type, plus every method entry for the first N=200 calls.
- Never log per GL call after that.
- `SWEETEAGL_TRACE=1` logs the first call of each slot offset, which shows the call order (E §8
  step 1).

### 3. `eagltest.c` → `eagltest` (executable)

Implement E §9 exactly:
1. `dlopen` OpenGLES, then `/private/var/root/gpu/SweetEAGL.dylib` (overridable via argv).
2. Build the properties dict with CoreFoundation.
3. `[[EAGLContext alloc] initWithAPI:3 properties:]` through `objc_msgSend`, then assert
   `API`==3.
4. `setCurrentContext:`.
5. `getMacroContextPrivate`; assert that all 58 slots are non-NULL.
6. Create a 64×64 BGRA IOSurface (CoreFoundation dict with `IOSurfaceWidth`/`Height`/
   `BytesPerElement`/`BytesPerRow`/`PixelFormat`), gen/bind a texture, `attachImage`, then an
   FBO with `glFramebufferTexture2D` — all **through the table slots**, as QuartzCore does.
7. Check `glCheckFramebufferStatus` (dlsym'd from OSMesa).
8. Clear red, `glFinish`, lock the surface and check that pixel (32,32) reads bytes
   `00 00 ff ff`.
9. Fence test (`glFenceSync`/`glClientWaitSync` via the slots).
10. Tear down.

Print one `PASS`/`FAIL` line per step and exit non-zero on any FAIL. Also add a `--cpu` flag that
forces the CPU-copy path, so both paths can be tested.

### 4. `build.sh`, `check.sh`, `README.md`

`build.sh` builds both into `build/phone/gpu/` (`SweetEAGL.dylib`, `eagltest`) and prints sha256s.

`check.sh` is your **definition of done**. It is host-only and must exit 0. It checks:
- Both binaries build with zero warnings under `-Wall -Wextra`.
- Both have `LC_CODE_SIGNATURE`, `platform ios`, `minos 16.0`.
  Use `tooling/opt/llvm/bin/llvm-objdump --macho --private-headers`.
- `--dylibs-used` shows no `@rpath`/`@loader_path`/`@executable_path`.
- Every `direct` slot name in `slots.c` is exported by
  `build/gpu/mesa-build/src/gallium/targets/osmesa/libOSMesa.8.dylib` (`llvm-nm -gU`), or is
  reachable through `OSMesaGetProcAddress`. If it's only reachable that way, say so in the README
  and keep a list.
- Every one of the 58 offsets in `eagl-slots.json` appears in `slots.c` exactly once.
- Every undefined symbol in `SweetEAGL.dylib` (`llvm-nm -u`) is in one of the sysroot stubs or is
  `dyld_stub_binder`.

`README.md` covers:
- What each file is.
- How to run it on the phone. This is for Claude: `scp` to `/var/root/gpu/` next to
  `libOSMesa.8.dylib`, then `./eagltest` and `./eagltest --cpu`.
- Every decision you made that the spec left open.
- Every place you were unsure, marked `UNVERIFIED`.

## Done =

`tooling/gpu/sweeteagl/check.sh` exits 0, everything is committed on `codex/eagl-shim`, and the
README lists the open questions. Then stop and report:
1. the commit hash;
2. `check.sh` output;
3. the list of slots that aren't plain pass-throughs;
4. anything in spec E you think is wrong.

## Out of scope (don't do)

- The `SweetGLES.bundle` / `gldInitializeLibrary` plugin wrapper. That's the next task, once
  `eagltest` passes on the phone.
- Injecting into backboardd, editing plists, kernel patches.
- `renderbufferStorage:fromDrawable:` and `presentRenderbuffer:`. App-side only, a later task.
- Rebuilding Mesa or changing its patches. If OSMesa lacks something you need, write it down in
  the README instead.
