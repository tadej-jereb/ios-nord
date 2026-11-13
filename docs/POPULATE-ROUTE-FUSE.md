# POPULATE-ROUTE-FUSE — an unprivileged FUSE mount as an rsync target

State: **proven on a 1 GiB copy of `build/final-1g.img`; not run on the 16 GiB
image or the full 144 341-file payload.** Every step below was executed as uid
1000, no loop device, no `sudo`, mountpoint under `$HOME/.hermes/cache/scratch/`.

Verdict: **usable as a fallback route, not as the primary one.** The mechanics
the task asks for all work — mount, file, 3-deep tree, symlink, hardlink,
`chmod 0755`, `chown 0:0`, `rsync -aH` with exit 0, clean unmount, `fsck_hfs -f`
returning 0 — but four defects make it slower to trust than a kernel loop mount:

| # | defect | consequence |
|---|---|---|
| 1 | `newfs_hfs -J` on Linux writes a journal-info block and allocates the 8 MiB buffer, but leaves the journal header **zeroed**; the driver refuses such a volume | every image built by `tooling/31-mkiosroot.sh` needs a 12-line header fixup before it can be mounted (script in §2) |
| 2 | a written file larger than ~196 MiB cannot be re-`open()`ed **in the same mount session** (`ENOENT`/`EIO`); the bytes are correct on disk and read fine after a remount | read-back verification inside the populate run fails on the 2 payload files >200 MB and the 21 >100 MB; `rsync --checksum` in the same session is unusable |
| 3 | `chmod`/`chown` on a **hard-linked** name silently no-op (rc 0, no change) | the ~36 400 dyld-cache hard links stay `0664 1000:1000`; nothing can promote them to `0644 0:0` through the mount |
| 4 | the volume is left unclean after part of the unmounts (see §7) | a `fsck_hfs -f` pass after every run is mandatory, not optional |

Two smaller facts: `statfs` is unimplemented so `df` reports 0 bytes free, and
writing until the volume is full returns `EIO` (not `ENOSPC`) and leaks the last
7 allocation blocks.

## 0. Scope and limits

* Image: `build/final-1g.img` (1 GiB, HFSX, journaled flag set, fsck -n clean,
  sha256 `d0bdf0fac3e2d66beb5950e96e157a10c916efbb7708bff984edf501a5aae1f7`),
  copied to `$HOME/.hermes/cache/scratch/populate-fuse/t.img`. The original was
  opened read-only and is unchanged (same sha256 after the run).
* Source tree for rsync: the already-mounted apfs-fuse DMG views at
  `/tmp/pv/{os,sys,app}` (see `docs/ROOTFS_READY.md`), unmodified.
* Not exercised: the 16 GiB volume, the full payload, xattrs/resource forks,
  case-collisions (`Foo`/`foo`), and journal replay by XNU after a panic. Only
  `fsck_hfs` was used as the consistency oracle.

## 1. The driver: why this one

Surveyed and rejected: `0x09/hfsfuse` (read-only, the whole point of the port
is "cannot write"), `darlinghq/darling-dmg` (read-only by design),
`pgiffuni/HFSplus` (FUSE over read-only libhfsp, unmaintained). The only
candidate with a *writable* HFS+/HFSX backend plus a FUSE front end is
`KarpelesLab/fstool` (Rust, `--features fuse`, HFS+ write with a real journal
on the read/write path, self-documented as `fsck.hfsplus`-clean).

The host has no `cargo`, and fstool pulls several hundred crates, so the run used
the tree's already-built binary rather than a fresh build:

    /home/tadej/ios-nord/tooling/opt/fstool/bin/fstool --version
    # fstool 0.5.4
    sha256sum tooling/opt/fstool/bin/fstool
    # 45edb6ce82019a7848f670b84b8626e0806c4f1427bd462479dd9c39795b4558
    sha256sum tooling/opt/fstool/fstool-0.5.4-unpriv.patch
    # c706016d65ce2ea9c498630f729ef457b045eb95bbd808ba91d108d578cd037c
    pkg-config --modversion fuse3          # 3.14.0 (headers present, no package install needed)
    ls -l /dev/fuse                        # crw-rw-rw- root root — writable by uid 1000

