# GPU lane A — how iOS 16.7 composites: QuartzCore / backboardd → IOSurface, IOMobileFramebuffer, IOGPU

Read `gpu-shared.md` first.

**Question:** on iOS 16.7.16 (iPhone X, D22AP, A11 "AGX G10"), what exactly does the compositor
(`backboardd` hosting CoreAnimation's render server in `QuartzCore`) call to (1) allocate the
surfaces it draws into, (2) render with the GPU, and (3) hand a finished frame to the display?
And when it finds no usable GPU, which software path does it take today on the Nord? The answer
decides where a Mesa/Adreno backend can be slotted in with the least surface area.

## Inputs

* dyld shared cache from the SystemOS cryptex (`087-86593-047.dmg`): `QuartzCore`, `IOSurface`,
  `IOMobileFramebuffer`, `IOGPU`, `Metal`, `MetalTools`, `AGXMetalG10` (or the A11 equivalent
  driver bundle name), `OpenGLES`, `CoreDisplay` if present, `IOKit`. Extract with any local
  dyld-cache extractor (e.g. `ipsw dyld extract`, `dyldextractor`); do not download Apple files.
* `/usr/libexec/backboardd` from the OS DMG.
* The kernel side we already have: `SweetFramebuffer.cpp` and the IOSurface/IOMobileFramebuffer
  stubs in `xnu-avicii/patches/` (read only) — note which user-client selectors they already answer.
* Live evidence: `logs/phone/` (e.g. `bbd-threads-0116-*.txt`, the newest `live-*.txt`), which show
  the backboardd thread doing the CPU compositing.

## What to determine

1. **Renderer selection.** Where QuartzCore decides between Metal, OpenGL ES and the software
   (`CA::OGL` / `CA::Render::...` software) path; which IOKit service names / properties / Metal
   device creation calls it probes (`MTLCreateSystemDefaultDevice`, `IOServiceMatching("IOGPU")`,
   `AGXAccelerator`, …) and what result makes it fall back. Name the functions and the order.
2. **Surfaces.** The IOSurface user-client selectors used for create / lookup / lock / unlock /
   `IOSurfaceGetBaseAddress` / use-count, and the properties dictionary QuartzCore passes
   (pixel format, bytes-per-row alignment, `IOSurfaceCacheMode`, compression/AGX-specific keys).
   Which of these must point at GPU-visible memory (i.e. need an SMMU mapping on our side).
3. **Scanout.** The `IOMobileFramebuffer` calls made per frame (`IOMobileFramebufferSwapBegin`,
   `SwapSetLayer`, `SwapEnd`, `SwapWait`, vsync callbacks) with their user-client selectors and
   argument structs, so the kernel can accept a GPU-rendered IOSurface for scanout.
4. **GPU submission.** On real hardware: the IOGPU / `IOGPUDevice` / `AGXAccelerator` user-client
   selectors Metal uses for command-buffer submit, resource create/map, and completion
   notification. We will **not** implement Apple's GPU ABI — the point is to know the seam:
   is it cheaper to (a) make QuartzCore's OpenGL ES path work over an EAGL-on-Mesa library
   (what raphael/HackiOS did), or (b) something else? Give your recommendation with evidence.
5. **What raphael did.** Cross-check against `refs/marnov999-raphael-ios-gpu` (NOTES.md,
   `tools/build-redwood-gl.sh`, patches 0113, 0120+): which of the above calls they intercept or
   reimplement, and anything they found that QuartzCore requires (entitlements, IOKit
   properties, boot-args).

## Owns

* `docs/gpu-research/A-quartzcore-compositing.md` (new). One file. Sections 1–5 above, each with
  the symbol names / selectors / offsets and the command that produced them.

## Report

The file above, plus a ≤15-line summary at its top: the call chain from a CA commit to a scanout
on real hardware, the fallback chain on the Nord today, and the recommended seam for Mesa.
