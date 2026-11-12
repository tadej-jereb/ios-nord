#!/usr/bin/env python3
"""Assert one H-series hybrid image is exactly what its recipe says it is.

Every image in this series keeps every *non-payload* boot-header byte equal to the stock
image, so that is asserted directly rather than restated as a table: the only header bytes
allowed to differ from stock are `kernel_size` (8..12), `ramdisk_size` (16..20) and the
20-byte sha1 `id` (0x240..0x254). RAMDISK and DTB sections must be the stock bytes, the
kernel section must equal the composed kernel for the target byte for byte, and every gap
between sections must be zero.

    check.py IMAGE KERNEL EXPECTED_MAGIC
"""
import struct
import sys

PART = 100663296
PAGE = 4096
STOCK = '/home/tadej/ios-nord/src/los21-boot.img'


def fail(msg):
    print(f'FAIL: {msg}')
    sys.exit(1)


def main():
    img_path, kern_path, magic = sys.argv[1], sys.argv[2], sys.argv[3]
    img = open(img_path, 'rb').read()
    kern = open(kern_path, 'rb').read()
    stock = open(STOCK, 'rb').read()

    if len(img) != PART:
        fail(f'{img_path}: {len(img)} bytes, not the {PART}-byte partition')
    if img[:8] != b'ANDROID!':
        fail('bad boot magic')
    if len(img) < 4096 + len(kern):
        fail('image shorter than its own kernel section')

    v = dict(ksize=struct.unpack_from('<I', img, 8)[0],
             rsize=struct.unpack_from('<I', img, 16)[0],
             tsize=struct.unpack_from('<I', img, 1648)[0])
    sv = dict(ksize=struct.unpack_from('<I', stock, 8)[0],
              rsize=struct.unpack_from('<I', stock, 16)[0],
              tsize=struct.unpack_from('<I', stock, 1648)[0])
    if v['ksize'] != len(kern):
        fail(f"kernel_size {v['ksize']} != composed kernel length {len(kern)}")

    # header: only ksize, rsize and the sha1 id may differ from stock
    allowed = set(range(8, 12)) | set(range(16, 20)) | set(range(0x240, 0x254))
    diffs = [i for i in range(1660) if img[i] != stock[i] and i not in allowed]
    if diffs:
        fail('boot header drifted from stock at: ' +
             ', '.join(f'{i:#x}({stock[i]:#04x}->{img[i]:#04x})' for i in diffs[:12]))

    # sections: kernel exact, ramdisk + dtb stock, gaps zero
    k_off = PAGE
    r_off = k_off + -(-v['ksize'] // PAGE) * PAGE
    d_off = r_off + -(-v['rsize'] // PAGE) * PAGE
    end = d_off + -(-v['tsize'] // PAGE) * PAGE
    if img[k_off:k_off + len(kern)] != kern:
        fail('kernel section is not the composed kernel')
    k_up = lambda n: -(-n // PAGE) * PAGE
    so = PAGE + k_up(sv['ksize'])
    sd = so + k_up(sv['rsize'])
    if img[r_off:r_off + v['rsize']] != stock[so:so + v['rsize']]:
        fail('ramdisk section is not the stock ramdisk')
    if img[d_off:d_off + v['tsize']] != stock[sd:sd + v['tsize']]:
        fail('dtb section is not the stock dtb')
    for lo, hi, name in ((1660, 4096, 'header page tail'), (k_off + len(kern), r_off, 'kernel pad'),
                         (r_off + v['rsize'], d_off, 'ramdisk pad'), (d_off + v['tsize'], end, 'dtb pad')):
        if any(img[lo:hi]):
            fail(f'non-zero fill in the {name} gap {lo:#x}..{hi:#x}')

    # kernel header of the payload itself
    if kern[0x38:0x3c] != b'ARMd':
        fail("payload has no 'ARMd' aarch64 Image magic at 0x38")
    imm = struct.unpack_from('<I', kern, 0)[0]
    if imm >> 26 != 0x5:
        fail(f'code0 {imm:#010x} is not a branch')

    # footer
    foot = img.rfind(b'AVBf')
    if foot < 0 or len(img) - foot != 64:
        fail('no AVB footer at the end of the partition')
    orig = struct.unpack_from('>Q', img, foot + 12)[0]
    if orig != end:
        fail(f'footer original_image_size {orig} != sections end {end}')

    print(f'OK: {img_path} kernel section {len(kern)} B, sections end {end}, '
          f'code0 {magic}, footer orig {orig}')


main()
