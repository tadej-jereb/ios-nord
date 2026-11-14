# CACHE_TRIM — dyld-1067 shared-cache acceptance rules, from the shipped binary

Source: disassembly of `build/rd-root.progs.stage/usr/lib/dyld` (dyld-1067, `__TEXT` at
vmaddr 0) with `tooling/opt/llvm/bin/llvm-objdump -d --macho`. Every rule below is quoted
from an address in that binary, not from dyld-955 source. Offline checker that applies
exactly these rules: `/home/tadej/.hermes/cache/scratch/dyldre/pf1067.py <cachedir>`
(code-signature blobs checked against XNU `cs_validate_csblob`: `csck.py` beside it).

## 1. Call order (pid 1, no `DYLD_SHARED_REGION`)

    ProcessConfig::DyldCache ctor            0x17f74
      CacheFinder ctor                       0x17ad4  dirfd: DYLD_SHARED_CACHE_DIR env, else
                                                      ignite() (skipped if dyld_flags bit 3),
                                                      else open("/System/Library/Caches/com.apple.dyld/")
      SyscallDelegate::getDyldCache          0x115ec -> loadDyldCache 0x11350
        options+4 forcePrivate ? mapSplitCachePrivate 0x39418
        reuseExistingCache                   0x39b14  __shared_region_check_np (kernel logs
                                                      "check_np(...) vm_shared_region_start_address() failed")
        mapSplitCacheSystemWide              0x39c7c
          preflightMainCacheFile             0x3a114  openat(dirfd,"dyld_shared_cache_arm64")
            preflightCacheFile               0x3a48c
          for each subCache suffix:          0x39d8c
            preflightSubCacheFile            0x3a2c4  openat(dirfd, main + suffix)
              preflightCacheFile             0x3a48c
          vm_allocate dyld_data page         0x39e0c
          __shared_region_map_and_slide_2_np 0x3a024  <- first point the kernel prints map(...)
          reuseExistingCache                 0x3a074

The kernel `map(...)` lines come only from the syscall at 0x3a024. Zero `map(` lines
means one of the steps above it returned 0.

## 2. preflightCacheFile (0x3a48c) rules, in order. The first one that fails ends the load

| addr    | rule | message stored in loadInfo.errorMessage |
|---------|------|------------------------------------------|
| 0x3a4e8 | `fstat(fd)` ok | shared cache file stat() failed |
| 0x3a520 | `pread(fd, 0x4000, 0)` returns exactly 0x4000, so **file >= 16 KiB** | shared cache file pread() failed |
| 0x3a55c | magic == `"dyld_v1   arm64\0"` | shared cache file has wrong magic |
| 0x3a5c8 | if mappingOffset >= 0xe0: `platform(0xd8)` == main exe platform (2) and simulator bit (byte 0xdd bit1) clear, or `altPlatform(0x170)` == platform | shared cache file is for a different platform |
| 0x3a600 | **1 <= mappingCount <= 8** (`sub w8,w26,#0x9; cmn w8,#0x9; b.hi`) — CacheInfo holds 8 x 0x30 mappings, count at +0x180 | shared cache file mappings are invalid |
| 0x3a628 | count >= 3 ⇒ `mapping[1].maxProt == 3` | shared cache data mapping was expected |
| 0x3a67c | `mapping[0].fileOffset == 0` | shared cache text file offset is invalid |
| 0x3a698 | `codeSignatureOffset(0x28) + codeSignatureSize(0x30) == st_size` | shared cache code signature size is invalid |
| 0x3a6ac | count >= 2 ⇒ last `maxProt == 1` | shared cache linkedit permissions are invalid |
| 0x3a6dc | count >= 2 ⇒ `mapping[0].maxProt` ∈ {1,5}; count == 1 ⇒ == 5 | shared cache text permissions are invalid |
| 0x3a71c | for i ≥ 1: `prev.addr+prev.size <= m[i].addr` and `prev.fileOffset+prev.size == m[i].fileOffset` | shared cache mappings overlap |
| 0x3a778 | m[1] RW ⇒ m[1..count-2] all maxProt 3 | shared cache data mappings have wrong permissions |
| 0x3a7bc | `fcntl(F_ADDFILESIGS_RETURN=0x61, {0, csOff, csSize})` != -1 (kernel blob validation) | code signature registration for shared cache failed |
| 0x3a7c8 | returned end offset >= codeSignatureOffset | code signature does not cover entire shared cache file |
| 0x3a814 | `mmap(0x4000, R|X, MAP_PRIVATE, fd, 0)` ok and equal to the pread page | first page of shared cache not mmap()able / not valid |
| 0x3a918 | mappingWithSlide entry with slideInfoFileSize != 0 in a 1-mapping file ⇒ `__throw_bad_optional_access` (abort, not a soft reject) | — |
| 0x3a974 | if mappingOffset > 0x1c8: `pread(fd, 0xe00, subCacheArrayOffset(0x188))` returns exactly 0xe00 (64 × 0x38 entries) | ...could not read subcache entries |

