# Task: make XNU accept the dyld shared cache's ad-hoc signature (errno 85), or prove it needs a patch

Repo /home/tadej/ios-nord. Kernel source: `~/xnu-8796.141.3` (pristine, `xnu-avicii/series` is the
patch set). Analysis + at most one small patch; no QEMU, no CI dispatch.

## The wall, measured twice

A hand-built trimmed dyld shared cache (19 files, every structural rule satisfied, image
`build/rd-root.cachetrial3.img` sha256 `e4a8e9cd…56d91f`) is refused by the **kernel**, not by dyld:

    sweetlog.txt:152  shared_region: … check_np(0x16ee03160) vm_shared_region_start_address() failed
    sweetlog.txt:153  unable to create a validated cs_blob object: 85
    sweetlog.txt:154  dyld cache '(null)' not loaded: code signature registration for shared cache failed

errno 85 = EBADEXEC, from `F_ADDFILESIGS_RETURN` on the **main** cache file, before any sub-cache and
before dyld's first `map()` print. The real cache (43 files) passes the same path with the same root,
so the difference is our synthesized code signature. A previous lane generated ad-hoc SHA-256
CodeDirectories with correct page hashes (`csck.py` validates them) and put
`codeSignatureOffset+Size == st_size`. Its checker lives in
`/home/tadej/.hermes/cache/scratch/lane8/` (`csck.py`, `validate3.py`) and the cache in
`.../lane8/cachev3/`.

`logs/qemu/20261114-142450-l8cache3` is the run; `docs/CACHE_TRIM.md` is the recovered dyld rule set
(§3 explains the silent-print path, §6 the sweetlog dump).

## What to determine

1. **Read the kernel's actual acceptance path** and quote it with file:line: `F_ADDFILESIGS_RETURN`
   → `ubc_cs_blob_add` / `cs_blob_create_validated` / `cs_validate_csblob` (likely
   `bsd/kern/ubc_subr.c`, `bsd/kern/ubc_subr_ext.c`, `osfmk/kern/cs_blobs.h`). Enumerate every
   condition that can return `EBADEXEC` on this path for an arm64 iOS file, in the order the code
   checks them. Pay attention to: SuperBlob index entries required (0xfade0c02 CD, 0xfade0cc0 Blob
   Wrapper), `hashType`, `platform`/`platformIdentifier`, `flags` (e.g. `CS_ADHOC`,
   `CS_LINKER_SIGNED`, `CS_REQUIRE_LV`), `pageSize`, `codeLimit` vs `codeSignatureOffset`,
   `hashSize`/`hashOffset` bounds, CD version, and any arm64-specific or cache-specific test
   (`CS_CDHASH_LEN`, `CS_SUPPORTSSCATTER`, `csblob->csb_platform_binary`).
2. **Diff our signature against those requirements concretely.** Parse the main file's SuperBlob and
   CodeDirectory from `.../lane8/cachev3/dyld_shared_cache_arm64` with Python, print every field next
   to the same field from the real cache's main file
   (`build/rd-root.progs.stage/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64`), and name
   the first condition our blob fails. If the answer is "no synthetic blob can pass without a
   private key", say so and name what is missing (e.g. CMS / team ID / a real Apple CD).
3. **Decide the cheapest real fix and implement only the cheap half:**
   - If it is a field we can set (`flags`, `platform`, `codeLimit`, index entries), regenerate the
     signature for the whole 19-file set, re-validate with `csck.py`, rebuild the image, and report
     the new sha256 — that is a boot the lead agent can run.
   - If it needs a kernel change, write `xnu-avicii/patches/0106-sweet-cache-cs-accept.patch`: the
     smallest change that lets a cache file's ad-hoc blob through this path (mirror what patch `0036`
     already does for exec-time signatures, or an explicit `F_ADDFILESIGS`-path relaxation gated on a
     boot-arg, default the same behaviour as today). Add it to `xnu-avicii/series`, run
     `xnu-avicii/tools/preflight.sh --tree ~/xnu-8796.141.3 --dry`, and **do not dispatch CI** — the
     lead agent reads the patch and dispatches.
4. State, in one line, what a single boot must show to prove the fix.

## Hard limits

No QEMU, no phone, no `fastboot`/`adb`/`dd`. Do not modify `build/*` except a new
`build/rd-root.cachetrial3.img` if you regenerate the signature (keep the old one as `.prev`), never
`build/rd-root.progs.*`, `build/rd-root.tier2*`, `tooling/*`, the phone logs, or `.hermes-lanes/`.
You may write `xnu-avicii/patches/0106-*`, `xnu-avicii/series`, `docs/CACHE_TRIM.md`, and scratch.
Leave `~/xnu-8796.141.3` clean. No `git commit`. Real disassembly/source quotes only.
