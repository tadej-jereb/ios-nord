# Codex task C: SweetGLES.bundle, the plugin iOS loads that installs SweetEAGL

**Repo:** `/home/tadej/ios-nord`.
**Worktree:** another Codex session runs at the same time, so work in your own git worktree:

```
cd /home/tadej/ios-nord
git worktree add ../ios-nord-C -b codex/sweetgles-bundle codex/eagl-shim
cd ../ios-nord-C
ln -s /home/tadej/ios-nord/build build
ln -s /home/tadej/ios-nord/tooling/opt tooling/opt
```

**Work only in:** `tooling/gpu/sweetgles/` (new). Do **not** edit `tooling/gpu/sweeteagl/`;
another session is changing `sweeteagl.c`. If you need a change there, describe it in your
report instead.

## Why

Kernel patch 0129, booted with `sweetgles=1`, makes the phone's `IOAcceleratorES` service publish
`IOGLESBundleName = "SweetGLES"`. This is verified on the phone, and backboardd survives with the
bundle absent. When any process (backboardd/QuartzCore first of all) calls
`-[EAGLContext initWithAPI:properties:]`, Apple's libGFXShared then `dlopen`s
`/System/Library/Extensions/SweetGLES.bundle/SweetGLES`.

That `dlopen` is our way into backboardd: no `DYLD_INSERT_LIBRARIES`, no plist edits.

The bundle's job is simple: when loaded, install SweetEAGL (`tooling/gpu/sweeteagl/`, already
working on the phone; `eagltest` 10/10). SweetEAGL then replaces `EAGLContext`'s methods, so
QuartzCore's **retry** gets a Mesa context.

## The plugin ABI as observed

From `~/.hermes/cache/scratch/lane-2/out/gfxs.dis`, libGFXShared `_gfxInitializeLibrary`,
0x1d3f6e8c4–0x1d3f6e9c8; read it yourself:

1. `dlopen(path, 5 /* RTLD_LAZY|RTLD_LOCAL */)`, then `dlsym("gldInitializeLibrary")`. If either
   fails, the bundle is skipped and `dlclose`d.
2. `gldInitializeLibrary(x0, x1, w2, x3, x4, x5)` is called with 6 arguments (globals, flags, three
   callbacks, a context). **Its return value is ignored.**
3. `dlsym("gldGetVersion")`, then `gldGetVersion(&a, &b, &c, &d)` with four `uint32_t *`. If it
   returns 0, or the values fail a handshake (`d & 0xffff00ff == 0`, `a == 4`, `b == 1`,
   `c == 0x10`, …), libGFXShared calls `_gfxPluginDisconnect`. **It may `dlclose` us.**

We cannot honestly implement Apple's GLD driver interface, so the plan is:
- `gldInitializeLibrary` installs SweetEAGL and returns 0.
- `gldGetVersion` returns 0, which deliberately fails the handshake, so Apple's renderer search
  ends without a plugin.
- Apple's in-flight `initWithAPI:3` then returns nil (expected; **UNVERIFIED**).
- QuartzCore retries `initWithAPI:2` (E §1 step 4), and the retry runs *our* replaced method.
  Task B makes it report API 3.

So the code that must survive a `dlclose` of the bundle is SweetEAGL itself.

## Deliverables (`tooling/gpu/sweetgles/`)

1. **`sweetgles.c` → `SweetGLES` (Mach-O dylib, the bundle executable)**
   - A constructor **and** `gldInitializeLibrary` both call one idempotent `install()`. It
     `dlopen`s `/System/Library/Extensions/SweetGLES.bundle/SweetEAGL.dylib` with
     `RTLD_NOW | RTLD_GLOBAL | RTLD_NODELETE`, calls its exported `sweeteagl_install()` and logs
     the result.
   - Explain in a comment why RTLD_NODELETE: our IMPs must outlive the bundle's `dlclose`.
   - Also pin itself: `dlopen(own path, RTLD_NOLOAD | RTLD_NODELETE)`.
   - `gldGetVersion` returns 0 and leaves the outputs zeroed.
   - Export exactly `_gldInitializeLibrary` and `_gldGetVersion`.
   - Log to `/private/var/root/gpu/sweetgles.log` (`O_APPEND`, at most 50 lines per process):
     the process name, each entry point, and install success or failure.
   - It must **never** crash or abort its host process. Every failure path returns quietly.
   - Build flags as in `tooling/gpu/sweeteagl/build.sh` (sysroot, `-Wl,-adhoc_codesign`),
     plus `-dynamiclib -install_name /System/Library/Extensions/SweetGLES.bundle/SweetGLES`.
     No `@rpath`/`@loader_path`: dyld refuses `@` paths on this phone.

