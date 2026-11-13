# rootrw=1 / ufsrw=1 — review of the writability and root-mount path

Host-only review ahead of the first root-rw boot. Nothing here needs the device; nothing
was flashed. Scope was the code that decides *writable* and *mounts*, i.e. everything that
can fail before the UFS host is even asked to write.

Line numbers are as of the series after the patches named below; the `bsd/sweet_hfs` files
are hfs-627.100.6 (`xnu-avicii/patches/0026-stage-hfs.sh`, commit `31d5ec2`).

## Findings, worst first

### 1. A failed root mount retries forever, with no delay — HIGH

`bsd/kern/bsd_init.c:886` (`while (TRUE)`) … `:913`. `vfs_mountroot()` returns `ENODEV`
for *any* mount failure (`bsd/vfs/vfs_subr.c:1394`), the real filesystem errno is printed
once by `vfs_subr.c:1392` (`hfs_mountroot failed: <errno>`), and then the loop re-runs
`setconf()`/`vfs_mountroot()` at full speed and prints `cannot mount root, errno = 19`
forever. Nothing sleeps, nothing counts, nothing gives up. On this phone there is no fsck
and no recovery volume, so a failed p6 is final — but it also *looks* exactly like a hang,
and the informative line scrolls away within a second. `IOFindBSDRoot` panics on driver
init failure (`iokit/bsddev/IOKitBSDInit.cpp`, patch 0028), so a *driver* fault is
distinguishable; a *mount* fault currently is not.

Patch `0096`: pace the retries 2 s apart, count them, panic after 20 (~40 s) with the
errno in the panic string. Distinct signature, bounded boot time, ring gets a `panic`.

### 2. Writes are bounded only by a GPT entry that is never sanity-checked — HIGH

`bsd/dev/sweet_ufs.c` `ufs_find_partition()` (patch 0028) takes `first`/`last` out of the
partition entry and sets `su.nblocks = last - first + 1`; `strategy()` then derives
`part_bytes` from it and `ufs_write_blocks()` enforces it. Nothing compares `last` with
the header's own `last_usable_lba` (offset 0x30) or its `alternate_lba` (0x20) — the two
fields that say where the disk actually ends. With `ufsrw=1` those bounds now *write*:
hfs puts the alternate volume header 1024 bytes below the **partition** end whenever the
volume is smaller than the partition (`hfs_vfsutils.c:344-370`, and we are exactly in that
case: 16 GiB volume inside 108 196 737 024 B), and flushes it on every mount
(`hfs_vfsops.c:3931`). An over-long or stale entry therefore writes past the partition
into whatever follows it.

Patch `0097`: read `last_usable_lba` from the header block that is already in the bounce
buffer, refuse a partition that ends past it, and log both numbers. Cheap, no extra I/O.

Related, and worth knowing before p6: 0069 puts the persistent console ring in the last
4 MiB + 4 KiB of the *same* partition (`SWEET_LOG_BLOCKS`). HFS's partition alternate
volume header is the last 1024 bytes of the partition, so it lands in the last block of
that ring: each rewrite clobbers the other. Harmless for booting (the primary header at
1024 and the journaled in-volume header at `volume_end - 1024` are what the next mount
reads), but the partition AVH will never be a valid backup header and the ring's final
1024 bytes are unstable. If the ring is ever moved, keep it off the last block.

### 3. Advertised I/O limits are half-missing — MEDIUM

`DKIOCGETMAXSEGMENTCOUNTREAD/WRITE` return 1 (patch 0028), so
`hfs_journal.c:1640-1700` clamps the journal's read *and* write size to one page (16 KiB)
— journal open, replay and `journal_create`'s zero-fill of a multi-hundred-MiB journal all
run at 16 KiB per UTRD. `DKIOCGETBYTECOUNTREAD/WRITE` are unimplemented, `DKIOCGETFEATURES`
returns `ENOTTY` and that is worse than it looks: `vfs_init_io_attributes()`
(`bsd/vfs/vfs_subr.c:4547`) returns early on it, so `mnt_maxreadcnt/mnt_maxwritecnt`,
`mnt_maxsegreadsize`, `mnt_ioscale` and `mnt_ioqueue_depth` are never set for the root at
all. `DKIOCISSOLIDSTATE` is missing too, so `MNTK_SSD` and `HFS_SSD` are never set.

Patch `0098`: features 0 (deliberately *not* FUA/barrier/UNMAP — nothing is claimed that
the CDB layer does not implement), solid-state 1, byte counts = `BOUNCE_SIZE`, segment
counts = `BOUNCE_SIZE / PAGE_SIZE` (= 1 MiB, which `strategy()` splits into 256 KiB PRDT
chunks anyway).

### 4. The mount-time volume-header flush failure is thrown away — MEDIUM

`hfs_vfsutils.c:705-710`: mounting read-write clears `kHFSVolumeUnmountedMask` and calls
`hfs_flushvolumeheader(hfsmp, HFS_FVH_WAIT)` **without looking at the result**. That is
the first write of the boot (journal replay runs earlier, `hfs_vfsutils.c:2626`); if the
write path is broken it is silent until launchd fails, with the volume left looking
clean.

Patch `0099`: keep the flush, print on failure, continue. Mount behaviour unchanged.

### 5. No `DKIOCUNMAP`, so no TRIM and no journal trim — LOW (informational)

