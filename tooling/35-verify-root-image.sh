#!/bin/bash
# 35-verify-root-image.sh - independent, unprivileged validation of a POPULATED
# HFSX root image against the reference tree it was populated from.
#
#   tooling/35-verify-root-image.sh IMAGE REFERENCE [options]
#
#   IMAGE       the built image (build/ios16-root.img). Read, never written.
#   REFERENCE   extracted copy of the iOS root the image should hold
#               (rsync of the three DMG mounts). Read, never written.
#
#   --ref-mount DIR  ownership overlay: for every reference path that also
#               exists under DIR, take uid/gid/mode/size from DIR instead of
#               from the extracted tree. An unprivileged extraction cannot
#               carry ownership, a live apfs-fuse mount can, so this is how
#               uid/gid becomes comparable.
#   --expect-files N    absolute assertion on the file count (e.g. 144341)
#   --expect-bytes N    absolute assertion on the total payload bytes
#   --limit N   offenders listed per class (default 5)
#   --keep      keep the raw inventories under $TMP, print the paths
#   --no-fsck   skip the fsck gate (reported as skipped)
#   --reader P  use an existing hfsinv binary instead of building one
#   -h|--help   this text
#
# The reader is built once, unprivileged, from the hfsplus Rust crate already
# in the local cargo registry, into $HOME/.hermes/cache/scratch/populate-verify
# (needs cargo once, --reader skips it). It reads only through the crate, so
# nothing mounts the image, nothing calls sudo, no writer byte is reused, and
# the verdict does not depend on the mount the populator produced.
#
# Classes, each with a reference side, an image side, a verdict and the first
# --limit offenders:
#   fsck            /usr/sbin/fsck.hfsplus -f -n must exit 0 ("appears to be OK")
#   volume          HFSX signature, unmounted bit, inconsistent bit, block size
#   missing/extra   path sets, excluding /.journal* and "HFS+ Private Data"
#   file count, bytes, symlink count
#   symlink target  byte-equal to the reference
#   mode            every path, plus requiring bits on the critical paths
#                   (/sbin/launchd, /usr/lib/dyld, /System/Library/dyld/*,
#                   /private/etc/*)
#   owner           uid and gid equal to the reference
#   hardlink        group path sets, inode record present, inode record
#                   metadata, and inode link count == group size. The link
#                   records' own mode/owner are reported, not gated: the inode
#                   record is what a mount reports.
#
# Exit status: 0 pass, 1 mismatch, 2 volume gate failed (fsck unclean, not
# HFSX, dirty or inconsistent), 3 image unreadable or no reader, 64 usage
# (including a path that is not a regular file).
#
# Deliberately NOT checked: file contents beyond size (no hashes), mtimes,
# Finder info, xattrs, ACLs, resource forks, decmpfs compression, journal and
# private-directory internals, directory sizes, catalog/extents consistency
# beyond fsck, and mountability at runtime. Ownership is only as good as the
# reference: a tree extracted unprivileged is itself 1000-owned, so pass
# --ref-mount or the owner class compares 1000 against 1000 and proves little.
set -uo pipefail

PROG=$(basename "$0")
HERE=$(cd -- "$(dirname -- "$0")" && pwd)
REPO=$(cd -- "$HERE/.." && pwd)
FSCK=/usr/sbin/fsck.hfsplus
SUITE=${VERIFY_SUITE:-$HOME/.hermes/cache/scratch/populate-verify}
CRATE_VER=0.4.0
BIN=$SUITE/bin/hfsinv-$CRATE_VER

img=""
ref=""
ref_mount=""
limit=5
do_fsck=1
keep=0
expect_files=""
expect_bytes=""

usage() { sed -n '2,55p' "$0" | sed 's/^# \{0,1\}//'; exit 64; }
say() { printf '%s\n' "$*"; }
note() { printf '  note: %s\n' "$*"; }
die() { printf '%s: %s\n' "$PROG" "$*" >&2; exit "${2:-64}"; }

