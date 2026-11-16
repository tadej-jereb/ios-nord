# Round 3, lane 3 — libdrm stand-in and the freedreno-darwin patch, against our 0126 uAPI

Read `next-shared.md` first. **Owns:** `docs/gpu-research/F-libdrm-darwin.md`, and the draft patch
files under `tooling/gpu/mesa-patches/` (new; plain `.patch` files against Mesa 25.0.7, not applied
anywhere in the repo).

**Problem:** lane C listed 14 Linux-isms in Mesa's freedreno path and a missing `<xf86drm.h>`
(`freedreno_priv.h:21`). HackiOS has a 12-file `freedreno-darwin` patch and a libdrm shim for its own
kernel. Produce the version that matches **our** kernel interface (`0126`).

Determine and draft:
1. **libdrm subset:** every `drm*` function and header freedreno (`src/freedreno/drm/`,
   `src/gallium/drivers/freedreno/`, `src/gallium/winsys/freedreno/`) and the loader use at build and
   run time. For each: implement over `/dev/dri/renderD128` + `ioctl`, fake (e.g. `drmGetVersion` →
   "msm" 1.10), or not needed. Note XNU's `_IOW` direction gotcha documented in 0126 (pure-`_IOW`
   requests must be encoded with `IOC_IN` by the shim) and list which requests that affects.
2. **mmap of buffers:** XNU does not route `mmap()` on a cdev to our `d_mmap` usefully; 0126 offers
   `MSM_INFO_IOS_MMAP` (0x80) through GEM_INFO. Show the exact change in `msm_bo.c`/`fd_bo` to use it.
3. **Linux-isms:** for each of lane C's 14 (eventfd, futex, memfd, sync_file, dma-buf, `/proc`,
   `clock_gettime` variants, …): where it is, and the Darwin replacement (or HackiOS's), as a hunk.
4. **IOSurface import:** the Mesa side of `MSM_INFO_IOS_IMPORT` (0x85): how a surface id becomes a
   `fd_bo` and a `pipe_resource` (modifier/pitch/format), matching what lane 2 says QuartzCore needs.
5. **Diff vs HackiOS:** where their patch assumes their kernel (`IOConnect` user client, selector
   numbers) and our cdev differs; adopt theirs wherever it already fits.
6. If lane 1's sysroot exists by the time you finish, try compiling the patched `src/freedreno/drm/`
   files with it and report the result; otherwise state that it is untested.

Report: the function table, the patch list (file → purpose → lines), and what remains untested.
