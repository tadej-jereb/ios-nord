# sysroot-test — re-runnable proof that the iOS 16 sysroot works

Two tiny C tests that decide whether a candidate sysroot can compile and link
iPhoneOS target code. They exist so the sysroot claim in
`docs/gpu-research/D-ios-sysroot.md` can be re-checked by anyone, on any day,
without trusting a transcript.

Provenance: both `.c` files are ours (written for ios-avicii), not Apple code.
No paths are baked into them — the sysroot always arrives via `-isysroot`.

## Invocation

```sh
./run.sh ~/.hermes/cache/scratch/sysroot-ios16
```

`run.sh` takes the sysroot directory as `$1` and refuses to start unless
`$1/usr/lib/libSystem.B.tbd` exists — a directory without text-based stubs is
not what these tests are about. Output (objects, dylibs, logs, the control's
spare sysroot) goes to `$OUT`, default
`/home/tadej/.hermes/cache/scratch/sysroot-test-out`, wiped at every start.
The sysroot itself is only ever read.

Toolchain prefix: `/home/tadej/ios-nord/tooling/opt/llvm/bin/`
(`clang` 18.1.8, `ld64.lld` 18.1.8, `llvm-objdump`). Unprivileged, in-tree.

Every compile and link carries exactly:

```
-target arm64-apple-ios16.0 -isysroot <sysroot> -DXNU_PLATFORM_iPhoneOS -fuse-ld=lld
```

`-isysroot` only — no `-nostdinc`: the point is to exercise this sysroot as a
sysroot, not to over-constrain the driver until it agrees.

## Tests

| Test | Passing means | A failure means |
| --- | --- | --- |
| `step1.c` (compile to `.o`) | The sysroot's libc, pthread, dlfcn, mach and `TargetConditionals` headers all parse for `arm64-apple-ios16.0`, and `TARGET_OS_IPHONE` reports a device (not a simulator). | The header surface is incomplete, mixed with a host SDK, or `TargetConditionals.h` is wrong — every C consumer of this sysroot will break. |
| `step2.c` (`-dynamiclib -lz`, then `llvm-objdump --macho --private-headers`) | The link succeeds and the dylib carries `LC_LOAD_DYLIB /usr/lib/libz.1.dylib`, `LC_LOAD_DYLIB /usr/lib/libSystem.B.dylib`, `LC_BUILD_VERSION platform ios` and `minos 16.0`, so `printf`, `pthread_create`, `dlopen` and `getpid` were bound by the `.tbd` stubs. | Either the stubs are missing/partial or a host library silently satisfied the link — imports will be wrong at dyld time on the phone. |
| control (same link, `libSystem.B.tbd` renamed away inside a copy of the sysroot) | The link **fails**, with `library not found for -lSystem` and `printf`/`getpid`/`pthread_*`/`dlopen` undefined. That is what proves the stubs did the work in test 2 rather than a host library leaking in. | Test 2's PASS was meaningless on this host — something outside the sysroot is satisfying symbol lookups. |

`run.sh` exits 0 only if step 1, step 2 and the control all behave. Prints one
`PASS`/`FAIL` line per item; exit 2 means the arguments were wrong.

## Status

Last full run, and the raw `llvm-objdump`, platform-decode and control output:
see `PROOF.txt`. All three pass against
`~/.hermes/cache/scratch/sysroot-ios16`.

This pair stops at link time. It does not run anything on the phone, and a
green result says nothing about whether the kernels or frameworks load — only
that the sysroot's libc surface is coherent enough to build against.

## Adding a test

Keep it small, keep it path-free (use `-isysroot` from `run.sh`, or `argv[0]`
and `dlopen` at runtime), and add a row to the table above saying what a
failure would mean. A test whose failure is not diagnostic is not a test.
