# ROOTFS_READY - populating the root volume, as one root step

State: the volume `build/ios16-root.img` (16 GiB, HFSX, case-sensitive,
journaled, fsck -n clean) exists and is empty. Everything that fills it needs
root and is now a single script, `tooling/33-populate-root.sh`. Run the lines
below in this order; nothing before line 10 is destructive.

## What is verified, and what is not

| step | state | evidence |
|---|---|---|
| apfs-fuse built unprivileged into `tooling/opt/apfs-fuse` | **verified** | `tooling/32-build-apfsfuse.sh --check`: clean clone of `66b86bd`, build, install, mount, unmount |
| apfs-fuse mounts all three DMGs unprivileged | **verified** | 087-86698-044 / 087-86593-047 / 087-86715-047 mounted, `root/` present, no loop device |
| DMG payload measured through apfs-fuse | **verified** | `tooling/33-populate-root.sh --dry-run`: 144 341 files, 11 304 857 126 B |
| hfsplus module loaded on this host | **verified** | `/proc/filesystems` contains `hfsplus`; `modprobe` is still in the script for a host without it |
| hard links on Linux HFS+ | **not run here** | module exports `hfsplus_link`; the script probes and falls back to copies |
| loop mount of the 16 GiB image, rsync, fsck -fy | **not run here** | needs the sudo password; that is what this document is for |
| the image survives a full populate | **not run here** | `--dry-run` reaches the mount, then stops |

Baseline sha256 of the empty image, taken before anything was written:

    21e00f47267c0f986dae16f65971f426780cb2c4eb441fc43318546f3107b5c9  build/ios16-root.img

## Size budget - read before line 10

* Volume: 17 179 869 184 B = 16 GiB exactly, of which 32 MiB is the HFS+ journal.
* On disk now: ~114 MB (sparse). Populating writes real blocks into the host
  file; it does **not** stay 114 MB.
* Payload: 144 341 files / 11 304 857 126 B unique. In HFS+ 4096-byte blocks that
  is 11 772 084 224 B = **10.96 GiB = 68.5 % of the volume**.
* Free afterwards: ~5.03 GiB = 31.5 %. XNU wants roughly 20 % free; this fits.
* If the driver cannot hard-link, the dyld cache (3.36 GiB) is copied instead:
  15.1 GB used = 88 %, ~2 GB free. The script picks the guard for the mode it
  actually probed.
* Catalog cost: 181 700 directory entries, ~36 400 of them hard links, plus
  journal traffic - the 5 % guard covers it.
* Host side: a sparse `.simg` holds only written blocks, ~11.8 GB. Keep 13 GB
  free next to `build/` (461 GB are available).

## Before you start - no root

1. `tooling/00-check-host.sh`

   All lines must say `ok`. Anything else: `sudo tooling/00-host-deps.sh`.

2. `tooling/32-build-apfsfuse.sh --check`

   Last line must be `check: unmounted cleanly`. Re-runnable; it keeps an
   existing binary.

3. `tooling/33-populate-root.sh --dry-run`

   Must end on `measured payload matches the pinned constants within 2 %` and
   must not print `warning:`.

## Gate

4. `cd build`

5. `sha256sum -c ios16-root.img.sha256.pre-populate`

   `ios16-root.img: OK`. A mismatch means the image is not the proven one - rerun
   `tooling/31-mkiosroot.sh --phase-image build/ipsw-x build/ios16-root.img 16G`
   after deleting the old file, and refresh the baseline.

6. `xxd -s 1024 -l 2 -p ios16-root.img`

   Must print `4858` (HFSX).

7. `/usr/sbin/fsck.hfsplus -n ios16-root.img | tail -1`

   Must print `** The volume iOSRoot appears to be OK.`

8. `df -B1 --output=avail . | tail -1`

   Must be more than `13000000000`.

9. `cd ..`

## Populate - destructive from here