That binary is upstream 0.5.4 with `fstool-0.5.4-unpriv.patch`: `allow_other`
off unless `FSTOOL_ALLOW_OTHER` is set (no `/etc/fuse.conf` edit), pending-record
lookup ahead of the on-disk B-tree, and `eprintln!` on failed `setattr`/`mkdir`/
`hardlink`. Rebuild command, if a fresh one is ever needed (needs rustup, not
present here):

    cd tooling/opt/fstool && git clone https://github.com/KarpelesLab/fstool src
    cd src && git checkout 1a1bd02 && git apply ../../fstool-0.5.4-unpriv.patch
    cargo build --release --features fuse && install -m755 target/release/fstool ../bin/fstool

## 2. Prerequisite: the image has no journal header

`tooling/31-mkiosroot.sh` calls `newfs_hfs -s -J`. On Linux `newfs_hfs`
allocates the journal-info block (block 1025) and an 8 MiB buffer at block 1026,
sets the journaled volume attribute — and never writes the `JNLx` header macOS
writes. Measured on both the 1 GiB and the 16 GiB image:

    python3 - <<'EOF'
    import struct
    fh=open('build/final-1g.img','rb'); fh.seek(1025*4096); i=fh.read(52)
    print(struct.unpack('>QQ', i[36:52]))     # (4202496, 8388608)  — buffer is allocated
    fh.seek(4202496); print(fh.read(16).hex()) # 00000000...        — header is zeroed
    EOF

Mounting such a volume dies before the first syscall:

    fstool mount t.img mnt/test1
    # fstool: invalid image: hfs+ journal: unrecognised header magic/endian (0x00000000/0x00000000)

The Linux kernel `hfsplus` driver tolerates this; fstool does not. Fix: write the
header fstool's own formatter emits (empty ring, `start == end == 512`,
big-endian, sequence 1, checksum over the first 44 bytes with the checksum field
zeroed). Script kept at `$HOME/.hermes/cache/scratch/populate-fuse/jfix.py`;
inline copy:

    python3 - <<'EOF'
    import struct, sys
    MAGIC, ENDIAN, JHDR, BLHDR = 0x4A4E4C78, 0x12345678, 512, 8192
    def ck(b):
        c = 0
        for x in b: c = ((c << 8) ^ ((c + x) & 0xFFFFFFFF)) & 0xFFFFFFFF
        return (~c) & 0xFFFFFFFF
    p = sys.argv[1]; f = open(p, 'r+b'); f.seek(1024); vh = f.read(512)
    bs, = struct.unpack('>I', vh[40:44]); jib, = struct.unpack('>I', vh[12:16])
    f.seek(jib * bs); off, size = struct.unpack('>QQ', f.read(52)[36:52])
    f.seek(off)
    if f.read(4) == struct.pack('>I', MAGIC): sys.exit(0)
    b = bytearray(512)
    struct.pack_into('>IIQQQI', b, 0, MAGIC, ENDIAN, JHDR, JHDR, size, BLHDR)
    struct.pack_into('>II', b, 40, JHDR, 1)          # jhdr_size, sequence_num
    struct.pack_into('>I', b, 36, ck(bytes(b[:44]))) # checksum last
    f.seek(off); f.write(b)
    EOF

(on a copy: `python3 - IMG < the block above`, or `sys.argv[1]` as written)

Result on the copy (`fsck -n` still clean, one-off repair on the first
`fsck -f` afterwards, clean on every subsequent cycle), and the patched copy
mounts and takes a write:

    python3 jfix.py t.img
    # t.img: journal header at 4202496 (size 8388608) written, cksum 0x871848e9
    /usr/sbin/fsck.hfsplus -n t.img | tail -1
    # ** The volume iOSRoot appears to be OK.

## 3. Mount and unmount

    cd $HOME/.hermes/cache/scratch/populate-fuse
    mkdir -p mnt/test1
    fstool mount t.img mnt/test1 &        # stays attached; AutoUnmount on process exit
    grep populate-fuse /proc/self/mounts
    # hfs+ /home/.../mnt/test1 fuse rw,nosuid,nodev,relatime,user_id=1000,group_id=1000 0 0
    ...
    umount mnt/test1                      # rc 0, clean detach

