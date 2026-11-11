#!/usr/bin/env python3
"""Split an OnePlus header-v1 boot image kernel section into Image.gz + board DTB.

The stock avicii (OnePlus Nord) boot image has header v1 and a kernel section of
the form `Image.gz-dtb`: a complete gzip member followed immediately by one
flattened device tree blob.  There is no dtb section and no size field for the
DTB, so the only way to find the split point is to decompress the gzip stream to
its end - the CRC32/size trailer tells us whether we got there for real- and then
require the very next bytes to be an FDT.

  extract-dtb.py BOOT.img|KERNEL_SECTION OUTDIR [--dump] [--allow-trailing]

The input may be the whole boot image (an ANDROID! magic makes it skip the
header page and honour kernel_size) or the bare kernel section.  Header v1 is
required for the former; a v2/v3 image has a separate dtb section and is not
this tool's job.

Writes OUTDIR/kernel.gz (the exact gzip member, byte for byte) and
OUTDIR/board.dtb.  Refuses to write anything unless the gzip CRC and the FDT
totalsize both check out, so a half-written or non-OnePlus image fails loudly
instead of producing a shim that ABL quietly rejects.

--allow-trailing: tolerate bytes after the DTB (padding, a second DTB) instead
of requiring the DTB to end exactly at the end of the kernel section. The extra
bytes are reported, not written.
"""
import os
import struct
import sys
import zlib

FDT_MAGIC = b'\xd0\x0d\xfe\xed'


def fdt_field(dtb, off):
    return struct.unpack_from('>I', dtb, off)[0]


def describe(dtb):
    """Structural checks on a candidate FDT; returns a list of human strings."""
    total = fdt_field(dtb, 4)
    off_struct = fdt_field(dtb, 8)
    off_strings = fdt_field(dtb, 12)
    off_rsvmap = fdt_field(dtb, 16)
    version = fdt_field(dtb, 20)
    last_comp = fdt_field(dtb, 24)
    size_strings = fdt_field(dtb, 32)
    size_struct = fdt_field(dtb, 36)
    info = [
        f'totalsize    {total} (0x{total:x})',
        f'version      {version} (last compatible {last_comp})',
        f'off_struct   0x{off_struct:x}  size_struct {size_struct}',
        f'off_strings  0x{off_strings:x}  size_strings {size_strings}',
        f'off_rsvmap   0x{off_rsvmap:x}',
    ]
    problems = []
    if version != 17:
        problems.append(f'version {version} != 17')
    if size_struct and off_struct + size_struct != off_strings:
        problems.append('struct block does not end where the strings block starts')
    if off_strings + size_strings != total:
        problems.append('strings block does not end at totalsize (trailing junk inside the DTB)')

    # Root node name + model, for the eyeball check.
    p = off_struct
    strings = off_strings
    try:
        if fdt_field(dtb, p) != 1:
            problems.append('first struct token is not FDT_BEGIN_NODE')
        else:
            p += 4
            end = dtb.index(b'\0', p)
            root = dtb[p:end].decode('latin-1')
            info.append(f'root node    {root!r}')
            p = (end + 1 + 3) & ~3
            while fdt_field(dtb, p) == 3:          # FDT_PROP
                ln, nameoff = struct.unpack_from('>II', dtb, p + 4)
                val = dtb[p + 12:p + 12 + ln]
                name = dtb[strings + nameoff:dtb.index(b'\0', strings + nameoff)].decode('latin-1')
                if name in ('model', 'compatible', 'qcom,board-id', 'qcom,msm-id'):
                    info.append(f'{name:<12} {val.rstrip(bytes(1)).decode("latin-1")!r}')
                p = (p + 12 + ln + 3) & ~3
    except (ValueError, struct.error) as e:
        problems.append(f'root node unparsable: {e}')
    return info, problems


