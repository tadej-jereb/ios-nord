#!/usr/bin/env python3
"""Android sparse image (libsparse) encoder/decoder/inspector.

  sparse.py encode IN RAW OUT.simg     raw -> Android sparse (skips holes)
  sparse.py decode IMG.simg OUT.raw    Android sparse -> raw
  sparse.py info IMG.simg              header + chunk table summary
  sparse.py compare A B                compare two files of equal length

An HFS+ image is created as a sparse *host* file (truncate -s 16G), so its
unallocated area is a file hole: a plain `fastboot flash` would transmit all
16 GiB. The sparse format carries only allocated 4 KiB blocks, so the USB
transfer is the size of the real content. `fastboot` unpacks it in the
bootloader (libsparse), no host-side simg2img needed.

Format (AOSP system/core/libsparse/sparse_format.h, little endian):
  file header 28 B: magic 0xed26ff3a, 1.0, hdr 28/12, blk 4096,
                    total_blks, total_chunks, checksum
  chunk hdr 12 B:  RAW 0xcac1 (payload follows) | FILL 0xcac2 (4 B value) |
                   DONT_CARE 0xcac3, reserved, chunk_sz, total_sz
"""
import os, struct, sys

MAGIC = 0xED26FF3A
BLK = 4096
RAW, FILL, DONT_CARE, CRC32 = 0xCAC1, 0xCAC2, 0xCAC3, 0xCAC4
MAX_RAW_BLOCKS = 1024          # 4 MiB per raw chunk
MAX_HOLE_BLOCKS = 32768        # 128 MiB per DONT_CARE chunk


def encode(src, dst):
    total = os.path.getsize(src)
    if total % BLK:
        sys.exit(f'{src}: size {total} is not a multiple of {BLK}')
    total_blks = total // BLK
    stats = dict(chunks=0, holes=0, raw=0)
    with open(src, 'rb') as fi, open(dst, 'wb') as fo:
        fo.write(struct.pack('<IHHHHIIII', MAGIC, 1, 0, 28, 12, BLK,
                             total_blks, 0, 0))
        run = []                                     # pending non-zero blocks
        hole = 0                                     # pending hole blocks

        def put_hole(n):
            while n:
                part = min(n, MAX_HOLE_BLOCKS)
                fo.write(struct.pack('<HHII', DONT_CARE, 0, part, 12))
                stats['chunks'] += 1
                stats['holes'] += part
                n -= part

        def flush_raw():
            while run:
                part, run[:] = run[:MAX_RAW_BLOCKS], run[MAX_RAW_BLOCKS:]
                fo.write(struct.pack('<HHII', RAW, 0, len(part), 12 + BLK * len(part)))
                fo.write(b''.join(part))
                stats['chunks'] += 1
                stats['raw'] += len(part)

        for _ in range(total_blks):
            blk = fi.read(BLK)
            if blk.count(0) == BLK:                  # hole: coalesce
                flush_raw()
                hole += 1
            else:
                if hole:
                    put_hole(hole)
                    hole = 0
                run.append(blk)
                if len(run) >= MAX_RAW_BLOCKS:
                    flush_raw()
        if hole:
            put_hole(hole)
        flush_raw()
        fo.seek(0)
        fo.write(struct.pack('<IHHHHIIII', MAGIC, 1, 0, 28, 12, BLK,
                             total_blks, stats['chunks'], 0))
    return total_blks, stats['chunks'], stats['holes'], stats['raw']


def decode(src, dst, quiet=False):
    with open(src, 'rb') as fi:
        magic, major, minor, fhdr, chdr, blk, total_blks, chunks, _ = \
            struct.unpack('<IHHHHIIII', fi.read(28))
        if magic != MAGIC:
            sys.exit(f'{src}: not a sparse image (magic {magic:#x})')
        if (major, blk, fhdr, chdr) != (1, BLK, 28, 12):
            sys.exit(f'{src}: unsupported sparse variant '
                     f'(v{major}.{minor}, blk {blk}, hdrs {fhdr}/{chdr})')
        fi.seek(fhdr)
        written = 0
        with open(dst, 'wb') as fo:
            for n in range(chunks):
                ctype, _, csz, tsz = struct.unpack('<HHII', fi.read(chdr))
                if ctype == RAW:
                    fo.write(fi.read(csz * blk))
                    written += csz
                elif ctype == DONT_CARE:
                    fo.seek(csz * blk, 1)
                    written += csz
                elif ctype == FILL:
                    val = fi.read(4)
                    fo.write(val * (csz * blk // 4))
                    written += csz
                elif ctype == CRC32:
                    fi.read(tsz - chdr)
                else:
                    sys.exit(f'{src}: unknown chunk type {ctype:#x} at #{n}')
            # materialize the trailing hole that seek() left
            if written < total_blks:
                fo.seek(total_blks * blk - 1)
                fo.write(b'\0')
    return written, total_blks


def info(src):
    with open(src, 'rb') as fi:
        magic, major, minor, fhdr, chdr, blk, total_blks, chunks, csum = \
            struct.unpack('<IHHHHIIII', fi.read(28))
        if magic != MAGIC:
            sys.exit(f'{src}: not a sparse image')
        fi.seek(fhdr)
        kinds, raw, hole = {}, 0, 0
        for _ in range(chunks):
            ctype, _, csz, tsz = struct.unpack('<HHII', fi.read(chdr))
            kinds[ctype] = kinds.get(ctype, 0) + 1
            if ctype in (RAW, FILL):
                raw += csz
            elif ctype == DONT_CARE:
                hole += csz
            if ctype == RAW:
                fi.seek(csz * blk, 1)
            elif ctype == FILL or ctype == CRC32:
                fi.seek(tsz - chdr, 1)
    print(f'{src}: v{major}.{minor} blk={blk} total_blks={total_blks} '
          f'({total_blks * blk} bytes) chunks={chunks} checksum={csum:#x}')
    print(f'  stored blocks={raw} ({raw * blk} bytes) holes={hole} '
          f'({hole * blk} bytes) kinds={ {hex(k): v for k, v in kinds.items()} }')
    print(f'  file size={os.path.getsize(src)} bytes')
    return total_blks * blk, raw * blk


def compare(a, b):
    if os.path.getsize(a) != os.path.getsize(b):
        sys.exit(f'size differs: {os.path.getsize(a)} != {os.path.getsize(b)}')
    import hashlib
    na = nb = 0
    with open(a, 'rb') as fa, open(b, 'rb') as fb:
        while True:
            ba, bb = fa.read(1 << 20), fb.read(1 << 20)
            if not ba and not bb:
                break
            if ba != bb:
                sys.exit(f'first difference in {na >> 20} MiB block')
            na += len(ba)
            nb += len(bb)
    print(f'identical: {na} bytes match')


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    cmd = sys.argv[1]
    if cmd == 'encode' and len(sys.argv) == 4:
        t, c, h, r = encode(sys.argv[2], sys.argv[3])
        print(f'{sys.argv[3]}: {os.path.getsize(sys.argv[3])} bytes, '
              f'{t} blocks, {c} chunks, {r} stored, {h} hole blocks')
    elif cmd == 'decode' and len(sys.argv) == 4:
        w, t = decode(sys.argv[2], sys.argv[3])
        print(f'{sys.argv[3]}: {w}/{t} blocks written')
    elif cmd == 'info' and len(sys.argv) == 3:
        info(sys.argv[2])
    elif cmd == 'compare' and len(sys.argv) == 4:
        compare(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