while (($#)); do
	case $1 in
	--ref-mount) ref_mount=${2:-}; shift 2 || usage ;;
	--expect-files) expect_files=${2:-}; shift 2 || usage ;;
	--expect-bytes) expect_bytes=${2:-}; shift 2 || usage ;;
	--limit) limit=${2:-}; shift 2 || usage ;;
	--keep) keep=1; shift ;;
	--no-fsck) do_fsck=0; shift ;;
	--reader) BIN=${2:-}; shift 2 || usage ;;
	-h | --help) usage ;;
	-*) printf '%s: unknown option %s\n' "$PROG" "$1" >&2; usage ;;
	*)
		if [[ -z $img ]]; then img=$1
		elif [[ -z $ref ]]; then ref=$1
		else printf '%s: one IMAGE and one REFERENCE only\n' "$PROG" >&2; usage
		fi
		shift ;;
	esac
done
[[ -n $img && -n $ref ]] || usage
[[ -f $img ]] || die "not a file: $img" 64
[[ -r $img ]] || die "cannot read: $img (unprivileged reader, no root needed)" 3
[[ -d $ref ]] || die "not a directory: $ref" 64
[[ -z $ref_mount || -d $ref_mount ]] || die "no such overlay: $ref_mount" 64
[[ $limit =~ ^[0-9]+$ ]] || die "--limit wants a number" 64
img=$(cd "$(dirname "$img")" && pwd)/$(basename "$img")
ref=$(cd "$ref" && pwd)
[[ -n $ref_mount ]] && ref_mount=$(cd "$ref_mount" && pwd)
[[ -s $img ]] || { say "FAIL  volume  image is empty (0 bytes)"; exit 2; }