`umount` (util-linux) works unprivileged and is what to use; `fusermount3 -u`
fails here because `/etc/mtab` is a symlink to `/proc/self/mounts` and the entry
is already gone by the time it looks. There is no `allow_other`, so only uid
1000 can use the mount.

## 4. Evidence, in the order the task asked

(a) mount, unprivileged, mountpoint under scratch: **pass** — output in §3, table
shows `rw`, `user_id=1000`.

(b) file, 3-deep tree, symlink, hardlink: **pass**

    echo hello > f1.txt ; mkdir -p d1/d2/d3 ; ln -s ../f1.txt d1/link ; ln f1.txt hard.txt
    # all rc 0
    stat -c '%A %h %n' d1/link
    # lrwxrwxrwx 1 d1/link
    readlink d1/link
    # ../f1.txt

The hardlink is a real HFS+ one, not a copy: second name gets its own catalog
record and the data lives in `HFS+ Private Data` (the macOS inode mechanism),
`st_nlink` 2 on both names.

(c) mode 0755 and ownership 0:0: **pass for plain names, fail for hard links**

    chmod 0755 d1 ; chown 0:0 g.txt ; chown -h 0:0 sl2
    stat -c '%A %u:%g %h %n' d1 g.txt sl2
    # drwxr-xr-x 0:0 2 d1        -rw-rw-r-- 0:0 1 g.txt        lrwxrwxrwx 0:0 sl2
    # values survive unmount and are re-read from disk after remount
    chown 0:0 f1.txt ; stat -c '%u:%g' f1.txt
    # rc 0, still 1000:1000
    chmod 0644 hldst/a ; stat -c '%A' hldst/a hldst/b
    # -rw-rw-r-- on both — unchanged (was 0664)

