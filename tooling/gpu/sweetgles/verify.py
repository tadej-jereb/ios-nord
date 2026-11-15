#!/usr/bin/env python3
"""Host artifact checks; never executes a phone binary or contacts the phone."""
from pathlib import Path
import hashlib
import plistlib
import re
import struct
import subprocess

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
LLVM = REPO / 'tooling/opt/llvm/bin'
PHONE = REPO / 'build/phone'
BUNDLE = PHONE / 'SweetGLES.bundle'


def run(tool, *args):
    return subprocess.check_output([str(LLVM / tool), *map(str, args)], text=True)


def signed(path):
    """Validate ad-hoc CodeDirectory page hashes, not just LC_CODE_SIGNATURE presence."""
    data = path.read_bytes()
    assert struct.unpack_from('<I', data)[0] == 0xfeedfacf
    ncmds = struct.unpack_from('<I', data, 16)[0]
    pos = 32
    signature = None
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<II', data, pos)
        assert size >= 8 and pos + size <= len(data)
        if cmd == 0x1d:
            offset, length = struct.unpack_from('<II', data, pos + 8)
            signature = data[offset:offset + length]
        pos += size
    assert signature is not None, f'{path}: missing signature'
    magic, length, count = struct.unpack_from('>III', signature)
    assert magic == 0xfade0cc0 and length <= len(signature)
    directories = 0
    for i in range(count):
        kind, off = struct.unpack_from('>II', signature, 12 + i * 8)
        if kind != 0:
            continue
        cd = signature[off:]
        magic, length, version, flags, hashes, ident, special, slots, limit = struct.unpack_from('>9I', cd)
        hash_size, hash_type, platform, page = struct.unpack_from('4B', cd, 36)
        assert magic == 0xfade0c02 and flags & 2, 'not ad-hoc signed'
        assert hash_type == 2 and hash_size == 32, 'expected SHA256 CodeDirectory'
        assert length <= len(cd) and page <= 20 and limit <= len(data)
        assert slots == (limit + (1 << page) - 1) >> page
        for slot in range(slots):
            block = data[slot << page:min((slot + 1) << page, limit)]
            assert hashlib.sha256(block).digest() == cd[hashes + slot * hash_size:hashes + (slot + 1) * hash_size], 'invalid signature page hash'
        directories += 1
    assert directories == 1


def main():
    expected = {'SweetGLES', 'SweetEAGL.dylib', 'libOSMesa.8.dylib', 'Info.plist'}
    assert {p.name for p in BUNDLE.iterdir()} == expected
    with (BUNDLE / 'Info.plist').open('rb') as stream:
        plist = plistlib.load(stream)
    assert plist == {
        'CFBundleExecutable': 'SweetGLES', 'CFBundleIdentifier': 'com.sweet.sweetgles',
        'CFBundlePackageType': 'BNDL', 'CFBundleName': 'SweetGLES',
        'CFBundleVersion': '1.0', 'CFBundleSupportedPlatforms': ['iPhoneOS'],
    }
    assert (BUNDLE / 'Info.plist').read_bytes() == (HERE / 'Info.plist').read_bytes()
    print('PASS Info.plist: plistlib parses all required values')
    symbols = run('llvm-nm', '-gU', BUNDLE / 'SweetGLES').splitlines()
    exports = sorted(line.split()[-1] for line in symbols if line.strip())
    assert exports == ['_gldGetVersion', '_gldInitializeLibrary'], exports
    print('PASS SweetGLES exports exactly: ' + ', '.join(exports))
    for path in [BUNDLE / name for name in sorted(expected - {'Info.plist'})] + [PHONE / 'sweetgles/bundletest']:
        headers = run('llvm-objdump', '--macho', '--private-headers', path)
        assert 'ARM64' in headers and 'LC_CODE_SIGNATURE' in headers
        assert re.search(r'platform\s+ios\b', headers)
        assert re.search(r'minos\s+16\.0\b', headers)
        deps = run('llvm-objdump', '--macho', '--dylibs-used', path)
        assert '@' not in deps and 'LC_RPATH' not in headers, deps
        for line in deps.splitlines()[1:]:
            if line.strip():
                assert line.strip().startswith('/'), line
        signed(path)
        print(f'PASS {path.name}: arm64, valid ad-hoc SHA256 signature, platform ios, minos 16.0, absolute dylibs, no rpaths')
    assert '/System/Library/Extensions/SweetGLES.bundle/SweetGLES' in run('llvm-objdump', '--macho', '--dylibs-used', BUNDLE / 'SweetGLES')
    assert b'/System/Library/Extensions/SweetGLES.bundle/libOSMesa.8.dylib\0' in (BUNDLE / 'SweetEAGL.dylib').read_bytes()
    manifest = (PHONE / 'SweetGLES.bundle.sha256').read_text().splitlines()
    assert len(manifest) == 4
    assert {line.split()[1] for line in manifest} == {f'SweetGLES.bundle/{name}' for name in expected}
    for line in manifest:
        digest, name = line.split()
        assert hashlib.sha256((PHONE / name).read_bytes()).hexdigest() == digest
    print('PASS package: exactly 4 files, absolute Mesa lookup, all manifest SHA256s match')
    print('PASS host checks; phone load/retry/render remains UNVERIFIED')


if __name__ == '__main__':
    main()
