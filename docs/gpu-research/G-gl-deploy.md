# G — getting the GL userland into backboardd on this root

Round-3 lane 5. Deliverable: how the Mesa-for-iOS dylib and the EAGL shim (lanes 2–3) actually
get loaded into the window server on *this* phone. Nothing here was run on the phone; every
phone step is a command for the main agent. Host-side facts were read from the built root
image with `tooling/opt/fstool` (offline, no mount) and from the DMG-free copies in
`~/.hermes/cache/scratch/lane-5-deploy/`, cited below as `scratch/…`.

## Summary

1. **Recommended: route (c).** Publish `IOGLESBundleName = "SweetGLES"` (+2 companions) on
   `IOAcceleratorES` and put the shim at `/System/Library/Extensions/SweetGLES.bundle/SweetGLES`.
   `libGFXShared` dlopens exactly that path in any process making an `EAGLContext`, backboardd
   included — no launchd edit, no `DYLD_*`, no cache work. Same as the sweet and raphael forks.
2. **No root rebuild and no reflash:** root is rw (`tooling/71-phone-image.sh:43`), sshd is root
   over USB ECM, `/private/var` is on the root — scp'd files persist. Only the kernel patch needs
   CI, and it is gated by boot-arg `sweetgles`, so rollback is a reboot without the flag.
3. **Ad-hoc signing suffices; no trustcache entry exists to add.** `CS_SIGNED` comes from `0036:23`,
   `CS_PLATFORM_BINARY` from `0035:252-254`; `CS_REQUIRE_LV` is never set and `F_CHECK_LV` has no
   MAC hook, so library validation never runs. Trust caches are off outright (`0015`).
4. **Two traps:** `OpenGLES.framework`'s binary is **not a file** here (cache-only), so shadowing
   needs an env override; and launchd **drops `DYLD_INSERT_LIBRARIES`** (allow-list
   `LD_LIBRARY_PATH`/`DYLD_PRINT_*`) while dyld prunes it again unless AMFI answers syscall `0x5a`
   — which our stub does not implement. Route (a) needs one more kernel patch plus a re-exec shim.
5. Worst case is a backboardd crash-loop: **no panic** (no `_PanicOnCrash`), launchd throttles the
   respawns, sshd and USB stay up — phone reachable, no reflash, no fastboot (details §7).

## 1. How this root is built, updated, and where a dylib can live

The root is host-built and written once, then modified live:

* `tooling/31-mkiosroot.sh` makes an empty 16 GiB HFSX volume; `tooling/33-populate-root.sh`
  fills it from the three DMGs (`docs/ROOTFS_READY.md:82-100`; 144 341 files, 11.3 GB,
  `ROOTFS_READY.md:14`; ~5.0 GiB free afterwards, `:31-33`). It is `dd`'ed to `sda16`
  (= `userdata`) from recovery (`docs/IMAGE_PROVENANCE.md:584`).
* `tooling/73-root-add-ssh.sh` is the model for an *additive* root change: stage into a
  directory, then `fstool create` / offline replace / owner+mode in three phases, journal
  and `fsck` handling included (`73-root-add-ssh.sh:107-199`). It put Procursus into
  `/private/var/jb` and added the `com.openssh.sshd` job **into the launchd job cache**, keyed
  `/System/Library/LaunchDaemons/com.openssh.sshd.plist` (`:155-171`).
* On the phone the volume is read-write: `rootrw=1` sits in the GUI cmdline
  (`tooling/71-phone-image.sh:43`), `0031-sweet-read-write-root.patch:9-16` clears
  `MNT_RDONLY`, and `0029` does not enforce root authentication. `/private/var` is on the root
  itself — "SWEET has no data volume" (`0031:9-10`).
* The shell is real: `logs/phone/live-20261115-0114-ssh.txt:189,261,371` show `exec sshd`,
  `exec sw_vers`; the session was uid 0 on 20H392 (`IMAGE_PROVENANCE.md:585`).

So a dylib has three plausible homes, and two of them need no image work at all:

| path | put there by | survives reboot | who finds it |
|---|---|---|---|
| `/System/Library/Extensions/SweetGLES.bundle/` | `scp` over ssh (root, rw) | yes (on the root) | `libGFXShared`, by absolute path (§3) |
| `/private/var/jb/usr/lib/` | `scp` | yes | `DYLD_INSERT_LIBRARIES` target, or an explicit `dlopen` |
| `/usr/lib/` | `scp` | yes | link-time install name |

