#!/bin/bash
# Pack an avicii (OnePlus Nord, SM7250/lito) boot image, header v1 only.
#
# The stock OnePlus ABL parses header v2/v3 and then drops back to fastboot; it
# accepts v1 with `Image.gz-dtb` (a gzip stream with the board DTB appended) and
# nothing else.  So this wrapper is deliberately narrow: it always asks
# mkbootimg.py for --header_version 1 with the stock avicii base/offset/pagesize
# values, and it can re-parse what it produced.
#
#   mkbootimg_v1.sh --kernel Image.gz-dtb --ramdisk rd.bin -o out/shim-boot.img
#   mkbootimg_v1.sh --verify out/shim-boot.img
#
# Where the constants come from (all little-endian u32 in the stock header):
#   base 0x0, kernel_offset 0x8000, ramdisk_offset 0x1000000, tags_offset 0x100,
#   second_offset 0xf00000, pagesize 4096.
# Recorded from two independent avicii board configs that boot this phone
# (LineageOS device/oneplus/avicii BoardConfig.mk: BASE 0x0, PAGESIZE 4096;
# android_device_oneplus_avicii_TWRP: TAGS_OFFSET 0x100, KERNEL_OFFSET 0x8000,
# SECOND_OFFSET 0xf00000, RAMDISK_OFFSET 0x1000000, DTB_OFFSET 0x1f00000), and
# identical to the mkbootimg.py defaults the stock OOS images were built with.
# VERIFIED-BY-PARSER only: still run --verify on a real stock boot.img and
# diff the numbers before trusting them.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)

BASE=${BASE:-0x0}
KERNEL_OFFSET=${KERNEL_OFFSET:-0x8000}
RAMDISK_OFFSET=${RAMDISK_OFFSET:-0x1000000}
SECOND_OFFSET=${SECOND_OFFSET:-0xf00000}
TAGS_OFFSET=${TAGS_OFFSET:-0x100}
PAGESIZE=${PAGESIZE:-4096}
HDR=${HDR:-1}
MKBOOTIMG_PY=${MKBOOTIMG_PY:-$here/mkbootimg.py}
PYTHON=${PYTHON:-python3}

