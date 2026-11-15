# D — the minimal legal iOS 16 arm64 sysroot (round 3, lane 1)

## Summary

- A working cross sysroot exists at `~/.hermes/cache/scratch/sysroot-ios16`: **2218 files, 22 MB**,
  built only from apple-oss-distributions sources, zlib, LLVM's libc++ headers, and `.tbd` stubs
  generated from our own device dyld shared cache. No Apple SDK file is copied and no Apple code
  enters the repo.
- **Steps 1 and 2 are done and verified**: a C program using `errno.h`, `stdio.h`, `pthread.h`,
  `dlfcn.h`, `mach/*`, `sys/*`, `TargetConditionals.h`, `Availability*.h` compiles, and a program
  calling `printf`/`pthread_create`/`dlopen` links against the `.tbd` stubs — the dylib it produces
  carries `platform ios minos 16.0` and `LC_LOAD_DYLIB` entries for `libz.1.dylib` and
  `libSystem.B.dylib` with the versions the cache reported.
- **Steps 3–4 are partly done**: 1017 libc++ 18.1.8 headers and `zlib.h`/`zconf.h` are staged, but
  `<locale>` still fails on `strtoll_l` and four other `_l` forms unless `_USE_EXTENDED_LOCALES_`
  is defined, and a linked C++ dylib then dies on `_memmove`/`_strlen`/`_memcmp`, which no current
  `.tbd` exports.
- **Step 5**: `meson setup` **passes** (the original `ETIME` wall is gone); `ninja` all-targets
  stops at 34/752 edges, both FAILED edges being the libarchive subproject.
- **Step 6 is done**: `tooling/gpu/mksysroot.sh` (46 KB) is idempotent, pins 9 tarballs by tag and
  sha256, writes `MANIFEST.sha256`, and never deletes.
- **Reproduction warning:** the earlier prototype `assemble.sh:7` began with `rm -rf "$OUT"`, so
  re-running it erased every `.tbd` staged by the previous pass. `mksysroot.sh` generates stubs last
  and merges without deleting; the 13 `.tbd` names (10 files + 3 symlinks) are present now.

## Evidence

Primary: `/home/tadej/.hermes/cache/delegation/live/deleg_a07700d1/task-0.log` (the agent that built
the tree, 528 lines), the continuation `deleg_bc03fc59/task-0.log` (the script and the re-stage), and
the finished handoff `~/.hermes/cache/scratch/lane-1/HANDOFF.md`. Lane spec: `.hermes-lanes/next-lane-1-ios-sysroot.md`.

Every version, count and sha256 below is either quoted from those logs (cited as `task-0.log:NNN`)
or measured by a command run against the tree for this report; nothing comes from memory. Claims
marked `inferred` were not seen in a log and not re-verified.

Stale in the transcript/intake, corrected here: the sysroot is **2218 files / 22 MB**, not 1193 or
1199 (the 1017 libc++ headers were staged *after* the 19:01 build, so the script's own summary and
the earlier intake both predate them); `usr/include/c++/v1/` and `usr/include/zlib.h` are **present**
now; the `.tbd` count is **13 names**, all restaged. The dyld cache the stubs came from was an APFS
mount that is **unmounted** now (`lane-1/mnt/sysos` is empty), so re-running the `.tbd` stage needs
the cache remounted first.

## The sysroot

`usr/include/` = 2142 files, `usr/local/include/` = 65, `usr/lib` + `System/Library/Frameworks` =
10 files, plus `MANIFEST.sha256`. Sources were extracted under
`~/.hermes/cache/scratch/lane-1/src/`; the sha256 column is the tarball's, computed here
(`sha256sum`, in `src/dl/`) and identical to the pins inside `mksysroot.sh`.

