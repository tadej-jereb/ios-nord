# Task: reverse dyld-1067's cache preflight to find why our rebuilt cache is rejected silently

Analysis only — no QEMU, no phone. Repo /home/tadej/ios-nord.

## Situation

We cannot fit the 2.6 GiB dyld shared cache into the phone's 768 MiB `fastboot boot` budget, so a lane
built a trimmed cache. It now satisfies a careful re-implementation of the rules visible in dyld's
own strings and is structurally consistent (37 images, correct signatures of every mapping, real
trie, split into Apple's 15-file shape). Booted twice in QEMU, dyld **silently declines it**: zero
`shared_region … map(…)'dyld_shared_cache_arm64'` lines (a real cache gives 43), then
`Library not loaded: /usr/lib/libSystem.B.dylib … (no such file, no dyld cache)` and **no diagnostic
line at all** — not `shared cache file open() failed`, not `no shared cache file`, not `shared cache
is too old…`, not `mmap() the shared cache region failed`. Runs: `logs/qemu/20261114-123028-l8cache`
(single-file attempt) and `logs/qemu/20261114-134304-l8cache2` (split attempt).

Artifacts: dyld binary `build/rd-root.progs.stage/usr/lib/dyld` (dyld-1067), the rebuilt cache in
`/home/tadej/.hermes/cache/scratch/lane8/cachev2/` (15 files), the real cache for comparison in
`build/rd-root.progs.stage/System/Library/Caches/com.apple.dyld/`.

## What to determine

1. **Where the decision is made.** Disassemble (llvm-objdump, `tooling/opt/llvm`) the functions whose
   symbols ship stripped-but-present: `dyld3::preflightCacheFile`, `preflightMainCacheFile`,
   `preflightSubCacheFile`, and the caller that decides whether to attempt a cache map at all
   (`SharedCacheRuntime::mapSharedCache` / `loadDyldCache`). Establish the call order and every early
   return on the path.
2. **Why nothing is printed.** Find what gates `dyld::log`/`fprintf` in those paths — a global verbose
   flag, an env var (`DYLD_PRINT_*`), a boot-arg, or an `options.verbose`. Say exactly which one and
   how it can be set for pid 1 on this port (a `launchd.plist` env entry, a kernel boot-arg, or a
   `_COMM_PAGE` flag), so the next boot can be made to print its own rejection reason.
3. **Which condition our file actually fails.** Compare the disassembled checks against the real
   cache and the rebuilt one field by field (mapping count/prot permits/contiguity, signature
   superblob layout, `mappingWithSlide` size and count, `cacheType`/`cacheSubType`, subCache suffix
   array, `dylibsTrie`/`dylibsPBLSetAddr`, `platform`, magic, UUID), and name the first check that
   the rebuilt cache fails. If the failing check is a real requirement no trimmed cache can meet
   within 768 MiB, say so and name the minimum size that would satisfy it.
4. Optional and only if cheap: whether the silent path means dyld never even `open()`s the file
   (e.g. it keys off a kernel-provided shared-region base, a `_COMM_PAGE` value, or a boot-arg) — if
   that is the case, the whole trimmed-cache route is blocked for a reason that has nothing to do
   with our bytes, and that is the most valuable finding of all.

## Hard limits

Read-only on the repo except a new `docs/CACHE_TRIM.md` if you want to record the rules (say so).
Do not touch `build/*`, `tooling/*`, `logs/qemu/*`, the phone, `.hermes-lanes/`. No `git commit`.
Scratch under `/home/tadej/.hermes/cache/scratch/`. Real disassembly output only — quote addresses
and instructions, do not paraphrase into a guess. If a step needs a boot, say which one and what
line to look for instead of claiming it.
