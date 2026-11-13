# RAMDISK_ROOT - a ramdisk root on md0, and how it differs from the real one

State: `tooling/61-mkrd-root.sh` builds and verifies the image on the host. No
boot has happened with it. This document exists so that nobody mistakes the
result for the final root: it is a **throwaway scaffold that reaches the first
`exec /sbin/launchd`** (writable in RAM, nothing of it persists), not the 16 GiB
HFS root of `docs/IOSROOT.md`.

Two blockers make the ramdisk the right next rung:

1. The 16 GiB root populate needs root on the build host (`docs/ROOTFS_READY.md`
   lines 10-29 are unexecuted).
2. QEMU has no UFS, so a root that lives on `userdata` cannot be booted there at
   all (`docs/ROOTRW-REVIEW.md`, `docs/UFS_WRITE_AUDIT.md`).

The kernel already carries the two pieces the route needs: `mockfs` (`0021`) and
"ramdisk root without IOMEDIA" (`0022`), and `0024` made the mockfs pager path
safe for a *virtual* memory device. Nothing has to be built for this.

## 1. What shape the image must be - and why, from the code

**A raw HFS+ volume, byte for byte what a partition would hold.** Not cpio, not
tar, not a directory tree, not a Mach-O.

The chain, in kernel order:

| step | code | what it says |
|---|---|---|
| the device is made from the device tree | `iokit/bsddev/IOKitBSDInit.cpp:757-770` | reads `/chosen/memory-map` property `RAMDisk` = two `uintptr_t` {base, size}, calls `mdevadd(-1, base>>12, size>>12, 0)` |
| `rd=md0` selects it | `IOKitBSDInit.cpp:772-800` | `'m','d',digit,0` only; `mdevlookup()`; `panic("specified root memory device ... has not been configured")` if absent |
| it is a plain block device | `bsd/dev/memdev.c:640-700`, `:420-460` | 512-byte sectors (`DEV_BSIZE`), `d_strategy`/`d_read` over the RAM; `DKIOCGETMEMDEVINFO` reports `mi_phys = 0` for it |
| the root is mounted from it | `bsd/vfs/vfs_subr.c:1231-1266` | `bdevvp(rootdev)`, then walks `vfsconf`, calling each `vfc_mountroot` or `VFS_MOUNT` until one succeeds |
| `mockfs` is tried **first**, not last | `bsd/vfs/vfs_conf.c:197-207` places mockfs last in the *static* table, but `sweet_hfs` registers at init through `vfs_fsadd` (`0026` hunk at `bsd/sweet_hfs/...`, `vfs_fsadd` call) and is therefore appended **after** it | mockfs would claim any device |
| mockfs steps aside for a filesystem | `0026` hunk in `bsd/miscfs/mockfs/mockfs_vfsops.c` (`mockfs_check_macho`, new code at +129..+160) | reads block 0, accepts only `MH_MAGIC`/`MH_CIGAM`/`MH_MAGIC_64`/`MH_CIGAM_64`/`FAT_MAGIC`/`FAT_CIGAM`; anything else returns `EINVAL` and the next fs is tried |
| HFS takes it | `VFS_MOUNT` path for `sweet_hfs` | mounts the volume as the root |

So: if block 0 of the image is not a Mach-O magic, the image must be a
filesystem. The only block filesystems in this kernel are HFS (`0026`) and UFS-
root (`0028`), and only HFS can take an HFS image. A cpio or tar image would
fall through both and end in `vfs_mountroot: can't setup bdevvp` / a panic.
`61-mkrd-root.sh` asserts both ends of this: volume header magic `482b` at offset
1024, and a non-Mach-O block 0.

A Mach-O image is the *other* legitimate shape - mockfs serves the whole device
as one `/sbin/launchd` (`refs/dipa-studio-ios-sweet/tools/mkinit.py` exists to
build such a static frontend). That gets PID 1 running and nothing else: no
`/usr/lib/dyld`, no cache, so launchd dies at its first dylib. It is not this
route.