# ---------------------------------------------------------------------------
# --verify: parse a produced (or stock) image and print every header field.
# ---------------------------------------------------------------------------
verify() {
	"$PYTHON" - "$1" <<'PY'
import struct, sys, zlib

path = sys.argv[1]
d = open(path, 'rb').read()
# Offsets are boot_img_hdr_v1 as written by mkbootimg.py: cmdline[512] at 64,
# id[8] (uint32, 32 bytes) at 576, extra_cmdline[1024] at 608.
FIELDS = [('kernel_size', 8, 'I'), ('kernel_addr', 12, 'I'),
          ('ramdisk_size', 16, 'I'), ('ramdisk_addr', 20, 'I'),
          ('second_size', 24, 'I'), ('second_addr', 28, 'I'),
          ('tags_addr', 32, 'I'), ('page_size', 36, 'I'),
          ('header_version', 40, 'I'), ('os_version_raw', 44, 'I'),
          ('recovery_dtbo_size', 1632, 'I'),
          ('recovery_dtbo_offset', 1636, 'Q'),
          ('header_size', 1644, 'I')]

if len(d) < 1648:
    sys.exit(f'{path}: only {len(d)} bytes, too short for a v1 header')

magic = d[:8]
print(f'file            : {path} ({len(d)} bytes)')
print(f'magic           : {magic!r} {"OK" if magic == b"ANDROID!" else "WRONG"}')
v = {}
for name, off, fmt in FIELDS:
    v[name] = struct.unpack_from('<' + fmt, d, off)[0]
    print(f'{name:<16}: 0x{v[name]:x} ({v[name]})')
print(f'name            : {d[48:64].rstrip(chr(0).encode())!r}')
print(f'cmdline         : {d[64:576].rstrip(chr(0).encode())!r}')
print(f'id (sha1)       : {d[576:608].hex()}')
print(f'extra_cmdline   : {d[608:1632].split(bytes(1))[0]!r}')

osr = v['os_version_raw']
print(f'os version      : {(osr >> 11) >> 14}.{((osr >> 11) >> 7) & 0x7f}.{(osr >> 11) & 0x7f}'
      f' patch {2000 + ((osr & 0x7ff) >> 4)}-{(osr & 0xf):02d}')
print(f'kernel load addr: 0x{v["kernel_addr"]:x}  (base+0x8000 = 0x8000 expected)')
print(f'ramdisk load adr: 0x{v["ramdisk_addr"]:x}')
print(f'tags addr       : 0x{v["tags_addr"]:x}')

bad, warn = [], []
if magic != b'ANDROID!':
    bad.append('bad magic')
if v['header_version'] != 1:
    warn.append(f'header_version {v["header_version"]} (stock avicii ships v2 and boots it; '
                'v1 Image.gz-dtb is what this port packs)')
if (v['os_version_raw'] >> 11) == 0:
    bad.append('os_version is 0 - ABL refuses this image (anti-rollback); pass OS_VERSION')
if v['page_size'] != 4096:
    bad.append(f'page_size {v["page_size"]} != 4096')
if v['header_version'] in (0, 1) and v['header_size'] != 1648:
    bad.append(f'header_size {v["header_size"]} != 1648')
if v['recovery_dtbo_size'] or v['recovery_dtbo_offset']:
    warn.append('recovery_dtbo fields set; a v1 Image.gz-dtb image has none')
if v['second_size']:
    bad.append('second stage present; stock avicii has none')

# Sections and page alignment.
p = v['page_size']
ks, rs, ss = v['kernel_size'], v['ramdisk_size'], v['second_size']
k_off, r_off, s_off = p, p + ((ks + p - 1) // p) * p, 0
r_off = p + ((ks + p - 1) // p) * p
s_off = r_off + ((rs + p - 1) // p) * p
print(f'kernel section  : page 1 offset 0x{k_off:x} size {ks}')
print(f'ramdisk section : offset 0x{r_off:x} size {rs}')
print(f'total needed    : {s_off + ((ss + p - 1) // p) * p} bytes; file has {len(d)}')
if s_off + ((ss + p - 1) // p) * p > len(d):
    bad.append('image shorter than the header claims')
# Sizes are the real section lengths; only the sections after them are padded,
# so no page-alignment check on the sizes themselves.

# ABL only executes an image whose partition tail carries an AVB footer.
foot = d.rfind(b'AVBf')
if foot < 0 or len(d) - foot != 64:
    bad.append('no AVB footer at the end of the partition (ABL will not execute this image)')
else:
    orig, = struct.unpack_from('>Q', d, foot + 12)
    need = p + ((ks + p - 1) // p) * p + ((rs + p - 1) // p) * p
    print(f'avb footer      : present, original_image_size {orig}, sections end {need}')
    if orig < need:
        bad.append(f'footer original_image_size {orig} cuts into the sections ({need})')


# v1 kernel section must be a real gzip stream with the DTB appended; a stock v2 image
# holds a raw Image instead, which is reported rather than flagged.
kern = d[k_off:k_off + ks]
tail = b''
if kern[0x38:0x3c] == b'ARMd' and kern[:2] != b'\x1f\x8b':
    print('kernel section : raw aarch64 Image (stock v2 style, no appended DTB)')
elif kern[:2] != b'\x1f\x8b':
    bad.append('kernel section does not start with 1f 8b (not gzip)')
else:
    try:
        z = zlib.decompressobj(31)
        out = z.decompress(kern)
        if not z.eof:
            bad.append('gzip stream truncated')
        else:
            tail = kern[len(kern) - len(z.unused_data):]
            print(f'gzip ok         : {len(out)} bytes decompressed, '
                  f'crc ok, tail {len(z.unused_data)} bytes at 0x{len(kern) - len(z.unused_data):x}')
    except zlib.error as e:
        bad.append(f'gzip: {e}')


# The DTB must be an FDT that carries qcom,msm-id: that is the SoC base tree ABL
# needs in the dtb section.  A dtbo fragment overlay has no qcom,msm-id and is
# built out of __overlay__ nodes; ABL cannot use one as the board tree, which is
# exactly the bug this gate exists for (wrong dtb = image accepted, tree bogus).
def fdt_walk(blob):
    """Minimal FDT parser: (node names, property names), or (None, None)."""
    if blob[:4] != b'\xd0\x0d\xfe\xed':
        return None, None
    total, = struct.unpack_from('>I', blob, 4)
    if total > len(blob):
        raise ValueError(f'totalsize {total} exceeds the {len(blob)} dtb bytes')
    offs, offstr = struct.unpack_from('>2I', blob, 8)
    nodes, props, q = [], set(), offs
    while q + 4 <= total:
        tag, = struct.unpack_from('>I', blob, q)
        q += 4
        if tag == 1:                                    # FDT_BEGIN_NODE
            e = blob.index(b'\0', q)
            nodes.append(blob[q:e].decode('latin1'))
            q = (e + 4) & ~3
        elif tag == 3:                                  # FDT_PROP
            ln, no = struct.unpack_from('>2I', blob, q)
            q += 8
            e = blob.index(b'\0', offstr + no)
            props.add(blob[offstr + no:e].decode('latin1'))
            q = (q + ln + 3) & ~3
        elif tag == 2:                                  # FDT_END_NODE
            continue
        else:                                           # FDT_NOP / FDT_END
            break
    return nodes, props


def check_dtb(blob, where):
    try:
        nodes, props = fdt_walk(blob)
    except (ValueError, struct.error, IndexError) as e:
        bad.append(f'dtb section is not a parseable FDT ({where}): {e}')
        return
    if nodes is None:
        bad.append(f'no FDT magic in the dtb section ({where})')
        return
    print(f'board dtb       : totalsize {struct.unpack_from(">I", blob, 4)[0]} bytes, '
          f'{len(nodes)} nodes, {where}')
    if 'qcom,msm-id' not in props:
        bad.append('dtb section has no qcom,msm-id: it is a dtbo fragment overlay, '
                   'not the SoC base tree (use src/avicii-soc.dtb)')
    ov = [n for n in nodes if '__overlay__' in n]
    if ov:
        bad.append(f'dtb section carries __overlay__ nodes ({len(ov)} of them): '
                   'that is the dtbo overlay, not the SoC base tree '
                   '(use src/avicii-soc.dtb)')


dtb_size = 0
if v['header_version'] >= 2 and v['header_size'] >= 1660:
    dtb_size, = struct.unpack_from('<I', d, 1648)
dtb_blob, dtb_where = None, ''
if tail[:4] == b'\xd0\x0d\xfe\xed':
    dtb_blob, dtb_where = tail, 'appended to the kernel'
elif tail:
    bad.append('no FDT magic right after the gzip stream')
if dtb_blob is None and dtb_size:
    o = d.find(b'\xd0\x0d\xfe\xed', p)
    if o < 0:
        bad.append(f'dtb_size {dtb_size} declared but no FDT anywhere in the image')
    else:
        n, = struct.unpack_from('>I', d, o + 4)
        if n != dtb_size:
            bad.append(f'dtb at 0x{o:x} is {n} bytes, header declares dtb_size {dtb_size}')
        else:
            dtb_blob, dtb_where = d[o:o + n], f'dtb section at 0x{o:x}'
if dtb_blob is not None:
    check_dtb(dtb_blob, dtb_where)
elif not dtb_size:
    bad.append('no dtb section and no DTB appended to the kernel: ABL would boot '
               'its own tree instead of the board one')

print()
if warn:
    for w in warn:
        print(f'WARN: {w}')
if bad:
    print('FAIL:')
    for b in bad:
        print(f'  - {b}')
    sys.exit(1)
if warn and v['header_version'] != 1:
    print('PASS (geometry matches; stock-style v2 image, not a packed v1 one)')
else:
    print('PASS: header v1, stock avicii geometry, gzip+DTB kernel')
PY
}

if [ "${1:-}" = "--verify" ]; then
	[ $# -eq 2 ] || { echo "usage: $0 --verify FILE" >&2; exit 2; }
	verify "$2"
	exit
fi

KERNEL="" RAMDISK="" OUT="" EXTRA=()
while [ $# -gt 0 ]; do
	case "$1" in
	--kernel) KERNEL=$2; shift 2 ;;
	--ramdisk) RAMDISK=$2; shift 2 ;;
	-o|--output) OUT=$2; shift 2 ;;
	--header_version) HDR=$2; shift 2 ;;
	--kernel_offset|--ramdisk_offset|--tags_offset|--second_offset|--base|--pagesize)
		EXTRA+=("$1" "$2"); shift 2 ;;
	*) EXTRA+=("$1"); shift ;;
	esac
done
[ -n "$KERNEL" ] || { echo "error: --kernel required" >&2; exit 2; }
[ -n "$RAMDISK" ] || { echo "error: --ramdisk required" >&2; exit 2; }
[ -n "$OUT" ] || { echo "error: -o required" >&2; exit 2; }
[ -f "$MKBOOTIMG_PY" ] || { echo "error: mkbootimg.py not found at $MKBOOTIMG_PY" >&2; exit 2; }

# ABL verifies/rejects boot images by their AVB footer; without one the image is
# accepted by fastboot and then simply never executed. Unsigned hash footer
# (--algorithm NONE) is what the stock image itself carries.
PART_SIZE=${PART_SIZE:-100663296}
# ABL with secboot=enabled REFUSES a boot image whose os_version is 0 (anti-rollback):
# the image is accepted by fastboot, then dropped back after ~6 s. Stock carries
# 0x1c000185, which decodes to Android 14.0.0 / patch 2024-05 (imm26-style packing:
# major<<25 | minor<<18 | patch<<11 | (year-2000)<<4 | month). OS_VERSION below is a
# floor, not the stock tuple - docs/HYBRID.md packs stock's exact bytes.
OS_VERSION=${OS_VERSION:-14.0.0}
OS_VERSION_RAW=${OS_VERSION_RAW:-0x1c000185}
DTB_FILE=${DTB_FILE:-/home/tadej/ios-nord/src/avicii-soc.dtb}
OS_PATCH_LEVEL=${OS_PATCH_LEVEL:-2024-05}
"$PYTHON" "$MKBOOTIMG_PY" --header_version "$HDR" \
	--kernel "$KERNEL" --ramdisk "$RAMDISK" \
	--base "$BASE" --kernel_offset "$KERNEL_OFFSET" \
	--ramdisk_offset "$RAMDISK_OFFSET" --second_offset "$SECOND_OFFSET" \
	--tags_offset "$TAGS_OFFSET" --pagesize "$PAGESIZE" \
	--dtb "$DTB_FILE" --dtb_offset 0x1f00000 "${EXTRA[@]}" --os_version "$OS_VERSION" --os_patch_level "$OS_PATCH_LEVEL" -o "$OUT"

# Pad the sections to the partition and append the AVB footer, then verify.
AVBTOOL="${AVBTOOL:-$(dirname "$0")/avbtool.py}"
"$PYTHON" "$AVBTOOL" add_hash_footer --image "$OUT" \
	--partition_size "$PART_SIZE" --partition_name boot --algorithm NONE >/dev/null || {
	echo "error: could not add the AVB footer (ABL will not run the image)" >&2
	exit 1
}

# Never hand back an image the ABL will reject without saying so.
verify "$OUT"
