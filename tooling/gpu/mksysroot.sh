#!/bin/sh
# tooling/gpu/mksysroot.sh -- build the minimal iOS 16 arm64 (device) sysroot the
# Mesa freedreno cross build needs, out of legal parts only.
#
#   mksysroot.sh --cache <dyld_shared_cache_arm64> --out <dir> [options]
#
# What it produces (all inside <dir>):
#   usr/include/            C headers: xnu-8796.141.3 (bsd/sys, osfmk/mach, libkern,
#                           EXTERNAL_HEADERS), Libc-1534.100.14, libpthread-514.100.2,
#                           libmalloc-425.100.7, libplatform-375.120.2, Libm-2026,
#                           dyld-1042.1 dlfcn.h, AvailabilityVersions-141.1 headers,
#                           zlib-1.2.11 zlib.h/zconf.h, four synthesized headers
#   usr/local/include/      the private half of the same headers (SDK puts them here)
#   usr/lib/*.tbd           TAPI stubs for libSystem.B, libc++, libc++abi, libz
#   System/Library/Frameworks/*.tbd   IOKit, IOSurface, OpenGLES, CoreFoundation,
#                           QuartzCore, Metal
#   MANIFEST.sha256         sha256 of every input (tarballs, dyld cache, this script)
#                           followed by sha256 of every file written
#
# Provenance/licences, all redistributable:
#   apple-oss-distributions  APSL-2.0      (Libc, libpthread, libmalloc, libplatform,
#                                          Libm, AvailabilityVersions, xnu, dyld)
#   zlib 1.2.11              zlib licence
#   .tbd stubs               generated here from our own device dyld cache
#   synthesized headers      reimplementations written for ios-nord (no Apple text)
#
# Idempotency contract: a re-run never deletes anything under <dir>.  Headers are
# staged in <dir>/.work and then merged over <dir>; the .tbd set is regenerated in
# place.  Parts staged by another tool (usr/include/c++/v1, extra frameworks) are
# left alone -- the earlier prototype's `rm -rf "$OUT"` is exactly what lost them.
#
# Exit codes: 0 ok, 1 usage/bad input, 2 a step failed.

set -eu

PROG=$(basename "$0")
CACHE=
OUT=
SRC=
DO_TBD=yes
DO_FETCH=yes
QUIET=no

usage() {
	cat <<EOF
usage: $PROG --cache <dyld_shared_cache_arm64> --out <dir> [options]

  --cache PATH   dyld shared cache of the target OS (read only; the source of
                 every .tbd stub).  Must start with the "dyld_v1" magic.
  --out DIR      sysroot to create/update.  Nothing is written outside it.
  --src DIR      where upstream tarballs are cached/extracted.
                 default: <out>/.src   (kept inside <out> by design)
  --no-tbd       headers only; skip the .tbd generation (--cache not needed)
  --no-fetch     never download; fail if a pinned tarball is missing
  --quiet        only print the final summary
  -h, --help     this text

Pinned inputs (tag = the version the running iOS 16.7.16 cache reports):
  xnu-8796.141.3  Libc-1534.100.14  libpthread-514.100.2  libmalloc-425.100.7
  libplatform-375.120.2  Libm-2026  AvailabilityVersions-141.1  dyld-1042.1
  zlib-1.2.11
EOF
}

die() { printf '%s: %s\n' "$PROG" "$*" >&2; exit 1; }
step() { [ "$QUIET" = yes ] || printf '==> %s\n' "$*" >&2; }
say() { [ "$QUIET" = yes ] || printf '    %s\n' "$*" >&2; }

while [ $# -gt 0 ]; do
	case $1 in
	--cache) CACHE=${2:?--cache needs a path}; shift 2 ;;
	--out) OUT=${2:?--out needs a path}; shift 2 ;;
	--src) SRC=${2:?--src needs a path}; shift 2 ;;
	--no-tbd) DO_TBD=no; shift ;;
	--no-fetch) DO_FETCH=no; shift ;;
	--quiet) QUIET=yes; shift ;;
	-h | --help) usage; exit 0 ;;
	*) usage >&2; die "unknown argument: $1" ;;
	esac
done

[ -n "$OUT" ] || { usage >&2; die "--out is required"; }
if [ "$DO_TBD" = yes ]; then
	[ -n "$CACHE" ] || { usage >&2; die "--cache is required unless --no-tbd"; }
	[ -f "$CACHE" ] || die "no such dyld cache: $CACHE"
	head -c 7 "$CACHE" | grep -q 'dyld_v1' || die "not a dyld shared cache: $CACHE"
fi