`/var/jb/usr/lib` is where the previous port kept its injected dylib
(`docs/anonbeat1-NOTES.md:1325`: `cicpu.dylib` at `/var/jb/usr/lib`). Size is not a problem:
lane C expects ~10–15 MiB for the OSMesa artifact (`C-mesa-darwin-build.md:515`) against ~5 GiB
free; a permanent image change would be a `73`-style script plus a `fsck` gate, not a rebuild.

## 2. What our code-signing patches actually allow

Citations of the form `NNNN:LINE` are `xnu-avicii/patches/NNNN-*.patch:LINE`; bare paths under `bsd/`, `security/`, `config/`, `iokit/` are in the build tree `~/xnu-8796.141.3` and are labelled `inferred` where the repo's patches do not carry the same code.

Read `0025`, `0035`, `0036`, `0015`, `0104` — the whole of it:

* **Nothing can be required from the entitlement side.** The stub answers every query with
  `KERN_DENIED` and every copy with `KERN_NOT_FOUND` (`0025:112-158`); `0035` only parses an XML
  blob a signature actually carries, and an ad-hoc signature carries none — so our dylibs end up
  with no entitlements and nothing asks for them.
* **A signature the kernel validated is marked `CS_SIGNED`** (`0036:23`) and, on the root
  filesystem, `CS_PLATFORM_BINARY` (`0035:252-254`). `0104:29` is the only consumer: an exec is
  taken past the macOS platform check when `CS_SIGNED` is set. That is exactly what an
  `-adhoc_codesign` dylib gets after its page hashes check out (lane C produced such a file:
  CD `0x20400`, sha256, `C-mesa-darwin-build.md:558`). Unsigned code still dies at exec
  (`docs/AMFI_LAUNCHD.md:137-143`, run 5) — an ad-hoc signature is therefore *required*, not
  optional.
