#!/usr/bin/env python3
"""Pack an xnu kernel Mach-O + ADT into the payload the sweet shim boots.

  mkpayload.py KERNEL ADT OUT [--cmdline "..."] [--ramdisk IMAGE] [--shared-cache IMAGE]

The kernel is linked as a PIE with LC_DYLD_CHAINED_FIXUPS. Nobody else
(no kmutil, no iBoot) resolves those for us, and xnu only rebases static
kernelcaches itself, so the chains are walked here and every pointer is
rewritten to its unslid target. The shim then only copies flat segments.

Payload layout (little endian, all offsets from payload start):
  0x000  char  magic[8] = "SWEETXNU"
  0x008  u32   version = 1, nsegs
  0x010  u64   virt_base      kernel VA that maps to phys_base
  0x018  u64   entry_va       LC_UNIXTHREAD pc
  0x020  u64   adt_off, adt_size
  0x030  u64   kernel_end_va  end of the highest segment (page aligned)
  0x038  u64   phys_base      kernel-managed RAM (same values as the ADT's dram-base/size)
  0x040  u64   mem_size
  0x048  char  cmdline[608]
  0x2a8  seg[nsegs] { u64 vmaddr, vmsize, file_off(in payload), file_size }

--ramdisk appends IMAGE as one more segment after the kernel and moves
kernel_end past it, so the shim needs no changes: the image lands below the
ADT and boot_args, inside topOfKernelData (never handed to the VM), and the
ADT gets /chosen/memory-map "RAMDisk" = <phys, size> for IOFindBSDRoot to
turn into md0 (boot with rd=md0).  If that would put the image inside the
bootstrap console's framebuffer it is moved above it instead (see EARLY_FB_*),
and --ramdisk-addr ADDR overrides the physical address explicitly.
"""
import argparse, mmap, os, struct, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import adt  # noqa: E402

LC_SEGMENT_64, LC_UNIXTHREAD, LC_DYLD_CHAINED_FIXUPS, LC_MAIN = 0x19, 0x5, 0x80000034, 0x80000028
PAGE = 0x4000
BOOT_LINE_LENGTH = 608
CMDLINE = 0x48
SEG_TABLE = CMDLINE + BOOT_LINE_LENGTH	# 0x2a8

# The bootstrap console (xnu-avicii patches 0010/0012) paints the panel straight
# at physical 0xa0000000: start.s fills a 32-row band at 0xa0000000+2368*4320 and
# sweet_early_clear_row() repaints 32 more rows per printed line from row 0 down,
# so with sweetecon=1 the whole 1080x2400 panel is rewritten in 0xff000000 words
# from 0xa0000000 to 0xa0000000 + 2400*4320 = 0xa09e3400.  A ramdisk rooted at
# kernel_end (0x924c8000 for the 8G tier-2 payload) starts inside that window and
# its first ~10MB - file offset 0xdb38000 onward - is exactly what the console
# overwrites, which is what produced 'does not start with MH_MAGIC: 0xFF000000'.
EARLY_FB_PA = 0xa0000000
EARLY_FB_BAND = 2400 * 4320		# 0x9e3400: whole panel, EARLY_STRIDE bytes/row
RAMDISK_FLOOR = 0xa0200000		# never place the root image below this
RAMDISK_CLEAR = 0xa1000000		# 16MB up: clear of the whole 0xa09e3400 band


def parse_macho(buf):
    magic, cputype, cpusub, ftype, ncmds, sizeofcmds, flags, _ = struct.unpack_from('<8I', buf, 0)
    assert magic == 0xfeedfacf, 'not a 64-bit Mach-O'
    segs, entry, entryoff, fixups = [], None, None, None
    off = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<II', buf, off)
        if cmd == LC_SEGMENT_64:
            name = buf[off + 8:off + 24].split(b'\0')[0].decode()
            vmaddr, vmsize, fileoff, filesize = struct.unpack_from('<4Q', buf, off + 24)
            segs.append(dict(name=name, vmaddr=vmaddr, vmsize=vmsize, fileoff=fileoff, filesize=filesize))
        elif cmd == LC_UNIXTHREAD:
            flavor, count = struct.unpack_from('<II', buf, off + 8)
            # arm_thread_state64: x0..x28, fp, lr, sp, pc, cpsr
            entry, = struct.unpack_from('<Q', buf, off + 16 + 32 * 8)
        elif cmd == LC_MAIN:
            # newer ld64/lld emit LC_MAIN (entryoff into __TEXT) instead of a thread state
            entryoff, = struct.unpack_from('<Q', buf, off + 8)
        elif cmd == LC_DYLD_CHAINED_FIXUPS:
            fixups = struct.unpack_from('<II', buf, off + 8)	# dataoff, datasize
        off += size
    if entry is None and entryoff is not None:
        text = next((s for s in segs if s['name'] == '__TEXT'), None)
        entry = (text['vmaddr'] if text else 0) + entryoff
    return dict(cputype=cputype, cpusub=cpusub & 0xff, segs=segs, entry=entry, fixups=fixups)


