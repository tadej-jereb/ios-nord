# Codex task B: an OpenGL ES context from OSMesa (Mesa patch 0007), used by SweetEAGL

**Repo:** `/home/tadej/ios-nord`.
**Worktree:** another Codex session runs at the same time, so work in your own git worktree:

```
cd /home/tadej/ios-nord
git worktree add ../ios-nord-B -b codex/gles-context codex/eagl-shim
cd ../ios-nord-B
ln -s /home/tadej/ios-nord/build build              # sysroot + Mesa trees live here (not in git)
ln -s /home/tadej/ios-nord/tooling/opt tooling/opt  # clang, meson venv
```

**Work only in:**
- `tooling/gpu/mesa-patches/0007-*.patch` (new)
- `tooling/gpu/mesa-build.sh` (only to make the source/build dirs overridable)
- `tooling/gpu/gles-host-test/` (new)
- `tooling/gpu/sweeteagl/sweeteagl.c`: `init_context` and `get_api` only
- `tooling/gpu/sweeteagl/README.md`

**Never** modify `build/gpu/mesa-src` or `build/gpu/mesa-build`; the main agent's working build lives
there. Use your own copies `build/gpu/mesa-src-es` and `build/gpu/mesa-build-es`.

## Why

SweetEAGL (`tooling/gpu/sweeteagl/`) makes Apple's `EAGLContext` return OSMesa contexts. It
renders on the phone's GPU: `eagltest` passes 10/10 (`logs/phone/eagltest-2.txt`).

But OSMesa only creates **desktop** GL contexts. SweetEAGL asks for compat 3.3, while QuartzCore is
an OpenGL **ES** client. Its shaders are GLSL ES (`precision` qualifiers, `#version 100` or
`300 es`), and its use of `GL_BGRA`, `GL_EXT_*` and ES-only enums assumes an ES context. Mesa's
GLSL compiler only accepts ES shading-language versions in a desktop context through
compatibility extensions, and behaviour differs.