| Part (what it installs) | Source and version | sha256 of tarball | Licence |
|---|---|---|---|
| `sys/*`, `mach/*`, `machine/*`, `arm/*`, `libkern/*`, `bsm/*`, `mach_debug/*`, `EXTERNAL_HEADERS` | `apple-oss-distributions/xnu` tag `xnu-8796.141.3` | `f08bfe045a1fb552a6cbf7450feae6a35dd003e9979edf71ea77d1a836c8dc99` | APSL-2.0 |
| libc public headers, `xlocale/*`, `locale/FreeBSD/*`, `stdtime` | `Libc` tag `Libc-1534.100.14` | `eeb3c39d17638f060bb3734331ad72fc465ef21adedd49d8235c54996dca4ffe` | APSL-2.0 |
| `pthread.h`, `pthread/*`, `sys/qos.h`; private half in `usr/local/include` | `libpthread` tag `libpthread-514.100.2` | `3845098e4ce5a7cf69e84d6c84de4dea860454732bd18911be74ed5fc324b8e9` | APSL-2.0 |
| `malloc/*` | `libmalloc` tag `libmalloc-425.100.7` | `89139f3159c26a634294b601a1caacbec253f1ef243ca24b54125b520f83c4d8` | APSL-2.0 |
| `os/*` (public) and `usr/local/include/os/*` | `libplatform` tag `libplatform-375.120.2` | `c0962595da8899cf54445698fd71bddc2118edb8ce8e3d6e11a29ef96ad754bc` | APSL-2.0 |
| `math.h` arm64 branch, `fenv.h`, `complex.h` | `Libm` tag `Libm-2026` | `2a33044df4f8a899b49b4531fc5e91abc6c8e10e14567171e8829b2b15ddf84b` | APSL-2.0 |
| `Availability.h`, `AvailabilityInternal*.h`, `AvailabilityMacros.h`, `AvailabilityVersions.h` (+2 private) | `AvailabilityVersions` tag `AvailabilityVersions-141.1` | `4aea449803bd26bf7af37688f6defde48c897d03aa5e22abfda4accc97ced322` | APSL-2.0 |
| `dlfcn.h` | `dyld` tag `dyld-1042.1` | `5ff902c50c78e809e90fb92038b86e531aafbc6dff36d254d6548ce6d41a0aa8` | APSL-2.0 |
| `zlib.h`, `zconf.h` | zlib `1.2.11` (zlib.net fossils) | `c3e5e9fdd5004dcb542feda5ee4f0ff0744628baf8ed2dd5d66f8ca1197cb1a1` | zlib |
| `usr/include/c++/v1/` — 1017 files, `_LIBCPP_VERSION 180100` | LLVM/clang `18.1.8` local toolchain (`tooling/opt/llvm`), not a tarball; version read from `c++/v1/__config:65` | n/a (tree, not tarball) | Apache-2.0 WITH LLVM-exception |
| `.tbd` stubs (13 names) | generated from our cache `dyld_shared_cache_arm64`, sha256 `76874e8375252ee643011ff8063f0cce12355f05cf5f9897a34e5679667a65aa` (per `MANIFEST.sha256`) | — | generated here: symbol names + versions only |
| **synthesized** `TargetConditionals.h` (2151 B) | written for ios-nord; no Apple text | — | synthesized |
| **synthesized** `MacTypes.h` (689 B) | written for ios-nord; no Apple text | — | synthesized |
| **synthesized** `usr/local/include/pthread/priority_private.h` (1386 B) | written for ios-nord; the header exists in no tarball | — | synthesized |
| **generated** `sys/_symbol_aliasing.h` (27069 B) | emitted by `alias.py` (a port of xnu's `make_symbol_aliasing.sh`), a build product | — | synthesized |
| handwritten, same class: `sched.h` (1087 B), `math.h` (arm64 dispatcher) | written for ios-nord | — | synthesized |

Note on the libc++ count: `find usr/include/c++/v1 -type f | wc -l` says **1017**; the coordinator's
intake says 183 libc++ headers. The 1017 figure is what is on disk; 183 is `inferred` to count only
top-level headers rather than the `__*` detail headers. Either way the set is LLVM 18.1.8's, complete
enough that `<vector>`, `<string>`, `<map>` and `<stdexcept>` all parse.

The `.tbd` set, with the symbol count and the version each stub advertises (measured with a regex
count over the text, and the `current-version:` field):

| stub | symbols | current-version | install-name |
|---|---|---|---|
| `usr/lib/libSystem.B.tbd` | 7895 | 1319.100.3 | `/usr/lib/libSystem.B.dylib` |
| `usr/lib/libSystem.tbd` | symlink | — | — |
| `usr/lib/libc++.1.tbd` | 1880 | 1500.65.0 | `/usr/lib/libc++.1.dylib` |
| `usr/lib/libc++.tbd` | symlink | — | — |
| `usr/lib/libc++abi.tbd` | 366 | 1500.65.0 | `/usr/lib/libc++abi.dylib` |
| `usr/lib/libz.1.tbd` | 79 | 1.2.11 | `/usr/lib/libz.1.dylib` |
| `usr/lib/libz.tbd` | symlink | — | — |
| `System/.../CoreFoundation.framework/CoreFoundation.tbd` | 3089 | 1979.1.102 | `/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation` |
| `System/.../IOKit.framework/IOKit.tbd` | 2105 | 275.0.0 | `.../Versions/A/IOKit` |
| `System/.../IOSurface.framework/IOSurface.tbd` | 576 | 1.0.0 | `.../IOSurface.framework/IOSurface` |
| `System/.../OpenGLES.framework/OpenGLES.tbd` | 487 | 1.0.0 | `.../OpenGLES.framework/OpenGLES` |
| `System/.../QuartzCore.framework/QuartzCore.tbd` | 1114 | 1.11.0 | `.../QuartzCore.framework/QuartzCore` |
| `System/.../Metal.framework/Metal.tbd` | 600 | 306.6.6 | `.../Metal.framework/Metal` |

QuartzCore and Metal were **not** requested by the lane spec; they are there because lane A and lane
E/G touch them (open question 5).

## Tests

**Test 1 — C surface compiles** (`t/step1.c`: `errno.h`, `stdio.h`, `stdlib.h`, `string.h`,
`unistd.h`, `fcntl.h`, `pthread.h`, `dlfcn.h`, `sys/{types,stat,mman,sysctl,time}.h`,
`mach/{mach,mach_time,host_info,vm_page_size}.h`, `Availability*.h`, `TargetConditionals.h`, plus an
`#error` unless `TargetConditionals` reports an iOS device):

```
$ clang --target=arm64-apple-ios16.0 -isysroot ~/.hermes/cache/scratch/sysroot-ios16 -O2 -Wall -c t/step1.c -o t/step1.o
step1 compile OK
```

**Test 2 — link against the stubs** (literal command from `HANDOFF.md`, run against the canonical
tree):

```
$ clang -target arm64-apple-ios16.0 -isysroot ~/.hermes/cache/scratch/sysroot-ios16 \
    -DXNU_PLATFORM_iPhoneOS -O1 -Wall -c t/step2.c -o t/step2.o
$ ld64.lld -arch arm64 -dylib -platform_version ios 16.0 16.0 \
    -syslibroot ~/.hermes/cache/scratch/sysroot-ios16 -o t/libstep2.dylib t/step2.o -lz -lSystem
compile OK
link OK
-rwxrwxr-x 1 tadej tadej 65976 t/libstep2.dylib   # sha256 5d57d1aa25992e37f19551c33e81cc52523b20d3e84b8582c2815bfb295a463f
```

Re-run for this report (same commands, `-O2` instead of `-O1`, so the bytes differ and the
sha256 is `f515e3b6…` — the size, 65976 B, and the headers are identical). Without
`-DXNU_PLATFORM_iPhoneOS` the same link fails first (see gotcha 3):

```
ld64.lld: error: undefined symbol: _pthread_join$UNIX2003
>>> referenced by t/step2.o:(symbol _step2+0x44)
```

The linked dylib's headers (`llvm-objdump --macho --private-headers`):

```
      cmd LC_BUILD_VERSION
   cmdsize 32
  platform ios
       sdk 16.0
     minos 16.0
    ntools 1
      tool lld
   version 18.1.8
          cmd LC_LOAD_DYLIB
      cmdsize 48
         name /usr/lib/libz.1.dylib (offset 24)
   time stamp 0 Thu Jan  1 01:00:00 1970
      current version 1.2.11
compatibility version 1.0.0
          cmd LC_LOAD_DYLIB
      cmdsize 56
         name /usr/lib/libSystem.B.dylib (offset 24)
   time stamp 0 Thu Jan  1 01:00:00 1970
      current version 1319.100.3
compatibility version 1.0.0
```

**That output is also the proof the stubs are the source.** There is no Mach-O binary anywhere under
the sysroot — `file` on all 13 stub names returns `ASCII text` (10 files) or `symbolic link` (3), e.g.
`usr/lib/libSystem.B.tbd: ASCII text, with very long lines (65325)`. Yet the linker emitted
`current version 1319.100.3`, a number that exists only as `current-version: 1319.100.3` on
`usr/lib/libSystem.B.tbd:5`; likewise `1.2.11` is `usr/lib/libz.1.tbd:5`. The versions cannot have
come from a binary on disk, because there is none: they came out of the text stubs, which came out of
the cache header.

**Test 3 — C++17** (`t/step3.cpp`: `std::vector`, `std::string`, `std::map`, `std::make_unique`,
`throw std::runtime_error`). Current state, verbatim:

```
$ clang --target=arm64-apple-ios16.0 -isysroot … -std=c++17 -DXNU_PLATFORM_iPhoneOS \
    -nostdinc++ -isystem …/usr/include/c++/v1 -c t/step3.cpp -o t/step3.o
…/usr/include/c++/v1/locale:719:68: error: use of undeclared identifier 'strtoll_l'; did you mean 'wcstoll_l'?
…/usr/include/c++/v1/locale:751:68: error: use of undeclared identifier 'strtoull_l'; …
…/usr/include/c++/v1/locale:776:10: error: use of undeclared identifier 'strtof_l'
…/usr/include/c++/v1/locale:781:10: error: use of undeclared identifier 'strtod_l'
…/usr/include/c++/v1/locale:786:10: error: use of undeclared identifier 'strtold_l'
7 errors generated.
```

With `-D_USE_EXTENDED_LOCALES_` added, the same TU **compiles** (113720 B object). Linking it then
fails, which is the real step-3 wall:

```
$ ld64.lld -arch arm64 -dylib -platform_version ios 16.0 16.0 -o /tmp/libstep3.dylib /tmp/step3.o \
    -L…/usr/lib -lc++ -lc++abi -lSystem
ld64.lld: error: undefined symbol: _strlen
ld64.lld: error: undefined symbol: _memmove
>>> did you mean: _wmemmove
ld64.lld: error: undefined symbol: _memcmp
```

`_memmove`, `_memcmp` and `_strlen` are exported by `/usr/lib/system/libsystem_c.dylib` in the cache
(1302 symbols, queried directly), but libSystem.B's stub does not list them: `libSystem.B.dylib`
exports only 3 symbols itself and the 7895-symbol stub is a folded union that reaches libsystem_c
through a re-export the stub no longer declares (gotcha 8).

**Test 4 — zlib**: `usr/include/zlib.h` is present (`zlib.h -- interface … version 1.2.11`),
`libz.1.tbd` has 79 symbols and `libz.tbd` is its symlink; test 2 links `-lz` through it. **No
`crt1.o`/`dylib1.o` is needed for `-dylib`**: both link tests above pass with `ld64.lld` and no crt.
(`inferred`: an executable would need `crt1.o`, which the sysroot does not have.)

**Test 5 — Mesa**: `meson setup` against this sysroot **passes** with
`-Dgallium-drivers=freedreno -Dgles2=enabled` (cross file `lane-1/cross-ios16-sysroot.ini`, source
tree `lane-3/patched`, mesa 25.0.7). `ninja` then builds the freedreno/ir3/fdl objects and stops at
34/752 edges on libarchive's `CommonCrypto/CommonCryptor.h` and `openssl/evp.h` (the subproject, not
the sysroot). Re-running `ninja -k 0` here continues past those and adds two sysroot-level failures:
`src/util/u_process.c:43` `'mach-o/dyld.h' file not found` and `src/util/os_misc.c:395`
`call to undeclared function 'host_statistics64'` (plus `mach_host_self`). `usr/include/pwd.h` is
missing too, which is what breaks libarchive's `struct passwd`.

