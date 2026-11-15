# SweetGLES bundle

Host-built GLD entry seam for the `sweetgles=1` kernel's `IOGLESBundleName=SweetGLES`.
Only `tooling/gpu/sweetgles/` is changed. No phone commands were run. No SDK, Apple
headers, or Apple implementation code is used; declarations and test fragments are
project code, with Khronos GL headers from Mesa and the existing source-built sysroot.

Run `tooling/gpu/sweetgles/check.sh` from this worktree. It packages the already-built
`build/phone/gpu/SweetEAGL.dylib`; it never invokes the parallel session's build script.
`package.sh` prefers `mesa-build-es/src/gallium/targets/osmesa/libOSMesa.8.dylib`,
falling back to the same path under `mesa-build`. It changes the **packaged copy's**
Mesa install ID to `/System/Library/Extensions/SweetGLES.bundle/libOSMesa.8.dylib` using
LLVM's install-name tool. Source artifacts are untouched. This also regenerates the
ad-hoc signature; `verify.py` verifies its CodeDirectory SHA256 page hashes.

Outputs are `build/phone/SweetGLES.bundle/` (exactly four files), its sibling
`SweetGLES.bundle.sha256`, and `build/phone/sweetgles/bundletest`. Build uses
`-Wall -Wextra -Werror`, arm64 iOS 16.0, and ad-hoc signing. Checks cover all three
packaged Mach-O files and bundletest, exported symbols, install names, plist values,
and manifest hashes. Host fakes exercise the real bundle constructor and entry points,
including reentry, failures, output zeroing, and the log cap. Host checks cannot prove
in-process dyld/ObjC behavior or rendering on the phone.

## Binary evidence and load sequence

Address references below are to these local, uncommitted disassemblies of 20H392:

- `gfxs.dis`: `/home/tadej/.hermes/cache/scratch/lane-2/out/gfxs.dis`
- `opengles.dis`: `/home/tadej/.hermes/cache/scratch/lane-2/out/opengles.dis`
- `qc.dis`: `/home/tadej/.hermes/cache/scratch/lane-a-quartzcore/out/qc.dis`

1. QuartzCore supplies the accelerated/client-retain-release properties, requests
   `initWithAPI:3 properties:`, and falls back to API 2 on nil (`qc.dis`
   `0x1882eb068–0x1882eb0f8`). It subsequently requires `[ctx API] == 3`
   (`0x1882eb118–0x1882eb124`). **UNVERIFIED on this bundle:** the first in-flight
   initializer returns nil, the fallback enters SweetEAGL, and the compositor accepts it.
2. libGFXShared constructs `/System/Library/Extensions/%s.bundle` then `%s/%s`
   (`gfxs.dis` `0x1d3f6e5f8–0x1d3f6e618`) and calls `dlopen(path, 5)`
   (`0x1d3f6e8c4–0x1d3f6e8cc`). This is the entry route we intend to use.
3. Our constructor calls one guarded `install()`. It retains a self handle opened with
   `RTLD_NOLOAD|RTLD_NODELETE`, then retains SweetEAGL from the absolute bundle path with
   `RTLD_NOW|RTLD_GLOBAL|RTLD_NODELETE`, and calls `sweeteagl_install()`. Handles are never
   closed. Both the original constructor attempt and the later GLD call use the same
   nonblocking atomic state guard. Success and failure are terminal for that process;
   recursive/concurrent entries return quietly instead of waiting inside a loader callback.
4. libGFXShared resolves `gldInitializeLibrary` and sets `x0,x1,w2,x3,x4,x5` before calling
   it (`gfxs.dis` `0x1d3f6e8d8–0x1d3f6e904`). Its return is ignored
   (`0x1d3f6e908`). Our entry calls the same `install()` and returns zero.
5. libGFXShared calls `gldGetVersion` with four 32-bit output addresses
   (`gfxs.dis` `0x1d3f6e934–0x1d3f6e944`). Zero return branches to disconnect
   (`0x1d3f6e948–0x1d3f6e95c`). We zero every non-NULL output and deliberately return zero.
   For a nonzero return, acceptance first requires `(d & 0xffff00ff) == 0`, then
   `a == 4, b == 1, c == 0x10` (`0x1d3f6e94c–0x1d3f6e9cc`). We never claim that ABI.
