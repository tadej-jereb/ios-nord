#!/usr/bin/env python3
"""Self-test for fdt-mem.py + mkadt_avicii.py on a synthetic avicii live FDT.

Builds a tree shaped like what lito's ABL hands over (two /memory nodes and a
/reserved-memory block with the cont_splash carve-out), dumps it with
tools/fdt-mem.py, generates an ADT with tools/mkadt_avicii.py and asserts the
avicii constants and the derived dram range.

  test_mkadt_avicii.py
"""
import os
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import adt  # noqa: E402

MEM_LOW = (0x80000000, 0x60000000)     # 1.5 GiB
MEM_HIGH = (0x100000000, 0x1e0000000)  # 7.5 GiB
SPLASH = (0xa0000000, 0x2300000)


def build_fdt():
    """Two /memory nodes plus /reserved-memory children, depth 3."""
    strings = b'#address-cells\0#size-cells\0model\0compatible\0reg\0device_type\0ranges\0'
    s = strings
    out = [struct.pack('>I', 1), bytes(4)]

    def prop(name, value):
        out.append(struct.pack('>III', 3, len(value), s.index(name.encode())))
        out.append(value + bytes(-len(value) % 4))

    def begin(name):
        raw = name.encode() + b'\0'
        out.append(struct.pack('>I', 1) + raw + bytes(-len(raw) % 4))

    def end():
        out.append(struct.pack('>I', 2))

    prop('#address-cells', struct.pack('>I', 2))
    prop('#size-cells', struct.pack('>I', 2))
    prop('model', b'OnePlus Technologies, AC2001 avicii')
    prop('compatible', b'qcom,avicii\0qcom,sm7250')
    for base, size in (MEM_LOW, MEM_HIGH):
        begin(f'memory@{base:x}')
        prop('device_type', b'memory')
        prop('reg', struct.pack('>4I', base >> 32, base & 0xffffffff, size >> 32, size & 0xffffffff))
        end()
    begin('reserved-memory')
    prop('#address-cells', struct.pack('>I', 2))
    prop('#size-cells', struct.pack('>I', 2))
    prop('ranges', b'')
    for name, (base, size) in (('hyp_region@80000000', (0x80000000, 0x600000)),
                               ('cont_splash_region', SPLASH),
                               ('cmd_db@80860000', (0x80860000, 0x20000))):
        begin(name)
        prop('reg', struct.pack('>4I', base >> 32, base & 0xffffffff, size >> 32, size & 0xffffffff))
        end()
    end()
    end()
    out.append(struct.pack('>I', 9))

    struct_block = b''.join(out)
    off_rsvmap, off_struct = 40, 56
    off_strings = off_struct + len(struct_block)
    total = off_strings + len(s)
    head = struct.pack('>10I', 0xd00dfeed, total, off_struct, off_strings,
                       off_rsvmap, 17, 16, 0, len(s), len(struct_block))
    return head + bytes(16) + struct_block + s


def props(n):
    return {k: v for k, f, v in n.props if not f}


def find(root, name):
    for c in root.children:
        if props(c).get('name') == name.encode() + b'\0':
            return c
    raise AssertionError(f'no child {name}')


