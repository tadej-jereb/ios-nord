#!/usr/bin/env python3
"""Self-test for tools/extract-dtb.py: build a synthetic Image.gz-dtb and split it.

Builds a file shaped exactly like a stock avicii header-v1 boot image (1648-byte
v1 header padded to 4096, kernel section = gzip(Image) + FDT, ramdisk page),
runs the extractor over it and checks the two halves come back byte-identical.
Then three negative cases: corrupted gzip CRC, no FDT after the stream,
truncated gzip.

  test_extract_dtb.py            # runs in a scratch dir, prints PASS/FAIL lines
"""
import gzip
import os
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
EXTRACT = os.path.join(HERE, 'extract-dtb.py')
PAGE = 4096


def fdt(struct_block, strings_block):
    """Assemble an FDT with the given struct/strings blocks."""
    off_rsvmap = 40
    off_struct = off_rsvmap + 16
    off_strings = off_struct + len(struct_block)
    total = off_strings + len(strings_block)
    head = struct.pack('>10I', 0xd00dfeed, total, off_struct, off_strings,
                       off_rsvmap, 17, 16, 0, len(strings_block), len(struct_block))
    return head + bytes(16) + struct_block + strings_block


def prop(name, value, strings, out):
    out.append(struct.pack('>III', 3, len(value), strings.index(name.encode())))
    out.append(value + bytes(-len(value) % 4))


def build_dtb(model=b'OnePlus Technologies, AC2001 avicii', mem=(0x80000000, 0x20000000)):
    strings = b'#address-cells\0#size-cells\0model\0reg\0'
    out = [struct.pack('>I', 1), bytes(4)]          # BEGIN_NODE ""
    prop('#address-cells', struct.pack('>I', 2), strings, out)
    prop('#size-cells', struct.pack('>I', 2), strings, out)
    prop('model', model, strings, out)
    name = b'memory@%x' % mem[0]
    out.append(struct.pack('>I', 1) + name + bytes(-len(name) % 4))
    prop('reg', struct.pack('>4I', 0, mem[0], 0, mem[1]), strings, out)
    out += [struct.pack('>I', 2), struct.pack('>I', 2), struct.pack('>I', 9), bytes(4)]
    return fdt(b''.join(out), strings)


def gz(data):
    return gzip.compress(data, 9, mtime=0)


def boot_img(kernel_section, ramdisk=b'\x1f\x8b fake ramdisk'):
    hdr = b'ANDROID!' + struct.pack('<8I', len(kernel_section), 0x8000, len(ramdisk),
                                    0x1000000, 0, 0, 0x100, PAGE)
    hdr += struct.pack('<2I', 1, (12 << 11) | (11 << 4) | 6)
    hdr += b'avicii'.ljust(16, b'\0') + b'console=null'.ljust(128, b'\0')
    hdr += bytes(8) + bytes(1024) + struct.pack('<IQI', 0, 0, 1648)
    hdr = hdr.ljust(PAGE, b'\0')
    body = kernel_section.ljust(-len(kernel_section) % PAGE, b'\0') + ramdisk.ljust(PAGE, b'\0')
    return hdr + body, len(kernel_section)


def run(path, outdir, *extra):
    return subprocess.run([sys.executable, EXTRACT, path, outdir, *extra],
                          capture_output=True, text=True)