6. Disconnect optionally resolves/calls `gldTerminateLibrary`, then **does** `dlclose`
   (`gfxs.dis` `0x1d3f6ed30–0x1d3f6ed48`). We intentionally export no terminate entry.
   **UNVERIFIED on phone:** pinning preserves our state and the installed SweetEAGL IMPs
   through this cleanup. Retaining the SweetEAGL handle is additional lifetime protection.

Corrections to the task's ABI narrative: `w2` is the accumulated device mask (`gfxs.dis`
`0x1d3f6e678–0x1d3f6e688`, `0x1d3f6e8f4`). `x5` is **flags rather than a context pointer**:
`x19` receives the caller's `x6` at `0x1d3f6e310`, its low bits are inspected/combined with
linked-OS flags at `0x1d3f6e3e0–0x1d3f6e3ec`, and it is forwarded at `0x1d3f6e900`.
Only two callbacks (`x3/x4`) are directly identifiable here; `x1` is an opaque pass-through
from the caller (`0x1d3f6e33c`, `0x1d3f6e8f0`), so a third callback is not established or
ruled out. `x0` points at service entries read as 32-bit values (`0x1d3f6e458–0x1d3f6e460`).
Disconnect's `dlclose` is definite when a handle exists, rather than merely possible
(`0x1d3f6ed28–0x1d3f6ed48`). A third API-3 request is a **diagnostic addition** in bundletest;
QuartzCore's observed sequence is API 3 then API 2 (`qc.dis` `0x1882eb0a4–0x1882eb0f8`).
A zero masked version field is an acceptance condition, not a rejection condition
(`gfxs.dis` `0x1d3f6e950–0x1d3f6e954`). The task's zero-return rejection plan is correct.

## Stage-1 test

`bundletest [--via-bundle]` loads only Apple OpenGLES and libobjc normally. Its only
SweetEAGL opens use `RTLD_NOLOAD`; it neither opens SweetGLES nor opens Mesa nor calls
`sweeteagl_install`. It rejects preload/Mesa/CPU override environments and a shim already
loaded before the first context request. Run it in a fresh throwaway process.

It prints nil/non-nil and the reported API for requests 3, 2, 3. For this proposed route,
PASS requires initial nil, non-nil retries reporting API 3, and SweetEAGL resident afterward.
It closes the NOLOAD probe handle before using the fallback context. It then checks all
required slots, sets the current context, makes a 64x64 BGRA IOSurface, attaches it to a
texture/FBO, checks completeness through the table, clears red, finishes, and checks the
center bytes `00 00 ff ff` and `GL_NO_ERROR`, then tears down. Output is unbuffered so a
crash preserves the last completed step. The install transcript stages this same executable
as `sweetgles-stage/eagltest`, satisfying the task's `eagltest --via-bundle` spelling without
overwriting the existing direct-injection eagltest.

The context-first table ABI is visible in `opengles.dis` `0x1d3f4e058–0x1d3f4e064`;
`getMacroContextPrivate` returns `_private+0x20` at `0x1d3f5211c`. Slot evidence for
all GL operations copied from the project's eagltest follows; load offsets in the stubs
are 0x20 larger because they are relative to `_private`.

| Operation | Table slot | `opengles.dis` function address |
|---|---:|---:|
| GenTextures | 0x318 | 0x1d3f4d50c |
| BindTexture | 0x30 | 0x1d3f4cefc |
| TexParameteri | 0x988 | 0x1d3f4dda4 |
| GenFramebuffers | 0x1518 | 0x1d3f4e270 |
| BindFramebuffer | 0x1508 | 0x1d3f4df78 |
| FramebufferTexture2D | 0x1530 | 0x1d3f4e220 |
| CheckFramebufferStatus | 0x1520 | 0x1d3f4e04c |
| Viewport | 0xa80 | 0x1d3f4def4 |
| ClearColor | 0x68 | 0x1d3f4c9a0 |
| Clear | 0x58 | 0x1d3f4cf9c |
| Finish | 0x2d0 | 0x1d3f4d414 |
| GetError | 0x338 | 0x1d3f4d5a0 |
| DeleteFramebuffers | 0x1510 | 0x1d3f4e0f8 |
| DeleteTextures | 0x1e0 | 0x1d3f4d2b8 |

