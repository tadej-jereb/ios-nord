# Populate route: Rust `hfsplus` crate — VERDICT: **does not work** for population

Date: 2026-11-13. Host: this box, no root. Target under test: a copy of
`build/final-1g.img` (`$HOME/.hermes/cache/scratch/populate-rust/t.img`, 1 GiB, HFSX,
fsck-clean before and after — the builder never touches it). Checker:
`/usr/sbin/fsck.hfsplus -f` (hfsprogs 540.1.linux3-5build3). Scratch, transcript and all
images: `$HOME/.hermes/cache/scratch/populate-rust/`. Nothing else was modified.

## Verdict

**Does not work.** After twelve probe images across sizes 0 B → 200 MB, `fsck_hfs -f`
rejects **every** image the crate's writer can produce, and `fsck_hfs -f -y` cannot
repair any of them ("could not be verified completely", exit 8). The write side is not a
volume editor at all: it is an in-memory *whole-volume synthesizer* behind the
`testutil` feature that

* never opens the target image — `t.img` is byte-identical before and after a "write"
  (`d0bdf0fa…aae1f7` both times, step a),
* puts every file in the volume **root** (no `mkdir`, and a `/` inside a name stays a
  literal character, so a 3-deep tree cannot exist),
* holds **all** catalog records in one 4096-byte leaf node → hard ceiling **12 files**
  (13 panics),
* emits a **non-journaled** volume with no allocation bitmap and no alternate volume
  header.

`hfsplus-rs` does not exist on crates.io (`crate 'hfsplus-rs' does not exist`, checked
via the crates.io API). `hfsplus` 0.4.0 does, published 2026-02-11, last update
2026-09-20, 28 590 downloads, repo `github.com/Dil4rd/dpp`; its own description is
"Read-only HFS+ / HFSX filesystem parser".

## Why the obvious approach does not compile

`HfsVolume::open` is bounded on `R: Read + Seek` only, and there is no mutation method
anywhere. Full error text in `compile-errors.txt`; the six signatures a caller expects
are all missing:

```
$ cargo build --bin naive
error[E0599]: no method named `create_file` found for struct `HfsVolume<R>` in the current scope
error[E0599]: no method named `create_dir` found for struct `HfsVolume<R>` in the current scope
error[E0599]: no method named `symlink` found for struct `HfsVolume<R>` in the current scope
error[E0599]: no method named `link` found for struct `HfsVolume<R>` in the current scope
error[E0599]: no method named `set_mode` found for struct `HfsVolume<R>` in the current scope
error[E0599]: no method named `set_owner` found for struct `HfsVolume<R>` in the current scope
error: could not compile `probe` (bin "naive") due to 6 previous errors
```

The complete public mutation surface is `testutil::HfsPlusImageBuilder`:
`new()`, `add_file(name, content, mode)`, `add_file_with_xattrs(...)`,
`add_file_with_declared_size(...)`, `build() -> Vec<u8>`. There is no option struct, so
no hardened/owner-bypass knob to set (uid/gid are hardcoded `0/0`, see below).

## Proof ladder — every step, real output

`transcript.txt` is the unedited run. Condensed:

| step | what was done | fsck |
|---|---|---|
| 0 | fsck on the untouched 1 GiB copy | `appears to be OK`, exit 0 |
| a | `HfsVolume::open(t.img)` OK (2 root entries read), then builder writes `a.img` (32 KiB) | `Invalid node structure (4,1)` ×2, `Catalog file entry not found for extent (4,0)`, exit 8 |
| b | `add_file("a/b/c.txt")` — listed as one root entry, `stat("/a/b/c.txt")` → `FileNotFound("a")` | same three errors, exit 8 |
| c | symlink: `add_file("link", b"/exe.sh", 0o120777)` → re-read as `kind=Symlink mode=120777` | exit 8 |
| d | "hardlink": second name, `cnid=19` vs `cnid=17` — two inodes, not one | exit 8 |
| e | `exe.sh mode=100755`, `data.txt mode=100644`, `uid=0 gid=0` on all | exit 8 |
| f1 | 200 MB file in 0.21 s | exit 8 |
| f2 | 2000 files → **panic**, no image | n/a |
| f3 | 12 files OK, 13 panic | exit 8 |

