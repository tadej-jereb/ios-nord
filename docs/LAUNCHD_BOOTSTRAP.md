# LAUNCHD_BOOTSTRAP - the first userland exec, statically

What has to be on the volume before `/sbin/launchd` can run as PID 1, in the
order a boot will stop on it, and what each stop looks like. Everything here was
read off the iOS 16.7.16 (20H392, iPhone10,3/D22AP) payload and the kernel tree;
nothing was executed on the phone.

State this document starts from, from the p6 ring
(`logs/p6-kernel-ring.clean.txt`):

    145  hfs: Initializing the journal ...
    146  hfs: mounted iOSRoot on device b(1, 0)
    147  SWEET: root volume is not authenticated (error 25); continuing unsealed
    148  devfs_kernel_mount: kernel_mount failed: 2
    150  load_init_program: attempting to load /usr/appleinternal/sbin/launchd.development
    152  load_init_program: attempting to load /sbin/launchd

and then the recorded panic, `load_init_program: opening of /sbin/launchd
failed, errno 2` (`docs/IMAGE_PROVENANCE.md:334`; that wording is not in the
kernel tree checked out here, but the code path below is the one that ran).
Both errno 2s have the same cause: the volume is empty. This document says what
"not empty" means, precisely, and in which order.

## Method and instruments

| what | how |
|---|---|
| payload | `build/ipsw-x/087-86698-044.dmg` (OS volume), `087-86593-047.dmg` (SystemOS cryptex), `087-86715-047.dmg` (AppOS cryptex) mounted read-only through `tooling/opt/apfs-fuse/bin/apfs-fuse` |
| binaries | `/sbin/launchd` sha256 `12370e5e…cac61c` (541 600 B), `/usr/lib/dyld` sha256 `58068345…933757` (922 912 B), `/sbin/mount` sha256 `ac55c4c7…` |
| disassembly | `llvm-objdump -d --no-show-raw-insn`; stub-to-symbol map rebuilt from `LC_DYLD_CHAINED_FIXUPS` import table, so every `bl` below is named |
| code signature | SuperBlob parsed by hand: CodeDirectory slots, page hashes, entitlements blob, entitlement hashes |
| strings | `llvm-strings -a -t x`; the file offset is printed - virtual address is offset + 0x100000000 |
| kernel | `/home/tadej/xnu-8796.141.3` (`bsd_init.c`, `kern_exec.c`, `devfs_vfsops.c`, `vfs_syscalls.c`, `tty_cons.c`, `randomdev.c`) |
| patches | `xnu-avicii/patches/0015,0025,0029,0035,0036,0037,0038,0042` |

All file offsets are into the file named next to them. Nothing here is a guess
about what a program "usually" does: each claim has an address, a string offset
or a source line.

## 1. What the kernel does, and where it stops

`bsd_init` order (all `bsd/kern/bsd_init.c`):

    691  vfsinit()                     <- devfs_init() runs here, creates the /dev nodes
    870  vfs_mountroot()               <- the HFSX root is mounted here
    977  devfs_kernel_mount("/dev")
    1021 siginit, bsd_utaskbootstrap
    1078 load_init_program(p)          <- exec of /sbin/launchd; panics on failure

`devfs_kernel_mount` is `devfs_vfsops.c:487`:

    kernel_mount("devfs", NULLVP, NULLVP, "/dev", NULL, 0, MNT_DONTBROWSE,
                 KERNEL_MOUNT_NOAUTH | KERNEL_MOUNT_DEVFS, ctx)

`kernel_mount` (`vfs_syscalls.c:291`) namei()s the path when `vp == NULLVP`
(line 307-317) and returns the namei error untouched. On an empty volume
`/dev` does not exist, so namei returns **ENOENT = 2** and the mount is never
attempted. It is not a bootstrap-order problem: the mount point is simply
missing. Nothing retries - the later `mount -P 1/2` jobs mount other things.

