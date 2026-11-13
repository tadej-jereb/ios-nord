# AMFI, the launchd exec and the `CS_KILLED` wall

The skeleton ramdisk boots, HFS mounts it as the root, `load_init_program` opens
`/sbin/launchd` and the kernel kills it before dyld runs:

```
load_init_program: attempting to load /sbin/launchd
SWEET EARLY PANIC: unexpected SIGKILL of launchd (CS_KILLED) with reason -- namespace 9 code 0xe description none
```

The binary is not the problem: `/sbin/launchd` is the pinned iOS 16.7.16 one,
ad-hoc signed, 127/127 page hashes valid, 22 entitlements, `CS_ADHOC` set. This
page names the kernel code that decides, why it decides that way on our build,
and the patch that settles it (`0104-sweet-ios-exec-platform.patch`).

## 1. The exact path

| step | site | what it is |
|---|---|---|
| 1 | `bsd/kern/kern_exec.c:7391` | `process_signature()`: `if (proc_platform(p) == PLATFORM_IOS)`, inside `#if XNU_TARGET_OS_OSX` |
| 2 | `bsd/kern/kern_exec.c:7392-7406` | `psa == NULL` (every `execve()`, `load_init_program` included, has no `posix_spawn` attr), so the only accepted proof is the `com.apple.private.security.no-sandbox` entitlement or the `unentitled_ios_sim_launch` boot-arg |
| 3 | `bsd/kern/kern_exec.c:7407-7413` | **the decision**: `os_reason_create(OS_REASON_EXEC, EXEC_EXIT_REASON_WRONG_PLATFORM)` = namespace 9, code 0xe, `error = EACCES`, `goto done` |
| 4 | `bsd/kern/kern_exec.c:7560-7565` | `!unexpected_failure` → `proc_csflags_set(p, CS_KILLED)` then `psignal_with_reason(p, SIGKILL, …)` |
| 5 | `bsd/kern/kern_sig.c:2063-2072` | `signum == SIGKILL && p == initproc` → `panic_plain("unexpected SIGKILL of %s %s with reason -- namespace %d code 0x%llx …")` |

Namespace 9 is `OS_REASON_EXEC` (`bsd/sys/reason.h:96`), code 0xe is
`EXEC_EXIT_REASON_WRONG_PLATFORM` (`bsd/sys/reason.h:257`): the kernel considers
launchd an alien-platform binary, not a badly signed one. Page hashes and the
cdhash were already through.

## 2. Why it fires on this build

`XNU_TARGET_OS_OSX` comes from a macOS deployment target, not from the board.
The series is built by `.github/workflows/xnu.yml` on a macOS runner against
`xnu-8796.141.3` (macOS 13.5), so `makedefs/MakeInc.def:70` emits
`-DXNU_TARGET_OS_OSX` for the whole kernel. An iPhoneOS-config kernel has no
such check; ours is a macOS-governed kernel carrying an iOS userland.

The escape hatch in step 2 does not fire for this userland, for two reasons:

* `com.apple.private.security.no-sandbox` is a *simulator* affordance the iOS
  binary simply does not carry. The staged launchd has 22 `com.apple.private.*`
  entitlements — among them `com.apple.private.amfi.can-allow-non-platform` —
  and zero occurrences of `no-sandbox` in `build/rd-root.stage/sbin/launchd`.
* `unentitled_ios_sim_launch=1` works (`/tmp/amfi-ctl`, section 4) but is an
  extra boot-arg on every run, and leaves a missing entitlement as the nominal
  reason an iOS init can start.

Entitlements themselves are not the blocker: `0035` parses the signed XML
entitlements into an `OSDictionary` and answers `IOVnodeHasEntitlement()` from it.
The binary is simply classified as the wrong platform, and the only documented
way past that check is a key iOS does not ship.

Which of our patches is in the chain, in order: `0029` downgrades the root
authentication panic, without which `bsd_init.c` stops long before any exec;
`0035`/`0036` give the kernel an AMFI answer at all and set `CS_SIGNED` /
`CS_PLATFORM_BINARY` on the root volume, so the blob that reaches this check is
valid — but `CS_PLATFORM_BINARY` never reaches `imgp->ip_csflags`, the exec
copies only the flags in the mask at `bsd/kern/kern_exec.c:1388-1398`, and the
platform question is asked from `proc_platform()`, i.e. from the Mach-O's own
platform field. `0042` is the patch that put the `exec %s` line beside the
refusal. No patch of ours *introduces* the check — it is stock XNU policy the
macOS target brings along — but nothing in our stand-in can satisfy it, and that
is the seam the fix belongs in.

## 3. The fix — `0104-sweet-ios-exec-platform.patch`

`bsd/kern/kern_exec.c`, `#if defined(ARM64_BOARD_CONFIG_SWEET)`:

* new `sweet_ios_exec_platform_ok()` next to `process_signature()`, returning
  true only when the exec is on an iOS-platform binary whose signature already
  validated through this exec (`imgp->ip_csflags & CS_SIGNED`, set after the
  page hashes checked out, `bsd/kern/kern_exec.c:1388-1398`);
* both platform branches (missing attr *and* attr naming another platform) skip
  the `EXEC_EXIT_REASON_WRONG_PLATFORM` refusal when it returns true;
* the decision is logged per exec (`SWEET: signed iOS binary, taken past the OSX
  platform check`), next to `0042`'s `exec <name>` line;
* `sweet_ios_exec_platform=0` restores the stock check exactly;
  `unentitled_ios_sim_launch=1` and the entitlement probe keep working and are
  still tried first.