## 2. The command line and what the md driver needs from the payload

    rd=md0 keepsyms=1 debug=0x8 launchd_log_serial=1 launchd_disable_all_timeouts=1 -v

`rd=md0` is the whole of it for the driver - `md0` only, no `/dev/` prefix, no
`rootdev=`. The rest is the usual bring-up line. The device itself is not named
on the command line at all: it comes from the ADT.

`avicii/tools/mkpayload.py --ramdisk IMAGE` does the payload side
(`mkpayload.py:26,132-137,164-172`):

* appends the image as one more segment right after the kernel and moves
  `kernel_end` past it, so the shim needs no change;
* pads the size up to a 16 KiB page (`PAGE = 0x4000`) - the size in the ADT is
  the padded one;
* writes `/chosen/memory-map` `RAMDisk` = `<phys, size>` with `phys` derived from
  the kernel's own relocation, and asserts the property is not already there.

Constraints this puts on the builder:

* the image lands below the ADT and `boot_args`, inside `topOfKernelData`, and is
  never handed to the VM allocator;
* it must stay **virtual** (`mdevadd(..., 0)`), not `pmd=`/physical: memdev's
  `mdPhys` path shifts physical page numbers by `PAGE_SHIFT`, which is 14 on this
  build, while `mdBase` counts 4 KiB pages - `0024` exists precisely because of
  that mismatch;
* the boot image now carries the ramdisk, so
  `fastboot getvar max-download-size` must be checked before any flash of it.

## 3. The set, and the honest size

Built from the DMGs only, exactly the items of `docs/LAUNCHD_BOOTSTRAP.md`
section 5, steps 1-9:

| item | bytes |
|---|---|
| `/System/Library/Caches/com.apple.dyld/` - 43 files, `.symbols` left out, hard-linked out of `private/var/db/.rdcache` (nlink 2) | 2 738 257 920 |
| 21 boot-table Programs of the `launchd` config (`auearlyboot`, `mount`, `keybagd`, `cc_fips_test`, `tzinit`, `init_data_protection`, `seputil`, `fsck`, `xpcroleaccountd`, `prng_seedctl`, `xpcproxy`, `dirs_cleaner`, `usermanagerd`, `MSUEarlyBootTask`, `mobile_obliterator`, `finish_demo_restore`, `FinishRestoreFromBackup`, `init_featureflags`, `sysstatuscheck`, `nvram`, `launchd_cache_loader`) | 2 920 592 |
| `/sbin/launchd` | 541 600 |
| `/usr/lib/dyld` | 922 912 |
| `/private/etc/{fstab,master.passwd,group,passwd,ttys,hosts}`, `SystemVersion.plist`, keybag placeholder, two `.migrated` markers | 10 302 |
| 28 directories | 0 |
| **set total, blocks counted once** | **2 742 653 326 B = 2.55 GiB** |
| image (HFS+, 4 KiB blocks, 112 %) | 3 089 104 896 B = 2.88 GiB |

The `.rdcache` names are the same blocks as the cache directory, so `du` on the
staging tree reports 2.74 GB twice over; only the once-counted figure is RAM.

`.symbols` (592 101 376 B) is a symbolication file, not mapped by dyld; the cache
still has the 43 files the checker calls for.

**It does not fit the RAM the kernel manages today.** That window is
0xb0000000..0xfd000000 = 1.20 GiB (`refs/rrrd-jpg-ios-sweet/NOTES.md:178` carries
the same wall for this cache: 3.10 GiB of 44 files). A 2.88 GiB image is 2.4x
over it. Options, none of them taken here:

* (A) give the ADT/kernel the phone's higher banks as well (the note above names
  `0x80000000+2G` and `0x100000000+0xfcc00000`; the carve-out holes need pmap
  work) - and check `max-download-size` for a ~3 GiB boot image;
* (B) prune subcaches (dyld maps every file the main cache references, so this is
  all-or-nothing in practice);
* (C) accept the skeleton image (below) for the first rungs and add the cache
  only once the RAM window exists.

