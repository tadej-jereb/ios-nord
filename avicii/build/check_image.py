#!/usr/bin/env python3
"""Structure checks and the stock-diff matrix for avicii/build images.

    check_image.py check  out/S3.img s3      # assert one image is exactly what its target claims
    check_image.py matrix                    # section-by-section diff of every built image vs stock

The check is the point: an image is only allowed to differ from stock inside the byte ranges its
target owns. Anything else is a bug in the builder, not a result to flash.
"""
import os
import struct
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
STOCK = os.path.join(ROOT, 'src', 'los21-boot.img')
OUT = os.path.join(ROOT, 'avicii', 'build', 'out')
PART = 100663296
PAGE = 4096
HDR_V2_SIZE = 1660
FDT_MAGIC = b'\xd0\x0d\xfe\xed'
AVB_MAGIC = b'AVBf'

FIELDS = [
    ('magic', 0, '8s'), ('kernel_size', 8, 'I'), ('kernel_addr', 12, 'I'),
    ('ramdisk_size', 16, 'I'), ('ramdisk_addr', 20, 'I'), ('second_size', 24, 'I'),
    ('second_addr', 28, 'I'), ('tags_addr', 32, 'I'), ('page_size', 36, 'I'),
    ('header_version', 40, 'I'), ('os_version', 44, 'I'), ('name', 48, '16s'),
    ('id', 576, '32s'), ('recovery_dtbo_size', 1632, 'I'),
    ('recovery_dtbo_offset', 1636, 'Q'), ('header_size', 1644, 'I'),
    ('dtb_size', 1648, 'I'), ('dtb_addr', 1652, 'Q'),
]

# Everything in the header except kernel_size, ramdisk_size and id must be stock's.
FIXED_RANGES = [(12, 16), (20, 48), (48, 64), (1632, 1644), (1644, 1660)]

# target -> byte ranges (start, end, label) that may differ from stock, and the section contents.
PAYLOAD_STOCK = 'stock'
PAYLOAD_PARK = 'park'


def die(msg):
    print('FAIL: ' + msg)
    sys.exit(1)


def parse(d, where):
    if len(d) < HDR_V2_SIZE:
        die(f'{where}: {len(d)} bytes, shorter than a v2 header')
    v = {}
    for name, off, fmt in FIELDS:
        val = struct.unpack_from('<' + fmt, d, off)[0]
        v[name] = val
    if v['magic'] != b'ANDROID!':
        die(f'{where}: bad magic {v["magic"]!r}')
    return v