(d) rsync of real files from the apfs-fuse DMG view: **pass**

    rsync -aH --numeric-ids /tmp/pv/os/root/usr/libexec/ mnt/test1/rs3/
    # rc 0; stats: 383 files (337 reg, 45 dir, 1 link), 210 303 389 B literal
    find mnt/test1/rs3 -type f | wc -l   # 337
    find mnt/test1/rs3 -type l | wc -l   # 1
    md5sum .../rs3/addressbooksyncd + 25 more files vs source   # 26/26 match
    rsync -aH --numeric-ids hlsrc/ mnt/test1/hldst/ ; stat -c %h mnt/test1/hldst/*
    # 2 2 — rsync -H does create links, not copies

Mode 0755 and mtime survive rsync; ownership does not without a second pass,
because rsync as non-root does not chown at all (`cp -a` does — see §6).

(e) unmount + `fsck_hfs -f`: **pass in the sense that the driver is fixable, but
4 of 7 unmounts left the volume unclean** — see §7.

(f) 200 MB and 2000 small files, timed: **run**

    200 MiB single file via cp                 9.5 s   22.1 MB/s
    2000 files, 25 B each, open+write+close   28.0 s   71.3 files/s
    (immediate read-back of that 200 MiB file failed EIO in-session — defect 2;
     `fstool cat` of the same file md5-matched the source)

Extrapolation is in §5.

## 5. Rates and extrapolation

Measured, wall clock, on this host:

| workload | result | rate |
|---|---|---|
| 200 MiB single file, `cp` | 9.5 s | 22.1 MB/s |
| 2000 files, 25 B each, open+write+close | 28.0 s | 71.3 files/s |
| 337 real files / 210 MB, `rsync -aH` | 20.7 s | 10.2 MB/s, 16.3 files/s |
| 334 MB real dyld file, `rsync -a` | wrote fine, size exact, read-back EIO in session | ~22 MB/s |

Model from the mixed rsync (data at 22.1 MB/s leaves 0.0331 s of per-file
overhead): 11 304 857 126 B / 22.1 MB/s = 512 s of data, 144 341 × 0.0331 s =
4777 s of per-file work → **≈ 88 min**, plus a full `chown -R 0:0` pass at the
small-file rate (≈ 34 min) → **≈ 2 h**, call it 1.5–2.5 h with variance. File
count, not bytes, is the cost driver: the pure data bound is 8.5 min and the
pure per-file bound is 34 min. All of this is ~2–3× a kernel loop mount.

Two extra costs the numbers do not show: every metadata change is journalled, so
bytes are written twice (8 MiB ring, ~1.7 M transactions for the full payload),
and re-reading the tree for the chown pass re-opens all 144 341 files — where
defect 2 bites on the >196 MiB ones until a remount.

## 6. Metadata gaps

* **Ownership needs a second pass.** `rsync -a` as uid 1000 copies mode and mtime
  but leaves uid/gid at 1000:1000 (`rsync` skips chown when not root). Explicit
  `chown -R 0:0` afterwards works — except on hard links.
* **Hard links cannot take mode or owner** (defect 3). Both names keep what
  `create` gave them: `0664 1000:1000`. Affects the 36 400 dyld-cache entries.
* **Symlink mode is stuck at 0777** (source has 0755; `symlink()` carries no mode
  and Linux has no `chmod -h`). Owner can be set with `chown -h`.
* **Case sensitivity** was not exercised: the volume is HFSX, but name collisions
  (`libFoo` vs `libfoo` in one directory) were never put through the driver.
* **xattrs / resource forks** were not carried (the DMG view is read; `rsync -X`
  was not used). fstool claims both; unproven here.
* **`statfs` is unimplemented** — `df` on the mount prints `0 0 0`. Free space has
  to be read out of band (`fstool check IMAGE` prints free blocks).
* **No `allow_other`**: fine for a single-process rsync, breaks anything that
  drops privileges.

## 7. Stability

* Four mounts, ~25 min of mixed load, no wedge, no crash, no lost file. One
  chained agent-side invocation (`echo > file && sync && umount` inside a
  `bash -lic` wrapper) appeared to sit for minutes without creating the file;
  the same write from a plain `sh -c` completed immediately and the mount stayed
  usable, so it is the harness shell, not the driver. Nothing was lost either
  time.
* **Defect 2**: any file above ~196 MiB written in the current session cannot be
  reopened — `open(2)` returns `ENOENT` (strace) and the shell shows `EIO`. The
  bytes are on disk and complete: `fstool cat IMAGE /big/file | md5sum` matched
  the source, and after unmount + `fsck -f` + remount the same `md5sum` matched
  through the mount. The threshold is not sharp (196 MiB failed while 200 and
  204 MiB in the same batch passed), so it is a race/fragmentation effect in the
  extent-overflow path, not a size cut-off.
* **Unclean unmounts.** `fsck -f` after each cycle: repair after the first mount
  with the hand-written journal header (expected), then repair after a run with
  337 files + 200 MB of big-file churn, clean, repair after 2000 unlinks plus
  more big files, repair after `kill -9`, clean after two metadata-only cycles.
  Findings were always benign and always repairable with rc 0:

      Unused node is not erased (node = 191)
      Volume bitmap needs minor repair for orphaned blocks
      Invalid volume free block count (It should be 204454 instead of 204448)

  Never a catalog or B-tree structure error, never a lost or truncated file. No
  `fsck_hfs -f` run ever returned non-zero: it fixes the volume and reports
  `repaired successfully`.
* **Running out of space** returns `EIO` on write, not `ENOSPC`, leaves a
  partially written file, and leaks blocks 262137–262143 (the last 7). On 16 GiB
  with ~5 GB spare this should only matter at the very end.
* **`kill -9` of the daemon** leaves a stale FUSE entry (`ls` → `ENOENT`, entry
  still in `/proc/self/mounts`); plain `umount MOUNTPOINT` clears it. The volume
  then needs `fsck -f` before reuse.
* Deleted files free their blocks only on unmount, so `fstool check` while
  mounted under-reports free space.

## 8. What this does not prove

The 16 GiB image, the 144 341-file payload, `--checksum` verification in one
session, journal replay by XNU after a panic, xattrs, case collisions. The
volume used here is the 1 GiB `final-1g.img`, single-filesystem, and every
number above is from a machine whose page cache is warm and unloaded.