def apply_chained_fixups(buf, m):
    """Rewrite every chained rebase in buf (the whole file) to its plain target VA."""
    if not m['fixups']:
        return 0
    data_off, _ = m['fixups']
    _, starts_off, _, _, imports_count, _, _ = struct.unpack_from('<7I', buf, data_off)
    assert imports_count == 0, 'kernel has binds; only rebases are supported'
    image_base = m['segs'][0]['vmaddr']		# __TEXT, holds the mach header
    seg_count, = struct.unpack_from('<I', buf, data_off + starts_off)
    nfix = 0
    for i in range(seg_count):
        seg_info, = struct.unpack_from('<I', buf, data_off + starts_off + 4 + 4 * i)
        if not seg_info:
            continue
        base = data_off + starts_off + seg_info
        size, page_size, fmt, seg_offset, max_valid, page_count = struct.unpack_from('<IHHQIH', buf, base)
        starts = struct.unpack_from('<%dH' % page_count, buf, base + 22)
        seg = m['segs'][i]
        for p, start in enumerate(starts):
            if start == 0xffff:
                continue
            assert not start & 0x8000, 'DYLD_CHAINED_PTR_START_MULTI not supported'
            loc = seg['fileoff'] + p * page_size + start
            while True:
                raw, = struct.unpack_from('<Q', buf, loc)
                target, nxt, stride = decode(raw, fmt, image_base)
                struct.pack_into('<Q', buf, loc, target)
                nfix += 1
                if not nxt:
                    break
                loc += nxt * stride
    return nfix


def decode(raw, fmt, image_base):
    """Return (unslid target VA, next, stride) for one chained pointer."""
    if fmt in (2, 6):		# DYLD_CHAINED_PTR_64 / _64_OFFSET
        assert not raw >> 63, 'bind in kernel'
        target = raw & ((1 << 36) - 1)
        high8 = (raw >> 36) & 0xff
        nxt = (raw >> 51) & 0xfff
        if fmt == 6:
            target += image_base
        return target | (high8 << 56), nxt, 4
    if fmt == 8:		# DYLD_CHAINED_PTR_64_KERNEL_CACHE
        target = raw & ((1 << 30) - 1)
        nxt = (raw >> 51) & 0xfff
        return image_base + target, nxt, 4
    if fmt in (1, 7, 9, 12):	# arm64e variants (stock VMAPPLE kernel only; PAC is not re-signed)
        auth = raw >> 63
        nxt = (raw >> 51) & 0x7ff
        stride = 4 if fmt in (7, 12) else 8
        if auth:
            target = raw & 0xffffffff
        else:
            target = raw & ((1 << 43) - 1)
            target |= ((raw >> 43) & 0xff) << 56
        if fmt in (7, 9, 12) or auth:
            target += image_base
        return target, nxt, stride
    raise ValueError(f'unsupported chained pointer format {fmt}')


def add_map_entry(adt_blob, name, phys, size):
    """Append /chosen/memory-map <name> = <phys, size> (two uintptr_t)."""
    root, _ = adt.parse(adt_blob)
    chosen = next(c for c in root.children if c.name == 'chosen')
    mmap = next(c for c in chosen.children if c.name == 'memory-map')
    assert mmap.prop(name) is None, 'ADT already has %s' % name
    mmap.props.append((name, 0, struct.pack('<2Q', phys, size)))
    return adt.serialize(root)