# --- reader ----------------------------------------------------------------
# Built once into the scratch suite: the crate from the local cargo registry,
# plus the patch that exposes the two hard link fields its public API drops
# (fdType and the BSD "special" word). Rebuilt when the binary is gone.
build_reader() {
	command -v cargo >/dev/null || die "no cargo, cannot build the reader (or pass --reader)" 3
	local src
	src=$(ls -d "$HOME"/.cargo/registry/src/*/hfsplus-"$CRATE_VER" 2>/dev/null | head -1)
	[[ -n $src ]] || die "hfsplus $CRATE_VER missing from the cargo registry" 3
	local b=$SUITE/build
	rm -rf "$b"
	mkdir -p "$b"
	cp -r "$src" "$b/hfsplus" || die "cannot copy the crate" 3
	chmod -R u+w "$b/hfsplus"
	cat >"$b/reader.patch" <<-'EOF'
	--- a/src/catalog.rs
	+++ b/src/catalog.rs
	@@ -44,6 +44,8 @@
	     pub access_date: u32,
	     pub backup_date: u32,
	     pub permissions: HfsPlusBsdInfo,
	+    /// Finder `fdType`; `hlnk` marks an HFS+ hard link record.
	+    pub fd_type: u32,
	     pub data_fork: ForkData,
	     pub resource_fork: ForkData,
	     pub text_encoding: u32,
	@@ -217,8 +219,10 @@
	             let access_date = cursor.read_u32::<BigEndian>()?;
	             let backup_date = cursor.read_u32::<BigEndian>()?;
	             let permissions = parse_bsd_info(&mut cursor)?;
	-            // Skip user info (16 bytes) and finder info (16 bytes)
	-            let mut _skip = [0u8; 32];
	+            // Finder user info: fdType, then 12 more bytes we do not need,
	+            // then 16 bytes of finder info.
	+            let fd_type = cursor.read_u32::<BigEndian>()?;
	+            let mut _skip = [0u8; 28];
	             cursor.read_exact(&mut _skip)?;
	             let text_encoding = cursor.read_u32::<BigEndian>()?;
	             let _reserved2 = cursor.read_u32::<BigEndian>()?;
	@@ -233,6 +237,7 @@
	                 access_date,
	                 backup_date,
	                 permissions,
	+                fd_type,
	                 data_fork,
	                 resource_fork,
	                 text_encoding,
	--- a/src/lib.rs
	+++ b/src/lib.rs
	@@ -65,6 +65,11 @@
	     pub create_date: u32,
	     pub modify_date: u32,
	     pub permissions: HfsPermissions,
	+    /// HFS+ hard link machinery: `fd_type` is `hlnk` on a link record;
	+    /// on one, `special` is the CNID of the inode, on the inode it is the
	+    /// link count. `special` is 0 for ordinary files.
	+    pub fd_type: u32,
	+    pub special: u32,
	     pub data_fork_extents: u32,
	     pub resource_fork_size: u64,
	     /// Present when the file is transparently compressed. `size` above is then
	@@ -411,6 +416,8 @@
	                         group_id: f.permissions.group_id,
	                         mode: f.permissions.file_mode,
	                     },
	+                    fd_type: f.fd_type,
	+                    special: f.permissions.special,
	                     data_fork_extents: f
	                         .data_fork
	                         .extents
	@@ -432,6 +439,8 @@
	                     group_id: f.permissions.group_id,
	                     mode: f.permissions.file_mode,
	                 },
	+                fd_type: 0,
	+                special: 0,
	                 data_fork_extents: 0,
	                 resource_fork_size: 0,
	                 compression: None,
	EOF
	patch -p1 --batch --forward --quiet -d "$b/hfsplus" <"$b/reader.patch" ||
		die "cannot patch the reader crate" 3
	cat >"$b/Cargo.toml" <<-'EOF'
		[package]
		name = "hfsinv"
		version = "0.1.0"
		edition = "2021"

		[dependencies]
		hfsplus = { path = "hfsplus" }

		[profile.release]
		opt-level = 2
	EOF
	mkdir -p "$b/src"
	cat >"$b/src/main.rs" <<-'EOF'
			// hfsinv - dump an HFSX/HFS+ volume inventory straight from the image bytes.
	//
	// Reads through the hfsplus crate only: no mount(8), no FUSE, no root, and no
	// code shared with the writer, so nothing the writer believes is trusted.
	// Writes TSV to stdout; names and symlink targets are backslash-escaped
	// (\t \n \r \\ \xNN). Records:
	//   VOL  sig is_hfsx attrs block_size total_blocks free_blocks files folders
	//   T    hl mode uid gid nlink size cnid inode path [target]
	//        T is F S C B P ? for files, D for dirs, L for symlinks; hl=1 marks an
	//        HFS+ hard link record (path shares `inode` with its siblings);
	//        on a normal file nlink is the inode's link count, on a link record 0.
	//   ERR  path reason
	//   END  files dirs symlinks hardlink_records bytes
	use hfsplus::EntryKind;
	use std::fs::File;
	use std::io::{BufReader, Write};

	const HLNK: u32 = 0x686c_6e6b; // 'hlnk'

	fn esc(s: &[u8]) -> String {
	    let mut o = String::new();
	    for &b in s {
	        match b {
	            b'\\' => o.push_str("\\\\"),
	            b'\t' => o.push_str("\\t"),
	            b'\n' => o.push_str("\\n"),
	            b'\r' => o.push_str("\\r"),
	            0x20..=0x7e => o.push(b as char),
	            _ => o.push_str(&format!("\\x{b:02x}")),
	        }
	    }
	    o
	}

	fn main() {
	    let img = std::env::args().nth(1).unwrap_or_else(|| {
	        eprintln!("usage: hfsinv IMAGE");
	        std::process::exit(64);
	    });
	    let f = match File::open(&img) {
	        Ok(f) => f,
	        Err(e) => {
	            // Still a machine-readable line: the caller separates "no such
	            // file" from "not a volume".
	            println!("FATAL\topen: {e}");
	            std::process::exit(3);
	        }
	    };
	    let mut v = match hfsplus::HfsVolume::open(BufReader::new(f)) {
	        Ok(v) => v,
	        Err(e) => {
	            println!("FATAL\t{e}");
	            std::process::exit(3);
	        }
	    };
	    let h = v.volume_header().clone();
	    let out = std::io::stdout();
	    let mut out = out.lock();
	    let _ = writeln!(
	        out,
	        "VOL\t{:04x}\t{}\t{:08x}\t{}\t{}\t{}\t{}\t{}",
	        h.signature, h.is_hfsx, h.attributes, h.block_size, h.total_blocks, h.free_blocks,
	        h.file_count, h.folder_count
	    );
	    // An empty but valid volume walks fine and yields nothing; a walk failure
	    // on a volume that opened is structural damage, reported as FATAL.
	    let entries = match v.walk() {
	        Ok(e) => e,
	        Err(e) => {
	            let _ = writeln!(out, "FATAL\twalk: {e}");
	            std::process::exit(3);
	        }
	    };
	    let (mut files, mut dirs, mut symlinks, mut hls, mut bytes) = (0u64, 0u64, 0u64, 0u64, 0u64);
	    for e in &entries {
	        let st = match v.stat(&e.path) {
	            Ok(s) => s,
	            Err(err) => {
	                let _ = writeln!(out, "ERR\t{}\tstat: {err}", esc(e.path.as_bytes()));
	                continue;
	            }
	        };
	        let p = &st.permissions;
	        let is_hl = st.fd_type == HLNK;
	        if is_hl {
	            hls += 1;
	        }
	        let (t, inode, nlink, size) = match e.entry.kind {
	            EntryKind::Directory => {
	                dirs += 1;
	                ('D', st.cnid, 0u32, 0u64)
	            }
	            EntryKind::Symlink => {
	                symlinks += 1;
	                ('L', if is_hl { st.special } else { st.cnid }, 0u32, st.size)
	            }
	            EntryKind::File => {
	                files += 1;
	                bytes += st.size;
	                let t = match p.mode & 0o170000 {
	                    0o140000 => 'S',
	                    0o020000 => 'C',
	                    0o060000 => 'B',
	                    0o010000 => 'P',
	                    _ => 'F',
	                };
	                let inode = if is_hl { st.special } else { st.cnid };
	                let nlink = if is_hl { 0 } else if st.special == 0 { 1 } else { st.special };
	                (t, inode, nlink, st.size)
	            }
	        };
	        let path = esc(e.path.as_bytes());
	        if t == 'L' {
	            let tgt = match v.read_file(&e.path) {
	                Ok(b) => b,
	                Err(err) => {
	                    let _ = writeln!(out, "ERR\t{path}\treadlink: {err}");
	                    Vec::new()
	                }
	            };
	            let _ = writeln!(
	                out,
	                "L\t{}\t{:04o}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
	                is_hl as u8, p.mode & 0o7777, p.owner_id, p.group_id, nlink, size, st.cnid, inode,
	                path, esc(&tgt)
	            );
	        } else {
	            let _ = writeln!(
	                out,
	                "{t}\t{}\t{:04o}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
	                is_hl as u8, p.mode & 0o7777, p.owner_id, p.group_id, nlink, size, st.cnid, inode,
	                path
	            );
	        }
	    }
	    let _ = writeln!(
	        out,
	        "END\t{files}\t{dirs}\t{symlinks}\t{hls}\t{bytes}"
	    );
	}
	EOF
	( cd "$b" && cargo build --release --offline --quiet ) || die "reader build failed" 3
	mkdir -p "$SUITE/bin"
	install -m 0755 "$b/target/release/hfsinv" "$BIN"
}
if [[ ! -x $BIN ]]; then
	say "building the read-only reader (one time)"
	mkdir -p "$SUITE"
	build_reader
fi
[[ -x $BIN ]] || die "no readable reader at $BIN" 3

work=$(mktemp -d "${TMPDIR:-/tmp}/35-verify.XXXXXX")
trap 'rm -rf "$work"' EXIT
inv=$work/image.tsv

# --- gate 1: is there a volume at all ---------------------------------------
"$BIN" "$img" >"$inv" 2>"$work/reader.err"
rrc=$?
if ((rrc != 0)) || ! head -1 "$inv" | grep -q '^VOL'; then
	say "== volume"
	say "   FAIL cannot read a volume out of $img"
	sed -n '1,5p' "$inv" | sed 's/^/   | /'
	sed -n '1,5p' "$work/reader.err" | sed 's/^/   | /'
	exit 3
fi

say "== volume"
mapfile -t VOL < <(head -1 "$inv" | tr '\t' '\n')
sig=${VOL[1]} hfsx=${VOL[2]} attrs=${VOL[3]} bs=${VOL[4]}
blocks=${VOL[5]} free=${VOL[6]} hfiles=${VOL[7]} hfolders=${VOL[8]}
vfail=0
if [[ $hfsx == true && $sig == 4858 ]]; then
	say "   signature        HFSX (0x4858), case sensitive      ok"
else
	say "   signature        0x$sig, is_hfsx=$hfsx            FAIL  (not a case-sensitive HFSX volume)"
	vfail=1
fi
if (((16#$attrs & 0x100) != 0)); then say "   unmounted bit    set                              ok"
else say "   unmounted bit    clear                            FAIL  (volume not cleanly unmounted)"; vfail=1; fi
if (((16#$attrs & 0x800) != 0)); then say "   inconsistent     set                              FAIL  (kHFSBootVolumeInconsistent)"; vfail=1
else say "   inconsistent     clear                             ok"; fi
if (((16#$attrs & 0x2000) != 0)); then say "   journaled        set (mkfs -J)"; else note "journaled bit clear"; fi
if [[ $bs =~ ^[0-9]+$ ]] && ((bs >= 512 && bs <= 65536)); then say "   block size       $bs"
else say "   block size       $bs  FAIL"; vfail=1; fi
say "   used bytes       $(((blocks - free) * bs)) of $((blocks * bs)) ($free blocks free)"
note "header counts $hfiles files / $hfolders folders are reported, not gated"

# --- gate 2: fsck, the hard one ---------------------------------------------
# fsck -n never writes, so the image stays untouched and stays comparable.
say "== fsck gate ($FSCK -f -n)"
if ((!do_fsck)); then
	say "   skipped by --no-fsck"
else
	timeout 3600 "$FSCK" -f -n "$img" >"$work/fsck.log" 2>&1
	frc=$?
	if ((frc == 0)) && grep -q 'appears to be OK' "$work/fsck.log"; then
		say "   exit 0, volume appears to be OK"
	else
		say "   FAIL exit $frc, volume is not clean"
		sed -n '/\*\*/p' "$work/fsck.log" | tail -"$limit" | sed 's/^/   | /'
		exit 2
	fi
fi
((vfail == 0)) || exit 2

# --- compare ----------------------------------------------------------------
say ""
python3 - "$img" "$inv" "$ref" "$ref_mount" "$limit" "$expect_files" "$expect_bytes" <<'PY'
import os, sys

inv_path, ref_root, overlay, limit = sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5])
expect_files, expect_bytes = sys.argv[6], sys.argv[7]
PRIV = "/\x00\x00\x00\x00HFS+ Private Data"
SKIP = {".journal", ".journal_info_block"}
CRIT = ("/sbin/launchd", "/usr/lib/dyld", "/System/Library/dyld/", "/private/etc/")