2. **`Info.plist`**: XML, with `CFBundleExecutable` SweetGLES, `CFBundleIdentifier`
   com.sweet.sweetgles, `CFBundlePackageType` BNDL, `CFBundleName`, `CFBundleVersion` 1.0,
   `CFBundleSupportedPlatforms` iPhoneOS. Check that it parses with Python's `plistlib`.

3. **`package.sh`** assembles `build/phone/SweetGLES.bundle/` from:
   - `SweetGLES` (built here);
   - `SweetEAGL.dylib` (from `tooling/gpu/sweeteagl/build.sh` output);
   - `libOSMesa.8.dylib` (from `build/gpu/mesa-build-es/...` if it exists, else `build/gpu/mesa-build/...`);
   - `Info.plist`.

   It also prints sha256s and writes `build/phone/SweetGLES.bundle.sha256`. SweetEAGL already
   looks for `/System/Library/Extensions/SweetGLES.bundle/libOSMesa.8.dylib` first, so verify
   that path string is in the binary.

4. **`install-cmds.txt` and `undo-cmds.txt`**: literal commands for the main agent, **not run by
   you**.
   - **Install:**
     1. Make `/` writable. Check how other repo tooling does it: grep `tooling/` and `docs/` for
        `mount -uw` and for `/System/Library/Extensions`, and cite what you find. Don't invent.
     2. `mkdir` the bundle directory and copy the 4 files in.
     3. Set `chown root:wheel`, `0755` on the directory, `0644` on the files.
     4. Verify with `ls -l` and `shasum -a 256` against the `.sha256` file.
   - **Undo:** `rm -rf` the bundle, plus: "or boot without `sweetgles=1`".
   - Then the stage-1 test sequence:
     1. Run a throwaway process that creates an `EAGLContext` **without** preloading SweetEAGL:
        `eagltest --via-bundle` (deliverable 5).
     2. Only after that passes, `killall backboardd`, then what to watch in `sweetgles.log`,
        `sweeteagl.log` and the kernel log.

5. **`bundletest.c` → `bundletest`**: a stage-1 check that goes through **only** Apple's path.
   1. `dlopen` OpenGLES; do not `dlopen` our libraries.
   2. Call `[[EAGLContext alloc] initWithAPI:3 properties:{Accelerated, ClientRetainRelease}]`
      and print whether it is nil.
   3. Retry with API 2, then API 3 again, as QuartzCore does.
   4. Print whether `SweetEAGL.dylib` is now loaded (`dlopen` with `RTLD_NOLOAD`), and each
      context's `API`.
   5. Then run the same clear-to-red IOSurface check as `tooling/gpu/sweeteagl/eagltest.c`
      through the table. Reuse its code by copying the minimal parts; don't modify eagltest.
   6. Print `PASS`/`FAIL` per step.

6. **`check.sh`** (host-only, exits 0):
   - Everything builds with zero warnings and is signed, `platform ios`, `minos 16.0`.
   - No `@` paths.
   - `SweetGLES` exports exactly the two `gld*` symbols (plus nothing unexpected; list them).
   - `Info.plist` parses.
   - `package.sh` produces all 4 files.

7. **`README.md`** covers:
   - the load sequence above, with the uncertain steps marked **UNVERIFIED**;
   - what the main agent should look for on the phone;
   - failure modes and what each would look like (bundle not loaded, handshake path crashes,
     `initWithAPI:3` not nil, QuartzCore not retrying).

## Rules

- No Apple SDK, headers or code. Never touch `xnu-avicii/`, `avicii/`, the phone, or any git
  remote. No pushes. Commit only on `codex/sweetgles-bundle`.
- Every claim about Apple's binaries must cite an address in the `.dis` files.

## Done =

`tooling/gpu/sweetgles/check.sh` exits 0 and everything is committed. Report:
1. the commit hash;
2. `check.sh` output;
3. anything in the ABI reading above that you found to be wrong;
4. any change SweetEAGL itself needs.
