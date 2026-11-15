# SweetEAGL

C runtime replacement for eight `EAGLContext` methods, implementing the table
ABI described in [spec E](../../../docs/gpu-research/E-eagl-shim-spec.md).
The library and test are arm64 iOS 16.0 Mach-O files, cross-built on Linux.
No Apple SDK, Objective-C/framework headers, copied Apple implementation, EGL,
kernel client, or direct DRM calls are used. The repo's existing Darwin libc
headers and framework link stubs are used. All Objective-C calls use dynamically
resolved runtime functions.

`check.sh` is **host evidence only**. No phone binary has been executed here.
Rendering, runtime method compatibility, and cache coherency are **UNVERIFIED**.

## Files and build

| File | Purpose |
|---|---|
| `abi.h`, `objc.c` | Own CF/IOSurface/Objective-C declarations and runtime loader |
| `internal.h`, `sweeteagl.c` | Context ownership, installation, logging, import, CPU transfers |
| `gen_slots.py` | Stdlib Python generator; reads both research data files, Mesa's Khronos registry, exports and generated proc-name table |
| `slots.h`, `slots.c` | Committed generated offsets, metadata and correctly typed context-first wrappers |
| `eagltest.c` | E §9 smoke test, including forced CPU-copy operation |
| `build.sh` | Warning-free cross-build and SHA-256 output; optional output-directory argument |
| `check.sh`, `verify.py` | Reproducibility, slot coverage, symbol resolution and Mach-O checks |
| `proc-only.txt` | Direct names reachable through `OSMesaGetProcAddress`, without exported symbols |
| `check-output.txt` | Final host verification transcript |

1. Build and verify on the host:

```sh
tooling/gpu/sweeteagl/check.sh
```

The default outputs are `build/phone/gpu/SweetEAGL.dylib` and
`build/phone/gpu/eagltest`. Compilation uses the requested repo clang/sysroot,
`-target arm64-apple-ios16.0`, `-DXNU_PLATFORM_iPhoneOS`, lld ad-hoc signing,
`-Wall -Wextra -Werror`, and `-shared` for the dylib. Only these two build artifacts
are written outside this source directory. No Mesa sources/build outputs change.

The generator takes GL prototypes from Mesa's Khronos `gl.xml` (Apache-2.0),
not any Apple source. Mesa's generated `shared-glapi/glapi_mapi_tmp.h` and linked
binary provide static evidence for proc-only resolution; `verify.py` checks the
resolver chain, lookup names and linked symbol. This does not assert that every
entry point is enabled for every possible context. Runtime resolution always
tries `OSMesaGetProcAddress` before `dlsym`; missing required QC functions abort
installation before any methods change. A missing optional entry logs once and
returns zero. The complete proc-only list is [proc-only.txt](proc-only.txt).

## Phone handoff (run by the phone agent)

1. Set the SSH destination on the host:

```sh
PHONE=root@PHONE_ADDRESS
```

2. Copy the two binaries next to the existing, proven `libOSMesa.8.dylib`:

```sh
scp build/phone/gpu/SweetEAGL.dylib build/phone/gpu/eagltest "$PHONE:/var/root/gpu/"
```

3. Open the phone shell:

```sh
ssh "$PHONE"
```

4. Enter the GPU directory:

```sh
cd /var/root/gpu
```

5. Run the normal import test:

```sh
./eagltest
```

6. Run the CPU-copy test:

```sh
./eagltest --cpu
```

Each test prints numbered PASS/FAIL steps and exits nonzero on failure.
The normal test permits automatic CPU fallback; its PASS alone does **not** prove
zero-copy. Inspect `sweeteagl.log` for `surface IOSurface-ID import` versus
`surface CPU copy`. Neither test installs anything or modifies phone partitions.

An absolute shim path can be supplied as another argument. `SWEETEAGL_MESA`
overrides Mesa loading and must be absolute. Otherwise the loader tries
`/System/Library/Extensions/SweetGLES.bundle/libOSMesa.8.dylib`, then
`/private/var/root/gpu/libOSMesa.8.dylib`. The dylib install name is
`/private/var/root/gpu/SweetEAGL.dylib`. There are no dyld path-expansion tokens
in load commands. `SWEETEAGL_TRACE=1` logs the first call at each known slot;
`SWEETEAGL_CPU=1` forces copying. Logging uses an append-only, unbuffered fd at
`/private/var/root/gpu/sweeteagl.log`, first 200 method entries globally, and one
record per event/stub/trace offset. No per-frame GL logging continues afterward.

## Decisions and spec corrections