* **Library validation never runs.** Our MAC policy registers only
  `mpo_vnode_check_signature` (`0035:261-263`); `mpo_file_check_library_validation` — which
  answers dyld's `fcntl(F_CHECK_LV)` (`bsd/kern/kern_descrip.c:4181` (build tree, inferred),
  `security/mac_file.c:154-161` (build tree, inferred)) — is NULL, so the check is a no-op, and
  `CS_REQUIRE_LV` is never ORed into a blob. `cs_library_val_enable` also defaults to 0 because
  `CONFIG_ENFORCE_LIBRARY_VALIDATION` is not in any machine config
  (`bsd/kern/kern_cs.c:102-105` (build tree, inferred), `config/MASTER.arm64.MacOSX` — *inferred,
  build-tree config, not the repo's*). Same conclusion the previous port reached: "No CS_REQUIRE_LV
  in the patches, so an ad-hoc dylib loads" (`docs/anonbeat1-NOTES.md:1316`).
* **No team ID, no trustcache.** Trust caches are switched off at init when Image4/AMFI kexts
  are absent (`0015:15-20`) and every query path returns early (`0015:30-35,44-48,56-60,70-77,
  85-89`); `.TrustCache` stays at interface version 0 (`0025:170`). A cdhash cannot be added to
  a cache that does not exist — **no trustcache entry is needed or possible**.
* **The one gap that matters: the AMFI dyld-policy syscall.** dyld asks
  `amfi_check_dyld_policy_self` (= `__mac_syscall("AMFI", 0x5a, …)`; import visible in
  `/usr/lib/dyld`, disassembled at `scratch/lane-5-deploy/dyld.dis:48274`) and, when the call
  fails, `Security::amfiFlags()` returns 0 (`dyld.dis:48276-48277`) and dyld then calls
  `pruneEnvVars` (`dyld.dis:23401-23402`). Our policy is named `"SWEET AMFI"` (`0035:266`) and
  has no `mpo_policy_syscall`, so `__mac_syscall("AMFI", …)` ends in `ENOPOLICY` and **every
  `DYLD_*` variable is discarded**. This is the kernel-side half of route (a) (§4).

**Verdict:** ad-hoc signing is enough for a dylib to be mapped and executed here, provided it is
placed on the root filesystem (so the platform-binary path applies as it does for the whole
iOS root already). No entitlement work, no cdhash work. Only route (a) needs a kernel change.

## 3. The three injection routes

### (a) `DYLD_INSERT_LIBRARIES` via the backboardd job — needs one kernel patch and one shim

Two independent blocks, both proven:

* **launchd drops it.** The job's `EnvironmentVariables` are filtered through
  `job_is_dyld_var()` — allowed are `LD_LIBRARY_PATH`, the `DYLD_PRINT_*` names, plus a
  per-job escape flag (`job+0x56c`, bit 7) — everything else gets
  `Disallowing environment variable: %s` and is not added (`scratch/lane-5-deploy/launchd.dis`
  `0x10001a720-0x10001a7b4` for the list, `0x1000092dc-0x1000092f4` for the call site and
  message;  `DYLD_INSERT_LIBRARIES` is not in the list). This is what both ports found the hard
  way: "launchd refuses to pass DYLD_ variables from a job description, which is why the kernel
  adds this one" (`refs/heliumstudio-hackios-xnu-kernel/xnu/hakios.patch:615-623`) and
  "launchd strips DYLD_* so the env alone does nothing"
  (`refs/marnov999-raphael-ios-gpu/tools/sweet-root-overlay.py:457-458`).
* **dyld prunes it** unless AMFI grants bit `0x2` (§2). Both ports had to patch that in:
  `refs/anonbeat1-ios-sweet/xnu/patches/0121-sweet-amfi-dyld-env-vars.patch` (adds the
  `mpo_policy_syscall` answering `0x5a` with flags `1<<1 | 1<<8`, and renames the policy to
  `"AMFI"`), and HackiOS's `kern.exec_inject` sysctl that appends the variable in
  `exec_extract_strings` (`hakios.patch:624-700`).

Given both patches, the remaining way in is a re-exec shim, exactly as raphael does it:
`ProgramArguments = ["/usr/libexec/sweet_shim", "/usr/libexec/backboardd"]` with
`DYLD_INSERT_LIBRARIES` set on backboardd's job as well (belt and braces), shim source
`refs/marnov999-raphael-ios-gpu/userland/sweet_shim.c:17,22,72` — `setenv` then
`execv(argv[1], &argv[1])`.

Risks: three new moving parts (kernel patch, shim binary, plist edit) on the process that owns
the screen; the shim is on the critical path of every backboardd spawn, and if it or its target
plist entry is wrong the job never starts — raphael hit exactly that with mediaserverd and lost
the GUI to the boot logo (`sweet-root-overlay.py:441-443`). It also drags Mesa into *every*
backboardd start, including the ones before the panel is up.

### (b) Shadowing `OpenGLES.framework` — the framework binary is not a file

`fstool ls build/ios16-root.img /System/Library/Frameworks/OpenGLES.framework` returns only
`CVMSPlugin*.exp`, `Info.plist`, `GLEngine.bundle/` (itself empty) and `_CodeSignature/` — **no
`OpenGLES` executable**. The image lives in the dyld cache
(`/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64` + 42 subcaches + `.symbols`,
2710 images, `docs/CACHE_TRIM.md:133`), and lane A extracted it from there. The same holds for
`GLEngine.bundle` (empty) and `AppleMetalGLRenderer.bundle` (only `default.metallib`).

Consequences: a file dropped at the framework path is ignored, because dyld resolves the path to
the cache image. Overriding requires `DYLD_LIBRARY_PATH`/`DYLD_FRAMEWORK_PATH` (*inferred*: dyld
does allow a path override of a cache image, but it needs the environment, i.e. route (a) again,
plus `DYLD_*` pruning applies). And you would then own the whole public EAGL/GLES ABI, while the
plugin route only owns the driver interface `gldInitializeLibrary`. Rebuilding/patching the dyld
cache is the other way, and `CACHE_TRIM.md` shows the cost.

Verdict: not a first move; fine as a later, deliberate step.

### (c) A `gld*` plugin bundle named by `IOGLESBundleName` — recommended

`libGFXShared` (`_gfxInitializeLibrary`) enumerates `IOAcceleratorES`, reads `IOGLESBundleName`
(string) and `IOGLESDefaultUseMetal` off the service
(`scratch/lane-5-deploy/gfx.dis:0x1d3f6e544-0x1d3f6e584`), builds
`"/System/Library/Extensions/%s.bundle"` (`0x1d3f6e5f8`) and then `"%s/%s"` (`0x1d3f6e614`) —
i.e. `/System/Library/Extensions/SweetGLES.bundle/SweetGLES` — and later
`dlopen(path, RTLD_LAZY(5))` (`0x1d3f6e8cc`), `dlsym("gldInitializeLibrary")` (`0x1d3f6e8d8`) and
`dlsym("gldGetVersion")`. A bundle that fails to load, or lacks the symbol, is silently skipped
(`0x1d3f6e964`) — it fails soft, it does not crash the caller.

Properties on the accel service, as sweet and raphael set them
(`refs/marnov999-ios26-sweet/xnu/patches/0100-sweet-new-files.patch:33666-33668`; comment at
`:33655-33665`; `refs/marnov999-raphael-ios-gpu/xnu/patches/0112-...:946-950`), give the whole
chain: an application's own `EAGLContext` runs on our Mesa, Apple's GLES-on-Metal stays named as
the Metal renderer but is not defaulted to. "Without them EAGLContext found no renderer at all"
(`A-quartzcore-compositing.md:114-115`).

Risks: the property set is all-or-nothing — with `IOGLESBundleName` published and a *broken*
bundle, there is no renderer at all, which is worse than today's CPU path; and the same property
applies to every process, not just backboardd. But: no plist, no shim, no `DYLD_*`, no env
filtering, nothing on backboardd's spawn path except a `dlopen` that fails soft, and a
boot-arg gate makes the whole thing one reboot wide.

### Fallback: route (a), if (c) does not work

**Route (a) — `DYLD_INSERT_LIBRARIES` + re-exec shim (§3(a)) — is the fallback.** Switch when:
(1) stage 1 (§5) gives a non-nil `EAGLContext` but no frames — the property chain worked, so the
fault is below this seam, where (a) does not reach (*inferred*; check lanes 2–3 first); (2) the
properties are published and *even Apple's own* processes get no renderer — they are global (§3(c)
risks), so the properties are at fault and (a) leaves `0107`'s service alone; (3) lane 2's
`gldInitializeLibrary` contract cannot be met — the dylib goes in without `IOGLESBundleName`.