def unesc(s):
    out, i = bytearray(), 0
    b = s.encode()
    while i < len(b):
        c = b[i]
        if c == 0x5c and i + 1 < len(b):
            d = b[i + 1]
            if d == 0x74: out.append(9); i += 2; continue
            if d == 0x6e: out.append(10); i += 2; continue
            if d == 0x72: out.append(13); i += 2; continue
            if d == 0x5c: out.append(0x5c); i += 2; continue
            if d == 0x78 and i + 3 < len(b):
                out.append(int(b[i + 2:i + 4], 16)); i += 4; continue
        out.append(c); i += 1
    return out.decode("utf-8", "surrogateescape")

class E:
    __slots__ = ("t", "mode", "uid", "gid", "nlink", "size", "inode", "target")
    def __init__(s, t, mode, uid, gid, nlink, size, inode, target=None):
        s.t, s.mode, s.uid, s.gid, s.nlink, s.size, s.inode, s.target = t, mode, uid, gid, nlink, size, inode, target

img, errs, jmeta = {}, [], []
for line in open(inv_path, "rb").read().decode("utf-8", "surrogateescape").split("\n"):
    f = line.split("\t")
    if not f or f[0] in ("", "VOL", "END"): continue
    if f[0] == "ERR":
        errs.append((unesc(f[1]), f[2])); continue
    try:
        t, hl, mode, uid, gid, nlink, size, cnid, inode = f[0], f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8]
        path = unesc(f[9])
        if path in ("/.journal", "/.journal_info_block"):
            jmeta.append(path); continue
        tgt = unesc(f[10]) if t == "L" and len(f) > 10 else None
    except (IndexError, ValueError):
        errs.append((line, "unparsable")); continue
    img[path] = E(t, int(mode, 8), int(uid), int(gid), int(nlink), int(size), int(inode), tgt)