* **Incomplete extraction:** E §4's 58 offsets omit `glGetString` at `0x03b0`.
  All well-formed offmap offsets are covered, not just QC's 58. Five offsets
  missing from the offmap are added using E §4: `0x01c8`, `0x0970`, `0x09a0`,
  `0x0be8`, `0x2008`. There are 402 unique mapped entries.
* **Malformed offmap:** `0x00d0` contains the entire export list and is excluded
  from named mappings. Other lines contain aliases plus a stray
  `glGetFramebufferParameteriAPPLE`; the concrete non-stray name wins. Lines
  containing only that suspicious name remain logging stubs, **UNVERIFIED**;
  no real ABI for those offsets is invented. Genuine aliases use their first
  spelling except shared delete slot `0x1280`, which checks program versus shader.
* **Every callable address has an adapter:** even metadata kind `direct` means
  a typed C wrapper that makes the supplied OSMesa context current and removes
  arg0. Raw Mesa addresses cannot be stored in this table. Integer, floating
  and stack arguments are compiled with the actual prototype. `wrap` marks QC
  or special handling, and `stub` marks known missing/ambiguous names.
* The private record is `calloc(0x2088)`, owner at `+0`, API at `+0x10`, table
  at `+0x20`, opaque context at table word zero (E §2). Word one is intentionally
  NULL as expressly permitted by E §2/task. All other table words, including
  unextracted holes, contain a callable zero-return stub before named entries
  are installed. Unknown holes log as offset zero, not a fabricated mapping.