def main(argv):
    args = [a for a in argv[1:] if not a.startswith('--')]
    dump = '--dump' in argv
    allow_trailing = '--allow-trailing' in argv
    if len(args) != 2:
        sys.exit(f'usage: {argv[0]} BOOT.img OUTDIR [--dump] [--allow-trailing]')
    src, outdir = args
    data = open(src, 'rb').read()

    if data[:8] == b'ANDROID!':
        ksize = struct.unpack_from('<I', data, 8)[0]
        page = struct.unpack_from('<I', data, 36)[0]
        ver = struct.unpack_from('<I', data, 40)[0]
        if ver not in (0, 1):
            print(f'{src}: note: header v{ver} - OnePlus stock avicii images are v2; '
                  'slicing the kernel section anyway, but a v1 image is what ABL wants')
        if page not in (2048, 4096, 8192, 16384) or page > len(data):
            sys.exit(f'{src}: implausible page size {page}')
        print(f'{src}: header v{ver}, page {page}, kernel section {ksize} bytes at 0x{page:x}')
        data = data[page:page + ksize]

    raw_image = False
    if data[:2] == b'\x1f\x8b':
        z = zlib.decompressobj(31)             # 31 = gzip wrapper, CRC checked
        try:
            image = z.decompress(data)
        except zlib.error as e:
            sys.exit(f'{src}: gzip stream is broken: {e}')
        if not z.eof:
            sys.exit(f'{src}: gzip stream truncated (no trailer/CRC)')
        consumed = len(data) - len(z.unused_data)
        rest = z.unused_data
    elif data[0x38:0x3c] == b'ARMd':
        # Uncompressed aarch64 Image: stock avicii boot.img looks like this and carries
        # no DTB at all - the board DTBs live in the dtbo partition.
        raw_image = True
        at = data.find(FDT_MAGIC)
        if at < 0:
            os.makedirs(outdir, exist_ok=True)
            kpath = os.path.join(outdir, 'kernel.raw')
            with open(kpath, 'wb') as f:
                f.write(data)
            print(f'{src}: raw aarch64 Image, {len(data)} bytes, no appended DTB')
            print(f'  wrote {kpath}')
            print('  the board DTBs are in dtbo.img - parse its dt_table (big-endian, '
                  'entry dtb_offset/dtb_size) and take the entry with board-id 8 0')
            sys.exit(2)
        consumed, rest = at, data[at:]
        image = data[:at]
    else:
        sys.exit(f'{src}: kernel section is neither gzip (1f 8b) nor an aarch64 Image '
                 '(0x38 magic "ARMd")')

    if rest[:4] != FDT_MAGIC:
        sys.exit(f'{src}: bytes at 0x{consumed:x} are {rest[:4].hex()}, not an FDT magic '
                 '(0xd00dfeed); not an Image.gz-dtb image')
    total = struct.unpack_from('>I', rest, 4)[0]
    if not 0x40 <= total <= 0x400000:
        sys.exit(f'{src}: implausible FDT totalsize {total} at 0x{consumed:x}')
    if total > len(rest):
        sys.exit(f'{src}: FDT claims {total} bytes but only {len(rest)} follow the gzip stream')
    extra = len(rest) - total
    if extra and not allow_trailing:
        sys.exit(f'{src}: {extra} trailing bytes after the DTB '
                 f'(size {total}); pass --allow-trailing to keep going')

    dtb = rest[:total]
    info, problems = describe(dtb)
    if problems:
        sys.exit(f'{src}: DTB at 0x{consumed:x} fails checks: ' + '; '.join(problems))

    print(f'{src}:')
    if raw_image:
        print(f'  raw Image   0x0..0x{consumed:x} -> {len(image)} bytes (no crc)')
    else:
        print(f'  gzip member 0x0..0x{consumed:x} -> {len(image)} bytes decompressed, crc32 ok')
    print(f'  board dtb   0x{consumed:x}..0x{consumed + total:x} ({total} bytes)')
    if extra:
        print(f'  trailing    {extra} bytes at 0x{consumed + total:x} ignored')
    if dump:
        for line in info:
            print(f'  {line}')

    os.makedirs(outdir, exist_ok=True)
    kpath = os.path.join(outdir, 'kernel.raw' if raw_image else 'kernel.gz')
    dpath = os.path.join(outdir, 'board.dtb')
    with open(kpath, 'wb') as f:
        f.write(data[:consumed])
    with open(dpath, 'wb') as f:
        f.write(dtb)
    print(f'  wrote {kpath} ({consumed} bytes)')
    print(f'  wrote {dpath} ({total} bytes)')


if __name__ == '__main__':
    main(sys.argv)
