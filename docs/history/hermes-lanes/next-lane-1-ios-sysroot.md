# Round 3, lane 1 — an iOS 16 arm64 sysroot built from legal parts, and Mesa past configure

Read `next-shared.md` first. **Owns:** `docs/gpu-research/D-ios-sysroot.md`, `tooling/gpu/mksysroot.sh`
(new), the sysroot itself under `~/.hermes/cache/scratch/sysroot-ios16/` (never in the repo).

**Problem:** lane C proved the toolchain (clang 18 + `ld64.lld`, ad-hoc signing) but Mesa's configure
stops at `meson.build:971 Could not get define 'ETIME'` because `errno.h` does not exist for
`arm64-apple-ios16.0` on this host. Build the smallest sysroot that gets Mesa's freedreno + GLES
build through, from legal sources only.

Do, in order, verifying each step with a tiny test program before the next:
1. **C headers:** Apple's open-source Libc / libpthread / Libsystem / xnu at the versions closest to
   iOS 16.7 (name the tags; xnu-8796.141.3 is the kernel we run). Download fresh copies into
   scratch (apple-oss-distributions on GitHub) — do **not** use `~/xnu-8796.141.3`, which the main
   agent resets between builds. `errno.h`, `stdio.h`, `pthread.h`, `dlfcn.h`, `mach/*`, `sys/*`,
   `TargetConditionals.h`, `Availability*.h`. Test: a C file using them compiles.
2. **Link stubs:** `.tbd` files for `libSystem.B.dylib` (and its re-exports), `libz.1.dylib`,
   `libc++.1.dylib`, `libc++abi.dylib`, `IOSurface.framework`, `IOKit.framework`,
   `CoreFoundation.framework`, `OpenGLES.framework` (if Mesa's front end needs it) — generated from
   **our** dyld shared cache with a local tool (e.g. `ipsw dyld tbd`, `tapi`-compatible generator, or
   a small script reading exports), with install names and current/compat versions as in the cache.
   Test: a C program calling `printf`, `pthread_create`, `dlopen` links and `llvm-objdump` shows the
   right `LC_LOAD_DYLIB`s.
3. **C++:** LLVM libc++ headers matching the cache's libc++ ABI (find its version string in the
   cache) + `libc++.tbd`. Test: a C++17 file with `std::vector`/`std::string` links.
4. **zlib:** `zlib.h`/`zconf.h` (zlib's own release) + `libz.tbd`. **crt1.o / dylib1.o** — for a
   dylib build, find out whether any are needed with `ld64.lld` (they usually are not for `-dylib`).
5. **Mesa:** rerun lane C's meson configure with this sysroot (`--sysroot` / cross file), report how far
   `ninja` gets for `-Dgallium-drivers=freedreno -Dgles2=enabled` and the first hard error. The
   libdrm and Linux-isms walls belong to lane 3 — note them, do not solve them here.
6. Write `tooling/gpu/mksysroot.sh`: idempotent, takes the dyld cache path and an output dir, never
   writes outside them; records sha256 of every input.

Report: the file list of the sysroot with the source and licence of each part, the tests that pass,
and the Mesa build's progress (objects built / first error).