* **Real OpenGL ES context:** Mesa patch 0007 adds `OSMESA_ES_PROFILE` (`0x38`)
  and selects Mesa's `API_OPENGLES2` state tracker. We request ES 3.0 with a
  private 16×16 RGBA buffer; Mesa returns at least that version if the screen
  supports it. If creation fails (including an older Mesa without 0007), we
  request desktop compatibility GL 3.3. `SWEETEAGL_DESKTOP=1` forces that path.
  The chosen profile and actual Mesa version are logged; GL strings are preserved.
  API-2 and API-3 requests both return API **3**, including in the private record,
  because QuartzCore retries API 2 and then requires `[ctx API] == 3` (E §1).
  ES3 serves ES2 clients. `gles2=enabled` is required; existing shared glapi is
  sufficient, and `gles1` is unnecessary. See
  [native proof](../gles-host-test/PROOF.txt) for real ES dispatch, GLSL ES
  1.00/3.00, BGRA sampling, exact FBO pixels, sync and the desktop control.
  The native proof uses Linux softpipe: the iOS freedreno context and IOSurface
  import still need a phone run. The desktop control's results must not be
  interpreted as guaranteed GLSL ES failure on desktop Mesa. Before deploying,
  handle the existing `glAlphaFunc` forwarding slot: a resolved address raises
  `GL_INVALID_OPERATION` in ES. Its wrapper/generator are outside this task's
  edit scope; exact locations and the extension comparison are in the
  [handoff notes](../gles-host-test/README.md#deployment-handoff).
* **Import contract:** E §5/§8's EGL/dma-buf description and suggested GLESv2
  dylib are superseded by the task and Mesa patch 0005. The image pointer is
  the IOSurface ID, passed to Mesa's `glEGLImageTargetTexture2DOES`.
* **CPU fallback needs writeback:** E §5's upload alone cannot satisfy E §9's
  render-target pixel check. CPU copies retain the surface per texture, refresh
  nondirty textures before draws/clears, mark the current FBO's color texture
  dirty, and read dirty targets back at finish/flush. Transfers handle row stride
  explicitly and preserve PBO binding, alignment, row length and pixel skips.
  Readback uses a temporary read FBO and preserves the previous read binding.
  Texture deletion drops retained surfaces; context teardown frees all state.
  This deliberately synchronous fallback prioritizes correctness over speed.
* CPU uploads use `GL_RGBA8` storage with `GL_BGRA` bytes. Table `glTexImage2D`
  translates Apple's `GL_BGRA` internal-format token into `GL_RGBA8`; external
  format/bytes remain unchanged. Only single-plane, four-byte BGRA or format-0
  surfaces, full geometry, level zero, and `GL_TEXTURE_2D` are accepted.
* Inversion forces CPU copying and reverses rows on upload/writeback.
  **UNVERIFIED:** how CA combines `invert` with its own texture matrices.
  Format-0 follows the requested BGRA path, but E §5 says wrapped format-0
  images can be alpha-first. Their precise component convention is
  **UNVERIFIED**; no undocumented alpha swizzle is guessed.
* `GL_APPLE_fence`, `GL_EXT_debug_label`, and `GL_EXT_debug_marker` are appended
  only if missing. Legacy APPLE fence names are emulated with conservative
  synchronous finish at SetFence; object/fence completion is immediate afterward.
  QC's actual fence slots use real Mesa GLsync. Debug labels/markers are no-ops.
  Mesa's existing extension list is otherwise preserved; we do not add PVRTC,
  YCbCr, texture_xr, cubic filtering, tile rotation or framebuffer fetch.
  Unsupported invalid-argument cases in the legacy APPLE fence emulation do
  not synthesize Mesa GL errors (**UNVERIFIED** for clients beyond QC).
* `glFramebufferParameteriAPPLE` writes zero only for pname `0x8A79`, per
  E §§4/10. The inferred sample-count interpretation remains **UNVERIFIED**.
* `glFinishObjectAPPLE` always performs `glFinish` plus CPU writeback. Mesa
  texture limits are unmodified. `sharegroup` returns nil; `setParameter:to:`
  is a logged no-op. The other app-side methods are outside this task.
* **Stock current-context methods:** E §2 says they only need the sane private
  header. They remain stock. Their behavior, `_private` assignment through
  `object_setIvar`, retain/release, and superclass deallocation are **UNVERIFIED**
  until the phone test. Every slot uses Mesa's cheap current-context query before
  making current, so a separately changed Mesa TLS context cannot stale a cache.
  Installation is constructor-driven with explicit retry on failure; explicit
  concurrent installation and using one context concurrently on multiple threads
  are unsupported. Independent contexts can be used on independent threads.
* **E §10 enum error:** `0x8D41` is `GL_RENDERBUFFER`, not a rectangle
  texture target. Mesa's Khronos `include/GL/glext.h` defines
  `GL_TEXTURE_RECTANGLE` as `0x84F5`. This shim accepts only the task's
  `GL_TEXTURE_2D`, so it does not guess a translation for that spec error.
* **E §9 contradiction:** the offmap does contain `glCheckFramebufferStatus`
  at `0x1520`; its absence from QC call sites does not mean it lacks a slot.
  The test still uses the requested Mesa `dlsym` probe, with all other test GL
  work through the table.

## Slots with behavior beyond ordinary pass-through

All entries adapt the context-first ABI and optionally trace once. In addition:

| Offsets | Behavior |
|---|---|
| `0x0010` | AlphaFunc: pass through when available, else no-op |
| `0x03b0` | GetString: append safe shim extensions |
| `0x01e0` | DeleteTextures: remove retained surface/copy records |
| `0x0210`, `0x0220`, `0x0cb0`, `0x17d8`, `0x17e0`, `0x1fc0–0x1ff8` | Draw functions: refresh CPU copies and mark copied render targets dirty |
| `0x0058`, `0x1838`, `0x1840`, `0x1848`, `0x1850` | Clear functions: same CPU surface bookkeeping |
| `0x02d0`, `0x02d8` | Finish/Flush: write back copied render targets |
| `0x0970` | TexImage2D: translate BGRA internal format to RGBA8 |
| `0x0e80`, `0x0e88`, `0x0e90`, `0x0e98`, `0x0ea0`, `0x0ea8`, `0x0eb0` | Legacy APPLE fences: synchronous emulation |
| `0x0eb8` | FinishObjectAPPLE: finish and writeback |
| `0x1280` | Shared DeleteProgram/DeleteShader slot: discriminate by object type |
| `0x1978`, `0x1988`, `0x1990`, `0x1998` | Debug label/markers: no-ops |
| `0x2008` | Apple sample-count query: write zero |
| `0x0018`, `0x00b8`, `0x00c0`, `0x0660`, `0x0668`, `0x0678`, `0x0688`, `0x0690`, `0x0b00` | Ambiguous GetFramebufferParameteriAPPLE mappings: log once, return zero |
| `0x1fa0`, `0x1fa8`, `0x1fb0`, `0x1fb8` | Missing Mesa palette/matrix/weight functions: log once, return zero |

**UNVERIFIED fallback limits:** dirty tracking covers color attachment zero, the
QC draw/clear paths and their offmap aliases. MRT, direct image stores, blits or
out-of-table Mesa writes need additional dirty tracking. Copy refresh scans all
tracked images before each draw/clear; it is intentionally expensive. No hashes,
cross-context sharing, image-sharing cache, partial-surface uploads, or default
framebuffer presentation are implemented. A normal test passing via CPU fallback
does not validate the zero-copy route, and a host gate passing validates neither.