So the per-file shape is `[R|X or R] [R|W]* [R]`, at most 8 mappings, ascending in VM and
contiguous in the file, with the signature as the file's tail. No UUID is compared on this
path (H+0x58 is never read in 0x3a48c–0x3aa48).

mapSplitCacheSystemWide (0x39d24): if the main file declares sub-caches (`numSubCaches()+1`
at info+0x1a8 > 0) but mappingOffset <= 0x1c8 → "shared cache is too old, missing cache
suffixes". At most 64 files in total (dyld CacheInfo array 0x2b000/0xac0). The kernel allows 256 files
and 2048 mappings (`bsd/vm/vm_unix.c:2206,2860`).

## 3. Why nothing is printed

* The only rejection print is `"dyld cache '%s' not loaded: %s\n"` at **0x181c8**, gated by
  `loadInfo.cacheFileFound` (sp+0x30), **not** by a verbose flag. cacheFileFound = 1 once
  `openat` of the main file succeeds (0x3a240), 0 on ENOENT (0x3a26c).
* **Sub-cache errors are discarded.** `preflightSubCacheFile` receives `x1 = x19+0x18`
  (0x39dac), a local SharedCacheLoadInfo zeroed on every iteration (0x39d8c–0x39d9c). Its
  message never reaches the caller. A rejected sub-cache therefore prints
  `dyld cache '<NULL path>' not loaded: <NULL>` (the path field x19+0x18 is still zero at that point).
