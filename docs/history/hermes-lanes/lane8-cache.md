# Task: can a trimmed dyld shared cache fit in the phone's fastboot budget?

Repo: /home/tadej/ios-nord. Read `.hermes-lanes/shared.md` for the repo rules, then
`docs/PHONE_TEST.md` (§10-12) and the phone section of `docs/STATUS.md`.

## The problem, established

The phone boots our payload over `fastboot boot`, and `max-download-size` is **805 306 368 B**
(768 MiB). The boot image today carries `build/rd-root.skeleton.img`, 32 MiB, built `--no-cache`,
so the panel stops at `dyld: Library not loaded: /usr/lib/libSystem.B.dylib` — the predicted
no-cache stop. QEMU, which has the cache, maps it fine and runs launchd to 64 further execs.

The full cache is 2 608 MB in `build/rd-root.progs.stage/System/Library/Caches/com.apple.dyld/`
(`dyld_shared_cache_arm64` + `.01` … subcache files). That cannot ride over fastboot. The question
this lane exists to answer, with a real artifact: **what is the smallest cache that still lets
launchd's exec find `libSystem.B.dylib`, and does it fit under 768 MiB?**

## What to do

1. **Establish what launchd actually needs.** `/sbin/launchd` links `LC_LOAD_DYLINKER /usr/lib/dyld`
   and its `LC_LOAD_DYLIB`s; every name must be resolvable from the cache. Work the closure from
   `libSystem.B.dylib` outward for launchd and for `/usr/lib/dyld` itself. Useful facts already on
   disk: `avicii/rd-root/jobs-boot.tsv` and the `61` staging tree. Parse the Mach-O headers with
   Python; do not guess which dylib pulls in which.
2. **Try to build a subset cache.** Options, in order of preference:
   a. Apple's `dyld_shared_cache_util` / `update_dyld_shared_cache` — likely absent on Linux;
   b. the iOS 16.7 D22AP cache in the OS DMG: check whether `cache-builder`-style tools, or the
      per-dylib `dyld_shared_cache_arm64*` extraction that `fstool`/`ipsw`-like tools can do, let
      you rebuild a cache from a chosen dylib list. If a tool is missing, say which and stop;
   c. if a rebuild is not feasible in this environment, the fallback question becomes: **can the
      cache be delivered outside the boot image?** — but do not implement that, just answer whether
      a subset cache is buildable here at all.
3. **If a subset cache is produced**, state its size, its file list, whether dyld will accept it
   (path table must contain `libSystem.B.dylib` and `libobjc.A.dylib`), and stage it into a copy of
   the skeleton root at the exact path
   `/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64` (+ any subcache files), in
   `build/rd-root.cachetrial.stage`, built with the same `61` inputs as the skeleton. Do not touch
   `build/rd-root.skeleton.img`, `build/rd-root.img`, `build/rd-root.progs.*`, `build/ios16-root.img`.

## Hard limits

- No QEMU in this spawn (the lead agent boots). No phone, no fastboot/adb, no `dd`.
- Do not edit `tooling/61-mkrd-root.sh`, `60`, `62`, `70`; you may *call* them. Do not `git commit`.
- Own only `build/rd-root.cachetrial.*`, `avicii/rd-root/cache-subset.txt` (new), and a scratch dir
  under `/home/tadej/.hermes/cache/scratch/`.
- Every number must come from a command you ran. If the answer is "a subset cache cannot be built
  with the tools on this host", that is a perfectly good answer — say it plainly with the evidence
  (tool absence, version mismatch, format).

## Report

The launchd/dyld closure (names + where each comes from), whether a subset cache is buildable here
and with what tool, its size and file list if built, whether it fits under 768 MiB with the rest of
the skeleton, and the one QEMU boot the lead agent should run to prove it (cmdline and what line it
must show).