# reference tree, plus the optional ownership overlay
ref, refino = {}, {}
stack = [""]
while stack:
    rel = stack.pop()
    full = os.path.join(ref_root, rel) if rel else ref_root
    try:
        names = sorted(os.listdir(full))
    except OSError as e:
        errs.append(("/" + rel if rel else "/", f"reference list: {e}")); continue
    for n in names:
        if not rel and n in SKIP: continue
        p = os.path.join(full, n)
        relp = "/" + (rel + "/" if rel else "") + n
        try: st = os.lstat(p)
        except OSError as e:
            errs.append((relp, f"reference stat: {e}")); continue
        if os.path.isdir(p) and not os.path.islink(p):
            stack.append((rel + "/" + n).lstrip("/"))
            e = E("D", st.st_mode & 0o7777, st.st_uid, st.st_gid, 1, 0, None)
        elif os.path.islink(p):
            try: tgt = os.readlink(p)
            except OSError as ex: tgt = ""; errs.append((relp, f"readlink: {ex}"))
            e = E("L", st.st_mode & 0o7777, st.st_uid, st.st_gid, 1, st.st_size, None, tgt)
        else:
            e = E("F", st.st_mode & 0o7777, st.st_uid, st.st_gid, st.st_nlink, st.st_size, None)
        ref[relp] = e
        refino[relp] = (st.st_dev, st.st_ino)