The nodes are not the issue either: `devfs_init` (`devfs_vfsops.c:109-155`)
already registered `console` (0622), `tty`, `kmem` (with boot-arg `kmem`),
`null`, `zero`, `klog`, `oslog`, `oslog_stream` and, from `random_init`
(`bsd/dev/random/randomdev.c:99-119`), `random` and `urandom`; `fdesc` adds
`/dev/fd`. They live in the devfs tree before the mount, so as soon as `/dev`
exists the mount succeeds and they are all visible.

`load_init_program` (`kern_exec.c:6873`) then tries, in this order,
`/usr/appleinternal/sbin/launchd.debug`, `…launchd.development` (DEVELOPMENT
build), `/sbin/launchd` (line 6834-6842), and panics
`Process 1 exec of %s failed, errno %d` (line 6929). `load_init_program_at_path`
(line 6751) sets `envp = USER_ADDR_NULL` (line 6824): **launchd starts with an
empty environment** - no `PATH`, no `HOME`, no `DYLD_*`. `set_security_token(p)`
gives the process uid/gid 0.

`errno 2` is only the first of the errors this path can return. The ones after
it are the interesting ones, because they are what the next boots will print:

| errno | kernel site | meaning |
|---|---|---|
| 2 ENOENT | `kern_exec.c:6822` open of the image | the file is not there |
| 6 ENXIO | `load_return_to_errno` | `LC_LOAD_DYLINKER` target (`/usr/lib/dyld`) missing |
| 85 EBADEXEC | AMFI hook via `ubc_cs_blob_add` | signature rejected, `CS_SIGNED` absent |
| 86 EBADARCH | macho load, `exec_check_permissions` | not arm64 |
| 88 EBADMACHO | `load_machfile` | truncated / bad load commands |

Patch `0042` prints `exec %s` on the development build's "iOS binary without
no-sandbox" path, so a successful exec is visible on the console as
`exec launchd`.

## 2. What launchd does before it can start anything

`LC_MAIN` entry is file offset 92596 (va `0x1000169b4`). Straight-line reads of
that function, in order:

| va | what | evidence |
|---|---|---|
| `0x1000169cc` | `getenv("LAUNCH_DID_REEXEC")`, `getenv("XPC_USERSPACE_REBOOTED")`, `sysctlbyname("kern.initproc_spawned")` | strings at 0x586b1, 0x586c3, 0x586da |
| `0x100016a44` | `isatty(1)`; on 0 prints `%s cannot be run directly (stdout: %d)` (0x5870c) - not fatal | |
| `0x100016a94` | `getpid() != 1` prints `%s cannot be run directly (pid = %d)` (0x58733) then `abort_with_reason(7,1,…)` via `0x10003d3c0` | `0x100016ab4`; `abort_with_reason` at `0x10003d408` |
| `0x100016ad4` | fd 0, 1, 2 are each pointed at `/dev/null`: three `(0,0) (1,1) (2,2)` calls to `0x100016fa0`, which `open("/dev/null", O_RDWR\|O_NOCTTY, 0666)` (`0x100016fc0`, string 0x57f56) and `dup2()`s it; skipped when the lean/restore byte at 0x1000728b9 is set | failure tolerated: `dup2(-1, fd)` only errors |
| `0x100010dd0` | `console_log()`: formats the line, then `dispatch_sync_f` to `console_write` (`0x100010e30`), which **`open("/dev/console", O_WRONLY\|O_NOCTTY, 0666)`** once (cached in the global at 0x1000721e0), `write()`s, and drops the fd again on `EPIPE` | `0x100010e54` string 0x57467, `_open` stub `0x100051520`, flags `#0x20001`, mode 438 |
| `0x100016af8` | `memorystatus_control` with selector `0x22000040`, jetsam watermark | |
| `0x100016b00` | config read `0x1000452e0` (boot-args, limits plist), then log `hello` (0x58758, level 5) | |
| `0x100016c0c` | `sysctlbyname("kern.bootargs")` (0x5875e, wrapper `0x10003de58`) then logs `boot-args = %s` (0x5876c) | |
| `0x100016c48` | `proc_disable_wakemon(getpid())`, fatal on error | `0x100016f58` |
| `0x100016c6c` | env dispatch: Lean Testing (0x5877b), Restore (0x5879e), BaseSystem (0x587bc) | |
| `0x100016cfc` | `setsid()`; `EPERM` tolerated, anything else crashes | `0x100016d24 cmp #1` |
| `0x100016d44` | **`chdir("/")`** (0x56439); on error `os_crash` with `Could not chdir to /` | `0x100016f80` `__os_assert_log`/`__os_crash` |
| `0x100016d58` | **`setlogin("root")`** (0x53ae1); on error `os_crash` `Could not set login name to "root"` | |
| `0x100016d70` | `signal()` loop over `SIGKILL, SIGTERM, …` with mask setup | |
| `0x100016d80` | `proc_pidinfo(pid, PROC_PIDUNIQIDENTIFIERINFO=18, 1, buf, 192)` at `0x10003dd0c`; failure crashes with `could not get unique pid` (0x5880c) | |
| `0x100016dcc` | `task_set_special_port(self, TASK_BOOTSTRAP_PORT=4, MACH_PORT_NULL)` - "neuter bootstrap port" (0x588a5), assumes-log only | |
| `0x100016df4` | `mach_ports_register(self, ports, 1)`, then `xpc_mach_send_create_with_disposition(MACH_MSG_TYPE_COPY_SEND)` - the inheritance port (0x588cb) | |
| `0x100016e54` | `uuid_generate`, uid/euid/egid snapshot | |
| `0x100016f1c` | `dispatch_activate`, `dispatch_main` | the boot jobs run from here |

