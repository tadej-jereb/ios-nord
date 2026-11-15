#!/usr/bin/env python3
"""Host-only artifact and coverage gate; never executes phone binaries."""
from collections import Counter
from pathlib import Path
import re
import subprocess
import gen_slots

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
LLVM = REPO / 'tooling/opt/llvm/bin'

def run(tool, *args):
    return subprocess.check_output([str(LLVM / tool), *map(str, args)], text=True)

def slot_rows():
    return [(int(off, 16), name, kind, int(qc)) for off, name, kind, qc in re.findall(
        r'\{(0x[0-9a-f]+), "(gl\w+)", "(direct|wrap|stub)", ([01]),',
        (HERE / 'slots.c').read_text())]

def availability():
    exports = set(re.findall(r'\b_(gl\w+)\b', run('llvm-nm', '-gU', gen_slots.MESA)))
    generated = (REPO / 'build/gpu/mesa-build/src/mapi/shared-glapi/glapi_mapi_tmp.h').read_text()
    proc = {'gl' + n for n in re.findall(r'"(\w+)\\0"', generated)}
    # Verify these lookup strings occur in the actual linked binary too. A
    # random dlsym name is not evidence: require Mesa's generated lookup table
    # AND its entry.c object in the link, plus OSMesa's actual resolver chain.
    binary = gen_slots.MESA.read_bytes()
    proc = {n for n in proc if n[2:].encode() + b'\0' in binary}
    source = (REPO / 'build/gpu/mesa-src/src/gallium/frontends/osmesa/osmesa.c').read_text()
    assert 'return _mesa_glapi_get_proc_address(funcName);' in source
    symbols = run('llvm-nm', gen_slots.MESA)
    assert '_OSMesaGetProcAddress' in symbols and '_mesa_glapi_get_proc_address' in symbols
    return exports, proc

def main():
    rows = slot_rows()
    expected, qc = gen_slots.offsets()
    counts = Counter(off for off, _, _, _ in rows)
    assert counts == Counter({off: 1 for off in expected}), 'missing/duplicate/unexpected offset'
    assert {off for off, _, _, called in rows if called} == qc
    assert next(kind for off, _, kind, _ in rows if off == 0x3b0) == 'wrap'
    assert 0xd0 not in counts
    assert all(off % 8 == 0 and 0x10 <= off < 0x2068 for off in counts)
    print(f'PASS coverage: {len(rows)} unique slots, all 58 QC offsets, glGetString 0x03b0 wrap')
    exports, proc = availability()
    direct = {name for _, name, kind, _ in rows if kind == 'direct'}
    assert direct <= exports | proc, sorted(direct - exports - proc)
    proc_only = sorted(direct - exports)
    assert (HERE / 'proc-only.txt').read_text().splitlines() == proc_only, 'proc-only list stale'
    print(f'PASS Mesa resolution: {len(direct)} direct names; {len(proc_only)} proc-address-only (proc-only.txt)')
    stubs = sorted(off for off, _, kind, _ in rows if kind == 'stub')
    print(f'INFO non-pass-through stub offsets: {", ".join(f"0x{x:04x}" for x in stubs)}')
    stub_symbols = set()
    for path in (REPO / 'build/gpu/sysroot').rglob('*.tbd'):
        stub_symbols.update(re.findall(r'(?<![A-Za-z0-9_])(_[A-Za-z0-9_.$]+)', path.read_text()))
    for name in ('SweetEAGL.dylib', 'eagltest'):
        path = REPO / 'build/phone/gpu' / name
        headers = run('llvm-objdump', '--macho', '--private-headers', path)
        assert 'ARM64' in headers
        assert 'LC_CODE_SIGNATURE' in headers
        assert re.search(r'platform\s+ios\b', headers)
        assert re.search(r'minos\s+16\.0\b', headers)
        deps = run('llvm-objdump', '--macho', '--dylibs-used', path)
        assert not re.search(r'@(rpath|loader_path|executable_path)', deps)
        undefined = set(run('llvm-nm', '-u', path).splitlines())
        assert undefined <= stub_symbols | {'dyld_stub_binder'}, sorted(undefined-stub_symbols-{'dyld_stub_binder'})
        assert not any(x.startswith('_objc_') or x.startswith('_class_') for x in undefined)
        print(f'PASS {name}: arm64, signed, platform ios, minos 16.0, absolute dylibs, {len(undefined)} undefined symbols in stubs')
    print('PASS host checks (phone execution remains UNVERIFIED)')

if __name__ == '__main__':
    main()