Constraints held:

* **Unsigned code still dies.** `CS_SIGNED` is only set once a blob validated,
  so an unsigned or invalid image has `imgp->ip_csflags` without it and takes the
  stock `CS_KILLED` path unchanged — `sweet_ios_exec_platform=0` reproduces it
  verbatim (§4, run 3).
* **One path for phone and QEMU.** The gate is board-conditional only
  (`ARM64_BOARD_CONFIG_SWEET`), which both targets share; nothing keys on QEMU or
  on the ramdisk, and the phone boot (`unentitled_ios_sim_launch=1` today) behaves
  identically either way.
* **Every prior boot-arg still works**, and there is a new one to turn the
  behaviour off again.

Not covered on purpose: an image that *declares* a non-iOS platform while the
process platform is iOS (the `else if` branch) now also passes when signed. That
is the same policy question and the same escape; nothing here touches page hashes,
cdhashes or the trust path.

## 4. Run log

Loop, unattended, 30 s per run, no device:
`tooling/60-qemu-boot.sh --ramdisk build/rd-root.skeleton.img --cmdline '<S>' --secs 60 --out /tmp/<out>`.
`cpu-factor=10` is added to the given cmdline because TCG trips the IRQ-off
watchdog at 13 s without it (`/tmp/amfi-base`, 13.53 s: `Interrupts held disabled
for 14286688 nanoseconds`). The cmdline is otherwise the same string in every run.
(`screen.png` was missing on runs 3-5 because `60-qemu-boot.sh` was being edited
elsewhere at the time — `bash: line 489: syntax error`; `screen.txt` and
`result.json` were unaffected. Run 6 was taken after that edit settled and renders
both PNGs.)

| # | out | kernel | extra on the cmdline | result | panic line |
|---|---|---|---|---|---|
| 1 | `/tmp/amfi-base2` | before (base) | none | panic 30.87 s, 1 867 exceptions | `SWEET EARLY PANIC: unexpected SIGKILL of launchd (CS_KILLED) with reason -- namespace 9 code 0xe description none` |
| 2 | `/tmp/amfi-ctl` | before (base) | `unentitled_ios_sim_launch=1` | panic 30.67 s, **past the SIGKILL** | `SWEET EARLY PANIC:  initproc failed to start -- exit reason namespace 6 subcode 0x1 description: Library not loaded: /usr/lib/libSystem.B.dylib` |
| 3 | `/tmp/amfi-after` | after (`0104`) | none | panic 30.79 s, **past the SIGKILL** | `SWEET EARLY PANIC:  initproc failed to start -- exit reason namespace 6 subcode 0x1 description: Library not loaded: /usr/lib/libSystem.B.dylib` |
| 4 | `/tmp/amfi-off` | after (`0104`) | `sweet_ios_exec_platform=0` | panic 30.59 s, wall back | byte-identical to run 1 |
| 5 | `/tmp/amfi-unsigned` | after (`0104`) | none, **unsigned** init binary | panic 30.58 s, wall back | byte-identical to run 1 |
| 6 | `/tmp/amfi-after2` | after (`0104`) | none, repeat of run 3 | panic 30.70 s, **past the SIGKILL** | same dyld line as run 3 |

Runs 1–2 fix the wall's identity: the *only* difference between them is the
platform escape in step 2, and it moves the stop from the CS_KILLED panic to
dyld (namespace 6 = `OS_REASON_DYLD`) complaining about the missing dylib cache.
That is the documented next wall, not this page's. The panic line names the
description verbatim, and names the same binary (`/sbin/launchd`, cdhash
`5C15DB07-B3BC-3DF3-B62F-3E498B993B8E`).

### 4.1 Runs with `0104` built in

Run 3 is the task: the plain cmdline, no escape, gets past the SIGKILL and stops
in dyld instead — the deferred `Library not loaded: /usr/lib/libSystem.B.dylib`
(`no dylib cache`), which is the next wall.

Run 4 flips the new switch off and reproduces the old panic word for word, so the
decision is ours and is one bool.

Run 5 is the unsigned control: `build/rd-root.stage` copied with `cp -al`,
`LC_CODE_SIGNATURE` located by walking the load commands and its SuperBlob magic
(`0xfade0cc0` at offset 516336) zeroed, image rebuilt with
`fstool create --type hfs+ --size 33554432 -O block_size=4096 -O journaled=false`
(cache dirs dropped). The same kernel that passes a signed launchd kills an
unsigned one at the same place with the same reason, so `CS_SIGNED` is doing the
gating and unsigned code is not being waved through.

## 5. Build record

    commit db6ff74  (series 0104 appended, SHA256SUMS refreshed)
    CI run 43481308385 -R tadej-jereb/ios-nord -n xnu-kernel-sweet, success 8m21s
    kernel.development.sweet sha256 3ae348afd12056d82cce75ce422f1f9c24a26313bd76cf0193ce78ae10128a67
                                    (17 205 848 B; base was 17 187 784 B)
    preflight: PASS (dry), 99/99 series entries apply in order
    check-hunk-counts.py: all 96 patch files OK
    gh workflow run xnu.yml -f mode=build -f macos_version=13.5
                       -f kernel_config=DEVELOPMENT -f machine_config=SWEET

## 6. If it ever has to come out

`sweet_ios_exec_platform=0` at the boot prompt restores the stock refusal for the
lifetime of one boot. The patch is the last entry in `xnu-avicii/series`, touches
one file and one decision, and reverts cleanly (`git apply -R`).