abspath() { case $1 in /*) printf '%s\n' "$1" ;; *) printf '%s\n' "$PWD/$1" ;; esac; }
OUT=$(abspath "$OUT")
[ -n "$SRC" ] && SRC=$(abspath "$SRC") || SRC=$OUT/.src

# ---- every write must land under $OUT -----------------------------------------
under() { # under DIR PATH -> PATH when PATH is inside DIR
	case $2 in "$1" | "$1"/*) printf '%s\n' "$2" ;; *) die "refusing to write outside $OUT: $2" ;; esac
}
mk() { mkdir -p "$(under "$OUT" "$1")"; }
# cp that keeps every destination inside $OUT
cpto() { # cpto SRC DESTDIR
	mk "$2"
	cp -a "$1" "$(under "$OUT" "$2")/"
}

mkdir -p "$OUT"
T=$OUT/.work.$$
mk "$T"
trap 'rm -rf "$T"' 0
trap 'exit 2' 1 2 3 15

# ---- pinned sources -----------------------------------------------------------
# field 1: extracted directory name, 2: upstream tag (also the tarball name),
# 3: upstream project (github org dir, or "zlib" for the zlib.net fossil)
PINNED='AvailabilityVersions-AvailabilityVersions-141.1 AvailabilityVersions-141.1 AvailabilityVersions
xnu-xnu-8796.141.3 xnu-8796.141.3 xnu
Libc-Libc-1534.100.14 Libc-1534.100.14 Libc
libpthread-libpthread-514.100.2 libpthread-514.100.2 libpthread
libmalloc-libmalloc-425.100.7 libmalloc-425.100.7 libmalloc
libplatform-libplatform-375.120.2 libplatform-375.120.2 libplatform
Libm-Libm-2026 Libm-2026 Libm
dyld-dyld-1042.1 dyld-1042.1 dyld
zlib-1.2.11 zlib-1.2.11 zlib'

sha_of() { sha256sum "$1" | cut -d' ' -f1; }

url_of() { # url_of PROJECT TAG
	case $1 in
	zlib) printf 'https://zlib.net/fossils/%s.tar.gz\n' "$2" ;;
	*) printf 'https://github.com/apple-oss-distributions/%s/archive/refs/tags/%s.tar.gz\n' "$1" "$2" ;;
	esac
}

pin_sha() { # sha_of_pin PROJECT
	case $1 in
	AvailabilityVersions) echo 4aea449803bd26bf7af37688f6defde48c897d03aa5e22abfda4accc97ced322 ;;
	xnu) echo f08bfe045a1fb552a6cbf7450feae6a35dd003e9979edf71ea77d1a836c8dc99 ;;
	Libc) echo eeb3c39d17638f060bb3734331ad72fc465ef21adedd49d8235c54996dca4ffe ;;
	libpthread) echo 3845098e4ce5a7cf69e84d6c84de4dea860454732bd18911be74ed5fc324b8e9 ;;
	libmalloc) echo 89139f3159c26a634294b601a1caacbec253f1ef243ca24b54125b520f83c4d8 ;;
	libplatform) echo c0962595da8899cf54445698fd71bddc2118edb8ce8e3d6e11a29ef96ad754bc ;;
	Libm) echo 2a33044df4f8a899b49b4531fc5e91abc6c8e10e14567171e8829b2b15ddf84b ;;
	dyld) echo 5ff902c50c78e809e90fb92038b86e531aafbc6dff36d254d6548ce6d41a0aa8 ;;
	zlib) echo c3e5e9fdd5004dcb542feda5ee4f0ff0744628baf8ed2dd5d66f8ca1197cb1a1 ;;
	esac
}

step "sources in $SRC"
# --src defaults to <out>/.src, so a default run writes nothing outside <out>
mkdir -p "$SRC/dl"
while read -r dirname tag proj; do
	dir=$SRC/$dirname
	[ -d "$dir" ] && continue
	tar=$SRC/dl/$tag.tar.gz
	if [ ! -f "$tar" ]; then
		[ "$DO_FETCH" = yes ] || die "missing tarball $tar (--no-fetch)"
		url=$(url_of "$proj" "$tag")
		step "fetch $tag"
		curl -fsSL --retry 3 -o "$tar.part" "$url" || die "download failed: $url"
		mv "$tar.part" "$tar"
	fi
	want=$(pin_sha "$proj")
	case $want in
	"("*) say "$proj: no sha256 pin, trusting $tar" ;;
	*) got=$(sha_of "$tar")
	   [ "$got" = "$want" ] || die "sha256 mismatch for $tar: want $want got $got" ;;
	esac
	say "extract $tag"
	tar xzf "$tar" -C "$SRC" || die "extract failed: $tar"
	[ -d "$dir" ] || die "tarball $tar did not produce $dir"
done <<EOF
$PINNED
EOF

LIB=$SRC/Libc-Libc-1534.100.14
PTH=$SRC/libpthread-libpthread-514.100.2
MAL=$SRC/libmalloc-libmalloc-425.100.7
PLAT=$SRC/libplatform-libplatform-375.120.2
LIBM=$SRC/Libm-Libm-2026
AV=$SRC/AvailabilityVersions-AvailabilityVersions-141.1
XN=$SRC/xnu-xnu-8796.141.3
DY=$SRC/dyld-dyld-1042.1
ZL=$SRC/zlib-1.2.11
for d in "$LIB" "$PTH" "$MAL" "$PLAT" "$AV" "$XN" "$DY" "$ZL"; do
	[ -d "$d" ] || die "missing extracted tree: $d"
done

# ---- embedded generators (written under $OUT/.work, never into the repo) ------
G=$T/gen
mkdir -p "$G"

cat >"$G/dsc.py" <<'DSCEOF'
#!/usr/bin/python3 -I
"""Minimal read-only dyld shared cache reader (lane 1, ios-nord).

Header field offsets per dyld's dyld_cache_format.h as used by iOS 16 caches;
cross-checked against refs/ry-diffusion-Bergamota/tools/renegade/pacstrip_cache.py:51-58
(imagesOffset at 0x1C0, subCacheArray at 0x188, mapping table entries 32 bytes).
Read-only; every offset bounds-checked by the caller's reads.
"""
import struct, os, sys

MAGIC_PREFIX = b"dyld_v1"
LC_SEGMENT_64, LC_ID_DYLIB, LC_DYLD_INFO, LC_DYLD_INFO_ONLY = 0x19, 0xD, 0x22, 0x80000022
LC_DYLD_EXPORTS_TRIE = 0x80000033


class Cache:
    def __init__(self, main_path):
        self.main_path = os.path.abspath(main_path)
        self.dir = os.path.dirname(self.main_path)
        self.base = os.path.basename(self.main_path)
        with open(self.main_path, "rb") as f:
            self.hdr = f.read(max(0x4000, os.path.getsize(self.main_path)))
        if not self.hdr.startswith(MAGIC_PREFIX):
            raise SystemExit("not a dyld shared cache: bad magic %r" % self.hdr[:8])
        self.mapping_offset, self.mapping_count = struct.unpack_from("<II", self.hdr, 0x10)
        self.subcache_offset, self.subcache_count = struct.unpack_from("<II", self.hdr, 0x188)
        self.images_offset, self.images_count = struct.unpack_from("<II", self.hdr, 0x1C0)
        self.dyld_in_cache = struct.unpack_from("<Q", self.hdr, 0x78)[0]
        self.subcaches = []
        for i in range(self.subcache_count):
            uuid = self.hdr[self.subcache_offset + 56 * i: self.subcache_offset + 56 * i + 16]
            suffix = self.hdr[self.subcache_offset + 56 * i + 24: self.subcache_offset + 56 * i + 56]
            self.subcaches.append((uuid, suffix.split(b"\0")[0].decode()))
        # per-file mapping tables: addresses are global, files index into subcaches
        self.maps = []
        for idx, fn in enumerate([self.base] + [self.base + s for _, s in self.subcaches]):
            path = os.path.join(self.dir, fn)
            with open(path, "rb") as f:
                head = f.read(0x1000)
            if not head.startswith(MAGIC_PREFIX):
                continue
            moff, mcnt = struct.unpack_from("<II", head, 0x10)
            for i in range(mcnt):
                addr, size, foff, maxp, initp = struct.unpack_from("<QQQII", head, moff + 32 * i)
                self.maps.append((addr, size, path, foff))
        self.maps.sort()

    def translate(self, addr, n=1):
        for addr0, size, path, foff in self.maps:
            if addr0 <= addr and addr + n <= addr0 + size:
                return path, foff + (addr - addr0)
        raise KeyError("0x%x not mapped" % addr)

    def read(self, addr, n):
        path, off = self.translate(addr, n)
        with open(path, "rb") as f:
            f.seek(off)
            return f.read(n)

    # --- images -----------------------------------------------------------
    def images(self):
        for i in range(self.images_count):
            addr, mod, ino, pathoff, pad = struct.unpack_from("<QQQII", self.hdr, self.images_offset + 32 * i)
            with open(self.main_path, "rb") as f:
                f.seek(pathoff)
                path = f.read(1024).split(b"\0")[0].decode()
            yield addr, path
        if self.dyld_in_cache:
            yield self.dyld_in_cache, "/usr/lib/dyld"

    def find(self, path):
        for addr, p in self.images():
            if p == path:
                return addr
        return None

    # --- mach-o -----------------------------------------------------------
    def load_commands(self, addr):
        magic, cpu, sub, ftype, ncmds, sizeofcmds = struct.unpack("<IiiIII", self.read(addr, 24))
        if magic != 0xFEEDFACF:
            raise SystemExit("bad mach magic 0x%x at 0x%x" % (magic, addr))
        lcs = self.read(addr + 32, sizeofcmds)
        off = 0
        for _ in range(ncmds):
            cmd, cmdsize = struct.unpack_from("<II", lcs, off)
            yield cmd, lcs[off: off + cmdsize]
            off += cmdsize

    def dylib_id(self, addr):
        out = {}
        for cmd, body in self.load_commands(addr):
            if cmd == LC_ID_DYLIB:
                name_off, ts, cur, compat = struct.unpack_from("<IIII", body, 8)
                out = dict(name=body[name_off:].split(b"\0")[0].decode(), current_version=cur,
                           compat_version=compat, timestamp=ts)
        return out

    def segments(self, addr):
        for cmd, body in self.load_commands(addr):
            if cmd == LC_SEGMENT_64:
                name = body[8:24].split(b"\0")[0].decode()
                vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<QQQQ", body, 24)
                yield name, vmaddr, vmsize, fileoff, filesize

    def trie(self, addr):
        """Raw export trie bytes of the image at addr (empty when absent).

        Cache images carry LC_DYLD_EXPORTS_TRIE (0x80000033), whose dataoff is a
        __LINKEDIT file offset, not a vmaddr -- convert through __LINKEDIT.
        """
        info = None
        for cmd, body in self.load_commands(addr):
            if cmd == LC_DYLD_EXPORTS_TRIE:
                info = struct.unpack_from("<II", body, 8)
        if not info or info[1] == 0:
            return b""
        linkedit = None
        for name, vmaddr, vmsize, fileoff, filesize in self.segments(addr):
            if name == "__LINKEDIT":
                linkedit = (vmaddr, fileoff)
        if linkedit is None:
            return b""
        va = linkedit[0] + (info[0] - linkedit[1])
        return self.read(va, info[1])

    def symbols(self, addr):
        """(name, flags, kind, extra) via the export trie."""
        yield from walk(self.trie(addr), 0, b"")


def uleb(data, off):
    val = shift = 0
    while True:
        b = data[off]
        off += 1
        val |= (b & 0x7F) << shift
        shift += 7
        if not b & 0x80:
            return val, off


REEXPORT, STUB_RESOLVER, WEAK_DEF, THREAD_LOCAL = 0x08, 0x10, 0x04, 0x01


def walk(data, start, prefix):
    if start >= len(data):
        return
    tsize, off = uleb(data, start)
    if tsize:
        end = off + tsize
        flags, off = uleb(data, off)
        if flags & REEXPORT:
            ordinal, off = uleb(data, off)
            yield prefix.decode(), flags, "reexport", dict(ordinal=ordinal,
                                                          import_name=data[off:end].split(b"\0")[0].decode())
        else:
            flags2, off = (flags, off)
            yield prefix.decode(), flags, "defined", {}
        off = end
    nchild = data[off]
    off += 1
    for _ in range(nchild):
        edge = b""
        while data[off]:
            edge += bytes([data[off]])
            off += 1
        off += 1
        node, off = uleb(data, off)
        yield from walk(data, node, prefix + edge)


if __name__ == "__main__":
    c = Cache(sys.argv[1])
    print("magic", c.hdr[:16], "maps", len(c.maps), "images", c.images_count,
          "subcaches", len(c.subcaches))
    if len(sys.argv) > 2:
        a = c.find(sys.argv[2])
        print("addr", hex(a) if a else None, c.dylib_id(a) if a else "")
        if a and len(sys.argv) > 3:
            n = 0
            for s, f, k, o in c.symbols(a):
                print(hex(f), k, s, o)
                n += 1
                if n > 20:
                    break
DSCEOF

cat >"$G/gen_tbd.py" <<'TBDEOF'
#!/usr/bin/python3 -I
"""Emit a TAPI v4 .tbd for one image of a dyld shared cache.

  gen_tbd.py CACHE IMAGE_PATH OUT.tbd [--union PATH ...]

install-name / current-version / compatibility-version come from the image's own
LC_ID_DYLIB, symbols from its export trie (weak / thread-local / reexport flags
preserved).  --union adds the exports of the given extra images (used for
libSystem.B, which reexports 40 libsystem_* libraries through LC_REEXPORT_DYLIB).
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dsc

WEAK, TLV, REEXPORT = 0x04, 0x01, 0x08


def ver(v):
    return "%d.%d.%d" % (v >> 16, (v >> 8) & 0xFF, v & 0xFF)


def main():
    args = sys.argv[1:]
    union = []
    while "--union" in args:
        i = args.index("--union")
        union.append(args[i + 1])
        del args[i:i + 2]
    cache_path, image, out = args
    c = dsc.Cache(cache_path)
    own = c.find(image)
    if own is None:
        raise SystemExit("image not in cache: %s" % image)
    ident = c.dylib_id(own)
    reexports = []
    syms = {}
    for path in union:
        a = c.find(path)
        if a is None:
            raise SystemExit("union image not in cache: %s" % path)
        reexports.append(path)
        for name, flags, kind, extra in c.symbols(a):
            if flags & REEXPORT:
                continue
            # first definition wins; a weak def stays weak
            if name not in syms:
                syms[name] = flags
    for path in [image] + union:
        a = c.find(path)
        for name, flags, kind, extra in c.symbols(a):
            if flags & REEXPORT:
                continue
            syms.setdefault(name, flags)

    plain, weak, tlv, objc_cls, objc_meta, objc_ivar = [], [], [], [], [], []
    for name, flags in sorted(syms.items()):
        if name.startswith("_OBJC_CLASS_$_"):
            objc_cls.append(name[len("_OBJC_CLASS_$_"):])
        elif name.startswith("_OBJC_METADATA_$_"):
            objc_meta.append(name[len("_OBJC_METADATA_$_"):])
        elif name.startswith("_OBJC_IVAR_$_"):
            objc_ivar.append(name[len("_OBJC_IVAR_$_"):])
        elif flags & TLV:
            tlv.append(name)
        elif flags & WEAK:
            weak.append(name)
        else:
            plain.append(name)

    lines = ["--- !tapi-tbd", "tbd-version:     4", "targets:         [ arm64-ios ]",
             "install-name:    '%s'" % ident["name"],
             "current-version: %s" % ver(ident["current_version"]),
             "compatibility-version: %s" % ver(ident["compat_version"])]
    # reexported-libraries is NOT emitted: every reexport is folded into the
    # export list instead, so the sysroot needs only one tbd per dylib (lld
    # hard-errors on a reexport whose install name has no tbd in the sysroot).
    lines.append("exports:")
    lines.append("  - targets:         [ arm64-ios ]")
    for key, vals in (("symbols", plain), ("objc-classes", objc_cls), ("objc-ivars", objc_ivar),
                      ("objc-eh-types", objc_meta), ("thread-local-symbols", tlv),
                      ("weak-symbols", weak)):
        if vals:
            lines.append("    %s: [ %s ]" % (key, ", ".join(vals)))
        elif key == "symbols":
            lines.append("    symbols:         [  ]")

    lines.append("...")            # lld's TAPI reader wants the YAML end marker
    with open(out, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("%s: %d symbols (%d weak, %d tlv, %d objc classes), %d reexported libs"
          % (out, len(syms), len(weak), len(tlv), len(objc_cls), len(reexports)))


if __name__ == "__main__":
    main()
TBDEOF

cat >"$G/reexports.py" <<'REXEOF'
#!/usr/bin/python3 -I
"""Print one image path per line for every LC_REEXPORT_DYLIB of IMAGE.

  reexports.py CACHE IMAGE_PATH

LC_REEXPORT_DYLIB is 0x8000001f; the name is an lc_str starting at the end of
the 24-byte dylib_command (same layout as LC_LOAD_DYLIB).
"""
import sys, os, struct
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dsc

LC_REEXPORT_DYLIB = 0x8000001F
c = dsc.Cache(sys.argv[1])
a = c.find(sys.argv[2])
if a is None:
    raise SystemExit("image not in cache: %s" % sys.argv[2])
for cmd, body in c.load_commands(a):
    if cmd == LC_REEXPORT_DYLIB:
        off = struct.unpack_from("<I", body, 8)[0]
        print(body[off:].split(b"\0")[0].decode())
REXEOF

cat >"$G/alias.py" <<'ALIASEOF'
#!/usr/bin/python3 -I
"""Emit sys/_symbol_aliasing.h the way xnu's bsd/sys/make_symbol_aliasing.sh:79-122
does, but with a built-in version list instead of the SDK's availability.pl.

Rule (verbatim from that script): for every release R the file defines
  #if __ENVIRONMENT_IPHONE_OS_VERSION_MIN_REQUIRED__ >= <R encoded>
  #define __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_R(x) x
  #else
  #define __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_R(x)
so a symbol introduced in R is spelled bare when the deployment target >= R and
dropped entirely when the target is older.  Releases with a tertiary number are
skipped for iOS (script line 84-87), encoded as major*10000+minor*100.
"""
import sys

IOS = [(2, 0), (2, 1), (2, 2), (3, 0), (3, 1), (3, 2), (4, 0), (4, 1), (4, 2), (4, 3),
       (5, 0), (5, 1), (6, 0), (6, 1), (7, 0), (7, 1), (8, 0), (8, 1), (8, 2), (8, 3),
       (8, 4), (9, 0), (9, 1), (9, 2), (9, 3), (10, 0), (10, 1), (10, 2), (10, 3),
       (11, 0), (11, 1), (11, 2), (11, 3), (11, 4), (12, 0), (12, 1), (12, 2), (12, 3),
       (12, 4), (13, 0), (13, 1), (13, 2), (13, 3), (13, 4), (13, 5), (13, 6), (13, 7),
       (14, 0), (14, 1), (14, 2), (14, 3), (14, 4), (14, 5), (14, 6), (14, 7), (14, 8),
       (15, 0), (15, 1), (15, 2), (15, 3), (15, 4), (15, 5), (15, 6), (15, 7), (15, 8),
       (16, 0), (16, 1), (16, 2), (16, 3), (16, 4), (16, 5), (16, 6), (16, 7),
       (17, 0), (17, 1), (17, 2), (17, 3), (17, 4), (17, 5), (17, 6), (18, 0), (18, 1),
       (18, 2), (18, 3), (18, 4)]
MAC = [(10, 0), (10, 1), (10, 2), (10, 3), (10, 4), (10, 5), (10, 6), (10, 7), (10, 8),
       (10, 9), (10, 10), (10, 11), (10, 12), (10, 13), (10, 14), (10, 15)] + \
      [(m, 0) for m in range(11, 19)]

HEAD = '''/* Copyright (c) 2010 Apple Inc. All rights reserved.
 *
 * @APPLE_OSREFERENCE_LICENSE_HEADER_START@
 * @APPLE_OSREFERENCE_LICENSE_HEADER_END@
 *
 * Generated by tooling/gpu/mksysroot.sh from xnu-8796.141.3
 * bsd/sys/make_symbol_aliasing.sh (APSL-2.0) with a built-in version table,
 * because the SDK's availability.pl is not on this host.
 */

#ifndef _CDEFS_H_
# error "Never use <sys/_symbol_aliasing.h> directly.  Use <sys/cdefs.h> instead."
#endif

'''


def emit():
    out = [HEAD]
    for maj, minr in IOS:
        out.append("#if defined(__ENVIRONMENT_IPHONE_OS_VERSION_MIN_REQUIRED__) && "
                   "__ENVIRONMENT_IPHONE_OS_VERSION_MIN_REQUIRED__ >= %d\n" % (maj * 10000 + minr * 100))
        out.append("#define __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_%d_%d(x) x\n" % (maj, minr))
        out.append("#else\n#define __DARWIN_ALIAS_STARTING_IPHONE___IPHONE_%d_%d(x)\n#endif\n\n" % (maj, minr))
    for maj, minr in MAC:
        if maj == 10 and minr < 10 or maj < 10:
            value = maj * 100 + minr * 10
        else:
            value = maj * 10000 + minr * 100
        out.append("#if defined(__ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__) && "
                   "__ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__ >= %d\n" % value)
        out.append("#define __DARWIN_ALIAS_STARTING_MAC___MAC_%d_%d(x) x\n" % (maj, minr))
        out.append("#else\n#define __DARWIN_ALIAS_STARTING_MAC___MAC_%d_%d(x)\n#endif\n\n" % (maj, minr))
    return "".join(out)


sys.stdout.write(emit())
ALIASEOF

cat >"$G/mk_mach_stubs.sh" <<'MIGEOF'
#!/bin/sh
# Write the MIG-generated mach headers the SDK ships but xnu's source tree only
# carries as .defs.  Stubs: declaration-only, the subset client code actually
# calls.  Marked synthesized in the file headers.  Regenerating them with a real
# MIG is the honest fix (see docs/gpu-research/D-ios-sysroot.md, open questions).
set -eu
D=${1:?usage: mk_mach_stubs.sh <include-dir>}
mkdir -p "$D/mach"

hdr() { # hdr FILE DEFS NOTE
	{
		printf '/* %s -- synthesized declaration-only stub.\n' "$1"
		printf ' * xnu only ships the MIG source (%s) in the open tree and no MIG was\n' "$2"
		printf ' * available on the build host, so the routines client code calls are\n'
		printf ' * declared by hand here (%s).\n */\n' "$3"
		printf '#ifndef _MACH_%s_H_\n#define _MACH_%s_H_\n\n#include <mach/port.h>\n#include <mach/message.h>\n#include <mach/kern_return.h>\n#include <mach/std_types.h>\n#include <mach/mach_types.h>
#include <mach/clock_types.h>\n\n__BEGIN_DECLS\n' \
			"$(printf '%s' "$1" | tr 'a-z/' 'A-Z_')" "$(printf '%s' "$1" | tr 'a-z/' 'A-Z_')"
	}
}

tail_() { printf '\n__END_DECLS\n\n#endif /* stub */\n'; }

{ hdr mach/mach_port.h mach_port.defs "ports, port sets, right insertion"
cat <<'EOF'
kern_return_t mach_port_allocate(mach_port_name_t task, mach_port_right_t right,
    mach_port_name_t *name);
kern_return_t mach_port_allocate_name(mach_port_name_t task, mach_port_right_t right,
    mach_port_name_t name);
kern_return_t mach_port_deallocate(mach_port_name_t task, mach_port_name_t name);
kern_return_t mach_port_insert_right(mach_port_name_t task, mach_port_name_t name,
    mach_port_t poly, mach_msg_type_name_t polyPoly);
kern_return_t mach_port_mod_refs(mach_port_name_t task, mach_port_name_t name,
    mach_port_right_t right, mach_port_delta_t delta);
kern_return_t mach_port_construct(mach_port_name_t task, mach_port_options_ptr_t options,
    mach_port_context_t context, mach_port_name_t *name);
kern_return_t mach_port_destruct(mach_port_name_t task, mach_port_name_t name,
    mach_port_delta_t srdelta, mach_port_context_t guard);
kern_return_t mach_port_insert_member(mach_port_name_t task, mach_port_name_t name,
    mach_port_name_t pset);
kern_return_t mach_port_get_refs(mach_port_name_t task, mach_port_name_t name,
    mach_port_right_t right, mach_port_urefs_t *refs);
kern_return_t mach_port_get_attributes(mach_port_name_t task, mach_port_name_t name,
    mach_port_flavor_t flavor, mach_port_info_t port_info_out,
    mach_msg_type_number_t *port_info_outCnt);
kern_return_t mach_port_request_notification(mach_port_name_t task, mach_port_name_t name,
    mach_msg_id_t msgid, mach_port_mscount_t sync, mach_port_t notify,
    mach_msg_type_name_t notifyPoly, mach_port_t *previous);
EOF
tail_; } > "$D/mach/mach_port.h"

{ hdr mach/task.h task.defs "task ports, task_info, suspend/resume"
cat <<'EOF'
kern_return_t task_info(task_name_t target_task, task_flavor_t flavor,
    task_info_t task_info_out, mach_msg_type_number_t *task_info_outCnt);
kern_return_t task_suspend(task_t target_task);
kern_return_t task_resume(task_t target_task);
kern_return_t task_terminate(task_t target_task);
kern_return_t task_threads(task_t target_task, thread_act_array_t *act_list,
    mach_msg_type_number_t *act_listCnt);
kern_return_t task_get_special_port(task_t task, int which_port, mach_port_t *special_port);
kern_return_t task_set_special_port(task_t task, int which_port, mach_port_t special_port);
kern_return_t task_policy(task_t task, policy_t policy, policy_base_t base,
    mach_msg_type_number_t baseCnt, boolean_t set_limit, boolean_t change);
EOF
tail_; } > "$D/mach/task.h"

{ hdr mach/thread_act.h thread_act.defs "thread control"
cat <<'EOF'
kern_return_t thread_suspend(thread_act_t target_act);
kern_return_t thread_resume(thread_act_t target_act);
kern_return_t thread_terminate(thread_act_t target_act);
kern_return_t thread_info(thread_act_t target_act, thread_flavor_t flavor,
    thread_info_t thread_info_out, mach_msg_type_number_t *thread_info_outCnt);
kern_return_t thread_policy(thread_act_t thread, policy_t policy, policy_base_t base,
    mach_msg_type_number_t baseCnt, boolean_t set_limit);
kern_return_t thread_get_state(thread_act_t target_act, thread_state_flavor_t flavor,
    thread_state_t new_state, mach_msg_type_number_t *new_stateCnt);
kern_return_t thread_set_state(thread_act_t target_act, thread_state_flavor_t flavor,
    thread_state_t new_state, mach_msg_type_number_t new_stateCnt);
kern_return_t thread_switch(mach_port_name_t thread_name, int option, mach_msg_timeout_t option_time);
EOF
tail_; } > "$D/mach/thread_act.h"

{ hdr mach/vm_map.h vm_map.defs "vm map ops"
cat <<'EOF'
kern_return_t vm_allocate(vm_map_t target_task, vm_address_t *address, vm_size_t size, int flags);
kern_return_t vm_deallocate(vm_map_t target_task, vm_address_t address, vm_size_t size);
kern_return_t vm_protect(vm_map_t target_task, vm_address_t address, vm_size_t size,
    boolean_t set_maximum, vm_prot_t new_protection);
kern_return_t vm_inherit(vm_map_t target_task, vm_address_t address, vm_size_t size,
    vm_inherit_t new_inheritance);
kern_return_t vm_region(vm_map_t target_task, vm_address_t *address, vm_size_t *size,
    vm_region_flavor_t flavor, vm_region_info_t info, mach_msg_type_number_t *infoCnt,
    mach_port_t *object_name);
EOF
tail_; } > "$D/mach/vm_map.h"

{ hdr mach/mach_host.h mach_host.defs "host info, page size"
cat <<'EOF'
kern_return_t host_page_size(host_t host, vm_size_t *out_page_size);
kern_return_t host_info(host_t host, host_flavor_t flavor, host_info_t host_info_out,
    mach_msg_type_number_t *host_info_outCnt);
kern_return_t host_statistics(host_t host_priv, host_flavor_t flavor,
    host_info_t host_info_out, mach_msg_type_number_t *host_info_outCnt);
kern_return_t host_get_clock_service(host_t host, clock_id_t clock_id, clock_serv_t *clock_serv);
kern_return_t host_get_io_master(host_t host, mach_port_t *io_master);
EOF
tail_; } > "$D/mach/mach_host.h"

{ hdr mach/host_priv.h host_priv.defs "privileged host ops"
cat <<'EOF'
kern_return_t host_set_time(host_priv_t host_priv, mach_timespec_t host_time);
kern_return_t host_reboot(host_priv_t host_priv, int options);
kern_return_t host_get_boot_info(host_priv_t host_priv, kernel_boot_info_t boot_info);
EOF
tail_; } > "$D/mach/host_priv.h"

{ hdr mach/host_security.h host_security.defs "host security"
cat <<'EOF'
kern_return_t host_security_create_task_token(host_security_t host_security,
    task_t parent_task, security_token_t sec_token, audit_token_t audit_token,
    host_t host, ledger_array_t ledgers, mach_msg_type_number_t ledgersCnt,
    boolean_t inherit_memory, task_t *child_task);
EOF
tail_; } > "$D/mach/host_security.h"

{ hdr mach/clock_priv.h clock_priv.defs "clock set"
cat <<'EOF'
kern_return_t clock_set_time(mach_port_t clock_serv, mach_timespec_t new_time);
kern_return_t clock_set_attributes(mach_port_t clock_serv, clock_flavor_t flavor,
    clock_attr_t clock_attr, mach_msg_type_number_t clock_attrCnt);
EOF
tail_; } > "$D/mach/clock_priv.h"

{ hdr mach/processor.h processor.defs "processor info"
cat <<'EOF'
kern_return_t processor_info(processor_t processor, processor_flavor_t flavor,
    host_t *host, processor_info_t processor_info_out, mach_msg_type_number_t *processor_info_outCnt);
kern_return_t processor_start(processor_t processor);
kern_return_t processor_exit(processor_t processor);
kern_return_t processor_set_threads(processor_t processor, thread_act_t thread);
kern_return_t processor_assign(processor_t processor, processor_set_t new_set,
    boolean_t wait);
EOF
tail_; } > "$D/mach/processor.h"

{ hdr mach/processor_set.h processor_set.defs "processor sets"
cat <<'EOF'
kern_return_t processor_set_info(processor_set_name_t set_name, int flavor, host_t *host,
    processor_set_info_t info_out, mach_msg_type_number_t *info_outCnt);
kern_return_t processor_set_default(host_t host, processor_set_t *default_set);
kern_return_t processor_set_policy_enable(processor_set_t pset, int policy);
kern_return_t processor_set_policy_disable(processor_set_t pset, int policy, boolean_t change_threads);
EOF
tail_; } > "$D/mach/processor_set.h"

ls "$D/mach" | wc -l
MIGEOF

cat >"$G/sched.h" <<'SCHEDEOF'
/* sched.h -- synthesized for the ios-nord cross sysroot.
 *
 * The iOS SDK ships usr/include/sched.h, but no apple-oss-distributions project
 * carries it (Libc-1534.100.14 has no sched.h; xnu only has the kernel's
 * osfmk/kern/sched.h).  libc++'s __threading_support:43 includes <sched.h> for
 * sched_yield(), so a POSIX-shaped declaration set is enough.  These are our
 * own declarations of documented POSIX/Apple API -- no Apple text is copied.
 * The symbol set is checked against libSystem.B.tbd, which exports all three.
 */
#ifndef _SCHED_H_
#define _SCHED_H_

#include <sys/cdefs.h>
#include <sys/types.h>

__BEGIN_DECLS

struct sched_param {
	int sched_priority;
	char __opaque[4];
};

#define SCHED_OTHER 0
#define SCHED_FIFO 4
#define SCHED_RR 2

int sched_yield(void);
int sched_get_priority_max(int);
int sched_get_priority_min(int);
int sched_getparam(pid_t, struct sched_param *);
int sched_setparam(pid_t, const struct sched_param *);
int sched_setscheduler(pid_t, int, const struct sched_param *);
int sched_getscheduler(pid_t);

__END_DECLS

#endif /* _SCHED_H_ */
SCHEDEOF

cat >"$G/TargetConditionals.h" <<'TCEOF'
/* TargetConditionals.h -- synthesized for the ios-nord cross sysroot.
 *
 * Apple ships this file only inside the SDK (it is not in any
 * apple-oss-distributions project: checked Libc-1534.100.14 and
 * xnu-8796.141.3 EXTERNAL_HEADERS, neither carries it).  This is a
 * reimplementation of the documented TARGET_* macro surface, not an
 * Apple file; written for ios-nord, no licence restriction.
 *
 * Values describe the build target this sysroot exists for:
 * arm64, iOS device (not simulator), 64-bit little-endian.
 */
#ifndef __TARGETCONDITIONALS__
#define __TARGETCONDITIONALS__

#define TARGET_OS_MAC               1
#define TARGET_OS_WIN32             0
#define TARGET_OS_UNIX              0
#define TARGET_OS_EMBEDDED          1
#define TARGET_OS_IPHONE            1
#define TARGET_OS_IOS               1
#define TARGET_OS_MACCATALYST       0
#define TARGET_OS_MACOS             0
#define TARGET_OS_OSX               0
#define TARGET_OS_TV                0
#define TARGET_OS_WATCH             0
#define TARGET_OS_VISION            0
#define TARGET_OS_DRIVERKIT         0
#define TARGET_OS_EXCLAVEKIT        0
#define TARGET_OS_SIMULATOR         0
#define TARGET_OS_UNKNOWN           0

#define TARGET_OS_WIN32_64          0
#define TARGET_OS_WINCE             0
#define TARGET_OS_LINUX             0

#define TARGET_CPU_PPC              0
#define TARGET_CPU_PPC64            0
#define TARGET_CPU_68K              0
#define TARGET_CPU_X86              0
#define TARGET_CPU_X86_64           0
#define TARGET_CPU_ARM              0
#define TARGET_CPU_ARM64            1
#define TARGET_CPU_MIPS             0
#define TARGET_CPU_SPARC            0
#define TARGET_CPU_ALPHA            0
#define TARGET_CPU_RISCV32          0
#define TARGET_CPU_RISCV64          0
#define TARGET_CPU_ARM64E           0

#define TARGET_RT_MAC_CFM           0
#define TARGET_RT_MAC_MACHO         1
#define TARGET_RT_LITTLE_ENDIAN     1
#define TARGET_RT_BIG_ENDIAN        0
#define TARGET_RT_64_BIT            1
#define TARGET_RT_MAC_68881         0
#define TARGET_RT_MAC_FCNTL         0
#define TARGET_RT_HAS_FLOAT16       1

#endif /* __TARGETCONDITIONALS__ */
TCEOF

cat >"$G/MacTypes.h" <<'MCTEOF'
/* MacTypes.h -- minimal stand-in (Carbon's real one is not in any
 * apple-oss-distributions project).  Only the scalar typedefs libkern/OSTypes.h
 * and the MIG host build need.  Synthesized for ios-nord. */
#ifndef __MACTYPES__
#define __MACTYPES__

#include <stdint.h>

typedef int8_t   SInt8;
typedef uint8_t  UInt8;
typedef int16_t  SInt16;
typedef uint16_t UInt16;
typedef int32_t  SInt32;
typedef uint32_t UInt32;
typedef int64_t  SInt64;
typedef uint64_t UInt64;
typedef float    Float32;
typedef double   Float64;
typedef SInt16   OSErr;
typedef SInt32   OSStatus;
typedef UInt32   OSType;
typedef UInt32   FourCharCode;
typedef unsigned char Boolean;

#endif /* __MACTYPES__ */
MCTEOF

cat >"$G/math.h" <<'MTHEOF'
/* math.h -- dispatcher for the ios-nord sysroot.
 *
 * Libm's Source/math.h only knows ppc and i386; the arm64 SDK header is
 * Source/ARM/math.h (installed here as architecture/arm/math.h).  arm64 gets the
 * arm header, as the SDK does.
 */
#ifndef __MATH_H__
#define __MATH_H__

#if defined(__arm__) || defined(__arm64__)
#include <architecture/arm/math.h>
#elif defined(__i386__) || defined(__x86_64__)
#include <architecture/i386/math.h>
#else
#error Unknown architecture
#endif

#endif /* __MATH_H__ */
MTHEOF

cat >"$G/priority_private.h" <<'PPEOF'
/* pthread/priority_private.h -- synthesized minimal stand-in.
 *
 * No apple-oss-distributions tag of libpthread ships this file (checked
 * 514.100.2 and 539.100.4: both only reference it, e.g. private/pthread/
 * qos_private.h:28), so the private-surface type it must provide is declared
 * here: the pthread priority word used by the qos_private prototypes.
 * Layout follows the kernel's own use (pthread_priority_t is a 32-bit word:
 * band in the high byte, sched priority in the low 16 bits).
 */
#ifndef _PTHREAD_PRIORITY_PRIVATE_H_
#define _PTHREAD_PRIORITY_PRIVATE_H_

#include <stdint.h>

typedef uint32_t pthread_priority_t;

#define _PTHREAD_PRIORITY_SCHED_PRI_FLAG 0x80000000u
#define _PTHREAD_PRIORITY_PROMOTION_FLAG 0x40000000u
#define _PTHREAD_PRIORITY_SPECIAL_QOS_MASK 0x3f000000u
#define _PTHREAD_PRIORITY_BAND_MASK 0x00ff0000u
#define _PTHREAD_PRIORITY_SCHED_PRI_MASK 0x0000ffffu
#define _PTHREAD_PRIORITY_DEFAULT_RELATION_PRIORITY 0x80000000u

#define _PTHREAD_PRIORITY_BAND_UNSPECIFIED 0x3f000000u
#define _PTHREAD_PRIORITY_BAND_IDLE 0x00000000u
#define _PTHREAD_PRIORITY_BAND_BACKGROUND 0x01000000u
#define _PTHREAD_PRIORITY_BAND_UTILITY 0x11000000u
#define _PTHREAD_PRIORITY_BAND_DEFAULT 0x21000000u
#define _PTHREAD_PRIORITY_BAND_USER_INITIATED 0x31000000u
#define _PTHREAD_PRIORITY_BAND_USER_INTERACTIVE 0x41000000u

#endif /* _PTHREAD_PRIORITY_PRIVATE_H_ */
PPEOF

# ---- 1. C headers -------------------------------------------------------------
# Order matters only where a later copy must win; copies never delete, so a
# re-run over an existing tree is safe.
step "stage C headers"
IN=$T/usr/include
LOC=$T/usr/local/include
mkdir -p "$IN/sys" "$IN/libkern" "$IN/bsm" "$IN/mach_debug" "$IN/mach" "$IN/machine" \
	"$IN/arm" "$IN/malloc" "$IN/pthread" "$IN/os" "$LOC/os" "$LOC/pthread" "$LOC/sys" \
	"$IN/architecture/arm"

# xnu: the BSD and MACH public surface
cp -a "$XN/bsd/sys/." "$IN/sys/"
cp -a "$XN/osfmk/mach/." "$IN/mach/"
rm -rf "$IN/mach/machine"
mkdir -p "$IN/mach/machine"
cp -a "$XN/osfmk/mach/arm/." "$IN/mach/machine/"
# the SDK's mach/machine/thread_state.h carries THREAD_STATE_MAX, which
# mach/thread_status.h:85 relies on; the kernel-source copy does not
if ! grep -q '^#define THREAD_STATE_MAX' "$IN/mach/machine/thread_state.h"; then
	printf '#define THREAD_STATE_MAX ARM_THREAD_STATE_MAX\n' >>"$IN/mach/machine/thread_state.h"
fi
cp -a "$XN/bsd/machine/." "$IN/machine/"
cp -a "$XN/bsd/arm/." "$IN/arm/"
cp "$XN/osfmk/arm/arch.h" "$IN/arm/arch.h"       # SDK-generated upstream
cp -a "$XN/libkern/libkern/." "$IN/libkern/"
cp -a "$XN/bsd/bsm/." "$IN/bsm/"
cp -a "$XN/osfmk/mach_debug/." "$IN/mach_debug/"
cp -a "$XN/libsyscall/mach/mach/." "$IN/mach/"   # SDK-side mach shims (vm_page_size.h)
for f in "$XN"/osfmk/machine/*.h; do             # kernel-internal helpers the SDK tree lacks
	b=$(basename "$f")
	[ -e "$IN/machine/$b" ] || cp "$f" "$IN/machine/"
done
cp -a "$XN/EXTERNAL_HEADERS/." "$IN/"
cp "$XN/libsyscall/wrappers/gethostuuid.h" "$IN/"

# libc on top; its sys/cdefs.h is a #include_next shim, xnu's is the real one
for f in "$LIB"/include/sys/*; do
	b=$(basename "$f")
	[ "$b" = cdefs.h ] && continue
	[ -e "$IN/sys/$b" ] || cp -a "$f" "$IN/sys/"
done
cp -a "$LIB/include/." "$IN/" 2>/dev/null || true
rm -f "$IN/sys/cdefs.h"
cp "$XN/bsd/sys/cdefs.h" "$IN/sys/cdefs.h"
cp "$LIB/locale/xlocale_private.h" "$IN/"           # _ctype.h:67 includes it
cp -a "$LIB/locale/FreeBSD/." "$IN/"
cp "$LIB/stdtime/FreeBSD/timelocal.h" "$IN/"

# pthread + malloc + libplatform
cp -a "$MAL/include/malloc/." "$IN/malloc/"
cp -a "$PTH/include/sys/." "$IN/sys/"
cp -a "$PTH/include/pthread/." "$IN/pthread/"
cp "$PTH/include/pthread/pthread.h" "$IN/pthread.h"
cp -a "$PLAT/include/os/." "$IN/os/"
cp -a "$PLAT/private/os/." "$LOC/os/"
cp -a "$XN/libsyscall/os/." "$LOC/os/"
cp -a "$XN/libkern/os/." "$LOC/os/"
cp "$PTH/include/sys/qos.h" "$IN/pthread/qos.h"     # SDK installs public qos here
cp -a "$PTH/private/pthread/." "$LOC/pthread/"
cp -a "$PTH/private/sys/." "$LOC/sys/"
cp "$G/priority_private.h" "$LOC/pthread/priority_private.h"

# dlfcn (dyld) + the two headers no open-source project ships
cp "$DY/include/dlfcn.h" "$IN/dlfcn.h"
cp "$G/TargetConditionals.h" "$IN/TargetConditionals.h"
cp "$G/MacTypes.h" "$IN/MacTypes.h"
# sched.h exists in the SDK but in no open-source tree (libc++ needs sched_yield)
cp "$G/sched.h" "$IN/sched.h"
# nl_types.h lives in Libc's include/FreeBSD, not Libc's include/
cp "$LIB/include/FreeBSD/nl_types.h" "$IN/nl_types.h"

# math: Libm's Source/math.h has no arm64 branch; the SDK's arm64 header is
# Source/ARM/math.h, so dispatch to it for __arm64__
cp "$LIBM/Source/ARM/math.h" "$IN/architecture/arm/math.h"
cp "$G/math.h" "$IN/math.h"
cp "$LIBM/Source/fenv.h" "$IN/fenv.h" 2>/dev/null || true
cp "$LIBM/Source/complex.h" "$IN/complex.h" 2>/dev/null || true

# zlib 1.2.11 public headers (step 4: zlib.h must exist even before libz ships)
cp "$ZL/zlib.h" "$ZL/zconf.h" "$IN/"

# SDK-generated sys/ files: _symbol_aliasing.h (make_symbol_aliasing.sh needs the
# SDK's availability.pl) and syscall.h (makesyscalls.sh, run here directly)
/usr/bin/python3 -I "$G/alias.py" >"$IN/sys/_symbol_aliasing.h" ||
	die "could not write sys/_symbol_aliasing.h"
sh "$XN/bsd/sys/make_posix_availability.sh" "$IN/sys/_posix_availability.h" ||
	die "make_posix_availability.sh failed"
(cd "$T" && sh "$XN/bsd/kern/makesyscalls.sh" "$XN/bsd/kern/syscalls.master" header) ||
	die "makesyscalls.sh failed"
mv "$T/syscall.h" "$IN/sys/syscall.h"

# Availability*: xnu's EXTERNAL_HEADERS copy is the 2016 four-platform vintage and
# its __API_UNAVAILABLE rejects the 5-platform markup in iOS 16's own headers.
# Build AvailabilityVersions-141.1's templates instead; `availability` is a python
# script that preprocesses its own DSL first (CMakeLists.txt:63,112).
step "build Availability headers from AvailabilityVersions-141.1"
mkdir -p "$T/av"
cp "$AV/availability" "$AV/availability.dsl" "$T/av/"
(cd "$T/av" && /usr/bin/python3 -I ./availability --preprocess "$AV/availability" availability) ||
	die "availability --preprocess (self) failed"
for t in Availability.h AvailabilityInternal.h AvailabilityInternalLegacy.h \
	AvailabilityMacros.h AvailabilityVersions.h VersionMap.h; do
	(cd "$T/av" && /usr/bin/python3 -I ./availability --preprocess "$AV/templates/$t" "$t") ||
		die "availability preprocess failed: $t"
done
for t in AvailabilityInternalPrivate.h AvailabilityProhibitedInternal.h; do
	(cd "$T/av" && /usr/bin/python3 -I ./availability --preprocess "$AV/templates/$t" "$t") ||
		die "availability preprocess failed: $t"
done
for t in Availability.h AvailabilityInternal.h AvailabilityInternalLegacy.h \
	AvailabilityMacros.h AvailabilityVersions.h; do
	cp "$T/av/$t" "$IN/$t"
done
for t in AvailabilityInternalPrivate.h AvailabilityProhibitedInternal.h; do
	mkdir -p "$LOC"
	cp "$T/av/$t" "$LOC/$t"
done

# MIG-generated mach headers the SDK ships but the open tree only has as .defs
sh "$G/mk_mach_stubs.sh" "$IN" >/dev/null || die "mach stub generation failed"

# ---- 2. merge the staged headers over $OUT (no deletion) ----------------------
step "merge headers into $OUT"
cp -a "$T/usr" "$OUT/"
say "$(find "$OUT/usr/include" -type f | wc -l) files in usr/include, $(find "$OUT/usr/local/include" -type f | wc -l) in usr/local/include"

# ---- 3. .tbd stubs from our own dyld cache ------------------------------------
if [ "$DO_TBD" = yes ]; then
	step "generate .tbd stubs from $(basename "$CACHE")"
	C=$CACHE
	mkdir -p "$OUT/usr/lib"
	tbd() { # tbd IMAGE_PATH OUTDIR LEAF
		img=$1 dir=$2 leaf=$3
		set -- /usr/bin/python3 -I "$G/gen_tbd.py" "$C" "$img"
		for r in $(/usr/bin/python3 -I "$G/reexports.py" "$C" "$img"); do
			set -- "$@" --union "$r"
		done
		mkdir -p "$(under "$OUT" "$dir")"
		"$@" "$(under "$OUT" "$dir/$leaf.tbd")" || die "tbd failed for $img"
	}
	tbd /usr/lib/libSystem.B.dylib "$OUT/usr/lib" libSystem.B
	tbd /usr/lib/libc++.1.dylib "$OUT/usr/lib" libc++.1
	tbd /usr/lib/libc++abi.dylib "$OUT/usr/lib" libc++abi
	tbd /usr/lib/libz.1.dylib "$OUT/usr/lib" libz.1
	tbd /System/Library/Frameworks/IOSurface.framework/IOSurface \
		"$OUT/System/Library/Frameworks/IOSurface.framework" IOSurface
	tbd /System/Library/Frameworks/IOKit.framework/Versions/A/IOKit \
		"$OUT/System/Library/Frameworks/IOKit.framework" IOKit
	tbd /System/Library/Frameworks/OpenGLES.framework/OpenGLES \
		"$OUT/System/Library/Frameworks/OpenGLES.framework" OpenGLES
	tbd /System/Library/Frameworks/CoreFoundation.framework/CoreFoundation \
		"$OUT/System/Library/Frameworks/CoreFoundation.framework" CoreFoundation
	tbd /System/Library/Frameworks/QuartzCore.framework/QuartzCore \
		"$OUT/System/Library/Frameworks/QuartzCore.framework" QuartzCore
	tbd /System/Library/Frameworks/Metal.framework/Metal \
		"$OUT/System/Library/Frameworks/Metal.framework" Metal
	# ld64.lld resolves -lSystem/-lz/-lc++ through these short names, but the
	# install names in the cache are the versioned ones
	ln -sf libz.1.tbd "$OUT/usr/lib/libz.tbd"
	ln -sf libc++.1.tbd "$OUT/usr/lib/libc++.tbd"
	ln -sf libSystem.B.tbd "$OUT/usr/lib/libSystem.tbd"
	say "$(find "$OUT" -name '*.tbd' -type f | wc -l) tbd files, $(find "$OUT" -name '*.tbd' | wc -l) names incl. symlinks"
fi

# ---- 4. MANIFEST.sha256 : every input, then every output ----------------------
step "write MANIFEST.sha256"
M=$OUT/MANIFEST.sha256
{
	printf '# %s -- generated %s UTC\n' "$PROG" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf '# sha256 of every input, then of every file written under %s\n' "$OUT"
	printf '#\n# inputs\n'
	printf '%s  input:script:%s\n' "$(sha_of "$0" 2>/dev/null || echo unknown)" "$0"
	[ "$DO_TBD" = yes ] && printf '%s  input:dyldcache:%s\n' "$(sha_of "$CACHE")" "$CACHE"
	while read -r dirname tag proj; do
		url=$(url_of "$proj" "$tag")
		t=$SRC/dl/$tag.tar.gz
		if [ -f "$t" ]; then
			printf '%s  input:tarball:%s  (%s)\n' "$(sha_of "$t")" "$t" "$url"
		else
			printf '%-64s  input:tree:%s  (no tarball; %s)\n' "-" "$SRC/$dirname" "$url"
		fi
	done <<EOF
$PINNED
EOF
	printf '#\n# outputs\n'
	(cd "$OUT" && find . -type f ! -name MANIFEST.sha256 ! -path './.src/*' ! -path './.work.*' |
		LC_ALL=C sort | xargs -r sha256sum)
} >"$M" || die "could not write $M"

if [ "$QUIET" = yes ]; then
	printf '%s: %s files, %s tbd, %s\n' "$PROG" \
		"$(find "$OUT" -type f -not -path "$OUT/.src/*" -not -path "$OUT/.work*/*" | wc -l)" \
		"$(find "$OUT" -name '*.tbd' -type f | wc -l)" \
		"$(du -sh --exclude=.work.\* --exclude=.src "$OUT" | cut -f1)"
else
	printf '\n%s: ok\n  out      %s\n  files    %s (%s)\n  tbds     %s\n  manifest %s\n  src      %s\n' \
		"$PROG" "$OUT" \
		"$(find "$OUT" -type f -not -path "$OUT/.src/*" -not -path "$OUT/.work*/*" | wc -l)" \
		"$(du -sh --exclude=.work.\* --exclude=.src "$OUT" | cut -f1)" \
		"$(find "$OUT" -name '*.tbd' | wc -l)" "$M" "$SRC"
fi