def main():
    fails = 0

    def check(name, cond, detail=''):
        nonlocal fails
        print(('PASS ' if cond else 'FAIL ') + name + ('' if cond else f'  {detail}'))
        if not cond:
            fails += 1

    with tempfile.TemporaryDirectory() as tmp:
        image = os.urandom(9000) + b'\x00' * 500          # stand-in for an Image
        dtb = build_dtb()
        ks = gz(image) + dtb
        img, klen = boot_img(ks)
        src = os.path.join(tmp, 'boot.img')
        open(src, 'wb').write(img)

        out = os.path.join(tmp, 'out')
        r = run(src, out, '--dump', '--allow-trailing')
        check('happy path exits 0', r.returncode == 0, r.stderr.strip())
        if r.returncode == 0:
            k = open(os.path.join(out, 'kernel.gz'), 'rb').read()
            d = open(os.path.join(out, 'board.dtb'), 'rb').read()
            check('kernel.gz is the exact gzip member', k == gz(image))
            check('board.dtb is the exact DTB', d == dtb)
            check('kernel.gz decompresses to the original Image', gzip.decompress(k) == image)
            check('board.dtb totalsize field sane', struct.unpack_from('>I', d, 4)[0] == len(dtb))
            check('dump names the board', b'avicii' in d)

        # 1. corrupted CRC
        bad = bytearray(gz(image) + dtb)
        bad[-len(dtb) - 6] ^= 0xff                        # inside the gzip trailer
        p = os.path.join(tmp, 'badcrc.img')
        open(p, 'wb').write(boot_img(bytes(bad))[0])
        r = run(p, os.path.join(tmp, 'o1'))
        check('corrupt CRC rejected', r.returncode != 0 and 'crc' in (r.stderr + r.stdout).lower(),
              r.stderr.strip() or r.stdout.strip())

        # 2. no FDT after the gzip stream
        p = os.path.join(tmp, 'nodtb.img')
        open(p, 'wb').write(boot_img(gz(image))[0])
        r = run(p, os.path.join(tmp, 'o2'))
        check('missing DTB rejected', r.returncode != 0 and 'not an FDT' in r.stderr,
              r.stderr.strip())

        # 3. truncated gzip
        p = os.path.join(tmp, 'trunc.img')
        open(p, 'wb').write(boot_img(gz(image)[:len(gz(image)) // 2] + dtb)[0])
        r = run(p, os.path.join(tmp, 'o3'))
        check('truncated gzip rejected', r.returncode != 0, r.stderr.strip())

        # 4. trailing junk without --allow-trailing
        p = os.path.join(tmp, 'trail.img')
        open(p, 'wb').write(boot_img(gz(image) + dtb + bytes(64))[0])
        r = run(p, os.path.join(tmp, 'o4'))
        check('trailing bytes rejected without flag',
              r.returncode != 0 and 'trailing' in r.stderr, r.stderr.strip())

        # 5. no output written when the DTB is bad
        check('failed run left no board.dtb', not os.path.exists(os.path.join(tmp, 'o2', 'board.dtb')))

        # 6. bare kernel section (no boot header) works too
        p = os.path.join(tmp, 'kern.img')
        open(p, 'wb').write(ks)
        r = run(p, os.path.join(tmp, 'o6'))
        check('bare kernel section accepted', r.returncode == 0
              and open(os.path.join(tmp, 'o6', 'board.dtb'), 'rb').read() == dtb, r.stderr.strip())

        # 7. a v2 header is sliced like v1 (OnePlus stock avicii boot.img is v2) - and the
        # note goes to stdout, so a valid image still extracts
        p = os.path.join(tmp, 'v2.img')
        v2 = bytearray(open(src, 'rb').read())
        struct.pack_into('<I', v2, 40, 2)
        open(p, 'wb').write(v2)
        r = run(p, os.path.join(tmp, 'o7'))
        check('v2 header sliced, not refused', r.returncode == 0
              and 'v2' in r.stdout
              and open(os.path.join(tmp, 'o7', 'board.dtb'), 'rb').read() == dtb, r.stderr.strip())

        # 8. a raw aarch64 Image with no appended DTB exits 2 and keeps kernel.raw
        p = os.path.join(tmp, 'raw.img')
        raw = bytearray(0x1000)
        raw[0x38:0x3c] = b'ARMd'
        open(p, 'wb').write(bytes(raw))
        r = run(p, os.path.join(tmp, 'o8'))
        check('raw image without DTB -> kernel.raw, exit 2',
              r.returncode == 2 and 'dtbo' in r.stdout
              and os.path.getsize(os.path.join(tmp, 'o8', 'kernel.raw')) == 0x1000,
              r.stderr.strip())

    print('PASS all' if not fails else f'{fails} check(s) failed')
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
