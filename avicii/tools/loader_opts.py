#!/usr/bin/env python3
"""A/B lever for the two decisive boot_args numbers and the payload cmdline.

The ADT has no /memory node: the RAM the shim and the payload use is the
/chosen pair 'dram-base' + 'dram-size' (u64, little endian).  mkadt_avicii.py
writes them from the topmost live extent; mkpayload.py:141-146 (adt_dram) copies
them verbatim into the payload header (used at :164) and the shim hands them to
boot_args (avicii/shim/loader.c:123-124).  So rewriting these two properties on
an already generated ADT flips the whole boot: no kernel rebuild, no ADT
regeneration, no new seed.  mkpayload must be re-run afterwards; the payload
header is the only carrier.

  loader_opts.py low  --adt IN --out ADT [--fdt-json JSON]
  loader_opts.py high --adt IN --out ADT [--fdt-json JSON]
  loader_opts.py cmdline --stock | --fajita
  loader_opts.py check --fdt-json JSON --phys-base HEX [--dram-size HEX]

low  moves dram into the first live extent 0x80000000+0x3bb00000, i.e. dram-base
     0x80000000 and dram-size 0x3ba00000, and asserts it stays below 4 GiB.
     high restores the shipped high-bank values 0x180000000 / 0xfff00000 byte
     for byte.
Both also move /pram (reg = <panic_base panic_size>) to just above the new
range and keep /chosen embedded-panic-log-size at mkadt_avicii.PANIC_LOG_SIZE,
so xnu maps a panic log that the allocator never hands out.  Every other
property and node is left byte for byte as it was.

check asserts a phys_base is inside one /memory extent of the live FDT map and
is nonzero, and exits 1 otherwise.  Without it a typo in --dram-size boots a
phantom bank and the pmap dies with no message (avicii/CONSTANTS.md:200-203).
--dram-size defaults to the low-bank size 0x3ba00000; pass 0xfff00000 to check
the high bank.

The extents below are the live read in logs/mem-live.json (memory[0] and
memory[1]); the low extent is the whole bank and does contain the framebuffer
and the UFS host, which is exactly what the low-bank A/B has to survive.

Python 3 stdlib only, no silent defaults.
"""
import hashlib, json, os, re, struct, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import adt  # noqa: E402
from mkadt_avicii import PANIC_LOG_SIZE, FB, FB_SIZE, UFS, UFS_SIZE  # noqa: E402

# The live /memory extents, logs/mem-live.json:3-19 verbatim.  dram-size is the
# extent minus the panic log, which mkadt_avicii.py:262-263 carves off the top.
LOW_EXT = (0x80000000, 0x3bb00000)
HIGH_EXT = (0x180000000, 0x100000000)
LIMIT_4GIB = 0x100000000

# The shipped payload.bin cmdline (HANDOFF-XNU.md:50) and the fajita A/B set.
STOCK_CMDLINE = ('sweetsmp=0 sweettouch=0 sweetkeys=0 sweetfb_console=1 '
                 'sweetecon=1 debug=0xc keepsyms=1')
# pe_parse_boot_argn returns on the first token that matches, so the new flags
# go *before* debug=0xc: appended instead, 0xc would win and 0x144 would be dead.
DEBUG_ARGS = '-v debug=0x144'
FAJITA_CMDLINE = ('debug=0xc serial=3 cpus=1 keepsyms=1 -enable_kprintf_spam '
                  '-noprogress')
FAJITA_FILE = 'refs/edi194-ios-fajita/NOTES.md'
FAJITA_CITE = f'{FAJITA_FILE}:244'


def die(msg):
    print(f'loader_opts: {msg}', file=sys.stderr)
    raise SystemExit(1)


def arg(name, default=None):
    if name not in sys.argv:
        return default
    i = sys.argv.index(name)
    if i + 1 >= len(sys.argv) or sys.argv[i + 1].startswith('--'):
        die(f'{name} needs a value')
    return sys.argv[i + 1]