The four `os_crash` exits between `0x100016f40` and `0x100016f9c` are the
fatal ones: `could not set up inheritance port` (0x588cb), `could not get
unique pid` (0x5880c), `Could not chdir to /` and `Could not set login name to
"root"` (0x53ae1 is only the argument).

So launchd's own stdout/stderr are not a terminal and not the console: console
output is a separate, lazily opened fd that only log lines above the stderr
level use. Everything else goes through `os_log`. Note also what launchd does
**not** do at startup: it does not read `/private/etc/fstab`, does not create
`/var/run`, does not touch a plist before it has a bootstrap port. Its first
file operations are `/dev/null` (three times) and, on the first log line,
`/dev/console`.

### The compiled-in boot table

`__TEXT,__config` (file offset 411743, 8278 B) is a plist. Launchd runs the
`Boot` dict **in key order**, and `RequireSuccess` aborts the chain, so this
list is the real boot script:

    auearlyboot → dirs_cleaner → mount-phase-1 → mount-phase-2 → keybag
    → restore-datapartition → fips → finish-restore → tzinit → data-protection
    → recovery-mode → fsck-safe → fsck → sysstatuscheck → finish-obliteration
    → finish-demo-restore → xpcroleaccountd → usermanagerd(-switch)
    → init_featureflags → prng_seedctl → launchd_cache_loader
    → MSUEarlyBootTask → darwinos-boot-task → commit-boot-mode
    → detect-installed-roots → init-with-data-volume → workload-properties-init
    → cvcalibration-post-factory-fix

The same plist also carries `Bootstrap/Paths` (the directories launchd scans:
`/System/Library/LaunchDaemons`, `…/LaunchAngels`,
`/AppleInternal/Library/LaunchDaemons`, `…/LaunchAngels`,
`…/NanoLaunchDaemons`, `…/NanoLaunchDaemonsAltAccount`,
`…/DeveloperModeLaunchDaemons`), `Bootstrap/UserPaths` (`…/LaunchAgents`),
`ChildDefaults/PATH` = `/usr/bin:/bin:/usr/sbin:/sbin`, `SystemRoots`, and
`HighWatermark` 50. `performAfterUserspaceReboot` marks the jobs whose
cold-boot behaviour is in section 8.

The same two helpers are what jobs get: `dup_devnull` (`0x100016fa0`) for a
job's null stdio, and the spawn path adds `/dev/console` with
`posix_spawn_file_actions_addopen` for fd 0/1/2 (`0x1000249c4`, `0x1000249e8`,
`0x100024a0c`). `/dev/null` and `/dev/console` are therefore on the very first
spawned job's path, not only on launchd's.

### What it reads later