* `options.verbose` (SharedCacheOptions+6) = `Logging.segments` (Logging+1) =
  `DYLD_PRINT_SEGMENTS` (0x178a4), honoured only if Security+2 (AMFI flags bit 4). It only
  gates the success chatter ("Mapping the shared cache system wide", "mapped dyld cache
  file system wide", "re-using existing shared cache"). pid 1 cannot get it anyway: XNU
  `load_init_program_at_path` execs launchd with argv only (kern_exec.c:6752), and launchd.plist
  `EnvironmentVariables` apply to launchd's children, not to launchd's own dyld.
* boot-arg `dyld_flags` (kern_sysctl.c:2123 → apple[] `dyld_flags=0x…`) is read for pid 1 only on
  an internal install (0x1765c). Its bits select the cache source and dev/customer cache
  (bit 3: skip ignite, bits 4/5: drop the cryptex dir, bits 0/2: customer/dev); none of them logs.
* `dyld4::console` (0x17d20) for pid 1 opens `/dev/console` and writes the body there (the
  `dyld[1]: ` prefix goes to fd 2, which is not open). `/dev/console` → `kmoutput` →
  `console_write` → `_cnputs`, which returns at once when `disableConsoleOutput` is set
  (serial_console.c:274). The QEMU runs report `disableConsoleOutput: 1`, an empty serial and a blank screen,
  and the line never enters msgbuf. Patch 0047 appends every `_cnputs` byte to
  `_sweet_log_ring` (0xfffffe0007c525f8, 4 MiB; byte count `_sweet_log_total`
  0xfffffe0007c525f0) **before** that gate, so the line exists in RAM. It is not dumped by
  the QEMU harness today.

## 4. What the two trimmed-cache runs failed

Both failed the **same check, 0x3a600 (mappingCount ≤ 8)**:

* `20261114-123028-l8cache` (single file): main file has 143 mappings → main rejected,
  errorMessage "shared cache file mappings are invalid", printed to /dev/console only.
* `20261114-134304-l8cache2` (15 files): main and .01–.12 pass every rule (signatures valid
  per `cs_validate_csblob`, all page hashes match). `.41.dylddata` has **32 mappings**
  `[5, 3×30, 1]` (one RW mapping per image's `__DATA`, spread over 919 MiB of VM) → rejected
  silently (sub-cache message discarded). Apple's data sub-caches are `[5,3,3,1]`.

This is not a size wall. 30 RW regions (4.6 MiB of data) can be carried in 5 data sub-caches
of `[R|X hdr][R|W ≤6][R]` with no filler (+ ~2 pages + signature each), or in fewer files by
filling small VM gaps with file bytes: 6 runs → 1 file, +108 MiB; 12 → 2 files, +52 MiB;
18 → 3, +22.5 MiB; 24 → 4, +8.2 MiB. Every gap between regions is ≥ 0.73 MiB, so the 16 KiB
header and trailing-R pages fit.

## 5. Next walls already visible in the bytes (after the mapping count is fixed)

* **dyld_data mapping collides with the main header.** mapSplitCacheSystemWide appends a
  mapping at `sharedRegionStart + dynamicDataOffset(H+0x1f0)` (0x3a9f8, 0x39ffc), size
  `round_page(0x20)`. The rebuilt main has `dynamicDataOffset = 0`, so this lands on
  0x180000000, the same VA as its own R|X header mapping. Apple's has 0xaade4000 / max 0x4000
  (VA 0x22ade4000). Even if the kernel accepted that, reuseExistingCache (0x39bd4) wants
  `"dyld_data    v0"` at that address, and without it the DyldCache ctor halts with
  "dyld shared region dynamic config data was not set" (0x18338).
* Kernel side (vm_unix.c ~2400–2550): regular file, owned by uid 0 unless trust-cached,
  on the root volume. The real cache already passes these with the same staging.

## 6. Two hard-won rules not visible in dyld's code

1. **Any byte change requires re-signing.** The CodeDirectory covers every page of the file,
   including page 0 with `imagesText`, the trie pointers and `subCacheArray`. Editing the header
   after signing leaves `F_ADDFILESIGS_RETURN` returning `EBADEXEC` (kernel prints
   `unable to create a validated cs_blob object: 85`), dyld discards the cache before it ever walks
   the trie, and launchd reports `(no such file, no dyld cache)` — one stage *earlier* than a trie
   miss. Re-sign and re-image after every structural edit, and re-run `csck.py` on the final bytes.
2. **The `dylibsTrie` node layout is** `uleb terminalSize | terminal | u8 childrenCount |
   childrenCount × {cstring edge, uleb offset}`. Writing a `0x00` terminator after the child list
   instead of a count makes dyld read the first edge byte (`/` = 0x2f) as "47 children", so
   `trieWalk` returns null and every lookup misses — while a checker that shares the same wrong
   convention still reports a clean pass. `imagesText` entries are **32 B** (`uuid16 + loadAddress +
   textSegSize + pathOffset`), not 40. Validate any trie reader against Apple's own cache first
   (2710 images + 56 aliases; `/usr/lib/libSystem.B.dylib` → 858 there), then against ours
   (37 terminals ↔ 37 images bijection; libSystem → 32, libobjc → 0).


## 7. Making the next boot print its own reason

1. Dump `_sweet_log_ring` and `_sweet_log_total` at the end of the run, the same way msgbuf is
   dumped (k2p = va − gVirtBase + gPhysBase = 0x91c525f8 for the ring, if the kernel image is
   unslid as the msgbufp read implies). Grep for `not loaded:`.

   **Done in `tooling/60-qemu-boot.sh`** (writes `sweetlog.raw` = the exact bytes, `sweetlog.txt`
   = same with the NULs dropped, and `sweetlog_*` keys in `console_flags.json`). Verified on run
   `logs/qemu/20261114-141314-lane4-sweetlog2` (`build/rd-root.cachetrial2.img`, 60 s): the ring
   read linearly from 0x91c525f8, `_sweet_log_total` 9286, 100 % printable, and it contains

       dyld cache '(null)' not loaded: code signature registration for shared cache failed

   — i.e. the main cache was rejected at cs registration, *not* at the mapping count of 0x3a600
   that §4 predicted for `20261114-134304-l8cache2`; that run's own reason was never printed, so
   §4's mapping-count chain stands only as a static reading.  Note the ring is not a superset of
   msgbuf: it lacks the 82 early kernel lines of that run (`kprintf initialized`,
   `pe_arm_init_interrupts: …`, before the console channel exists) and carries userland output
   msgbuf does not (`Darwin Ignition Sequence`, `libignition: …`).
2. For a sub-cache reject that is the only signal dyld gives. Run `pf1067.py` before the boot instead.