def hexval(s, what):
    if not re.fullmatch(r'0[xX][0-9a-fA-F]+|[0-9][0-9a-fA-F]*', s.strip()):
        die(f'{what}: {s!r} is not a hex number')
    v = int(s, 16)
    if not v:
        die(f'{what}: 0 is not a usable value')
    return v


def find(node, name):
    for c in node.children:
        if c.name == name:
            return c
    return None


def fdt_extents(path):
    doc = {}
    try:
        with open(path) as f:
            doc = json.load(f)
        mem = [(int(e['base'], 0), int(e['size'], 0)) for e in doc['memory']]
        res = [(e['node'], int(e['base'], 0), int(e['size'], 0))
               for e in doc.get('reserved', [])]
    except (OSError, ValueError, KeyError, TypeError) as e:
        die(f'{path}: {e}')
    if not mem:
        die(f'{path}: no "memory" entries')
    return mem, res


def check_place(phys_base, extent, dram_size, fdt_json, below_4gib):
    """Placement assertion plus a note on every carve-out the range swallows."""
    ext = None
    if fdt_json:
        mem, reserved = fdt_extents(fdt_json)
        ext = next((e for e in mem if e[0] == phys_base and e[1] >= extent), None)
        if ext is None:
            die(f'0x{phys_base:x}+0x{extent:x} does not start a live /memory '
                'extent (' + ', '.join(f'0x{b:x}+0x{s:x}' for b, s in mem) + ')')
        for n, b, s in reserved:
            if b < phys_base + dram_size and b + s > phys_base:
                print(f'note: reserved {n} 0x{b:x}+0x{s:x} lies inside dram range',
                      file=sys.stderr)
        for b, s, what in ((FB, FB_SIZE, '/sweet-fbcon'),
                           (UFS, UFS_SIZE, '/sweet-ufs')):
            if b < phys_base + dram_size and b + s > phys_base:
                print(f'note: {what} MMIO 0x{b:x}+0x{s:x} lies inside dram range',
                      file=sys.stderr)
    if below_4gib and phys_base + extent > LIMIT_4GIB:
        die(f'0x{phys_base:x}+0x{extent:x} ends above 4 GiB (0x{LIMIT_4GIB:x})')
    where = 'live extent, confirmed' if ext else 'extent unverified'
    print(f'check: phys_base 0x{phys_base:x} extent 0x{extent:x} dram-size '
          f'0x{dram_size:x} top 0x{phys_base + dram_size:x}, {where}, '
          f'{"below" if below_4gib else "may exceed"} 4 GiB')


def set_u64(node, name, value):
    """Replace an existing 8-byte property in place, keeping its flags."""
    for i, (n, flags, v) in enumerate(node.props):
        if n == name:
            if len(v) != 8:
                die(f'/{node.name} {name} is {len(v)} bytes, expected 8')
            node.props[i] = (n, flags, value.to_bytes(8, 'little'))
            return
    die(f'/{node.name} has no {name} property')


