#!/usr/bin/env python3
"""Dump the live-FDT memory map of an avicii board.dtb as JSON for mkadt_avicii.py.

  fdt-mem.py board.dtb > avicii-fdt-mem.json

Reads /memory@... reg entries and every /reserved-memory child into

  {"source": ..., "memory": [{"node":..., "base":"0x..","size":"0x.."}], "reserved": [...]}

and nothing else. mkadt_avicii.py subtracts the reserved list from the memory
list and takes the topmost usable extent, so this file describes the map the
bootloader handed us rather than any address anyone remembered.

Cell sizes come from the root '#address-cells'/'#size-cells' (lito: 2/2). A tree
without a /memory node means ABL did not add one - say so instead of emitting an
empty map.
"""
import json
import struct
import sys

MAGIC = b'\xd0\x0d\xfe\xed'
BEGIN_NODE, END_NODE, PROP, NOP, END = 1, 2, 3, 4, 9


def be32(b, off):
    return struct.unpack_from('>I', b, off)[0]


def main(argv):
    if len(argv) != 2 or argv[1] in ('-h', '--help'):
        sys.exit(f'usage: {argv[0]} board.dtb   (writes dram ranges as JSON; '
                 'expects a device live FDT, a static DTB has no /memory)')
    blob = open(argv[1], 'rb').read()
    if blob[:4] != MAGIC:
        sys.exit(f'{argv[1]}: not an FDT (magic {blob[:4].hex()})')
    total = be32(blob, 4)
    if total > len(blob):
        sys.exit(f'{argv[1]}: totalsize {total} exceeds file size {len(blob)}')

    p, strings = be32(blob, 8), be32(blob, 12)
    depth = 0
    ac = sc = 2
    path = []
    mem, reserved = [], []

    while p < total:
        tok = be32(blob, p)
        p += 4
        if tok == BEGIN_NODE:
            end = blob.index(b'\0', p)
            name = blob[p:end].decode('latin-1')
            p = (end + 1 + 3) & ~3
            depth += 1
            path.append(name)
        elif tok == END_NODE:
            depth -= 1
            if path:
                path.pop()
            if depth <= 0:
                break
        elif tok == PROP:
            ln, nameoff = struct.unpack_from('>II', blob, p)
            val = blob[p + 8:p + 8 + ln]
            end = blob.index(b'\0', strings + nameoff)
            pname = blob[strings + nameoff:end].decode('latin-1')
            p = (p + 8 + ln + 3) & ~3
            here = '/' + '/'.join(x for x in path if x)
            if depth == 1:
                if pname == '#address-cells' and ln == 4:
                    ac = be32(val, 0)
                elif pname == '#size-cells' and ln == 4:
                    sc = be32(val, 0)
            elif pname == 'reg' and depth >= 2:
                ent = (ac + sc) * 4
                for off in range(0, ln - ent + 1, ent):
                    base = int.from_bytes(val[off:off + ac * 4], 'big')
                    size = int.from_bytes(val[off + ac * 4:off + ent], 'big')
                    if not size:
                        continue
                    rec = {'node': here, 'base': hex(base), 'size': hex(size)}
                    if depth == 2 and path[-1].startswith('memory'):
                        mem.append(rec)
                    elif depth == 3 and path[1] == 'reserved-memory':
                        rec['compatible'] = _compat(blob, strings, p, path, depth)
                        reserved.append(rec)
        elif tok in (NOP, END):
            if tok == END:
                break
        else:
            sys.exit(f'{argv[1]}: bad struct token {tok} at 0x{p - 4:x}')

    if not mem:
        sys.exit(f'{argv[1]}: no /memory node (ABL did not add the live map)')
    json.dump({'source': argv[1], 'memory': mem, 'reserved': reserved},
              sys.stdout, indent=1)
    print()


def _compat(blob, strings, p, path, depth):
    """Best-effort 'compatible' of the current reserved-memory child."""
    try:
        q, d = p, depth
        while d == depth:
            tok = be32(blob, q)
            q += 4
            if tok == PROP:
                ln, nameoff = struct.unpack_from('>II', blob, q)
                end = blob.index(b'\0', strings + nameoff)
                if blob[strings + nameoff:end] == b'compatible':
                    return blob[q + 8:q + 8 + ln].replace(b'\0', b' ').decode('latin-1').strip()
                q = (q + 8 + ln + 3) & ~3
            elif tok == BEGIN_NODE:
                q = (blob.index(b'\0', q) + 1 + 3) & ~3
                d += 1
            elif tok == END_NODE:
                d -= 1
            elif tok == END:
                return ''
        return ''
    except (ValueError, struct.error):
        return ''


if __name__ == '__main__':
    main(sys.argv)
