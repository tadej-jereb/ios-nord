#!/usr/bin/env python3
"""Unwrap an Apple IM4P device-tree blob into a raw ADT (FDT) file.

The iPhone X reference userland needs its own device tree as the ADT /product node
(avicii/tools/mkadt_avicii.py takes it from build/ipsw-x/d22ap.adt). The IPSW member
`Firmware/all_flash/DeviceTree.<board>.im4p` is an IM4P container (type `dtre`) whose
payload is a BER OCTET STRING, LZFSE-compressed (`bvx2`) or stored.

usage: im4p-adt.py IN.im4p OUT.adt [--type dtre]
"""
import os
import sys

MAGIC = b'\xd0\x0d\xfe\xed'
IM4P = b'IM4P'
LZFSE = b'bvx2'


def elements(blob, start=0):
    """Yield (tag, content) for the BER elements of the outer SEQUENCE."""
    p = start
    while p < len(blob):
        tag = blob[p]
        p += 1
        ln = blob[p]
        p += 1
        if ln & 0x80:
            n = ln & 0x7f
            ln = int.from_bytes(blob[p:p + n], 'big')
            p += n
        yield tag, blob[p:p + ln]
        p += ln


def unwrap(blob, want_type='dtre'):
    if blob[:1] != b'\x30':
        sys.exit(f'not a BER SEQUENCE (starts {blob[:4].hex()})')
    p = 1                                    # skip the outer SEQUENCE header
    ln = blob[p]
    p += 1
    if ln & 0x80:
        p += ln & 0x7f
    mtype, payload = None, None
    for tag, content in elements(blob, p):
        if tag != 0x16:                      # 0x16 = the string-tagged fields
            if tag == 0x04:
                payload = content
                break
            continue
        if content == IM4P:
            continue
        if mtype is None and len(content) == 4:
            mtype = content
            if want_type and mtype != want_type.encode():
                sys.exit(f'IM4P type is {mtype!r}, expected {want_type!r}')
            continue
    if mtype is None:
        sys.exit(f'not an IM4P (no {IM4P!r} member)')
    if payload is None:
        sys.exit('no OCTET STRING payload found')
    return payload


def main(argv):
    args = [a for a in argv[1:] if not a.startswith('--')]
    if len(args) != 2:
        sys.exit(f'usage: {argv[0]} IN.im4p OUT.adt [--type dtre]')
    src, dst = args
    want = 'dtre'
    for a in argv:
        if a.startswith('--type='):
            want = a.split('=', 1)[1]
    payload = unwrap(open(src, 'rb').read(), want)

    if payload[:4] == LZFSE:
        try:
            import lzfse
            out = lzfse.decompress(payload)
        except ImportError:
            sys.exit('needs the lzfse module: /usr/bin/python3 -m pip install --user '
                     '--break-system-packages lzfse')
        note = f'lzfse {len(payload)} -> {len(out)} bytes'
    else:
        out = payload
        note = f'stored {len(out)} bytes'

    # Apple ADT is NOT an FDT: it is (nprops, nchildren) + 32-byte-named properties.
    # Validate with the same parser mkadt uses, and look for the /product node.
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import adt
    root, end = adt.parse(out)
    names = [dict((k, v) for k, f, v in c.props).get('name') for c in root.children]
    if b'product\0' not in names:
        sys.exit(f'{src}: parsed as ADT ({len(names)} children) but no /product node')
    open(dst, 'wb').write(out)
    print(f'{src}: {note}, ADT parsed, /product present, wrote {dst} ({len(out)} bytes)')
    print(f'  children: {len(names)}, parsed {end} of {len(out)} bytes')


if __name__ == '__main__':
    main(sys.argv)
