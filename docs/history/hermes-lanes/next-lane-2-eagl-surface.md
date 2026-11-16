# Round 3, lane 2 — the exact EAGL / OpenGL ES surface QuartzCore's GLES renderer uses

Read `next-shared.md` first. **Owns:** `docs/gpu-research/E-eagl-shim-spec.md`.

**Problem:** round-1 lane A concluded the cheapest way off the CPU renderer is to answer QuartzCore's
OpenGL ES rung with an `EAGLContext` implemented over Mesa (`docs/gpu-research/A-*.md` §1). Before
anyone writes that shim, we need its precise contract: every Objective-C method and every GL / EGL-ish
entry point the window server (backboardd + QuartzCore) calls, in what order, with which arguments.

Determine (from the dyld cache's `QuartzCore`, `OpenGLES.framework`, `IOAccelerator`/`IOGPU` client
code, and `backboardd`; plus HackiOS's `eagl.c` / `mkeagl.py` in `refs/`):
1. **Discovery:** how QuartzCore decides GLES is available — `IOAcceleratorES` / `IOGLESBundleName` /
   `IOGLESMetalBundleName` / `IOGLESDefaultUseMetal` properties, `CA_ENABLE_OGL`, which bundle path
   it `dlopen`s, which class names it looks up (`EAGLContext`, `EAGLSharegroup`, …).
2. **Objective-C surface:** every `EAGLContext` / `EAGLSharegroup` / `CAEAGLLayer` selector reached,
   with types: `initWithAPI:` / `initWithAPI:properties:` (which property keys), `setCurrentContext:`,
   `renderbufferStorage:fromDrawable:`, `presentRenderbuffer:`, `texImageIOSurface:target:...`
   (or the C variant), `setParameter:to:`, sharegroup use. Mark each as required vs optional.
3. **C surface:** the `gl*` functions `CA::OGL::Renderer` / `GLESContext` import (from QuartzCore's
   imports of `OpenGLES`) — the full list, grouped: state, textures (incl. IOSurface textures and
   formats like BGRA, 64-bit RGBA_half), FBOs, shaders/programs, draws, sync (`glFenceSync`,
   `glClientWaitSync`, `glFlush`/`glFinish`), extensions it queries (`glGetString(GL_EXTENSIONS)`
   checks), and the `APPLE_*` extensions it needs.
4. **IOSurface ↔ texture/renderbuffer path:** how an IOSurface becomes a texture or render target, and
   what the shim must map to our kernel's `MSM_INFO_IOS_IMPORT` (0x85) → GEM handle → Mesa
   `EGLImage`/dma-buf-style import (see `0126` and HackiOS's version). Who presents: does QuartzCore
   hand finished IOSurfaces to `IOMobileFramebuffer` itself (lane A says renderer-agnostic scanout)?
5. **Cross-check with HackiOS `eagl.c`:** what it implements, what it stubs, and gaps vs points 2–4.

Report: a table (symbol / selector → required? → what Mesa/EGL call implements it → notes) that a
developer can implement top to bottom, plus a minimal test program outline (a process that makes an
`EAGLContext`, renders a coloured quad into an IOSurface-backed renderbuffer, presents it).
