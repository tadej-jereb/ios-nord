# GPU lane B — inventory of the HackiOS / raphael GPU userland, and what the Adreno 620 still needs

Read `gpu-shared.md` first.

**Question:** the HackiOS projects already put Mesa freedreno under iOS on an Adreno 640
(Xiaomi raphael). What exactly exists, what is A640-specific, and what is missing or different
for our Adreno 620 and our kernel (`xnu-avicii`)?

## Inputs

* `https://github.com/Gsjsjzhznsz/hackios-xnu-userland` — clone read-only to
  `refs/gsjsjzhznsz-hackios-xnu-userland/` (if missing). Record the commit hash you read.
* `https://github.com/HeliumStudio-Dev/hackios-xnu-kernel` branch `raphael-bringup` — clone to
  `refs/heliumstudio-hackios-xnu-kernel/` (if missing). Record the commit hash.
* `refs/marnov999-raphael-ios-gpu/` (local): `NOTES.md`, `xnu/patches/0105`–`0141`, `tools/`.
* Our side: `avicii/CONSTANTS.md` "GPU" section and `xnu-avicii/series` (read only) to see which
  kernel layers exist here (0119 power, 0122 GMU, 0123 command processor at the time of writing).

## What to determine

1. **Component list.** Every userland piece and how they connect: the Mesa patch set
   (version, files touched, what "freedreno-darwin" changes: winsys, `drm` shim, `libdrm`
   replacement), `redwood-drm`, `eagl.c` / `mkeagl.py`, any IOSurface glue, how the libraries are
   built and placed in the root, and how QuartzCore/apps are made to load them (interposing,
   replacing `OpenGLES.framework`, `DYLD_*`, a launchd plist, a tweak injector).
2. **The kernel ABI they need.** The exact ioctls / user-client selectors the userland calls
   (KGSL-style or DRM msm-style: `GET_PARAM`, `GEM_NEW`, `GEM_INFO`, `GEM_CPU_PREP`,
   `SUBMITQUEUE_NEW`, `GEM_SUBMIT`, `WAIT_FENCE`, …), their argument structs, and where raphael's
   kernel implements them (patch + function). This becomes the spec for our layer 5.
3. **A640 → A620 delta.** Everything hard-coded for the A640 / SM8150 in that stack: GPU id and
   chip id, GMEM size (1 MiB vs our 512 KiB), number of CCUs, UBWC settings, firmware names,
   `highest_bank_bit`, register addresses, MDP/DPU scanout addresses. List each with file:line
   and the A620 value it should become (cite Mesa `freedreno_devices.py` `GPUId(620)` or
   `avicii/CONSTANTS.md`; mark anything not found there as **UNVERIFIED**).
4. **Licences and provenance.** Licence of each repo/file, which parts are Apple-derived (headers,
   stubs) and must stay out of our git, which can be vendored as patches.
5. **Gaps.** What is not public (anything the NOTES or READMEs mention but the repos do not
   contain), and what our project would have to write from scratch.

## Owns

* `docs/gpu-research/B-hackios-inventory.md` (new). One file, sections 1–5.
* The two clones under `refs/` (read-only use; never commit into them).

## Report

The file above, with a top summary: a table of components × {exists publicly, A620 change
needed, effort guess (S/M/L, marked as a guess)}, and the ordered list of the ioctls our layer-5
kernel uAPI must provide for that userland to run unmodified.