def main():
    fails = 0

    def check(name, cond, detail=''):
        nonlocal fails
        print(('PASS ' if cond else 'FAIL ') + name + ('' if cond else f'  {detail}'))
        if not cond:
            fails += 1

    with tempfile.TemporaryDirectory() as tmp:
        dtb = os.path.join(tmp, 'board.dtb')
        open(dtb, 'wb').write(build_fdt())
        js = os.path.join(tmp, 'mem.json')
        r = subprocess.run([sys.executable, os.path.join(HERE, 'fdt-mem.py'), dtb],
                           capture_output=True, text=True)
        check('fdt-mem exits 0', r.returncode == 0, r.stderr.strip())
        open(js, 'w').write(r.stdout)
        check('fdt-mem finds both memory nodes', r.stdout.count('"memory"') >= 1
              and '0x60000000' in r.stdout and '0x1e0000000' in r.stdout)
        check('fdt-mem finds the splash carve-out', '0x2300000' in r.stdout)

        adt_out = os.path.join(tmp, 'avicii.adt')
        r = subprocess.run([sys.executable, os.path.join(HERE, 'mkadt_avicii.py'),
                            adt_out, '--fdt-json', js], capture_output=True, text=True)
        check('mkadt exits 0', r.returncode == 0, r.stderr.strip())
        if r.returncode:
            print(r.stdout)
            sys.exit(1)
        root, _ = adt.parse(open(adt_out, 'rb').read())
        chosen = props(find(root, 'chosen'))
        check('dram-base is the top of the high bank',
              chosen['dram-base'] == struct.pack('<Q', MEM_HIGH[0]))
        check('dram-size excludes the panic log',
              chosen['dram-size'] == struct.pack('<Q', MEM_HIGH[1] - 0x100000))
        check('panic log sits above dram', props(find(root, 'pram'))['reg'][:8]
              == struct.pack('<Q', MEM_HIGH[0] + MEM_HIGH[1] - 0x100000))

        cpus = find(root, 'cpus').children
        check('8 CPUs', len(cpus) == 8, str(len(cpus)))
        mpidr = [struct.unpack('<I', props(c)['reg'])[0] for c in cpus]
        check('MPIDR 0x000-0x700', mpidr == [i << 8 for i in range(8)], str(mpidr))
        clk = [struct.unpack('<I', props(c)['clock-frequency'])[0] for c in cpus]
        check('A55 1.8 GHz, A76 2.2/2.4 GHz', clk == [1804800000] * 6 + [2208000000, 2400000000], str(clk))
        check('qcom,kryo475', props(cpus[0])['compatible'].startswith(b'qcom,kryo475\0'))

        gic = props(find(find(root, 'arm-io'), 'gic'))
        check('virtual timer INTID 19', struct.unpack('<I', gic['virtual-timer-intid'])[0] == 19)
        check('GICD reg relative to /arm-io', struct.unpack_from('<Q', gic['reg'], 0)[0] == 0x17a00000 - 0x01000000)

        fb = props(find(root, 'sweet-fbcon'))
        check('/sweet-fbcon reg 0xa0000000', struct.unpack_from('<Q', fb['reg'], 0)[0] == 0xa0000000)
        check('framebuffer 1080x2400 stride 4800',
              (struct.unpack('<I', fb['width'])[0], struct.unpack('<I', fb['height'])[0],
               struct.unpack('<I', fb['stride'])[0]) == (1080, 2400, 4800))
        check('/sweet-ufs ufshc', props(find(root, 'sweet-ufs'))['compatible'] == b'qcom,ufshc\0')
        check('xiaomi,sweet kept', b'xiaomi,sweet' in props(root)['compatible'])

        # mkadt must refuse without an FDT.
        r = subprocess.run([sys.executable, os.path.join(HERE, 'mkadt_avicii.py'),
                            os.path.join(tmp, 'nofdt.adt')], capture_output=True, text=True)
        check('refuses without --fdt-json', r.returncode != 0 and 'fdt-json' in r.stderr)

        # A reserved hole inside the top bank must move dram below it.
        doc = __import__('json').loads(open(js).read())
        doc['reserved'].append({'node': '/reserved-memory/top', 'base': hex(MEM_HIGH[0]), 'size': hex(MEM_HIGH[1])})
        js2 = os.path.join(tmp, 'mem2.json')
        open(js2, 'w').write(__import__('json').dumps(doc))
        r = subprocess.run([sys.executable, os.path.join(HERE, 'mkadt_avicii.py'),
                            os.path.join(tmp, 'b.adt'), '--fdt-json', js2], capture_output=True, text=True)
        check('a hole over the whole top bank falls back to the low bank',
              r.returncode == 0 and 'below 4 GiB' in r.stderr, r.stderr.strip())
        if r.returncode == 0:
            root, _ = adt.parse(open(os.path.join(tmp, 'b.adt'), 'rb').read())
            base = struct.unpack_from('<Q', props(find(root, 'chosen'))['dram-base'], 0)[0]
            check('fallback dram avoids the splash carve-out',
                  base < 0x100000000 and not (base < SPLASH[0] + SPLASH[1] and 0xa2300000 > base),
                  hex(base))

    print('PASS all' if not fails else f'{fails} check(s) failed')
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