def add_ramdisk_to_adt(adt_blob, phys, size):
    """Return the ADT with /chosen/memory-map RAMDisk = <phys, size> (two uintptr_t)."""
    root, _ = adt.parse(adt_blob)
    chosen = next(c for c in root.children if c.name == 'chosen')
    mmap = next(c for c in chosen.children if c.name == 'memory-map')
    assert mmap.prop('RAMDisk') is None, 'ADT already has a RAMDisk'
    mmap.props.append(('RAMDisk', 0, struct.pack('<2Q', phys, size)))
    return adt.serialize(root)


def adt_dram(adt_blob):
    """Kernel-managed RAM <base, size> from the ADT's /chosen dram-base/dram-size."""
    root, _ = adt.parse(adt_blob)
    chosen = next(c for c in root.children if c.name == 'chosen')
    return (struct.unpack('<Q', chosen.prop('dram-base'))[0],
            struct.unpack('<Q', chosen.prop('dram-size'))[0])


def build(kernel_path, adt_path, out_path, cmdline, ramdisk_path=None, shared_cache_path=None,
          ramdisk_addr=None):
    buf = bytearray(open(kernel_path, 'rb').read())
    m = parse_macho(buf)
    nfix = apply_chained_fixups(buf, m)
    segs = [s for s in m['segs'] if s['vmsize']]
    text = next((s for s in segs if s['name'] == '__TEXT' and s['fileoff'] == 0), None)
    assert text is not None, 'no __TEXT segment at file offset 0 (PAGEZERO-only or stripped?'
    # virt_base: 32MB (16K-granule L2 block) below the mach header, so start.s's
    # block mapping that starts at the header's block begins exactly at phys_base.
    virt_base = text['vmaddr'] & ~(0x2000000 - 1)
    kernel_end = max(s['vmaddr'] + s['vmsize'] for s in segs)
    kernel_end = (kernel_end + PAGE - 1) & ~(PAGE - 1)

    adt_blob = open(adt_path, 'rb').read()
    # The ADT decides where the kernel's RAM is (mkadt.py --highmem).
    PHYS_BASE, MEM_SIZE = adt_dram(adt_blob)
    pieces = [(s['vmaddr'], s['vmsize'], buf[s['fileoff']:s['fileoff'] + s['filesize']]) for s in segs]
    ramdisk, shared_cache = None, None
    if ramdisk_path:
        image = open(ramdisk_path, 'rb').read()
        rd_size = (len(image) + PAGE - 1) & ~(PAGE - 1)
        assert EARLY_FB_PA + EARLY_FB_BAND <= RAMDISK_CLEAR, 'RAMDISK_CLEAR is inside the early console band'
        kernel_pa_end = kernel_end - virt_base + PHYS_BASE
        if ramdisk_addr is None:
            rd_pa = kernel_pa_end
            # Leave a hole over the bootstrap console's framebuffer instead of
            # dropping the root image into the words the kernel repaints.
            if rd_pa < RAMDISK_FLOOR:
                rd_pa = RAMDISK_CLEAR
        else:
            rd_pa = ramdisk_addr
        if rd_pa & (PAGE - 1):
            raise SystemExit(f'--ramdisk-addr {rd_pa:#x} is not {PAGE:#x}-aligned')
        if rd_pa < kernel_pa_end:
            raise SystemExit(f'--ramdisk-addr {rd_pa:#x} runs into the kernel, which ends at '
                             f'{kernel_pa_end:#x}')
        rd_va = rd_pa - PHYS_BASE + virt_base
        if rd_pa < EARLY_FB_PA + EARLY_FB_BAND and rd_pa + rd_size > EARLY_FB_PA:
            print(f'warning: ramdisk {rd_pa:#x} overlaps the early console band '
                  f'[{EARLY_FB_PA:#x}, {EARLY_FB_PA + EARLY_FB_BAND:#x})', file=sys.stderr)
        hole = rd_pa - kernel_pa_end
        kernel_end = rd_va + rd_size
        pieces.append((rd_va, rd_size, image))
        adt_blob = add_ramdisk_to_adt(adt_blob, rd_pa, rd_size)
        ramdisk = (hex(rd_pa), hex(rd_size))
        ramdisk_va = f'va {rd_va:#x}, hole {hole:#x}'
    else:
        ramdisk_va = None
    if shared_cache_path:
        # iBoot hands the kernel the dyld shared cache as a /chosen/memory-map
        # region and the arm kernel maps it before initproc; without the region
        # an iOS dyld reports 'no dylib cache' even when the files are on the root.
        sc = open(shared_cache_path, 'rb').read()
        sc_size = (len(sc) + PAGE - 1) & ~(PAGE - 1)
        sc_va = kernel_end
        kernel_end = sc_va + sc_size
        sc_pa = sc_va - virt_base + PHYS_BASE
        pieces.append((sc_va, sc_size, sc))
        adt_blob = add_map_entry(adt_blob, 'dyld shared cache', sc_pa, sc_size)
        shared_cache = (hex(sc_pa), hex(sc_size))

    hdr_size = SEG_TABLE + 32 * len(pieces)
    # Written through an mmap: a RAMDisk root is gigabytes, and holding the whole
    # payload as a bytearray costs as much again as the image itself (a 3 GiB root
    # died at 4.2 GiB anon in a 4 GiB cgroup).
    total = (hdr_size + sum(len(d) + (-len(d) & 0xf) for _, _, d in pieces)
             + len(adt_blob) + (-len(adt_blob) & 0xf))
    fd = open(out_path, 'w+b')
    fd.truncate(total)
    out = mmap.mmap(fd.fileno(), total)
    seg_table = []
    off = hdr_size
    CHUNK = 1 << 25
    for vmaddr, vmsize, data in pieces:
        for a in range(0, len(data), CHUNK):
            n = min(len(data) - a, CHUNK)
            out[off + a:off + a + n] = data[a:a + n]
        off += len(data) + (-len(data) & 0xf)
        seg_table.append((vmaddr, vmsize, off - len(data) - (-len(data) & 0xf), len(data)))
    adt_off = off
    out[adt_off:adt_off + len(adt_blob)] = adt_blob
    off += len(adt_blob) + (-len(adt_blob) & 0xf)
    assert off == total, f'written {off} != {total}'

    struct.pack_into('<8sII', out, 0, b'SWEETXNU', 1, len(pieces))
    struct.pack_into('<7Q', out, 0x10, virt_base, m['entry'], adt_off, len(adt_blob), kernel_end,
                     PHYS_BASE, MEM_SIZE)
    # Refuse rather than truncate: a dropped tail arg (rootrw=1, rd=) is a boot
    # that fails for a reason nothing in the log names.
    cl = cmdline.encode()
    if len(cl) > BOOT_LINE_LENGTH - 1:
        raise SystemExit(f'cmdline is {len(cl)} bytes, the payload header holds '
                         f'{BOOT_LINE_LENGTH - 1}: {cmdline!r}')
    out[CMDLINE:CMDLINE + len(cl)] = cl
    for i, t in enumerate(seg_table):
        struct.pack_into('<4Q', out, SEG_TABLE + 32 * i, *t)
    info = dict(cputype=hex(m['cputype']), cpusub=m['cpusub'], fixups=nfix, virt_base=hex(virt_base),
                entry=hex(m['entry']), kernel_end=hex(kernel_end), ramdisk=ramdisk,
                ramdisk_va=ramdisk_va, shared_cache=shared_cache, size=total,
                segs=[(s['name'], hex(s['vmaddr']), hex(s['vmsize'])) for s in segs])
    out.flush()
    out.close()
    fd.close()
    return info


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('kernel'); ap.add_argument('adt'); ap.add_argument('out')
    ap.add_argument('--cmdline', default='debug=0xc serial=3 cpus=1 keepsyms=1')
    ap.add_argument('--ramdisk', help='root image for md0 (boot with rd=md0)')
    ap.add_argument('--ramdisk-addr', type=lambda s: int(s, 0), default=None,
                    help='physical address for --ramdisk (default: after the kernel, or '
                         f'{RAMDISK_CLEAR:#x} when that would land in the early console band)')
    ap.add_argument('--shared-cache', help='dyld shared cache to place as /chosen/memory-map "dyld shared cache"')
    a = ap.parse_args()
    info = build(a.kernel, a.adt, a.out, a.cmdline, a.ramdisk, a.shared_cache, a.ramdisk_addr)
    for k, v in info.items():
        if k != 'segs':
            print(f'{k}: {v}')
    if info['ramdisk']:
        print(f'ramdisk_placement: phys {info["ramdisk"][0]} size {info["ramdisk"][1]} {info["ramdisk_va"]}')
    for s in info['segs']:
        print('  ', *s)