Without the cache the same set is **4 191 822 B** and the image 32 MiB
(`--no-cache`): that is the rung that proves the md device, the HFS mount and the
`/dev` + devfs + `exec launchd` path. `.symbols` cannot be dropped to get under
1.20 GiB - even 2.55 GiB is over.

## 4. Building and checking it (host only)

    tooling/61-mkrd-root.sh --no-cache         # 32 MiB, first rung
    tooling/61-mkrd-root.sh                    # 2.88 GiB, needs the RAM window

    tooling/61-mkrd-root.sh --size 3GiB --out build/rd-root.img
    tooling/61-mkrd-root.sh --qemu             # runs tooling/60-qemu-boot.sh if present

`--qemu` assumes that wrapper takes `--ramdisk IMG --cmdline "..."`; it did not
exist yet when this was written, so that flag set is unproven.

The script mounts the DMGs read-only through `tooling/opt/apfs-fuse`, stages the
set in `build/rd-root.stage`, writes the image with the patched unprivileged HFS+
writer `tooling/opt/fstool`, replays owners/modes through a FUSE mount of the
image, then runs `tooling/34-check-bootstrap.sh build/rd-root.stage --min-files 0`
and `fsck.hfsplus -n`. No root, no loop device, nothing on the phone.

What was produced and verified on the host, full run:

```
34-check-bootstrap.sh: absent 0, mismatch 0, ready to boot
119 files, same count as the staging
launchd, dyld and the etc files are byte-identical to the staging copy
43 cache files, link count 2, all in the image
clean: 0 error(s), 0 warning(s)
fsck: ** The volume RD-root appears to be OK.
image build/rd-root.img: 3089104896 B (2,9G)
```

and the skeleton run: `absent 1, mismatch 0`, on `cache-image` only - which is
the definition of that rung.

The image `sha256` differs on every rebuild: HFS+ stamps the volume header with
the creation time. The content is held still the other way - `cmp` against the
staged files, which come straight from the DMGs (step 2's pinned launchd hash is
checked by the checker).

Not verified, and not verifiable on the host: that devfs mounts on the staged
`/dev`, that dyld gets a shared region from the hard-linked cache, that the boot
jobs' `RequireSuccess` is satisfied, and whether `mount -P 1` accepts the `fstab`
line. Only a boot answers those; `docs/LAUNCHD_BOOTSTRAP.md` section 8 lists the
same class of unknowns for the real root.

### 4.1 The one boot tried (QEMU, skeleton image)

`tooling/60-qemu-boot.sh --ramdisk build/rd-root.skeleton.img --cmdline 'rd=md0 ...'`
(the wrapper got a `--ramdisk` pass-through to `mkpayload.py` for this), log in
`logs/qemu/20261113-183753/`:

```
Added memory device md0/rmd0 (01000000/12000000) at FFFFFE00084C800 ... for 0000000002000000
BSD root: md0, major 1, minor 0
hfs: mounted RD-root on device b(1, 0)
load_init_program: attempting to load /sbin/launchd
SWEET EARLY PANIC: unexpected SIGKILL of launchd (CS_KILLED) with reason -- namespace 9 code 0xe
```

So the shape is right: the md driver made md0 from the ADT property, HFS mounted
the image as the root volume, and the kernel reached the exec. The stop is **one
step earlier than dyld** - AMFI's platform check kills launchd with `CS_KILLED`
(namespace 9, 0xe) on this kernel before any dylib is loaded. That is independent
of the ramdisk (the bytes are the pinned ones) and is not a defect of this
image; `0104` takes it (`docs/AMFI_LAUNCHD.md`), and the same cmdline then stops
in dyld with `Library not loaded: /usr/lib/libSystem.B.dylib` - which a cache-less
image cannot get past.

QEMU is not the phone (no UFS, different GIC/timer, `cpu-factor=10`); see
`docs/QEMU_AVICII.md` for what transfers.

Two host-side limits worth knowing:

* `tooling/34-check-bootstrap.sh` cannot be pointed at a *mounted* image: fstool's
  FUSE layer returns ENOENT for `getattr("/")`, so the checker's first `find` and
  its `chdir-root` item fail there. It therefore runs on the staging tree, which
  carries the same relative paths, modes and bytes; the image is checked
  separately by file count, `cmp` of launchd/dyld/etc, link count, `fstool check`
  and `fsck`.
* `chown` on a hard-linked file through fstool writes a second catalog record and
  corrupts the volume (`fsck`: "Incorrect number of file hard links"), and is a
  silent no-op anyway. The 43 cache files therefore keep uid 1000, gid 1000,
  mode 0755 - readable for every user, which is all dyld needs.

## 5. Where this differs from the real 16 GiB root

| aspect | real root (`docs/IOSROOT.md`) | this ramdisk |
|---|---|---|
| storage | `userdata`, HFSX, journaled, 16 GiB | RAM, HFS+, **no journal**, ~3 GiB |
| writability | rw, journaled, survives a reset | writable, but **only in RAM**: `DKIOCISWRITABLE` returns 1 (`bsd/dev/memdev.c:434`), so launchd's writes succeed, and none of them reach flash - every write is gone on the next boot |
| fsck job | `/sbin/fsck` has a real journal to replay, `RequireRun` | unjournaled; `fsck -qy`/`-qL` run and can "repair" the RAM copy, but the next boot starts from the pristine image, so no repair ever survives |
| APFS cryptex graft | `/System/Cryptexes/OS` symlink and `private/preboot/Cryptexes/{OS,App}` tree | no preboot tree, no `System/Cryptexes` symlink; the cache is at its root path instead of being a hard link into a cryptex. `mount -P 1` resolves an APFS boot container and will still complain about a missing data volume |
| device nodes | devfs provides them | the same - devfs is kernel-side, the tree only carries the empty `/dev` |
| job plists | 491 files in `/System/Library/LaunchDaemons` | **none**. launchd's `Boot` table is inline in `/sbin/launchd` `__TEXT,__config`, so the boot tasks run without a plist; every other daemon is absent and never scanned |
| dyld cache | 44 files incl. `.symbols`, hard links from the cryptex | 43 files, `.symbols` out, hard links from `private/var/db/.rdcache` |
| cache owner | `root:wheel` | `1000:1000` 0755 (fstool limit, section 4) |
| `/private/etc/fstab` | `/dev/ufsroot0 /private/var hfs rw 0 2` | `/dev/md0 /private/var hfs ro 0 2` - `/private/var` is already on this volume, `ro` matches the medium. Whether HFS accepts a second mount of the same device, and whether `hfs` passes `mount -P`'s `-t nonfs` allow list, are the two things only a boot settles |
| boot payload | root read from flash, small boot image | image **inside** the boot image; `max-download-size` matters |
| what it is for | the configuration that stays | a scaffold for the first `exec launchd`; delete it once `userdata` boots |

A boot job table entry that cannot resolve even on the real volume is worth
naming here: `restore-datapartition` (`/usr/libexec/HorizonSetup`) and
`darwinos-boot-task` (`/usr/libexec/darwinos-boot-task`) do not exist in 20H392 -
they are iOS 17/18 entries in this `launchd`'s table. The ramdisk ships the 21
that do exist; the two are reported missing by nothing, silently.

## 6. Ladder

1. `tooling/61-mkrd-root.sh --no-cache` - 32 MiB; boot it with `rd=md0`.
   Judge the stop line: `devfs_kernel_mount: kernel_mount failed: 2` means the
   image/HFS is wrong; `hfs: mounted <label> on device b(1, 0)` then
   `load_init_program` is the mount side working. Under QEMU the current wall
   comes right after it, at `CS_KILLED` (section 4.1).
2. `tooling/61-mkrd-root.sh` - 2.88 GiB, once the kernel-managed window is over
   3 GiB. With the code-signing gate settled, judge this one at a dyld/cache
   error instead.
3. Then the real volume (`docs/ROOTFS_READY.md`), which is what stays.