`JOURNAL_USE_UNMAP` is only set from `DK_FEATURE_UNMAP` (`hfs_journal.c:1631`), and
`hfs_issue_unmap()` (`VolumeAllocation.c:601`) is the only `DKIOCUNMAP` caller; with the
ioctl unimplemented both the initial TRIM scan and per-transaction journal trimming are
skipped. Correct, just slower and no free-space hygiene. No patch — it is a separate
change with its own failure modes.

### 6. `/sweet-ufs` in the ADT carries no partition name and no sector size — LOW

`avicii/tools/mkadt_avicii.py:363-370` writes `name`, `phandle`, `compatible`, `reg` only.
The partition label comes from boot-arg `ufsroot=` with `"userdata"` hardcoded as the
fallback in the driver, and the LBA unit is the `UFS_BLOCK` constant, never checked against
the device's READ CAPACITY. So nothing in the ADT *can* disagree with the live GPT — and
nothing cross-checks either. They agree today (label `userdata`, 4 KiB LBA: the GPT's
`userdata` first LBA `0x2B8C00` is a 4 KiB unit (`docs/anonbeat1-NOTES.md:867`, which also
records LUN 0 as `0x1D7D800 x 4 KiB`), and p5 already found the partition by
name). Note the note's partition size (109 643 MiB) is larger than the p6 partition
(108 196 737 024 B); the first block is read live, so only the size assumption differs, and
both keep the 16 GiB volume far inside the partition.
`no GPT partition named` / nonsense LBA, not as a clear diagnostic. Note for the doc, no
patch.

## What is fine, and why

* **`rootrw` / `ufsrw` reach the kernel.** The p6 payload cmdline is 144 bytes
  (`… rd=ufsroot0 ufsroot=userdata ufsrw=1 rootrw=1 -v debug=0x144 keepsyms=1`), the header
  holds 607, the shim copies all 608 bytes of `p->cmdline` into a zeroed `boot_args`
  (`avicii/shim/loader.c:375`), and `PE_parse_boot_argn` matches `name=` and stores 1
  (`pexpert/gen/bootargs.c`, `PE_parse_boot_argn_internal`). Hardened anyway:
  `loader.c` now NUL-terminates the field, and `mkpayload.py` refuses a cmdline over 607
  bytes instead of silently cutting it (it used to truncate — the tail of our cmdline is
  where `rootrw=1` lives).
* **Patch 0031 clears `MNT_RDONLY` in time.** `vfs_rootmountalloc_internal` sets
  `MNT_RDONLY | MNT_ROOTFS` (`vfs_subr.c:1147`); 0031 clears the read-only bit right after
  `mp->mnt_devvp = rootvp` and before the `vfc_mountroot` call (`:1251-1258`), nothing
  re-sets it afterwards (`bsd_init.c` only ORs `MNT_ROOTFS`, `:918`), and hfs derives
  `ronly = vfs_isrdonly(mp)` from it (`hfs_vfsops.c:1120`). `MNT_ROOTFS` survives, so the
  dirty-unmount bypass added by 0031 (`hfs_vfsutils.c:202-224`) still keys on the right
  condition. `DKIOCISWRITABLE` — the second gate, `hfs_vfsops.c:1392` — was returning 0
  unconditionally until patch 0030 fixed it to `su.writable`.
* **Nothing clamps writes at the volume end, and nothing needs to.** `strategy()` bounds
  only against `part_bytes`; the 16 GiB volume in a 108 GB partition is the "degenerate"
  case hfs handles explicitly, so writes past the volume end are *required*, not
  tolerated: alternate volume headers go to `part_bytes - 1024` and to
  `volume_end - 1024` (`hfs_vfsutils.c:344-370`). Both stay inside the partition:
  `nblocks * 4096` is 4 KiB aligned by construction, the trailing 1024 bytes live in the
  partition's last 4 KiB block, and the read-modify-write of that block is one LBA inside
  the bounds.
* **The journal math cannot trip the driver.** `jib_offset` is `journalInfoBlock *
  blockSize` inside the volume, `journal_open()` validates size/start/end against
  256 KiB…1 GiB, 512-byte alignment and `phys_blksz <= min_fs_blksz`
  (`hfs_journal.c:1895-1922, 2019-2055`) — never against the volume size, so a stale
  journal lands in partition slack instead of returning `EINVAL`. Replay writes go through
  the same bounded `strategy()`.
* **Mount failure is not a panic loop.** `IOFindBSDRoot` panics only on driver init
  failure (0028); a mount failure returns through `vfs_rootmountfailed()` and the
  `hfs_mountroot failed: <errno>` line is the one to read before the flood.

## Patches

    0096-sweet-mountroot-bounded-retry.patch   bsd/kern/bsd_init.c
    0097-sweet-ufs-gpt-bound-check.patch       bsd/dev/sweet_ufs.c
    0098-sweet-ufs-io-limits.patch             bsd/dev/sweet_ufs.c
    0099-sweet-hfs-vh-flush-error.patch        bsd/sweet_hfs/core/hfs_vfsutils.c

These four sit after 0095 and before 0100 (the write-path plumbing set: retire/retry,
power mode, short transfers, FUA) — 0100-0103 cover the command layer, these cover
bounds, limits and diagnosis, no overlap. Verified in series order over the real
post-0069 file: `0030 → 0034 → 0069 → 0097 → 0098 → 0100 → 0101 → 0102 → 0103` all
`git apply` clean, `check-hunk-counts.py` clean on all 93 patches. Host-side edits, not
patches: `avicii/shim/loader.c` (CommandLine terminator), `avicii/tools/mkpayload.py`
(refuse an over-long cmdline).