The fix is the real thing: let OSMesa create an **ES 2/3 context** (Mesa's `API_OPENGLES2`), the
same API Mesa gives EGL clients.

## Read first

1. `build/gpu/mesa-src/src/gallium/frontends/osmesa/osmesa.c`: `OSMesaCreateContextAttribs`
   and how it fills `struct st_context_attribs` (`profile`, `major`, `minor`).
2. `tooling/gpu/mesa-patches/0005-*.patch` (OSMesa's GPU screen and the IOSurface import). Your
   patch must apply **on top of 0001–0006** and must not break 0005's
   `glEGLImageTargetTexture2DOES` path in an ES context.
3. `build/gpu/mesa-src/include/GL/osmesa.h`: the existing `OSMESA_PROFILE` values.
4. `tooling/gpu/mesa-build.sh` (cross build) and `tooling/gpu/sweeteagl/README.md` (the shim's
   design).
5. `docs/gpu-research/E-eagl-shim-spec.md` §1 step 6 (QuartzCore requires `[ctx API] == 3`) and
   §4 (the extension list QuartzCore probes).

## Deliverables

1. **`tooling/gpu/mesa-patches/0007-osmesa-es-context.patch`**
   - Add `OSMESA_ES_PROFILE` to `osmesa.h`. Pick a value that collides with nothing in that header
     and comment the choice.
   - With `OSMESA_ES_PROFILE`, `OSMesaCreateContextAttribs` creates an `API_OPENGLES2` context
     whose version is `OSMESA_CONTEXT_MAJOR/MINOR_VERSION` (default 3.0; accept 2.0–3.2 as far as
     the screen supports it).
   - `OSMesaGetProcAddress` must keep working for ES contexts.
   - In an ES context, `glGetString(GL_VERSION)` must start with `OpenGL ES 3.` and
     `GL_SHADING_LANGUAGE_VERSION` with `OpenGL ES GLSL ES`.
   - The patch must apply cleanly after 0001–0006 (`patch -p1 --dry-run` on a fresh copy of the
     pristine tree, `~/.hermes/cache/scratch/lane-3/pristine`), in the repo's patch style:
     header comment, minimal diff.
   - If the shared glapi/dispatch needs ES enabled in the build, say exactly which meson option
     and why. `gles2=enabled` is already on.

2. **Host proof on Linux: you cannot run iOS binaries, so prove it natively.**
   - Build a host-native Mesa (x86_64 Linux) with the **same patches 0001–0007**: OSMesa +
     softpipe only, `-Dgallium-drivers=softpipe -Dosmesa=true -Dplatforms= -Dglx=disabled
     -Degl=disabled -Dgbm=disabled -Dllvm=disabled -Dvulkan-drivers=`.
   - If 0001–0006 make that impossible on Linux (they are Darwin-guarded, so they shouldn't),
     document it and apply 0007 alone to pristine.
   - Build into `build/gpu/mesa-build-host`. Put the scripts in `tooling/gpu/gles-host-test/`.
   - `gles-host-test.c` creates an `OSMESA_ES_PROFILE` 3.0 context and checks:
     1. The version strings above.
     2. That it compiles and links **GLSL ES 1.00** and **GLSL ES 3.00** shaders with `precision`
        qualifiers. A textured quad with alpha blending and a uniform `mat4`, as a compositor
        does.
     3. That it renders the textured quad into an FBO with a `GL_RGBA8` texture attachment,
        sampling a texture uploaded as `GL_BGRA_EXT`/`GL_UNSIGNED_BYTE` (needs
        `GL_EXT_texture_format_BGRA8888`; report whether Mesa's ES context exposes it).
     4. That `glReadPixels` gives exact expected pixels, with blending verified at one pixel.
     5. That `glFenceSync`/`glClientWaitSync` work.
     6. Negative control: the same ES shaders in a desktop compat 3.3 context. Report
        precisely what fails or differs; that is the evidence for why this task exists.
   - `run.sh` builds and runs everything and exits 0 on success. Commit its output as
     `PROOF.txt`.

3. **Cross build for iOS:**
   - Make `mesa-build.sh` take `MESA_SRC`/`MESA_BUILD` environment overrides, defaulting to the
     current paths.
   - Build `build/gpu/mesa-build-es` from `build/gpu/mesa-src-es` (pristine + 0001–0007).
   - It must reach the same 1134/1134 with zero failures, and `libOSMesa.8.dylib` must be
     ad-hoc signed.

4. **SweetEAGL uses it.** In `init_context`, request `OSMESA_ES_PROFILE` 3.0 first, then fall back
   to compat 3.3, logging which one it got. `SWEETEAGL_DESKTOP=1` forces compat. In `get_api`,
   report **3 for both API-2 and API-3 requests**: QuartzCore retries with API 2 and then
   requires `API == 3` (E §1 steps 4 and 6), and an ES3 context serves ES2 clients. Rebuild and
   run `tooling/gpu/sweeteagl/check.sh`; it must still pass. Update the README's
   "OSMesa is not an ES frontend" decision.

## Rules

- No Apple SDK, headers or code. Never touch `xnu-avicii/`, `avicii/`, the phone, or any git
  remote. No pushes. Commit only on `codex/gles-context`.
- Don't paper over failures. If something in Mesa can't do what's asked, stop and write down
  exactly what and where (file:line).

## Done =

`tooling/gpu/gles-host-test/run.sh` exits 0, the iOS cross build is 1134/1134, and
`sweeteagl/check.sh` passes, all committed. Report:
1. the commit hash;
2. PROOF.txt highlights, including the desktop-context negative control;
3. the extension list Mesa's ES context exposes, compared against E §4's sixteen;
4. anything the main agent must do differently when deploying the new `libOSMesa.8.dylib`.