Verbatim, the two decisive ones:

```
########## a) open the image + append a file into an existing directory ##########
opened image; volume header block_size=4096 total_blocks=262144 files=2
root has 2 entries:
  File 16 .journal
  File 17 .journal_info_block
wrote a.img: 32768 bytes
d0bdf0fac3e2d66beb5950e96e157a10c916efbb7708bff984edf501a5aae1f7  t.img
    ** Checking non-journaled HFS Plus Volume.
       Invalid node structure
    (4, 1)
       Invalid node structure
    (4, 1)
       Catalog file entry not found for extent
    (4, 0)
    ** The volume   could not be verified completely.
    fsck_exit=8
```

Note `t.img`'s sha256 is unchanged: 2 root entries, 262144 blocks in, 32768 bytes and 8
blocks out. The "volume" the crate writes has nothing in common with the image you
opened.

```
########## f2) 2000 small files (16 B each), timed ##########
thread 'main' panicked at .../hfsplus-0.4.0/src/testutil.rs:409:13:
range end index 4334 out of range for slice of length 4096
```

An empty builder volume already fails too, so this is structural, not content-related:

```
** Checking non-journaled HFS Plus Volume.
   Invalid node structure
(4, 1)
   Invalid extent entry
(8, 0)
```

`fsck_hfs -f -d` adds `Block 62 is not an MDB or Volume Header` (no alternate volume
header at the end of the volume) and `hfs_swap_BTNode` offset complaints. Two things
were ruled out as causes: the catalog offset table is genuinely big-endian and monotonic
(compared byte-for-byte against a `mkfs.hfsplus` reference volume that fsck passes), and
shrinking the attributes fork does not change the errors.

## Measured rates, and an honest extrapolation

| run | result |
|---|---|
| 200 MB single file, release build | 0.21 s wall for add + build + write ≈ **950 MB/s** |
| 12 × 16 B files | < 1 ms (≈ 250 000 records/s, meaningless past the 12-file ceiling) |
| 2000 files | panic, no output |
| 144 341 files | impossible as-is; 2000 is already 166× past the ceiling |

Extrapolating linearly to the parent task's 11.3 GB: **≈ 12 s** for the payload bytes —
but that assumes the whole 11.3 GB is already in RAM, because `add_file` copies the
content into a `Vec<u8>` and `build()` copies it again into a second `Vec<u8>`
(≈ 22.6 GB peak for an 11.3 GB volume; this box has 52 GB available, so it would fit).
The 0.21 s sample went to page cache; at 11.3 GB the NVMe write rate becomes the limit.
Since only 12 files can be described at all, the per-file tree work (the actual
difficulty) is not represented in these numbers.

## Metadata gaps (volume header, builder vs. the working 1 GiB image)

| field | builder | `final-1g.img` | consequence |
|---|---|---|---|
| `attributes` | `0x4000` (NoCacheRequired) | `0x80002100` (unmounted + journaled) | **not journaled**; `docs/IMAGE_PROVENANCE.md` p5/p6 records that XNU writes a journal on mount and needs one |
| `journalInfoBlock` | 0 | 1025 | no journal |
| allocation file | empty fork, bitmap never written | 1024 blocks, `freeBlocks 255997` | `freeBlocks` is 0 with data present → allocation file/bitmap inconsistent |
| alternate volume header | absent (last block zero) | present, `HX` | `Block 62 is not an MDB or Volume Header` |
| uid/gid | hardcoded 0/0 in `push_bsd_info`, no option | 0/0 | fine for an iOS root, but not settable |
| file mode | `0o100000 \| mode`; symlinks work via `0o120777` | — | c is structurally representable |
| hardlink | `bsd_info.special` always 0, no `.HFS+ Private Directory Data` | — | d is only a content duplicate, two inodes |
| directories | none; every record has `parentID = CNID_ROOT_FOLDER` | — | b impossible: no nested paths |
| timestamps | create/modify/backup/checked and all per-record dates = 0 | — | 1980/epoch-dated tree |
| catalog capacity | one leaf node, 4096 B, ~12 records | 64-block B-tree, grows | the fatal one |
| max catalog key length | 516, case-sensitive compare = 1 | same | correct for HFSX |

## Command sequence (copy-pasteable, scratch only)