# overlay: reference metadata as a privileged copy would have written it
cov = 0
if overlay:
    for relp, e in ref.items():
        src = overlay + relp
        try: st = os.stat(src)
        except OSError: continue
        e.uid, e.gid, e.mode, e.size = st.st_uid, st.st_gid, st.st_mode & 0o7777, (st.st_size if e.t == "F" else e.size)
        cov += 1
    # hard links share one inode, so one overlay source fixes the whole group
    groups = {}
    for relp, key in refino.items():
        if ref[relp].nlink > 1: groups.setdefault(key, []).append(relp)
    for key, members in groups.items():
        known = [m for m in members if overlay and os.path.exists(overlay + m)]
        if not known: continue
        src = ref[known[0]]
        for m in members:
            ref[m].uid, ref[m].gid, ref[m].mode = src.uid, src.gid, src.mode

def esc(p):
    return p.replace("\x00", "\\0")

rows = []
def check(cls, ok, refv, imgv, offenders):
    rows.append((cls, ok, str(refv), str(imgv), len(offenders), offenders[:limit]))

# path sets
refset, imgset = set(ref), set(img)
missing = sorted(refset - imgset)
extra = sorted(p for p in imgset - refset if p != PRIV and not p.startswith(PRIV + "/"))
check("missing paths", not missing, len(refset), len(refset) - len(missing), missing)
check("extra paths", not extra, len(imgset), len(imgset) - len(extra), extra)
check("reader errors", not errs, 0, len(errs), ["%s: %s" % (esc(a), b) for a, b in errs])
if jmeta: check("volume metadata", True, len(jmeta), len(jmeta), [])