| path | site | need |
|---|---|---|
| `/private/etc/com.apple.xpc.launchd.limits.plist` | `0x100045fbc` (string 0x62ea9) | optional; "no bootargs string" (0x62dc0) is logged when absent |
| `/etc/nologin` | `0x1000403bc` (string 0x61c30) | login gate, read when a user session is started |
| `/private/var/tmp/com.apple.launchd.XXXXXXXXXX` | string 0x5950d | `mkdtemp` scratch, needs a writable `/private/var/tmp` |
| `/System/Library/LaunchDaemons/com.apple.jetsamproperties*.plist` | strings 0x5727e, 0x57311 | jetsam limits |
| boot-args `launchd_*` | strings 0x62e49-0x632ab, parsed near `0x100045fbc` | see below |

Boot-args it honours (from the 0x62e49..0x632ab block):
`launchd_disable_all_timeouts=`, `launchd_force_data_status=`,
`launchd_proxyless_spawn=`, `launchd_instance_limit=`,
`launchd_usr_abandon_unmanaged=`, `launchd_verbose_coalition_logs=`,
`launchd_ios_sessions=`, `launchd_upward_connections_support=`,
`launchd_workload_properties_disabled=`, `launchd_automation=`,
`launchd_log_serial=`, `launchd_log_verbose_meta_limit=`,
`launchd_sync_interval=`, `launchd_sudden_shutdown=`, and
`launchd_cache_loader` as a plist key. None is needed for the first exec;
`launchd_log_serial=1` and `launchd_disable_all_timeouts=1` are the two worth
having on a bring-up kernel. It also reads `security.mac.amfi.developer_mode_status`
(sysctl string 0x53f3f) and `kern.bootargs` itself.

## 3. dyld and the shared cache

`launchd` links only `/usr/lib/libSystem.B.dylib` (1319.100.3) and
`/usr/lib/libobjc.A.dylib` (228.0.0), and `LC_LOAD_DYLINKER /usr/lib/dyld`
(load commands 9, 14 and 15). **Neither dylib exists as a file anywhere** -
not on the root volume, not in the cryptex (`/usr/lib` there holds only
`libstdc++`, trampolines). They exist only inside the dyld shared cache.

dyld's cache search strings (`/usr/lib/dyld`):

    0x718a8  /System/Library/Caches/com.apple.dyld/
    0x72207  /Library/Caches/com.apple.dyld/
    0x76597  /System/Volumes/Preboot/Cryptexes/OS/
    0x765bd  /private/preboot/Cryptexes/OS/
    0x765dc  /System/Cryptexes/OS
    0x797b9  Cryptexes/App            0x797c7  System/Cryptexes/App
    0x7a8bc  Cryptexes/OS             0x7a8c9  System/Cryptexes/OS
    0x753e5  dyld_shared_cache_arm64        (no arm64e variant: matches the arm64 kernel of patch 0004)
    0x708f1  DYLD_SHARED_CACHE_DIR  (unset: kernel passes envp = NULL)

The cache itself is in the SystemOS cryptex:
`System/Library/Caches/com.apple.dyld/` holds `dyld_shared_cache_arm64`
(393 216 B), `.01`-`.40`, `.41.dylddata`, `.42.dyldlinkedit` and `.symbols`
(592 101 376 B), 3.36 GiB in total. The first cache file carries the dylib path
table; `grep -a /usr/lib/libSystem.B.dylib` matches it.