Extra work (a) needs that (c) does not, one cost each:
* the `mpo_policy_syscall` AMFI patch answering `0x5a` (`0035:261-263` registers no such hook,
  `0035:266`; §2) — one more CI kernel build; dyld then keeps `DYLD_*` for every process.
* `sweet_shim` + a `ProgramArguments` edit (`sweet_shim.c:17,22,72`) — the shim is on every
  backboardd spawn's critical path; one wrong plist entry loses the GUI to the boot logo
  (`sweet-root-overlay.py:441-443`).
* (b), shadowing the cache image, is the **last resort**: the framework binary is not a file
  (§3(b)), so it needs that same `DYLD_*` override *plus* the whole EAGL/GLES ABI.

Undo for all three: §6 item 4.

## 4. The kernel patch (recommended route), exactly

Applied on top of `0107-sweet-empty-ioacceleratores.patch` in
`iokit/Kernel/arm/SweetFramebuffer.cpp`, in `AppleCLCD::start()` where the accelerator is
already published (`0107:27-36`), between `init()` and `registerService()`:

```c
	/* QuartzCore reaches its OpenGL ES renderer through libGFXShared, which reads these
	 * off this service and dlopens /System/Library/Extensions/<name>.bundle/<name>.
	 * Published empty (0107) there is no renderer and EAGLContext initWithAPI: fails.
	 * sweetgles=0 leaves the service as 0107 has it (CPU rendering, today's state). */
	uint32_t gles = 0;
	(void)PE_parse_boot_argn("sweetgles", &gles, sizeof(gles));
	if (gles != 0) {
		accel->setProperty("IOGLESBundleName", "SweetGLES");
		accel->setProperty("IOGLESMetalBundleName", "AppleMetalGLRenderer");
		accel->setProperty("IOGLESDefaultUseMetal", kOSBooleanFalse);
	}
```

Property list, complete (there is nothing else to set for GLES; `MetalPluginName`/
`MetalPluginClassName` are only needed if a Metal device is wanted, `0107:9-12`,
`A-quartzcore-compositing.md:96-101`):