def write_phys(adt_in, adt_out, extent, fdt_json, below_4gib):
    base = extent[0]
    size = extent[1] - PANIC_LOG_SIZE
    if adt_in == adt_out:
        die('--adt and --out are the same file')
    blob = b''
    try:
        blob = adt.load(adt_in)
    except (OSError, AssertionError) as e:
        die(f'{adt_in}: unreadable ADT ({e})')
    try:
        root, end = adt.parse(blob)
    except (struct.error, IndexError) as e:
        die(f'{adt_in}: unparsable ADT ({e})')
    if end != len(blob):
        die(f'{adt_in}: trailing bytes at 0x{end:x} (not a bare ADT?)')
    chosen = find(root, 'chosen')
    if chosen is None:
        die(f'{adt_in}: no /chosen node')
    pram = find(root, 'pram')
    if pram is None or pram.prop('reg') is None:
        die(f'{adt_in}: no /pram reg')
    if len(pram.prop('reg')) != 16:
        die(f'{adt_in}: /pram reg is {len(pram.prop("reg"))} bytes, expected 16')
    if chosen.prop('embedded-panic-log-size') != PANIC_LOG_SIZE.to_bytes(4, 'little'):
        die(f'{adt_in}: embedded-panic-log-size is not 0x{PANIC_LOG_SIZE:x}')
    old = (int.from_bytes(chosen.prop('dram-base'), 'little'),
           int.from_bytes(chosen.prop('dram-size'), 'little'))

    check_place(base, extent[1], size, fdt_json, below_4gib)

    set_u64(chosen, 'dram-base', base)
    set_u64(chosen, 'dram-size', size)
    panic_pa = base + size
    for i, (n, flags, v) in enumerate(pram.props):
        if n == 'reg':
            pram.props[i] = (n, flags, panic_pa.to_bytes(8, 'little')
                             + PANIC_LOG_SIZE.to_bytes(8, 'little'))
    # Defensive: a tree that also carries a /memory keeps it in step (this one does not).
    for c in root.children:
        if not c.name.startswith('memory'):
            continue
        reg = c.prop('reg')
        if reg is None or len(reg) != 16:
            die(f'/{c.name} reg is {len(reg) if reg else 0} bytes, expected 16')
        for j, (n, flags, v) in enumerate(c.props):
            if n == 'reg':
                c.props[j] = (n, flags, base.to_bytes(8, 'little')
                              + (size + PANIC_LOG_SIZE).to_bytes(8, 'little'))

    out = adt.serialize(root)
    open(adt_out, 'wb').write(out)
    print(f'{adt_out}: dram-base 0x{old[0]:x} -> 0x{base:x}, '
          f'dram-size 0x{old[1]:x} -> 0x{size:x}, '
          f'pram 0x{panic_pa:x}+0x{PANIC_LOG_SIZE:x}, {len(out)} bytes')
    print(f'payload header will get phys_base=0x{base:x} mem_size=0x{size:x}; '
          f'sha256 {hashlib.sha256(out).hexdigest()}')


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else None
    if mode in ('low', 'high'):
        extent = LOW_EXT if mode == 'low' else HIGH_EXT
        adt_in = arg('--adt') or die('--adt is required')
        adt_out = arg('--out') or die('--out is required')
        write_phys(adt_in, adt_out, extent, arg('--fdt-json'), mode == 'low')
    elif mode == 'cmdline':
        if '--stock' in sys.argv:
            i = STOCK_CMDLINE.index(' debug=0xc')
            print(STOCK_CMDLINE[:i] + ' ' + DEBUG_ARGS + STOCK_CMDLINE[i:])
        elif '--fajita' in sys.argv:
            print(f'{FAJITA_CMDLINE}  # {FAJITA_CITE}')
            print('# full 0057 phone set, for the later stages: '
                  'rd=ufsroot0 unentitled_ios_sim_launch=1 ignition_level=1 '
                  'wdt_test=no_user_checkin ufsrw=1 rootrw=1 '
                  f'launchd_unsecure_cache=1 wdt=-1  # {FAJITA_FILE}:41')
        else:
            die('cmdline needs --stock or --fajita')
    elif mode == 'check':
        fdt_json = arg('--fdt-json') or die('--fdt-json is required')
        base = hexval(arg('--phys-base') or die('--phys-base is required'),
                      '--phys-base')
        size = hexval(arg('--dram-size') or f'0x{LOW_EXT[1] - PANIC_LOG_SIZE:x}',
                      '--dram-size')
        check_place(base, size + PANIC_LOG_SIZE, size, fdt_json,
                    base + size + PANIC_LOG_SIZE <= LIMIT_4GIB)
    else:
        die('mode: low | high | cmdline | check')


if __name__ == '__main__':
    main()
