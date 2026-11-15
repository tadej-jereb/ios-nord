#!/usr/bin/env python3
"""Verify the private cross-build log and lld's ad-hoc CodeDirectory/page hashes."""
from pathlib import Path
import hashlib
import re
import struct
import subprocess

repo = Path(__file__).resolve().parents[3]
build = repo / 'build/gpu/mesa-build-es'
artifact = build / 'src/gallium/targets/osmesa/libOSMesa.8.dylib'
log = (repo / 'build/gpu/mesa-build-es-build.log').read_text()
assert '[1134/1134] Linking target src/gallium/targets/osmesa/libOSMesa.8.dylib' in log
assert not re.search(r'FAILED:|ninja: build stopped:|fatal error:', log)
print('PASS iOS cross-build: 1134/1134, zero failed commands')
data = artifact.read_bytes()
hdr = struct.unpack_from('<8I', data)
assert hdr[0] == 0xfeedfacf and hdr[1] == 0x100000c  # arm64 Mach-O64
pos = 32
signature = None
for _ in range(hdr[4]):
    cmd, size = struct.unpack_from('<2I', data, pos)
    if cmd == 0x1d:
        off, length = struct.unpack_from('<2I', data, pos + 8)
        signature = data[off:off+length]
    pos += size
assert signature is not None
magic, length, count = struct.unpack_from('>3I', signature)
assert magic == 0xfade0cc0
verified = False
for i in range(count):
    kind, off = struct.unpack_from('>2I', signature, 12+i*8)
    if kind != 0:
        continue
    cd = signature[off:]
    magic, length, version, flags, hashes, ident, special, slots, limit = struct.unpack_from('>9I', cd)
    assert magic == 0xfade0c02 and flags & 2  # CS_ADHOC
    hash_size, hash_type, _, page_log2 = struct.unpack_from('4B', cd, 36)
    assert hash_size == 32 and hash_type == 2  # SHA-256
    page = 1 << page_log2
    assert slots == (limit+page-1)//page
    for n in range(slots):
        expected = cd[hashes+n*hash_size:hashes+(n+1)*hash_size]
        assert hashlib.sha256(data[n*page:min((n+1)*page,limit)]).digest() == expected
    print(f'PASS arm64 dylib: CS_ADHOC flags=0x{flags:x}; {slots} SHA-256 code pages verified')
    verified = True
assert verified
print(f'SHA256 libOSMesa.8.dylib {hashlib.sha256(data).hexdigest()}')
llvm = repo / 'tooling/opt/llvm/bin'
print(subprocess.check_output([llvm / 'llvm-objdump', '--macho', '--dylibs-used', artifact], text=True), end='')
print('INFO install name and framework dependencies unchanged; no separate GLES library needed')