| key | type | value | why |
|---|---|---|---|
| `IOGLESBundleName` | CFString | `SweetGLES` | the bundle libGFXShared opens for the GLES rung |
| `IOGLESMetalBundleName` | CFString | `AppleMetalGLRenderer` | kept named so Metal callers still resolve a renderer |
| `IOGLESDefaultUseMetal` | CFBoolean | false | picks the `IOGLESBundleName` branch, not the Metal one |

Signing steps for every artifact (they are all ad-hoc; `tooling/opt/llvm`, no Apple tool):

```
clang -target arm64-apple-ios16.0 -fuse-ld=lld -Wl,-fixup_chains -Wl,-adhoc_codesign \
      -dynamiclib -install_name /System/Library/Extensions/SweetGLES.bundle/SweetGLES \
      -Wl,-rpath,@loader_path -o SweetGLES <shim objects> <lane 3's library flags>
```
Same flags with `-install_name …/libOSMesa.8.dylib` and the libdrm stand-in's own name (lane 3
fixes both) for the two libraries, so `@loader_path` resolves them inside the bundle
(`C-mesa-darwin-build.md:525-526`). Verify each with `llvm-objdump --macho -p`: `LC_BUILD_VERSION platform 2`, an `LC_CODE_SIGNATURE`
of CD `0x20400`, and the right `LC_ID_DYLIB` (`C-mesa-darwin-build.md:558`). The test binary in
§5 is signed the same way (it is `exec`ed, so it must carry `CS_SIGNED`, `0104:29`).

Bundle layout on the device:

```
/System/Library/Extensions/SweetGLES.bundle/         0755 root:wheel
    SweetGLES                                         0644 root:wheel   (raphael uses 0644: overlay:72)
    Info.plist    (CFBundleExecutable SweetGLES, CFBundleIdentifier com.sweet.sweetgles)  0644
    libOSMesa.8.dylib, libdrm.2.dylib                  0644 root:wheel
```

`gldInitializeLibrary`'s argument shape is lane 2's spec (`E-eagl-shim-spec.md`); it is called
with the plugin's flags and three callbacks (`gfx.dis:0x1d3f6e8e8-0x1d3f6e904`).

## 5. Rollout

Order: prove the dylib alone, prove the seam in a throwaway process, then let the properties
loose on backboardd. Each stage has a way to fail without touching the window server. (Lanes 1–3
had not written their reports yet when this was drafted — `D-ios-sysroot.md`,
`E-eagl-shim-spec.md`, `F-libdrm-darwin.md` are the inputs stage 0/1 assume.)