# Payload counts. "HFS+ Private Data" holds one inode record per hard-linked
# file: those are not names, so they never count as files or bytes, but a link
# record's own data fork is empty, so its bytes come from its inode record.
rpriv = lambda p: p == PRIV or p.startswith(PRIV + "/")
rfiles = [p for p in ref if ref[p].t == "F"]
rlinks = [p for p in ref if ref[p].t == "L"]
rdirs = [p for p in ref if ref[p].t == "D"]
rbytes = sum(ref[p].size for p in rfiles)
ifiles = [p for p in img if img[p].t not in ("L", "D") and not rpriv(p)]
ilinks = [p for p in img if img[p].t == "L"]
idirs = [p for p in img if img[p].t == "D" and not rpriv(p)]
priv_inode = {}
for p, e in img.items():
    if p.startswith(PRIV + "/iNode"):
        try: priv_inode[int(p.rsplit("iNode", 1)[1])] = e
        except ValueError: pass
hlrec = {p for p in ifiles if img[p].nlink == 0}
def isize(p):
    e = priv_inode.get(img[p].inode)
    return e.size if (p in hlrec and e) else img[p].size
ibytes = sum(isize(p) for p in ifiles)

def count(cls, ref_v, img_v, offenders):
    check(cls, ref_v == img_v, ref_v, img_v, offenders if ref_v != img_v else [])

count("file count", len(rfiles), len(ifiles), [f"expected {len(rfiles)}, image has {len(ifiles)}"])
count("symlink count", len(rlinks), len(ilinks), [f"expected {len(rlinks)}, image has {len(ilinks)}"])
count("directory count", len(rdirs), len(idirs), [f"expected {len(rdirs)}, image has {len(idirs)}"])
count("total bytes", rbytes, ibytes, [f"expected {rbytes}, image has {ibytes} (delta {ibytes - rbytes})"])
if expect_files: check("expected file count", len(ifiles) == int(expect_files), expect_files, len(ifiles), [f"image has {len(ifiles)}"])
if expect_bytes: check("expected total bytes", ibytes == int(expect_bytes), expect_bytes, ibytes, [f"image has {ibytes}"])

common = refset & imgset

# kind must agree for common paths
kindb = [p for p in refset & imgset if (ref[p].t == "D") != (img[p].t == "D") or (ref[p].t == "L") != (img[p].t == "L")]
check("kind", not kindb, len(common), len(common) - len(kindb), [f"{esc(p)}: reference {ref[p].t}, image {img[p].t}" for p in sorted(kindb)])

# symlink targets
tgt = [p for p in refset & imgset if ref[p].t == "L" and ref[p].target != img[p].target]
check("symlink target", not tgt, len(rlinks), len(rlinks) - len(tgt), [f"{esc(p)}: reference {ref[p].target!r}, image {img[p].target!r}" for p in sorted(tgt)])

# hard links: visible group sets identical, inode record real, metadata and
# link count on the inode record (the link records themselves carry the writer's
# own values, so they are reported but not gated)
rclasses = {}
for p in rfiles:
    if ref[p].nlink > 1: rclasses.setdefault(refino[p], []).append(p)
rgrp = {frozenset(v) for v in rclasses.values()}
iclasses = {}
for p in ifiles:
    if img[p].nlink == 0: iclasses.setdefault(img[p].inode, []).append(p)
igrp = {frozenset(v) for v in iclasses.values() if len(v) > 1}
hl_bad = [f"reference group {sorted(map(esc, g))} has no matching image group" for g in sorted(rgrp - igrp, key=sorted)]
hl_bad += [f"image group {sorted(map(esc, g))} not in reference" for g in sorted(igrp - rgrp, key=sorted)]
check("hardlink groups", not hl_bad, len(rgrp), len(igrp), hl_bad)

