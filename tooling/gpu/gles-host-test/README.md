# OSMesa OpenGL ES proof (Mesa 25.0.7)

This Linux test uses pristine Mesa plus **all seven** port patches. It runs on
softpipe, with no EGL, GLX, window system, LLVM, Apple SDK, or phone access.
Every GL entry point is obtained through `OSMesaGetProcAddress`.

1. Build and run the native proof:

```sh
tooling/gpu/gles-host-test/run.sh
```

`MESA_PRISTINE` may override the default
`$HOME/.hermes/cache/scratch/lane-3/pristine`; `JOBS` defaults to 8.
The script creates `build/gpu/mesa-src-host` and `mesa-build-host`, and keeps
ccache there. A patch-hash receipt rejects a stale source copy. An interrupted
copy/apply also fails closed; move it aside before retrying. It never edits the
main `mesa-src` or `mesa-build`. `gles2=enabled` is required for ES dispatch;
the existing `shared-glapi=enabled` needs no additional ES option.

2. Create `build/gpu/mesa-src-es` from pristine and apply patches 0001–0007
in order, dry-running each with `patch --batch --fuzz=0 -p1 --dry-run` before
applying. Then configure the private cross-build:

```sh
MESA_SRC="$PWD/build/gpu/mesa-src-es" MESA_BUILD="$PWD/build/gpu/mesa-build-es" tooling/gpu/mesa-build.sh setup
```

3. Build and keep its full output for the signature/build verifier:

```sh
MESA_SRC="$PWD/build/gpu/mesa-src-es" MESA_BUILD="$PWD/build/gpu/mesa-build-es" tooling/gpu/mesa-build.sh build > build/gpu/mesa-build-es-build.log 2>&1
```

4. Verify the cross-build and the actual SHA-256 code-page hashes in its
ad-hoc signature, then run the existing SweetEAGL gate:

```sh
python3 tooling/gpu/gles-host-test/verify-ios.py
tooling/gpu/sweeteagl/check.sh
```

The committed [PROOF.txt](PROOF.txt) contains native `run.sh` output followed
by these two verification outputs. The verifier reads the completed 1134-step
cross-build log; an incremental rebuild alone cannot establish that count.
The existing SweetEAGL gate reads the unchanged main Mesa tree for generated
slot/proc evidence. Its build intentionally also works with that older header:
`init_context` carries patch 0007's `0x38` token if the header lacks it.

The native screen reports **ES 3.1 / GLSL ES 3.10**. OSMesa versions remain
minimum requests, as documented by its existing API: requests for 2.0, 3.0,
and 3.1 return ES 3.1; 3.2 fails on this screen. Invalid versions fail too.
Both GLSL ES 1.00 and 3.00 shaders compile, link, and render a textured quad
using a nonidentity uniform mat4, RGBA8 FBO, RGBA8/BGRA_EXT byte upload, and
alpha blending. All 256 readback pixels match exactly. Sync completes.

The desktop compat 3.3 **negative control accepts both identical ES shaders
and renders the same pixels**. This test does not show a shader rejection on
desktop Mesa. It shows different version/GLSL strings and dispatch semantics:
`glAlphaFunc` succeeds on desktop and raises `GL_INVALID_OPERATION` in ES.
The ES image-import entry point remains exposed and reaches invalid-ID
validation; real IOSurface import is unverified on this Linux-only test.

## QuartzCore E §4 comparison

Raw native ES extensions, with no shim additions (full list in PROOF.txt):

| Extension | softpipe ES |
|---|---|
| GL_APPLE_fence | absent |
| GL_APPLE_texture_filter_cubic | absent |
| GL_APPLE_texture_ycbcr_basic_formats | absent |
| GL_APPLE_texture_ycbcr_extended_formats | absent |
| GL_APPLE_texture_xr | absent |
| GL_APPLE_tile_order_rot | absent |
| GL_EXT_shader_framebuffer_fetch | absent |
| GL_EXT_texture_filter_anisotropic | present |
| GL_EXT_texture_lod_bias | absent |
| GL_IMG_texture_compression_pvrtc | absent |
| GL_KHR_texture_compression_astc_ldr | absent |
| GL_OES_standard_derivatives | present |
| GL_OES_texture_float | present |
| GL_OES_texture_float_linear | present |
| GL_OES_texture_half_float | present |
| GL_OES_texture_half_float_linear | present |

That is **6/16** raw. SweetEAGL's existing synchronous APPLE fence emulation
adds `GL_APPLE_fence`, making **7/16** at its string wrapper on this screen.
`GL_EXT_texture_format_BGRA8888` and `GL_OES_EGL_image` are also present.
The iOS freedreno screen may expose a different list; this proof does not
establish its extensions or ES maximum version.

## Deployment handoff

Use **`build/gpu/mesa-build-es/src/gallium/targets/osmesa/libOSMesa.8.dylib`**
(not the old main build, and not the Linux `.so`) with the updated
`build/phone/gpu/SweetEAGL.dylib`. SHA-256 values and the signature check are
in PROOF.txt. The dylib's install name, OSMesa ABI, and framework dependencies
are unchanged. GL dispatch is inside libOSMesa; no extra GLES/glapi dylib is
needed. Mesa patches 0001–0007 must be applied to future source builds.
Keep `gles2=enabled` and rebuild SweetEAGL if replacing its headers.

The shim requests ES 3.0 first, logs the actual Mesa version, falls back to
compat 3.3 if creation fails, and honors `SWEETEAGL_DESKTOP=1`. Both accepted
EAGL API requests now report **3** in the method and private record. Verify
the logged ES profile, real IOSurface import, CPU-copy path, and API-2 retry
on the phone before relying on QuartzCore rendering.

**Known deployment issue outside this task's edit scope:**
`tooling/gpu/sweeteagl/slots.c:12` forwards `glAlphaFunc`, after resolving
it at `slots.c:3608`. A non-NULL resolver result does not mean the operation
is legal in ES. QuartzCore calls this slot (E §4); the native proof shows
it raises `GL_INVALID_OPERATION` in a genuine ES context. Main-agent follow-up
must handle that ES1 leftover in the wrapper/generator before deploying ES
as QuartzCore's default. Mesa's API metadata is
`build/gpu/mesa-src-es/src/mapi/glapi/gen/gl_API.xml:2567` (ES1, no ES2);
its unsupported-dispatch error is at
`build/gpu/mesa-src-es/src/mesa/main/context.c:788`. Those files and the
wrapper were not modified here. For comparison,
`SWEETEAGL_DESKTOP=1` retains the former desktop dispatch behavior.