**Stage 0 — files only, nothing running.** scp the bundle and a test binary; set owners/modes;
run the test binary (it `dlopen`s the plugin path itself — no properties needed, so this works
on today's kernel). Pass: `gldInitializeLibrary` returns, `gldGetVersion` answers, a triangle
comes back in the readback buffer. Failure here means lanes 2–3 have work, not the deployment.

**Stage 1 — the seam in a throwaway process.** Boot the kernel with `sweetgles=1`. The test
binary now also links `OpenGLES.framework` (the stub is in lane 1's sysroot) and creates a real
`EAGLContext` (`-[EAGLContext initWithAPI:2 properties:…]`) and renders through it. This is the
exact call QuartzCore makes; it exercises the property → `libGFXShared` → our bundle chain in a
process that may crash freely. Pass: non-nil context and correct pixels; `/dev/dri/renderD128`
and `/dev/kgsl-3d0` opened by our Mesa, `SWEET` lines in the console log.

**Stage 2 — backboardd.** `killall backboardd` (launchd has `KeepAlive: true`, it comes back).
Confirm in the console log: `exec backboardd`, our shim's own log line, then frames on the
panel. Watch for `Service only ran for … Pushing respawn out by …` (that is the crash loop).

**Undo:** §6.

**Prerequisite from lane A, not yet in the kernel:** the surfaces must be GPU-addressable —
`IOSurfaceClientBindAccel` (selector `0xc`, `A-quartzcore-compositing.md:304-306`) does not exist
in `xnu-avicii/patches/` (grep: no hit). Without it the GL renderer can compose the client
mapping only if our Mesa can get the buffer's GPU address another way; expect stage 1 to draw
into a private target and stage 2 to need that binding.

## 6. Undo

1. **Cheapest, no reboot:** `mv /System/Library/Extensions/SweetGLES.bundle{,.off}` then
   `killall backboardd`. But with the properties still published there is now no renderer, so
   this only helps if the *previous* bundle was good — keep one: `cp -a` the working bundle to
   `…bundle.good` before each change and restore with `mv` instead of removing.
2. **Back to today exactly, one reboot:** reboot with `sweetgles` unset. The service is then
   empty again as in `0107`, QuartzCore keeps the CPU renderer it uses today, and no file
   matters. This is why the gate defaults to off.
3. **Full removal:** `rm -rf /System/Library/Extensions/SweetGLES.bundle` (+ the test files
   under `/private/var/jb/gpu`), and reboot without `sweetgles`. If the bundle was also baked
   into the image, one more image build is needed — which is why the bundle goes in over ssh
   first and only into `tooling/` afterwards.
4. **Route (a) undo** (if that route is taken): restore `ProgramArguments` to
   `["/usr/libexec/backboardd"]` and delete the `EnvironmentVariables` key from the job — both in
   `/System/Library/xpc/launchd.plist` (`LaunchDaemons["/System/Library/LaunchDaemons/com.apple.backboardd.plist"]`)
   and in the plist file of the same name — then `killall backboardd`. Removing just the shim
   binary makes the job unspawnable, so restore the plist *before* deleting the shim. The kernel
   patch is inert with `sweetgles`/its boot-arg off, and `sweet_amfi_mac_conf.mpc_name = "AMFI"`
   is worth keeping either way (`libsystem_trace` needs it for `OS_ACTIVITY_DT_MODE`,
   `anonbeat1-NOTES.md:511`).

## 7. What a backboardd crash-loop does to the phone

* **No panic.** The job carries `KeepAlive: true` and `RunAtLoad: true` but **no
  `_PanicOnCrash`** (job dict in `build/ios16-root.img:/System/Library/xpc/launchd.plist`;
  backboardd has none even in the stock table, and the only seven jobs that ever had one —
  `containermanagerd`, `dt.remotepairingdeviced`, `mobile.lockdown`, `mobile.usermanagerd`,
  `remoted`, `trustd`, `watchdogd` — are already renamed `_PanicOnCrasX` by
  `tooling/61-mkrd-root.sh:463-484`). A crash is a respawn, not a reboot.
* **launchd throttles it itself:** `Service only ran for %llu seconds. Pushing respawn out by
  %llu seconds.`, `service exceeded successive crash limit. launch will be throttled`,
  `_ExponentialThrottling` (`strings build/rd-root.stage/sbin/launchd`). So it degrades instead
  of spinning — but the throttle is measured in seconds and the console will be noisy.
* **The recovery channel does not depend on it.** `com.openssh.sshd` is a separate inetd job on
  port 22, and USB ECM is a kernel `ifnet` (`0113`, `IMAGE_PROVENANCE.md:583-585`). sshd keeps
  accepting, so a looping backboardd is fixed by editing files and `killall`, no reboot.
* **SpringBoard goes with it** and is relaunched too (`ThrottleInterval: 5`, its own job) — a
  second loop, harmless.
* **What it looks like:** the last frame stays or the panel goes black; there is no console text
  because `sweetfb_console=1` is refused on a GUI cmdline (`docs/STATUS.md:28-29`). A
  power-cycle reboots into the same kernel and root, so even the worst case needs no fastboot
  recovery — the bundle and properties are still there, and only the ones with the flag set bite.
* A caveat on route (a): a *missing or non-executable shim* is the same shape of failure as a
  crashing backboardd, but with no crash to attribute it to — `service is defined to be
  constantly running` plus repeated spawn failures in the log. Check the shim path and mode
  before touching the job.

## 8. Commands for the main agent

Read-only first (nothing below changes the phone until stage 0's `scp`):

```
ssh -i ~/.ssh/ios_nord_ed25519 root@192.168.7.2 'mount | grep " on / "'
ssh -i ~/.ssh/ios_nord_ed25519 root@192.168.7.2 'df -k / /private/var'
ssh -i ~/.ssh/ios_nord_ed25519 root@192.168.7.2 'ls -ld /System/Library/Extensions /private/var/jb/usr/lib'
ssh -i ~/.ssh/ios_nord_ed25519 root@192.168.7.2 'plutil -p /System/Library/LaunchDaemons/com.apple.backboardd.plist'
ssh -i ~/.ssh/ios_nord_ed25519 root@192.168.7.2 'ps -o pid,comm -p $(pgrep -x backboardd)'
ssh -i ~/.ssh/ios_nord_ed25519 root@192.168.7.2 'ioreg -c IOAcceleratorES -r -d 1'
```

Stage 0/1 (write; `mkdir` + `scp` + modes):

```
ssh -i ~/.ssh/ios_nord_ed25519 root@192.168.7.2 mkdir -p /private/var/jb/gpu
scp -i ~/.ssh/ios_nord_ed25519 <out>/gltest root@192.168.7.2:/private/var/jb/gpu/
ssh -i ~/.ssh/ios_nord_ed25519 root@192.168.7.2 chmod 755 /private/var/jb/gpu/gltest
ssh -i ~/.ssh/ios_nord_ed25519 root@192.168.7.2 mkdir -p /System/Library/Extensions/SweetGLES.bundle
scp -i ~/.ssh/ios_nord_ed25519 <out>/SweetGLES.bundle/{SweetGLES,Info.plist,libOSMesa.8.dylib,libdrm.2.dylib} \
    root@192.168.7.2:/System/Library/Extensions/SweetGLES.bundle/
ssh -i ~/.ssh/ios_nord_ed25519 root@192.168.7.2 chown -R root:wheel /System/Library/Extensions/SweetGLES.bundle
ssh -i ~/.ssh/ios_nord_ed25519 root@192.168.7.2 chmod 644 /System/Library/Extensions/SweetGLES.bundle/*
ssh -i ~/.ssh/ios_nord_ed25519 root@192.168.7.2 chmod 755 /System/Library/Extensions/SweetGLES.bundle
ssh -i ~/.ssh/ios_nord_ed25519 root@192.168.7.2 /private/var/jb/gpu/gltest --plugin-only
```

Stage 2 (after a `sweetgles=1` boot):

```
ssh -i ~/.ssh/ios_nord_ed25519 root@192.168.7.2 /private/var/jb/gpu/gltest --eagl
ssh -i ~/.ssh/ios_nord_ed25519 root@192.168.7.2 'pgrep -x backboardd'          # old pid
ssh -i ~/.ssh/ios_nord_ed25519 root@192.168.7.2 killall backboardd
ssh -i ~/.ssh/ios_nord_ed25519 root@192.168.7.2 'sleep 15; pgrep -x backboardd'   # new pid = it respawned
```

Console log (host side, already the project's channel): `tooling/72-usbnet.sh logs/phone/live-NAME.txt`,
then grep it for `exec backboardd`, for the shim's line, and for `Pushing respawn out by`.
Note `iOSROOT.md`/`STATUS` warnings do not apply here — the root is written live, never
re-flashed, and `sweetgles` lives only on the fastboot cmdline.

## Open questions

* **`IOSurfaceClientBindAccel`** is missing (no hit in `xnu-avicii/patches/`). Does the GL
  renderer work at all against `SweetSurface`'s client mapping without it, or is it a hard
  prerequisite for stage 2? Lane A §2 has the shape; nobody has written it.
* **Does a broken bundle break more than backboardd?** The property applies to every process, so
  `SpringBoard`, `Camera`, any app that makes a context, all see it. Safe-fail is at dlopen/dlsym
  level only; a shim that loads and then returns garbage from `gldInitializeLibrary` may take
  the whole CA renderer down (raphael: "a process handed a half-made device aborts rather than
  falls back", `refs/marnov999-ios26-sweet/xnu/patches/0100-sweet-new-files.patch:33633`).
* **`IOGLESDefaultUseMetal` when `AppleMetalGLRenderer` cannot work**: it is a cache image, so
  the Metal branch can only ever be Apple's — fine for us, but it means the Metal renderer
  bundle cannot be replaced without the cache work of §3(b).
* **Is `setProperty` before `registerService()` enough for a nub attached to `AppleCLCD`?**
  Inferred from `0100`/`0112`, not tried on avicii.
* **The per-job escape flag at `job+0x56c` bit 7** — if it is `WaitForDebugger`/debugged, a job
  could get `DYLD_*` through launchd without a shim (inferred; the key was not identified).