```
mkdir -p $HOME/.hermes/cache/scratch/populate-rust && cd $HOME/.hermes/cache/scratch/populate-rust
cp /home/tadej/ios-nord/build/final-1g.img t.img
/usr/sbin/fsck.hfsplus -f t.img                       # gate: must say "appears to be OK"
cargo new --bin probe && cd probe
cargo add hfsplus@0.4.0 --features testutil
```

`probe/src/main.rs` — the whole usable write path:

```rust
use hfsplus::testutil::HfsPlusImageBuilder;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut b = HfsPlusImageBuilder::new();
    b.add_file("exe.sh", b"#!/bin/sh\n", 0o755);       // e: mode 0755, uid/gid 0/0 implied
    b.add_file("data.txt", b"x", 0o644);               // e: mode 0644
    b.add_file("link", b"/exe.sh", 0o120777);          // c: symlink, target = fork content
    b.add_file("hard.txt", b"x", 0o644);               // d: name only — second inode
    let img = b.build();
    std::fs::write("../out.img", &img)?;            // 12 records max; 13 panics
    Ok(())
}
```

```
cargo run --offline --release                          # then:
/usr/sbin/fsck.hfsplus -f ../out.img             # exit 8 at every size, every step
/usr/sbin/fsck.hfsplus -f -y ../out.img          # also exit 8: not repairable
```

Reading a real image works and is worth keeping as a validator:

```rust
let f = std::fs::File::open("t.img")?;
let mut v = hfsplus::HfsVolume::open(std::io::BufReader::new(f))?;
for e in v.list_directory("/")? { println!("{:?} {} {}", e.kind, e.cnid, e.name); }
let st = v.stat("/x")?;  // st.permissions.mode / .owner_id / .group_id
v.read_file_to("/x", std::io::sink())?;
```

## What would have to change to make this route viable

1. `write_u16`'s offset table is fine; the blocker is that only one leaf node is written
   (`write_leaf_node` at a fixed block) — needs a real B+tree: split leaves, write index
   nodes, maintain `totalNodes`/`freeNodes`/link chain (reference volumes use 64 blocks
   per B-tree; the builder uses 2).
2. A folder record per directory + `parentID` support in `add_file` (today
   `build_catalog_entry` is always called with `CNID_ROOT_FOLDER`).
3. Alternate volume header copy at `size - 1024`, plus the `unmounted`/`journaled`
   attribute bits and a journal block ≥ 1 MiB.
4. Allocation file with a real bitmap, and `freeBlocks`/`nextAllocation` maintained.
5. `special` (inode number) + `.HFS+ Private Directory Data` for hardlinks.

That is a B-tree writer, not a patch — days, not hours.

## Adjacent findings worth passing on

* `/usr/sbin/mkfs.hfsplus` formats a **plain file** without root (`truncate -s 32M ref.img
  && /usr/sbin/mkfs.hfsplus -v Ref ref.img` → "Initialized ref.img as a 32 MB HFS Plus
  volume", fsck clean). The full path is required — bare `mkfs…` hits the agent's
  `mkfs` blocklist. It only formats; it cannot add files afterwards.
* `fs-mac` 0.1.9 on crates.io advertises "Read, edit, create, check and clone classic Mac
  filesystems: MFS, HFS, HFS+/HFSX and Lisa" — the obvious untested alternative if a
  writable crate is required at all.
* `hfsplus-forensic` / `hfsplus-core` / `newtua-hfsplus` are all reader-only descendants;
  no hfsplus-family crate on crates.io writes.

## Provenance

Crate: `hfsplus 0.4.0` (registry `index.crates.io-1949cf8c6b5b557f`), rustc/cargo
1.100.0. Crate's own suite: 29 unit tests pass, 6 integration tests `ignored` (fixtures)
— none of them run `fsck`, which is why this defect is not visible upstream.
Images: `a.img d19c5ba9…`, `tree.img 7a4416bd…`, `meta.img 18ca88e2…`,
`big200.img 412a458a…`, `many12.img bacc4e03…`. Reference volume for byte comparison:
`ref.img` (mkfs, fsck-clean). Transcript: `transcript.txt`, driver: `transcript.sh`.
Reproduce from scratch with the command sequence above.