10. `sudo tooling/33-populate-root.sh --simg`

    Stages in order: `os`, `sysos`, `appos` (rsync), `dyld`, `cryptexlinks`,
    `logdirs`, `keybag`, `tweaks`, then unmount, `fsck -fy`, `fsck -n`, hash.
    Roughly 15-40 min (50 MB/s measured through one FUSE stream, plus 181 700
    file creations). Expect `volume ... need ...` before the first copy and
    `files 181xxx` before the unmount.

    Progress is recorded in `build/ios16-root.img.populate-state`, one `stage=`
    line per finished stage. If it stops, just run line 10 again: finished
    stages are skipped and rsync resumes partial files.

11. `sudo tooling/33-populate-root.sh --simg --restart`

    Only if the marker is stale or the image was re-made. Rewrites everything.

12. `sudo tooling/33-populate-root.sh --simg --adopt`

    Only if the volume has content but no marker (deleted `*.populate-state`).

## Verification after the run

13. `/usr/sbin/fsck.hfsplus -f -n build/ios16-root.img`

    Clean, no `** ... needs repair`.

14. `sha256sum build/ios16-root.img`

    Differs from the baseline; compare with `logs/33-populate-*.log` and with the
    block the script appended to `docs/IMAGE_PROVENANCE.md`.

15. `python3 tooling/sparse.py info build/ios16-root.img.simg`

    `total_blks=4194304`, `stored blocks` around 2 870 000, `holes` around
    1 320 000.

16. `python3 tooling/sparse.py decode build/ios16-root.img.simg /var/tmp/simg-check.img`

17. `sha256sum /var/tmp/simg-check.img`

    Must equal line 14 - the sparse form decodes back to the same bytes.

18. `rm -f /var/tmp/simg-check.img`

19. `sudo modprobe hfsplus`

20. `sudo mkdir -p /mnt/iosroot`

21. `sudo mount -t hfsplus -o loop,ro build/ios16-root.img /mnt/iosroot`

22. `sudo ls -l /mnt/iosroot/System/Library/CoreServices/SystemVersion.plist /mnt/iosroot/private/var/keybags/systembag.kb /mnt/iosroot/System/Library/Caches/com.apple.dyld | head`

    The plist is `-r--r--r-- root`, the keybag `-rw------- root`, the dyld
    entries show link count 2.

23. `sudo cat /mnt/iosroot/private/var/db/diagnostics/.migrated`

    Empty, owner `_logd` 272, mode 0644.

24. `sudo find /mnt/iosroot -xdev -type f | wc -l`

    Above 180 000.

25. `sudo df -B1 --output=used /mnt/iosroot`

    Between 11 and 13 GB. Much less means a stage was skipped.

26. `sudo umount /mnt/iosroot`

## Flashing gate

27. `tooling/opt/platform-tools/fastboot getvar partition-size:userdata`

    Must be at least `0x400000000` (16 GiB). The volume does not shrink.

28. `fastboot flash userdata build/ios16-root.img.simg`

29. `tooling/43-hash-images.sh build` - paste the block for the flashed files into
    `docs/IMAGE_PROVENANCE.md` if the script's own block is not enough.

## If it stops

| message | meaning |
|---|---|
| `needs root` | line 10 without `sudo` |
| `marker belongs to ... unknown - use --restart` | image re-made, marker stale |
| `volume too small: ... < ... needed` | image smaller than the payload; re-make at 16G |
| `this hfsplus driver cannot hard-link` | warning, not fatal; check the free space afterwards |
| `no dyld cache at ...` | the `sysos` stage was skipped or truncated; `--restart` |
| `fsck is not clean` | let it stop; do not flash. Re-run to repeat `fsck -fy` |

## Limits of this document

The sudo password was not available on the build host, so lines 10-29 are
unexecuted here. Line ordering, guards and resume behaviour were exercised up to
the loop mount by `--dry-run`; the mount, rsync, tweaks and fsck are the
remainder.