## Gotchas

1. **Read the cache header, never assume its layout.** Mapping/image table offsets and the 32-byte
   mapping entry come out of the file; a first attempt guessed and saw 43 mappings, the correct read
   of the same header gives 51 mappings, 2710 images, 42 subcaches (`task-0.log:70`, `:74`; reader at
   `dsc.py:23-27,42`). Rule: derive every offset from `0x10`/`0x188`/`0x1C0` and trust the count.
2. **`__API_AVAILABLE` in xnu's `EXTERNAL_HEADERS` is the 2016 four-platform vintage; iOS 16's own
   headers pass a fifth (bridgeos)**, so every TU dies with `expected function body after function
   declarator` at `sys/unistd.h:192` (`task-0.log:196`). Rule: generate `Availability*.h` by
   pre-processing AvailabilityVersions-141.1's templates with its own `availability` script
   (`mksysroot.sh:1005-1035`), never ship xnu's copies.
3. **`sys/cdefs.h` must be xnu's kernel copy, and using it makes `-DXNU_PLATFORM_iPhoneOS`
   mandatory.** Without that define `__DARWIN_ONLY_UNIX_CONFORMANCE` stays 0
   (`usr/include/sys/cdefs.h:534`; the iOS branch that sets 1 is `:546`), `__DARWIN_SUF_UNIX03`
   becomes `"$UNIX2003"` (`:725-729`), and the object references `_pthread_join$UNIX2003`, which no
   stub exports (`task-0.log:458` for the `_getpid` form). Rule: put the define in the cross file, not
   in a README.