Texture/surface/FBO ordering and the attach selector are visible at `qc.dis`
`0x188407980–0x188407b30` (attach at `0x188407ac8`); EAGL init and its properties forwarding
are at `opengles.dis` `0x1d3f51270–0x1d3f513d0`. Existing project declarations for
CF/IOSurface are in `test_abi.h`, copied minimally from `sweeteagl/abi.h`.

## Install, observation, and recovery

Use the numbered transcripts in `install-cmds.txt` and `undo-cmds.txt`; **not run here**.
Search performed: `rg -n -- 'mount -uw|/System/Library/Extensions' tooling docs`.
There was **no `mount -uw` recipe** in the pre-existing tracked tooling/docs. The existing
installation transcript (`docs/gpu-research/G-gl-deploy.md:338–357`) inspects `mount`, `df`,
and the Extensions directory, then uses root SSH/scp/chown/chmod. We cite and reuse that
route. If root is read-only, stop: no verified remount command is provided. The main agent
must record package hashes in `docs/IMAGE_PROVENANCE.md` before executing writes and must
use a `sweetgles=1` boot already arranged by the main agent. No kernel/boot procedure is
part of this task.

Ensure `/private/var/root/gpu` exists before testing. `sweetgles.log` contains process name,
PID, constructor/GLD entries, self-pin status, and the integer installer result, capped at
50 lines per process with O_APPEND. Logging errors never fail the host. The wrapper handles
its own loader/symbol failures quietly and contains no assert/abort; an external library's
constructor or installer can still fault or deadlock. Their safety is **UNVERIFIED** on
this entry path. The cap and nonblocking guard protect our own code only.

After the throwaway test passes, restart backboardd with the separately gated command.
Watch its PID's constructor, self-pin success, installer success, `gldInitializeLibrary`,
and deliberate `gldGetVersion` rejection in `sweetgles.log`; look for SweetEAGL installation,
context creation/API reporting, and failures in `sweeteagl.log`. Capture the project's kernel
log via `tooling/72-usbnet.sh` and watch `exec backboardd`, crashes, panic, or repeated
respawn messages. Do not equate our loader success with a working compositor.

| Failure | Expected observation / next action |
|---|---|
| Bundle never loaded | Fresh test has initial nil and failed retries, no SweetGLES entries; check registry property, four paths, ownership, signed artifacts, hashes, log-directory access. Missing log alone is inconclusive. |
| Dependency/install failure | Constructor then `install FAIL` or pin failure; check SweetEAGL/Mesa package and its own log. A failed install stays failed until a fresh process. |
| Handshake/unwind fault | Test dies after constructor/GLD log; correlate the last line and crash address with `gfxs.dis` `0x1d3f6e948–0x1d3f6e970`, disconnect `0x1d3f6ed18–0x1d3f6ed58`, and OpenGLES init cleanup `0x1d3f5161c`. Do not restart backboardd. |
| Initial API 3 is non-nil | Explicit FAIL with observed API; it contradicts the planned first-return prediction. Investigate the actual initialization path before backboardd. |
| Retry returns nil or API 2 | Explicit retry FAIL; inspect SweetEAGL install and its API-reporting change below. |
| QuartzCore never reaches retry | Throwaway test may pass while backboardd logs no new context creation. Confirm first nil and the conditional branch at `qc.dis` `0x1882eb0b8`, then debug the live caller; successful test alone cannot prove that branch ran. |
| Surface check fails | Attachment, completeness, GL error, or red-byte FAIL; investigate SweetEAGL/Mesa, leave backboardd alone. |

SweetEAGL needs the task-B behavior: an API-2 fallback context must report API 3, backed by
an actual ES3-capable Mesa context, for the observed QuartzCore gate (`qc.dis`
`0x1882eb118–0x1882eb124`). This work does not edit it. Its exported installer and absolute
bundle Mesa lookup already satisfy this bundle's interface. It must also tolerate installation
while an original Apple initializer is still in flight; the original cleanup releases `self`
(`opengles.dis` `0x1d3f5161c`). No additional concrete SweetEAGL change for that cleanup has
been established by host checks; validate with the throwaway process first.

Undo removes the bundle for future loads; it cannot reverse IMP replacement inside already
running processes. Alternatively boot without `sweetgles=1` (main agent's existing boot
workflow). Do not assume removal alone unloads deliberately pinned libraries.
