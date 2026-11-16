# Round 3, lane 5 — getting our GL userland loaded into backboardd on this root

Read `next-shared.md` first. **Owns:** `docs/gpu-research/G-gl-deploy.md`.

**Problem:** lanes 1–3 produce Mesa-for-iOS and an EAGL shim. None of them answers how those dylibs
end up *inside the window server* on this phone: the root is iOS 16.7's (signed system volume
semantics, dyld shared cache, cryptex), our kernel relaxes code signing in its own ways, and
`OpenGLES.framework` is not a file on disk but an image in the dyld shared cache. Produce the
deployment plan the main agent can execute in one root update (which needs the user's OK — you
only plan it).

Determine:
1. **How the root is built and updated today:** `tooling/61-mkrd-root.sh`, `docs/IOSROOT.md`,
   `docs/ROOTFS_READY.md`, `docs/AMFI_LAUNCHD.md`, `docs/CACHE_TRIM.md`, the `/var/jb` Procursus
   layout on the phone (from docs/logs only). Where a new dylib can live (`/var/jb/usr/lib`,
   `/usr/lib`, a framework path) and how the existing SSH tools got there and run.
2. **Code signing on our kernel:** what `sweet_amfi.c` and the trustcache patches in
   `xnu-avicii/patches/` (read only; find them by name) actually allow — ad-hoc signed dylibs loaded
   into a platform binary like `backboardd`? Library validation? Entitlements needed? What
   `ld64.lld -adhoc_codesign` produces (lane C proved it) and whether that is enough, or a
   trustcache entry (cdhash) must be added. Cite the patch lines.
3. **Getting code into backboardd:** compare, with risks:
   (a) `DYLD_INSERT_LIBRARIES` via `launchd.plist` `EnvironmentVariables` for
   `com.apple.backboardd` (does dyld honour it for this process on our kernel? AMFI flags?),
   (b) replacing/shadowing `OpenGLES.framework` (it is in the shared cache — can a root
   dylib override a cache image? dyld's rules for that on iOS 16, root-relative `DYLD_*` flags),
   (c) a framework bundle QuartzCore `dlopen`s by name via `IOGLESBundleName` /
   `IOGLESMetalBundleName` on `IOAcceleratorES` (round-1 lane A §1) — what path it resolves.
   How HackiOS and raphael did it (`refs/` — read only), and which fits our root best.
4. **Kernel-side properties:** the exact IOKit properties `IOAcceleratorES` (published empty by our
   kernel, round-1 lane A says patch `0107`-ish in *their* tree — find ours) must carry for QuartzCore
   to pick GLES, so the main agent can add them in one kernel patch.
5. **A safe rollout:** test first in a *non-critical* process (a small test binary run over SSH), then
   backboardd; how to undo (which files/plist keys to remove) if backboardd crash-loops; what a
   crash-loop of backboardd does to the phone (watchdog? reboot to fastboot? — cite logs if any).

Report: the recommended route with exact paths, plist keys, signing steps and the IOKit property
list; the fallback route; the undo procedure; and every step that needs the phone written as the
commands the main agent will run.