inode_bad, inode_note, notes = [], [], []
for g in sorted(rgrp & igrp, key=sorted):
    ipath = PRIV + "/iNode%d" % img[sorted(g)[0]].inode
    rec = img.get(ipath)
    members = sorted(g)
    if rec is None:
        inode_bad.append(f"{sorted(map(esc, g))}: no inode record {esc(ipath)}"); continue
    if rec.nlink not in (0, len(g)):
        inode_bad.append(f"{esc(ipath)}: link count {rec.nlink} != {len(g)} paths")
    r0 = ref[members[0]]
    for field in ("mode", "uid", "gid", "size"):
        if getattr(rec, field) != getattr(r0, field):
            inode_bad.append(f"{esc(ipath)}: inode {field} {getattr(rec, field)} != reference {getattr(r0, field)}")
    for m in members:
        if (img[m].mode, img[m].uid, img[m].gid) != (rec.mode, rec.uid, rec.gid):
            inode_note.append(f"{esc(m)}: link record {img[m].mode:04o} {img[m].uid}:{img[m].gid} vs inode {rec.mode:04o} {rec.uid}:{rec.gid}")
            break
check("hardlink inodes", not inode_bad, len(rgrp & igrp), len(rgrp & igrp) - len(inode_bad), inode_bad)

# modes on every path, then the critical paths called out on their own
modeb = [p for p in common if ref[p].t != "D" and ref[p].nlink <= 1 and ref[p].mode != img[p].mode]
modeb += [p for p in common if ref[p].t == "D" and ref[p].mode != img[p].mode]
check("mode", not modeb, len(common), len(common) - len(modeb), [f"{esc(p)}: reference {ref[p].mode:04o}, image {img[p].mode:04o}" for p in sorted(modeb)])

crit = [p for p in ref if p.startswith(CRIT)]
critb = [p for p in crit if p not in img or img[p].mode != ref[p].mode]
if not crit: notes.append("no /sbin/launchd, /usr/lib/dyld, /System/Library/dyld/* or /private/etc/* in the reference")
check("critical path modes", not critb, len(crit), len(crit) - len(critb), [f"{esc(p)}: reference {ref[p].mode:04o}, image {img.get(p).mode:04o}" if p in img else f"{esc(p)}: absent" for p in critb])

# ownership
owned = [p for p in common if ref[p].uid == 0 or ref[p].gid == 0]
# a hard link's own record is not where its owner lives; that is gated above
ownb = [p for p in common if ref[p].nlink <= 1 and (ref[p].uid, ref[p].gid) != (img[p].uid, img[p].gid)]
check("owner", not ownb, len(common) - len([p for p in common if ref[p].nlink > 1]), len(common) - len([p for p in common if ref[p].nlink > 1]) - len(ownb), [f"{esc(p)}: reference {ref[p].uid}:{ref[p].gid}, image {img[p].uid}:{img[p].gid}" for p in sorted(ownb)])

# --- report -----------------------------------------------------------------
bad = 0
w = max([len(r[0]) for r in rows] + [8])
print("%-*s %10s %10s  %s" % (w, "class", "reference", "image", "verdict"))
for cls, ok, refv, imgv, n, off in rows:
    print("%-*s %10s %10s  %s" % (w, cls, refv, imgv, "ok" if ok else "FAIL %d" % n if n else "FAIL"))
    if not ok:
        bad += 1
        for o in off: print("    %s" % o)
        if n > limit: print("    ... %d more" % (n - limit))
if inode_note:
    print("\nnote: %d hard link record(s) disagree with their inode record; the" % len(inode_note))
    print("      inode is what a mount reports, so this does not gate. e.g.")
    for n in inode_note[:limit]: print("      %s" % n)
for n in notes: print("\nnote: %s" % n)
if overlay: print("\nnote: ownership taken from overlay %s on %d paths" % (overlay, cov))
elif not owned:
    print("\nnote: the reference carries no 0:0 path (unprivileged extraction?);")
    print("      the owner class compares 1000 against 1000 and proves little.")
print("\n%d class(es) failed, %d image entries, %d reader errors" % (bad, len(img), len(errs)))
sys.exit(1 if bad else 0)
PY
rc=$?
say ""
if ((rc == 0)); then
	say "PASS  $img matches $ref"
elif ((rc == 1)); then
	say "FAIL  $img does not match $ref"
else
	say "FAIL  $img: the comparison itself broke (python exit $rc)"
fi
if ((keep)); then say "inventories kept: $inv $work/fsck.log"; trap - EXIT; else :; fi
exit $rc