def layout(v, where):
    """Section offsets from the header, page aligned, second stage absent."""
    if v['second_size']:
        die(f'{where}: second stage present')
    k_off = PAGE
    r_off = PAGE + -(-v['kernel_size'] // PAGE) * PAGE
    t_off = r_off + -(-v['ramdisk_size'] // PAGE) * PAGE
    end = t_off + v['dtb_size']
    return k_off, r_off, t_off, end


def target(name):
    """(payload, kernel bytes, allowed diff ranges, expected footer original_image_size)."""
    stock = open(STOCK, 'rb').read()
    sv = parse(stock, 'stock')
    shim_kernel = open(os.path.join(ROOT, 'avicii', 'shim', 'out-diag', 'p0f',
                                    'Image.gz-dtb'), 'rb').read()
    shim_rd = open(os.path.join(ROOT, 'avicii', 'shim', 'out-diag', 'p0f',
                                'ramdisk.bin'), 'rb').read()
    sk, sr, st, _ = layout(sv, 'stock')
    stock_kernel = stock[sk:sk + sv['kernel_size']]
    stock_rd = stock[sr:sr + sv['ramdisk_size']]
    orig = orig_size(stock, 'stock')
    del st
    spec = {
        # S1: identical to stock everywhere.
        's1': (PAYLOAD_STOCK, stock_kernel, stock_rd, [], orig),
        # S2: stock bytes, only the footer/vbmeta region is ours.
        's2': (PAYLOAD_STOCK, stock_kernel, stock_rd, [(orig, PART, 'footer')], orig),
        # S3: stock sections, kernel trimmed by its 10 trailing zero bytes.
        's3': (PAYLOAD_STOCK, stock_kernel[:-10], stock_rd,
               [(0x8, 0xc, 'kernel_size'), (0x240, 0x254, 'id')], orig),
        # S4: stock sections, kernel at the exact stock length -> only id may differ.
        's4': (PAYLOAD_STOCK, stock_kernel, stock_rd,
               [(0x240, 0x254, 'id')], orig),
        # S5: park shim, kernel zero padded to the stock length.
        # The whole stock kernel and ramdisk extents may differ (the payload is different and the
        # ramdisk is 98 bytes, so everything stock had behind it is gone or moved).
        's5': (PAYLOAD_PARK, shim_kernel + bytes(sv['kernel_size'] - len(shim_kernel)), shim_rd,
               [(0x8, 0xc, 'kernel_size'), (0x10, 0x14, 'ramdisk_size'), (0x240, 0x254, 'id'),
                (PAGE, sr + len(stock_rd), 'stock kernel+ramdisk extent')], None),
        # S6: park shim, natural small.
        's6': (PAYLOAD_PARK, shim_kernel, shim_rd,
               [(0x8, 0xc, 'kernel_size'), (0x10, 0x14, 'ramdisk_size'), (0x240, 0x254, 'id'),
                (PAGE, sr + len(stock_rd), 'stock kernel+ramdisk extent')], None),
    }
    if name not in spec:
        die(f'unknown target {name}')
    return spec[name]


def orig_size(d, where):
    if len(d) < 64 or d[-64:-60] != AVB_MAGIC:
        die(f'{where}: no AVBf footer at the end')
    return struct.unpack_from('>Q', d, len(d) - 64 + 12)[0]


def check(path, name):
    d = open(path, 'rb').read()
    stock = open(STOCK, 'rb').read()
    where = os.path.basename(path)
    v = parse(d, where)
    payload, exp_kernel, exp_rd, allowed, exp_orig = target(name)

    # -- fixed geometry ----------------------------------------------------
    if len(d) != PART:
        die(f'{where}: {len(d)} bytes != {PART}')
    if v['header_version'] != 2:
        die(f'{where}: header_version {v["header_version"]} != 2')
    if v['page_size'] != PAGE:
        die(f'{where}: page_size {v["page_size"]} != {PAGE}')
    if v['header_size'] != HDR_V2_SIZE:
        die(f'{where}: header_size {v["header_size"]} != {HDR_V2_SIZE}')
    if v['dtb_size'] != struct.unpack_from('<I', stock, 1648)[0]:
        die(f'{where}: dtb_size {v["dtb_size"]} != stock')
    if v['kernel_size'] != len(exp_kernel):
        die(f'{where}: kernel_size {v["kernel_size"]} != expected {len(exp_kernel)}')
    if v['ramdisk_size'] != len(exp_rd):
        die(f'{where}: ramdisk_size {v["ramdisk_size"]} != expected {len(exp_rd)}')
    for start, end in FIXED_RANGES:
        if d[start:end] != stock[start:end]:
            die(f'{where}: header bytes {start:#x}..{end:#x} differ from stock')

    k_off, r_off, t_off, end = layout(v, where)

    # -- section contents --------------------------------------------------
    if d[k_off:k_off + v['kernel_size']] != exp_kernel:
        die(f'{where}: kernel section is not the expected payload bytes')
    if d[r_off:r_off + v['ramdisk_size']] != exp_rd:
        die(f'{where}: ramdisk section is not the expected payload bytes')
    if d[t_off:t_off + v['dtb_size']] != stock[0x2bab000:0x2bab000 + v['dtb_size']]:
        die(f'{where}: dtb section does not match the stock dtb')
    if d[t_off:t_off + 4] != FDT_MAGIC:
        die(f'{where}: dtb section has no FDT magic')

    # -- footer ------------------------------------------------------------
    foot_off = len(d) - 64
    if d[foot_off:foot_off + 4] != AVB_MAGIC:
        die(f'{where}: footer magic missing at the end of the partition')
    orig = struct.unpack_from('>Q', d, foot_off + 12)[0]
    want_orig = -(-end // PAGE) * PAGE
    if orig != want_orig:
        die(f'{where}: original_image_size {orig} != page-aligned section end {want_orig}')
    if exp_orig is not None and orig != exp_orig:
        die(f'{where}: original_image_size {orig} != expected stock value {exp_orig}')
    if struct.unpack_from('>Q', d, foot_off + 20)[0] != orig:
        die(f'{where}: vbmeta_offset != original_image_size')
    n_vbmeta = struct.unpack_from('>Q', d, foot_off + 28)[0]
    if d[orig + n_vbmeta:foot_off].strip(b'\x00'):
        die(f'{where}: non-zero bytes between the vbmeta blob and the footer')

    # -- zero fill outside the image body ----------------------------------
    if d[foot_off + 64:].strip(b'\x00'):
        die(f'{where}: non-zero bytes past the footer')

    # -- diff against stock is confined to the target's own ranges ---------
    for i in range(min(len(d), len(stock))):
        if d[i] == stock[i]:
            continue
        if not (i >= orig or any(s <= i < e for s, e, _ in allowed)):
            die(f'{where}: unexpected difference at {i:#x} '
                f'(stock {stock[i]:#04x} -> ours {d[i]:#04x})')

    # -- identity claims ---------------------------------------------------
    if name == 's1':
        if d != stock:
            die('s1 is not byte-identical to stock')
    if name == 's2':
        # the body must be stock's bytes exactly; only the footer region may differ
        if d[:orig] != stock[:orig]:
            n = sum(1 for a, b in zip(d[:orig], stock[:orig]) if a != b)
            die(f'{where}: {n} differing bytes inside the stock body (below original_image_size)')

    print(f'OK {where}: target {name}, {len(d)} bytes, original_image_size {orig}, '
          f'kernel {v["kernel_size"]}, ramdisk {v["ramdisk_size"]}, dtb {v["dtb_size"]}')


REGIONS = [
    ('header', 0, HDR_V2_SIZE),
    ('kernel', 'k', 'n'),
    ('ramdisk', 'r', 'n'),
    ('dtb', 't', 'n'),
]


def region_bytes(d, v, kind):
    k_off, r_off, t_off, end = layout(v, 'img')
    if kind == 'header':
        return d[0:HDR_V2_SIZE]
    if kind == 'kernel':
        return d[k_off:k_off + v['kernel_size']]
    if kind == 'ramdisk':
        return d[r_off:r_off + v['ramdisk_size']]
    if kind == 'dtb':
        return d[t_off:t_off + v['dtb_size']]
    return d[-64:]


def describe(ours, theirs, label):
    if ours == theirs:
        return 'identical'
    if len(ours) == len(theirs):
        n = sum(1 for a, b in zip(ours, theirs) if a != b)
        if label in ('kernel', 'ramdisk'):
            return f'payload, all {len(ours)} bytes differ' if n == len(ours) else \
                   f'{n}/{len(ours)} bytes differ'
        if label == 'dtb':
            return f'size {len(ours)} vs {len(theirs)}, {n} bytes differ'
        head = next(i for i, (a, b) in enumerate(zip(ours, theirs)) if a != b)
        return f'{n} bytes differ, first at +{head:#x}'
    return f'size {len(ours)} vs {len(theirs)}'


def matrix():
    """Compact per-image table: header field by field, then whole-region comparisons."""
    stock = open(STOCK, 'rb').read()
    sv = parse(stock, 'stock')
    shy = __import__('hashlib').sha256(stock).hexdigest()
    sk_s, sr_s, st_s, _ = layout(sv, 'stock')
    lines = [f'STOCK reference: {len(stock)} bytes, sha256 {shy}, '
             f'original_image_size {orig_size(stock, "stock")}']
    names = [n for n in ('s1', 's2', 's3', 's4', 's5', 's6')
             if os.path.exists(os.path.join(OUT, n.upper() + '.img'))]
    for n in names:
        p = os.path.join(OUT, n.upper() + '.img')
        d = open(p, 'rb').read()
        v = parse(d, n)
        k_off, r_off, t_off, end = layout(v, n)
        orig = orig_size(d, n)
        lines += ['', f'== {n.upper()}  size {len(d)}  original_image_size {orig}  '
                      f'sha256 {__import__("hashlib").sha256(d).hexdigest()}']
        # header, field by field
        for name, off, fmt in FIELDS:
            if name in ('magic', 'name', 'id'):
                continue
            ours = struct.unpack_from('<' + fmt, d, off)[0]
            theirs = struct.unpack_from('<' + fmt, stock, off)[0]
            mark = '' if ours == theirs else '   <-- DIFFERS'
            lines.append(f'   {name:<20} {ours:>12} vs stock {theirs:<12}{mark}')
        lines.append(f'   {"cmdline":<20} ' + ('identical (235 bytes)' if
                     d[64:576] == stock[64:576] else 'DIFFERS'))
        lines.append(f'   {"id (sha1 20B)":<20} ' + ('identical' if
                     d[576:596] == stock[576:596] else 'differs (derived digest)'))
        lines.append(f'   {"header padding":<20} ' +
                     ('zero, as stock' if d[1660:4096] == stock[1660:4096] else 'DIFFERS'))
        # regions
        fd = len(d) - 64
        fs = len(stock) - 64
        lines.append(f'   {"kernel section":<20} ' + describe(
            d[k_off:k_off + v['kernel_size']], stock[sk_s:sk_s + sv['kernel_size']], 'kernel'))
        lines.append(f'   {"ramdisk section":<20} ' + describe(
            d[r_off:r_off + v['ramdisk_size']],
            stock[sr_s:sr_s + sv['ramdisk_size']], 'ramdisk'))
        lines.append(f'   {"dtb section":<20} ' + describe(
            d[t_off:t_off + v['dtb_size']],
            stock[st_s:st_s + sv['dtb_size']], 'dtb'))
        lines.append(f'   {"footer at":<20} {fd:#x} vs stock {fs:#x}  '
                     + 'AVBf ok' if d[fd:fd + 4] == AVB_MAGIC else 'MAGIC MISSING')
        vb = struct.unpack_from('>Q', d, fd + 28)[0]
        lines.append(f'   {"vbmeta size":<20} {vb} vs stock '
                     f'{struct.unpack_from(">Q", stock, fs + 28)[0]}')
        lines.append(f'   {"bytes differing":<20} {sum(1 for a, b in zip(d, stock) if a != b)}')
        lines.append('   extra bytes past the footer: ' +
                     ('none' if not d[fd + 64:].strip(b'\x00') else 'NON-ZERO'))
    print('\n'.join(lines))


def main():
    if len(sys.argv) < 2:
        die('usage: check_image.py check IMG TARGET | matrix')
    if sys.argv[1] == 'matrix':
        matrix()
        return
    if sys.argv[1] == 'check' and len(sys.argv) == 4:
        check(sys.argv[2], sys.argv[3])
        return
    die('usage: check_image.py check IMG TARGET | matrix')


if __name__ == '__main__':
    main()