The root volume ships `System/Cryptexes/OS -> ../../private/preboot/Cryptexes/OS`
but `/private/preboot` is **empty** in a plain copy - the graft only resolves if
`private/preboot/Cryptexes/OS` is populated. `tooling/33-populate-root.sh`
covers both routes: stage `sysos` copies the cryptex there, stage `dyld`
hard-links the cache to `/System/Library/Caches/com.apple.dyld`, stage
`cryptexlinks` hard-links every cryptex-only file to its root path (so
`/usr/lib/libSystem.B.dylib` is not needed, but `APFS.framework/APFS`,
`seputil`'s siblings and every framework a boot job loads are).

dyld needs `__shared_region_map_and_slide_2_np` (`/usr/lib/dyld` string
0xc82e2, kernel `bsd/vm/vm_unix.c:2877`) to map the cache; the cache was built
for a 16K-page device, the same granule SWEET uses. If that call fails the exec
dies inside dyld, after `exec` is printed.

## 4. AMFI, entitlements, and the unsealed root

The 20H392 `launchd` is **ad-hoc signed**: SuperBlob `0xfade0cc0`, 5 slots
(CodeDirectory, requirements, entitlements XML, DER entitlements, an 8-byte
empty CMS blob), CodeDirectory flags `0x2` = `CS_ADHOC`, hashType 2 (sha256),
127 pages of 4096 B. Entitlements: 22 keys, including

    com.apple.apfs.get-dev-by-role                  com.apple.private.amfi.can-allow-non-platform
    com.apple.private.iokit.system-nvram-allow      com.apple.private.kernel.system-override
    com.apple.private.persona-mgmt                  com.apple.private.pmap.load-trust-cache
    com.apple.private.record_system_event           com.apple.private.roots-installed-read-write
    com.apple.private.security.disk-device-access   com.apple.private.security.storage.driverkitd
    com.apple.private.security.storage.launchd      com.apple.private.security.system-mount-authority
    com.apple.private.set-atm-diagnostic-flag       com.apple.private.spawn-panic-crash-behavior
    com.apple.private.spawn-subsystem-root          com.apple.private.vfs.allow-low-space-writes
    com.apple.private.vfs.graftdmg                  com.apple.private.vfs.pivot-root
    com.apple.rootless.restricted-block-devices     com.apple.rootless.storage.early_boot_mount
    com.apple.rootless.volume.Preboot               com.apple.security.network.server

    (entitlements blob at 4462, payload 1669 B; CD special slot -5 =
     aa19776d… matches its sha256; slot -1 Info.plist `com.apple.xpc.launchd`
     = b41a0ed0…; slots -3/-4/-6 are zero, i.e. DER-only is unfilled)

What the SWEET stand-ins do with that:

* `0035` registers a built-in AMFI interface plus a MAC hook
  `mpo_vnode_check_signature` that, for any vnode whose mount has `MNT_ROOTFS`,
  sets `CS_PLATFORM_BINARY`, and parses the signature's XML entitlements blob
  into an `OSDictionary` (`SweetEntitlements.cpp`). Every entitlement query the
  kernel makes is answered from it.
* `0036` adds `*cs_flags |= CS_SIGNED` unconditionally, because `csproc_get_blob`
  and the csops/cdhash/platform queries ignore blobs without it.
* `0015` makes trust-cache queries return `KERN_NOT_FOUND`/`NOT_SUPPORTED`
  instead of panicking on the missing Image4/AMFI kexts.
* `0029` downgrades the root authentication failure to the printf already seen.
* `0038` answers the `AppleKeyStore` selectors keybagd uses, so `keybagd --init`
  gets a handle instead of needing a real SEP; the populate stage `keybag`
  additionally writes a placeholder `/private/var/keybags/systembag.kb`.

Two consequences that the populate step must respect:

1. **Everything that is exec'd has to be reachable through the root volume.**
   `MNT_ROOTFS` is tested on the vnode's mount. A hard link is a vnode in the
   root volume's catalog and passes; a path that resolves into a *mounted*
   cryptex (`/System/Cryptexes/OS/...` when that graft is a mount) does not.
2. **The signature has to be byte-intact.** The page hashes are checked by the
   kernel on fault (`cs_validate_page`, `bsd/kern/ubc_subr.c:5690-5830`): a bad
   hash sets `CS_VALIDATE_TAINTED` and the fault kills the process, printing
   `CODE SIGNING: cs_validate_page: … actual […] != expected […]` with
   `cs_debug` on. The entitlements blob is hashed against CD slot -5 before it
   is parsed. An edited or truncated binary loses both platform status and
   entitlements, and `launchd` without `can-allow-non-platform` cannot start the
   unentitled binaries it will meet.

Nothing needs to be *added* to the shipped signatures: they are already ad-hoc,
already carry the entitlements, and the CD hashes are correct (verified: 127/127
pages, slot -5, slot -1).

## 5. The ordered minimal set

Ordered by the first thing a boot stops on. Each step has the console line that
means it was reached, so a boot is judged by *where it stops*, not by whether it
"looks fine". `tooling/34-check-bootstrap.sh` checks exactly these steps offline.

| # | item | why it is here | stop line if missing/wrong |
|---|---|---|---|
| 0 | the volume is populated at all (≥144 341 files) | empty volume = current state | `load_init_program: … errno 2` |
| 1 | `/dev` exists, empty, root-owned, 0555/0755 | namei mount point for devfs (`bsd_init.c:977`); devfs then provides null/console/tty/zero/urandom/klog/fd | `devfs_kernel_mount: kernel_mount failed: 2`, then no stdio and no console output |
| 2 | `/sbin/launchd`: regular, 0755, arm64 `MH_EXECUTE`, `LC_LOAD_DYLINKER /usr/lib/dyld`, ad-hoc sig, CD page hashes + slot -5 correct, 22 entitlements | the exec target; `CS_SIGNED`/`CS_PLATFORM_BINARY` depend on it | `Process 1 exec of /sbin/launchd failed, errno N` (85 EBADEXEC / 86 EBADARCH / 88 EBADMACHO) |
| 3 | `/usr/lib/dyld`: arm64 `MH_DYLINKER`, 0755, sha256 `58068345…` | `LC_LOAD_DYLINKER`, loaded by the kernel before userland | `exec` printed, then 6 ENXIO |
| 4 | shared cache at `/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64` + 43 further files incl. `.dyldlinkedit`, path table containing `libSystem.B.dylib` and `libobjc.A.dylib`; cryptex files hard-linked at their root paths | the only home of libSystem/libobjc | `exec launchd` then a dyld error (`dyld: Library not loaded: /usr/lib/libSystem.B.dylib`) |
| 5 | `/` is a directory, `/private/var/tmp` 1777, `/private/tmp` 1777, `/private/var/{run,db,keybags}` | `chdir("/")` is fatal; `mkdtemp` under `/private/var/tmp` | `dyld: …`, then `launchd: Could not chdir to /` and a crash log |
| 6 | `/private/etc/{master.passwd,group,passwd,ttys,hosts}`, **`/private/etc/fstab`**, optional `limits.plist` | `setlogin`, `getpwnam`, `getfsent` | `Could not set login name to "root"`; for fstab `mount: can't get filesystem checklist` |
| 7 | `/System/Library/LaunchDaemons` and the other `Bootstrap/Paths` dirs; every job's `Program` resolves | the scan; `mount-phase-1` is launched from here | jobs never start |
| 8 | the boot jobs themselves, in table order: `auearlyboot`, `/sbin/mount`, `keybagd`, `cc_fips_test`, `tzinit`, `seputil`, `/sbin/fsck`, `xpcroleaccountd`, `prng_seedctl`, `xpcproxy` | `RequireSuccess` on `mount-phase-1/2`, `fips`, `fsck`, `tzinit`, `data-protection`, `recovery-mode` | `launchd: boot task … failed` / halt |
| 9 | `/private/var/keybags/systembag.kb` 0600, `/private/var/db/{diagnostics,uuidtext}/.migrated` | keybagd, libtrace logd | `keybagd: Failed to migrate directory` |

Step 6's `fstab` deserves its own paragraph, because it is the one item the
payload does not ship and the ADT does not cover.

`mount -P 1` (`/sbin/mount`, job `mount-phase-1`, `RequireSuccess` +
`RequireRun`) does **not** read a device-tree fstab for a phase > 0: with
`-P 1` it takes the branch at `0x100004e50` (`w21 = 1`, filesystem `nonfs`),
falls to `0x100004f1c` and calls `setfsent()`, i.e. `/etc/fstab`. On failure it
`errx`es at `0x1000050d8` with `mount: can't get filesystem checklist`. The
`IODeviceTree:/filesystems/fstab` path (`0x100004774`) belongs to the *boot
device* resolution used without `-P`, and the D22AP ADT does have
`/filesystems/fstab` with `max_fs_entries`/`vol.fs_mntopts` children (offset
~174 880 in `build/ipsw-x/d22ap.adt`) - but `avicii/adt/avicii-live.adt`
contains no `fstab` and no `filesystems` node at all. So on this port the file
is the only source, and it is missing from the DMG. A minimal
`/private/etc/fstab` is therefore part of the first-run set, not an extra.
`mount` also links `APFS.framework/APFS` and `MediaKit.framework/MediaKit` and
calls `APFSContainerGetBootDevice`, so it needs both in the cache even for an
HFS root.

The line itself (a starting point, see section 8):

    /dev/ufsroot0 /private/var hfs rw 0 2

Phase filtering is: `fs_type` must be `ro`, `rw` or `rq`, `fs_mntops` must not
contain `noauto`, and `fs_vfstype` goes through the `-t` allow list built from
`nonfs` (`0x1000066c0`, split on commas). The phase code compares `fs_vfstype`
against `nfs`, `url`, `ramdisk`, `apfs` and `net` by name
(`0x100005268`-`0x1000052dc`), so whether a literal `hfs` entry passes the allow
list or has to be written as `apfs` is the one part of this that only a boot
settles. Struct offsets used: `fs_vfstype` +0x10, `fs_mntops` +0x18, `fs_type`
+0x20.

## 6. Checking a populate before a boot

    tooling/34-check-bootstrap.sh ROOT [--reference DMG_MOUNT] [--json] [--quiet] [--min-files N]

Read-only, unprivileged, nothing executed. One line per item:
`ok` / `absent` / `mismatch` / `note`, exit 0 ready, 1 something absent, 2
something mismatched, 64 usage. `--reference` compares bytes against a DMG mount
for `launchd`, `dyld` and every job plist's binary.

What it does verify: presence, type, mode, owner, arm64 cputype, Mach-O file
type, `LC_LOAD_DYLINKER`, ad-hoc-ness (CMS absent, `CS_ADHOC` set), all 127 page
hashes, the entitlements hash against CD slot -5, each required entitlement key,
the pinned sha256, cache file count and path table, hard-link status of the
flattened cryptex files, `fstab`, and every `Program` key in
`/System/Library/LaunchDaemons`.

What it does not, and cannot: whether devfs actually mounts, whether dyld gets
a shared region, whether a job's `RequireSuccess` failure halts the boot, or
whether any of the 491 LaunchDaemons beyond the boot list works. Only a boot
answers those.

## 7. Suggested boot ladder

Each rung is one boot, judged by where it stops; nothing below is edited in the
kernel or the shim.

1. Populate (stages `os` `sysos` `appos` `dyld` `cryptexlinks` `keybag`
   `logdirs`), then check until `ready to boot`:

       tooling/34-check-bootstrap.sh /mnt/iosroot

2. Add the fstab line on the mounted volume, then re-check:

       printf '/dev/ufsroot0 /private/var hfs rw 0 2\n' | sudo tee /mnt/iosroot/private/etc/fstab

3. Boot with `launchd_log_serial=1 launchd_disable_all_timeouts=1 -v` on the
   kernel command line. Expect `exec launchd`, then either launchd's console
   log or a dyld error.
4. If it stops in a boot job, read the job name: `mount-phase-1` → fstab/APFS
   framework, `keybag` → AppleKeyStore selectors, `fsck` → `/sbin/fsck` and the
   HFS journal, `tzinit` → `/usr/share/zoneinfo`.

## 8. What could not be determined statically

* **`PerformAfterUserspaceReboot` on a cold boot.** 8 of the 29 boot jobs carry
  it (`dirs_cleaner`, `keybag`, `finish-restore`, `sysstatuscheck`,
  `usermanagerd`, `usermanagerd-switch`, `init_featureflags`,
  `launchd_cache_loader`); 15 carry `RequireSuccess`. Whether launchd skips them on the
  very first boot or runs them unconditionally is not visible in the binary
  beyond the key itself. The check treats them as required either way.
* **Ordering inside `launchd`.** The `Boot` dict order is the plist order, but
  launchd may start `auearlyboot` and the scan concurrently; only a boot shows
  it.
* **Whether missing `/dev/null` or `/dev/console` is survivable.** Both
  `dup2(-1, fd)` results are discarded (`0x100016fd8`, and the console write
  just returns short), so statically both are non-fatal, but with neither node
  there is no stdio for children and no output at all - indistinguishable from
  a hang.
* **How `setfsent()` reports a missing file.** The branch at `0x100004f30`
  distinguishes `errno != 0` (errx) from `errno == 0` (also errx via the exit
  code helper), so both end the job, but which one a Darwin `setfsent()` with no
  `/etc/fstab` produces is runtime.
* **Which entitlements launchd actually needs.** The kernel call sites for
  `pivot-root`, `graftdmg`, `rootless.*` and `storage.launchd` sit behind the
  sandbox/rootless/APFS kexts, which SWEET partly does not have
  (`0050` only ships a permissive policy). All 22 are present in the shipped
  signature, so nothing has to be added either way.
* **`mount -P 1` against an HFS root.** It resolves an APFS boot container and
  a data volume (`0x100005530` "mount: missing data volume"). With no APFS
  volume at all the outcome (`0x10000518c` "data volume missing, but not
  required in env" vs. a hard failure) depends on the `os_env_type` property in
  `/chosen`, which the live ADT does carry only as far as `chosen` itself. The
  `fs_vfstype` allow list (`-t nonfs`) is likewise unresolved for a literal
  `hfs` entry.
* **keybagd against the stub.** `0038` answers selectors with a handle; whether
  keybagd's first selector is 0/14 and accepts that answer is only visible in a
  boot log.
* **Whether `launchd` accepts fd 0/1/2 closed.** It reopens them itself, but the
  `isatty(1)` branch (`0x100016a44`) decides whether the "cannot be run
  directly" line is printed; with `envp == NULL` and no console the branch
  outcome is runtime.
* **The 491 LaunchDaemons outside the boot table.** Nothing below step 8 was
  analysed; they are checked for existence of their `Program` only.

## 9. Provenance

| claim | where |
|---|---|
| observed state | `logs/p6-kernel-ring.clean.txt:145-152`, `docs/IMAGE_PROVENANCE.md:334` |
| devfs ENOENT | `bsd/miscfs/devfs/devfs_vfsops.c:487-501`, `bsd/vfs/vfs_syscalls.c:291-337`, `bsd/kern/bsd_init.c:973-980` |
| exec path and panic texts | `bsd/kern/kern_exec.c:6834-6842, 6873-6930, 6751-6831` |
| devfs nodes | `bsd/miscfs/devfs/devfs_vfsops.c:109-155`, `bsd/dev/random/randomdev.c:99-119` |
| launchd startup | `/sbin/launchd` offsets in section 2; strings 0x53ae1, 0x56439, 0x57467, 0x57f56, 0x5875e, 0x5876c, 0x5880c, 0x588a5, 0x588cb |
| boot table | `/sbin/launchd` `__TEXT,__config`, file 411743..420021 |
| limits plist, nologin, tmp dir | strings 0x62ea9, 0x61c30, 0x5950d |
| dyld cache paths, cache name | `/usr/lib/dyld` strings 0x718a8, 0x72207, 0x76597-0x765dc, 0x7a8bc-0x7a8c9, 0x753e5, 0x708f1, 0xc82e2 |
| cache content | `087-86593-047.dmg` `System/Library/Caches/com.apple.dyld/` (44 files), path table in `dyld_shared_cache_arm64` |
| launchd signature | SuperBlob at 516336, CD at +52, slots at 16/4450/4462/6139/7244 |
| AMFI stand-ins | patches 0015, 0025, 0029, 0035, 0036, 0038 |
| ADT fstab | `build/ipsw-x/d22ap.adt` ~174 880 (`max_fs_entries`, `vol.fs_mntopts`); absent in `avicii/adt/avicii-live.adt` |
| `mount -P` flow | `/sbin/mount` `0x100004e50`, `0x100004f1c`, `0x1000050d8`, `0x100004774`; strings 0x74f1, 0x7756, 0x7768, 0x779a |