4. **`_USE_EXTENDED_LOCALES_` gates the `_l` functions.** `usr/include/stdlib.h:466-468` includes
   `xlocale/_stdlib.h` only inside `#ifdef _USE_EXTENDED_LOCALES_`, even though
   `xlocale/_stdlib.h:51,59` declares `strtoll_l`/`strtoull_l`; libc++'s `<locale>` needs all five.
   Rule: compile C++ with `-D_USE_EXTENDED_LOCALES_` or a `__config_site` that sets it.
5. **`machine/` and `mach/machine/` are not where the kernel tree names them.** `bsd/machine` and
   `osfmk/machine` are thin, `osfmk/mach/arm64` ships almost nothing, so `mach/machine` must be filled
   from `osfmk/mach/arm` and `THREAD_STATE_MAX` appended by hand because `osfmk/mach/thread_status.h:85`
   needs it while the kernel copy does not define it (`task-0.log:243-244`; `mksysroot.sh:930-938`).
   Rule: populate `mach/machine` from `osfmk/mach/arm`, then `grep -q '^#define THREAD_STATE_MAX'`
   before appending.
6. **Three headers in `sys/` are build products, not sources.** `_symbol_aliasing.h` (needs
   `make_symbol_aliasing.sh` + the SDK's `availability.pl` → replaced by `alias.py`),
   `_posix_availability.h` (`make_posix_availability.sh`) and `syscall.h` (`makesyscalls.sh`) are all
   missing from any tarball; without them Libc's `#include_next` chain fails
   (`task-0.log:146,150,162`). Rule: run the generators as a build step and check `grep -c '^#define'`
   on each output.
7. **The private half of the headers belongs in `usr/local/include`**, and one of them exists
   nowhere: `pthread/priority_private.h` is included by `libpthread/kern/kern_internal.h:35` and by
   xnu but shipped by no tag (`task-0.log:400-413`). Rule: mirror the SDK's split
   (`libpthread/private`, `libplatform/private`, `libsyscall/{os,mach}` → `usr/local/include`) and
   synthesize `priority_private.h`.
8. **A `.tbd` needs the trailing `...` and needs its re-exports folded in.** Without the YAML end
   marker `ld64.lld` says `could not load TAPI file … unsupported file type`, which reads like a
   broken file rather than a missing line (`task-0.log:446,462`); and `libSystem.B` re-exports 40
   `libsystem_*` libraries, so emitting `reexported-libraries` without their stubs hard-errors
   (`task-0.log:476`). Rule: always append `...` (`mksysroot.sh:465`) and fold re-export symbols into
   the export list instead of declaring re-exports (`mksysroot.sh:452-454`) — accepting that
   `_memmove`/`_strlen` then stay missing until the sub-library stubs exist.
9. **libc++ headers and the libc++ dylib are two different vintages, and clang++ prefers its own.**
   Headers are 180100 (LLVM 18.1.8), the device's `libc++.1.dylib` is 1500.65.0; `__config:13`
   `#include <__config_site>` fails outright without a site config (`task-0.log:494`), and clang++
   resolves `<vector>` from its resource dir unless told otherwise. Rule: stage `__config_site` with
   `_LIBCPP_ABI_VERSION 1`, `_LIBCPP_HARDENING_MODE _LIBCPP_HARDENING_MODE_FAST`, and always pass
   `-nostdinc++ -isystem <sysroot>/usr/include/c++/v1`.

## Status and plan

Steps as the lane spec numbers them.

| step | state |
|---|---|
| 1 C headers | **done** — test 1 compiles |
| 2 link stubs | **done** — test 2 links, 65976 B, `platform ios minos 16.0` |
| 3 C++ | **partial** — 1017 headers + `__config_site` staged; `<locale>` needs `_USE_EXTENDED_LOCALES_` (then compiles); link fails on `_memmove`/`_memcmp`/`_strlen` |
| 4 zlib | **done** — `zlib.h`/`zconf.h` 1.2.11, `libz.1.tbd` (79 syms) + `libz.tbd`; no crt needed for `-dylib` |
| 5 Mesa | **partial** — configure passes; `ninja` all-targets stops 34/752 on the libarchive subproject; the next walls are `mach-o/dyld.h`, `pwd.h`, `host_statistics64` |
| 6 `mksysroot.sh` | **done** — 46 KB, idempotent (two runs, identical outputs section), 9 tarballs pinned by tag+sha256, `MANIFEST.sha256`, `--no-tbd` when no cache is mounted (`:53`, `:84`) |

Remaining, in order, each with the check that closes it:

1. **Finish the libc++ link.** Add `libsystem_c` (and friends) stubs so `_memmove`/`_strlen`/`_memcmp`
   resolve. Verify: the test-3 link command exits 0 and `llvm-nm -u` on the dylib shows no `_mem*`.
2. **Stage `pwd.h`** (and `grp.h`) — not in Libc-1534.100.14's `include/`, so synthesize like
   `sched.h`. Verify: `ls usr/include/pwd.h` and libarchive's
   `archive_read_disk_set_standard_lookup.c` compiles.
3. **Stage `mach-o/dyld.h`** from `dyld-1042.1/include/mach-o/dyld.h`. Verify:
   `src/util/u_process.c` compiles.
4. **Extend the mach stubs** to declare `mach_host_self` and `host_statistics64` (currently
   `mach/mach_host.h:20` only has `host_statistics`). Verify: `src/util/os_misc.c` compiles.
5. **Re-run `ninja`** and record the first non-libarchive error. Verify: edge count above 34/752.
6. **Regenerate `MANIFEST.sha256`** — the current one is from the 19:01 build and predates the libc++
   staging and `sched.h`/`nl_types.h`. Verify: `sha256sum -c` over the outputs section.

## Open questions

1. **Rebuild-all vs cache-with-hashes.** `mksysroot.sh` re-stages everything on every run (idempotent
   but not incremental) and regenerates all stubs. Should the `.tbd` stage be skipped when the cache
   sha256 in `MANIFEST.sha256` is unchanged, or is a full rebuild each time the safer contract?
2. **LLVM-18 headers against a 1500.65.0 libc++ dylib.** `_LIBCPP_ABI_VERSION 1` makes the mangling
   agree (`__1`), but 180100 headers emit inline-ABI tags (`B8fe180100`) and assume libc++ symbols
   that 1500.65.0 may not export. Options: pin older libc++ headers matched to 1500.65.0 (no source
   for them here), or accept header-side inlining only and check every `_ZNSt3` reference against
   `libc++.1.tbd` before trusting it.
3. **Period mismatch.** `Libm-2026` and `AvailabilityVersions-141.1` are the tags GitHub carries, not
   the versions iOS 16.7.16 shipped; `Libm-2026`'s `math.h` needed a dispatch header because its
   default has no arm64 branch. Do we hunt for closer tags, or document the gap and move on?
4. **MIG: finish the patch set or stay declaration-only?** `mach/*` stubs are hand-written
   declarations where the SDK ships MIG output (`mk_mach_stubs.sh`). Declaration-only is enough for
   compiling but not for anything that inspects message layouts; finishing the MIG patch set costs
   migcom on the host.
5. **Keep QuartzCore and Metal?** Neither was requested by the lane spec; both are staged (1114 and
   600 symbols) because lanes A/E/G touch them. They are cheap, but they are unverified surface.

## Scratch

```
~/.hermes/cache/scratch/sysroot-ios16/          the sysroot (2218 files, 22 MB) + MANIFEST.sha256
~/.hermes/cache/scratch/lane-1/                 work area
  src/                                          9 extracted upstream trees + dl/ tarballs
  dsc.py  gen_tbd.py  gen_tbds.sh  gen_symbol_aliasing.py  patch_avail.py
  assemble.sh                                    the old prototype (its :7 was `rm -rf "$OUT"`)
  cross-ios16-sysroot.ini                        meson cross file (C, C++, ObjC, ar/ranlib/strip)
  t/step1.c  t/step2.c  t/step3.cpp  t/libstep2.dylib
  mesa-build/                                    meson 25.0.7 build dir, configured, 800 objects
  HANDOFF.md                                     the builder's own handoff note
~/.hermes/cache/scratch/lane-1/src/dl/*.tar.gz   the 9 pinned tarballs (sha256 in the table above)
~/.hermes/cache/delegation/live/deleg_a07700d1/task-0.log     builder transcript
~/.hermes/cache/delegation/live/deleg_bc03fc59/task-0.log     mksysroot.sh transcript
~/.hermes/cache/scratch/lane-3/patched/         mesa source tree the step-5 build used
```

The dyld cache itself is gone with its mount (`lane-1/mnt/sysos` is empty); the in-repo copy at
`build/rd-root.cachetrial.cache/dyld_shared_cache_arm64` has sha256
`8925abaa5fb115e78d2b4296ca70062e559a7cc73b04313f03699124b12a0b1d` (145 MB) and is **not** the file
the stubs were generated from (`76874e83…`), so treat it as a different cache until proven otherwise.
