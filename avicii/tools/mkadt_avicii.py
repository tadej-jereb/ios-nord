#!/usr/bin/env python3
"""Build the minimal Apple Device Tree that the AVICII (OnePlus Nord) xnu needs.

Forked from ios-sweet's tools/mkadt.py; only the platform-dependent parts differ
(see the avicii markers). Everything Apple-side - the D22AP identity, CSR
policy, panic log, buttons - is unchanged, including the node names
/sweet-fbcon and /sweet-ufs and the `xiaomi,sweet` compatible string that
SweetPlatformExpert matches on.

The kernel-managed RAM is NOT a constant here: lito has no /memory node in the
board DTS (ABL adds it), so dram-base/dram-size come from a JSON dump of the
*live* FDT, which tools/fdt-mem.py produces from an extracted board.dtb:

  tools/fdt-mem.py board.dtb > avicii-fdt-mem.json
  mkadt_avicii.py OUT.adt --fdt-json avicii-fdt-mem.json

The dram base is a choice, never a default: it is either the regbase the live FDT
reports, or a value given with --phys-base (checked against the extents in
--fdt-json, else against the published avicii-live.adt). Every line that prints a
regbase or a memsize also prints where it came from, so a fallback can never pass
for a measurement.

Usage: mkadt_avicii.py OUT.adt (--fdt-json FILE | --qemu)
                         [--phys-base HEX [--allow-high]] [--dump]
"""
import hashlib, json, os, struct, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import adt  # noqa: E402

# Fallback dram, used *only* when there is no regbase at all (--qemu, or an FDT with
# no usable memory entry) - never in place of one the FDT does report. A fallback
# that quietly disagrees with the published regbase is what once produced a
# 0x180000000 copy under a 0x90000000-shaped belief, so every user of it is printed
# with its provenance. The fallback sits wholly inside the live low bank and below
# the 0xa0000000 splash carve-out, so it never straddles the 0xbbb00000..0xc0000000
# hole, as on sweet.
PHYS_BASE_FALLBACK = 0x90000000
FALLBACK_MEM_SIZE = 0x0f000000
PHYS_BASE_MAX = 0x100000000   # 4 GiB; above it needs --allow-high
FDT_SRC = 'from /memory regbase, live FDT'
ADT_SRC = 'from /chosen dram-base in the ADT (unverified)'
FALLBACK_SRC = 'fallback; regbase absent'
# Smallest dram we believe from an FDT; below this the JSON is probably empty.
MIN_MEM_SIZE = 0x10000000

# The published/live ADT, used to check --phys-base when no --fdt-json is given.
ADT_LIVE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '../adt/avicii-live.adt')
# Panic log buffer, carved from the TOP of the dram range and exposed to XNU as
# /pram + /chosen/embedded-panic-log-size. Without it, pe_init.c's
# check_for_panic_log() leaves gPanicBase == 0, debug_log_init() bails out twice
# and the kernel hangs right after "kdp_core zlib memory".
PANIC_LOG_SIZE = 0x100000
# /arm-io children are relative to this; it must not be 0 (serial_init bails)
SOC_BASE = 0x01000000

# avicii/lito MMIO (lito.dtsi: gic@17a00000, ufshc@1d84000, cont_splash_region).
GICD, GICD_SIZE = 0x17a00000, 0x10000
GICR, GICR_SIZE = 0x17a60000, 0x100000
FB, FB_SIZE = 0xa0000000, 0x2300000   # cont_splash_region, 35 MiB
FB_W, FB_H, FB_STRIDE = 1080, 2400, 1080 * 4   # row = width*4, nothing pads it
UFS, UFS_SIZE = 0x01d84000, 0x3000    # ufshc@1d84000 "ufs_mem"; QEMU virt has none
TIMEBASE = 19200000
# lito arch timer PPI 11 (0x1b in DT numbering) -> XNU INTID 19, as on sweet.
VTIMER_INTID = 19
SWEET_ECID = 0x5357454554000001  # 'SWEET' + 1, synthetic

# QEMU virt (-M virt,gic-version=3 -cpu cortex-a76): GICD/GICR and the generic timer's CNTFRQ
QEMU_GICD, QEMU_GICR, QEMU_TIMEBASE = 0x08000000, 0x080a0000, 62500000
QEMU_VTIMER_INTID = 27

# lito CPU clocks: 6x Cortex-A55 (0x000-0x500) @1.8 GHz, then the two A76 -
# 0x600 on freq-domain1 (gold) @2.2 GHz, 0x700 on freq-domain2 (prime) @2.4 GHz
# (lito.dtsi:62,215-218,242-245 - the domain index ascends with the core tier).
# MPIDR = core << 8, physical-core order. avicii/CONSTANTS.md agrees; if the
# phone disagrees, read scaling_max_freq per policy and flip two entries here.
CPU_CLOCK_HZ = {6: 2208000000, 7: 2400000000}
CPU_CLOCK_DEFAULT = 1804800000

BOOT_MANIFEST_HASH = hashlib.sha384(b'sweet boot manifest').digest()

# The iOS userland is the iPhone X (iPhone10,3 / D22AP) IPSW. That tree is an
# Apple artifact (kept out of git): extract it from the IPSW firmware with
#   ipsw img4 im4p extract build/ipsw-x/Firmware/all_flash/DeviceTree.d22ap.im4p -o build/ipsw-x/d22ap.adt
D22AP_ADT = os.environ.get('D22AP_ADT') or os.path.join(
    os.path.dirname(os.path.abspath(__file__)), '../../build/ipsw-x/d22ap.adt')

u32 = lambda *v: struct.pack('<%dI' % len(v), *v)
u64 = lambda *v: struct.pack('<%dQ' % len(v), *v)
cstr = lambda s: s.encode() + b'\0'


def node(name, props=(), children=()):
    n = adt.Node()
    n.props = [('name', 0, cstr(name))] + [(k, 0, v) for k, v in props]
    n.children = list(children)
    return n


def d22ap_product(path=D22AP_ADT):
    """/product properties of the real D22AP tree, without the syscfg
    placeholders iBoot would fill in (flag bit set) and the node bookkeeping."""
    if not os.path.exists(path):
        print(f'warning: {path} missing, no /product node', file=sys.stderr)
        return None
    root, _ = adt.parse(open(path, 'rb').read())
    for c in root.children:
        if dict((k, v) for k, f, v in c.props).get('name') == b'product\0':
            return [(k, v) for k, f, v in c.props if not f and k not in ('name', 'AAPL,phandle')]
    raise SystemExit(f'{path}: no /product node')


def _int(v):
    return int(v, 0) if isinstance(v, str) else int(v)


def _subtract(extents, holes):
    """extents minus holes, both lists of (base, size)."""
    out = list(extents)
    for hb, hs in holes:
        he = hb + hs
        nxt = []
        for b, s in out:
            e = b + s
            if he <= b or hb >= e:              # disjoint
                nxt.append((b, s))
                continue
            if b < hb:
                nxt.append((b, hb - b))         # keep the part before the hole
            if he < e:
                nxt.append((he, e - he))        # and the part after
        out = nxt
    return out


def _hexval(name):
    v = _arg(name)
    if v is None:
        return None
    try:
        return int(v[2:] if v[:2].lower() == '0x' else v, 16)
    except ValueError:
        raise SystemExit(f'error: {name}: {v!r} is not hex')


def _extents_from_json(path):
    """(memory, holes) of an fdt-mem.py dump."""
    doc = json.load(open(path))
    mem = [(_int(e['base']), _int(e['size'])) for e in doc.get('memory', [])]
    holes = [(_int(e['base']), _int(e['size'])) for e in doc.get('reserved', [])]
    return mem, holes


def _extents_from_adt(path=ADT_LIVE):
    """The one extent the published ADT describes in /chosen, with the panic log
    added back: build() has already carved PANIC_LOG_SIZE off its top."""
    root, _ = adt.parse(adt.load(path))
    for c in root.children:
        if c.name == 'chosen':
            base = struct.unpack('<Q', c.prop('dram-base'))[0]
            size = struct.unpack('<Q', c.prop('dram-size'))[0] + PANIC_LOG_SIZE
            return [(base, size)], []
    raise SystemExit(f'{path}: no /chosen node')


def _containing(extents, phys_base):
    """End of the nearest extent that contains phys_base, or None."""
    ends = [b + s for b, s in extents if s and b <= phys_base < b + s]
    return min(ends) if ends else None


def _live_product_props():
    """Property count of /product in the published ADT (count only, no values)."""
    root, _ = adt.parse(adt.load(ADT_LIVE))
    for c in root.children:
        if c.name == 'product':
            return len(c.props)
    return 0


def dram(extents, holes, source, phys_base=None, allow_high=False):
    """Pick (base, size) and say where it came from.

    Without phys_base: the topmost usable extent of the live memory map, as before.
    With phys_base: that base, sized by the extent that contains it. Either way the
    size is a whole extent, not a guess - MIN_MEM_SIZE only filters the auto pick.
    """
    mem = [(b, s) for b, s in extents if s]
    if not mem:
        print(f'warning: regbase: {FALLBACK_SRC} - no usable "memory" entry; '
              f'dram {PHYS_BASE_FALLBACK:#x}+{FALLBACK_MEM_SIZE:#x}', file=sys.stderr)
        return PHYS_BASE_FALLBACK, FALLBACK_MEM_SIZE, FALLBACK_SRC

    if phys_base is not None:
        end = _containing(mem, phys_base)
        if end is None:
            lo, hi = min(b for b, _ in mem), max(b + s for b, s in mem)
            raise SystemExit(f'error: --phys-base {phys_base:#x} is outside every '
                             f'memory extent ({source}: {lo:#x}..{hi:#x})')
        if phys_base >= PHYS_BASE_MAX and not allow_high:
            raise SystemExit(f'error: --phys-base {phys_base:#x} is above 4 GiB; '
                             'pass --allow-high if the FDT really puts dram there')
        base, size = phys_base, end - phys_base
        inner = sum(max(0, min(e, end) - max(b, phys_base))
                    for b, s in holes for e in (b + s,))
        print(f'note: dram {base:#x}+{size:#x} {source}, extent {base:#x}..{end:#x}; '
              f'{inner:#x} reserved bytes inside are not subtracted', file=sys.stderr)
    else:
        usable = _subtract(mem, holes + [(0, 0x80000000)])
        usable = [(b, s) for b, s in usable if s >= MIN_MEM_SIZE]
        if not usable:
            print(f'warning: regbase: {FALLBACK_SRC} - every extent is holed out; '
                  f'dram {PHYS_BASE_FALLBACK:#x}+{FALLBACK_MEM_SIZE:#x}', file=sys.stderr)
            return PHYS_BASE_FALLBACK, FALLBACK_MEM_SIZE, FALLBACK_SRC
        base, size = max(usable, key=lambda e: e[0] + e[1])
        end = _containing(mem, base)
        # The exposed size is the extent's, so a hole can only shorten the tail.
        assert end - base >= size, (hex(base), hex(size), hex(end - base))
        if end - base != size:
            print(f'warning: regbase: {FDT_SRC}; dram {base:#x}+{size:#x} is shorter '
                  f'than its extent {base:#x}..{end:#x} after carve-outs', file=sys.stderr)
        else:
            print(f'note: regbase: {FDT_SRC}; dram {base:#x}+{size:#x}, whole extent',
                  file=sys.stderr)

    if base < 0x100000000:
        print(f'note: dram starts below 4 GiB ({base:#x}; {source}); '
              'the panic log and pmap assume highmem', file=sys.stderr)
    for rbase, rsize, what in ((FB, FB_SIZE, '/sweet-fbcon'),
                               (UFS, UFS_SIZE, '/sweet-ufs')):
        if rbase < base + size and rbase + rsize > base:
            print(f'note: {what} at {rbase:#x} overlaps dram {base:#x}+{size:#x} '
                  f'({source})', file=sys.stderr)
    return base, size, source


def build(seed=None, qemu=False, fdt_json=None, phys_base=None, allow_high=False):
    """qemu=True: same tree, but with QEMU virt's GIC addresses and CNTFRQ (tools/qemu-sweet.py).

    phys_base: explicit dram base; must land inside a memory extent of fdt_json (or
    of the published ADT when no --fdt-json is given), and needs allow_high above
    4 GiB.
    """
    if phys_base is not None:
        extents, holes = _extents_from_json(fdt_json) if fdt_json else _extents_from_adt()
        phys_base, mem_size, src = dram(extents, holes,
                                        FDT_SRC if fdt_json else ADT_SRC,
                                        phys_base, allow_high)
    elif fdt_json:
        phys_base, mem_size, src = dram(*_extents_from_json(fdt_json), source=FDT_SRC)
    elif qemu:
        print(f'warning: regbase: {FALLBACK_SRC} - QEMU has no FDT to read; '
              f'dram {PHYS_BASE_FALLBACK:#x}+{FALLBACK_MEM_SIZE:#x}', file=sys.stderr)
        phys_base, mem_size, src = PHYS_BASE_FALLBACK, FALLBACK_MEM_SIZE, FALLBACK_SRC
    else:
        raise SystemExit('error: --fdt-json FILE is required for the phone '
                         '(the live FDT is the only source of the memory map)')
    if mem_size <= 2 * PANIC_LOG_SIZE:
        raise SystemExit(f'error: dram {phys_base:#x}+{mem_size:#x} ({src}) cannot '
                         f'hold a {PANIC_LOG_SIZE:#x} panic log')
    # Carve the panic log off the top so the kernel never allocates over it.
    panic_base = phys_base + mem_size - PANIC_LOG_SIZE
    mem_size -= PANIC_LOG_SIZE
    print(f'note: panic log {panic_base:#x}+{PANIC_LOG_SIZE:#x} at the top of the '
          f'extent; dram-size {mem_size:#x} = extent minus panic log ({src})',
          file=sys.stderr)
    gicd, gicr, timebase = (QEMU_GICD, QEMU_GICR, QEMU_TIMEBASE) if qemu else (GICD, GICR, TIMEBASE)
    seed = seed if seed is not None else os.urandom(64)
    phandle = iter(range(1, 1000))
    ph = lambda: ('AAPL,phandle', u32(next(phandle)))

    chosen = node('chosen', [
        ph(),
        ('dram-base', u64(phys_base)),
        ('dram-size', u64(mem_size)),
        ('random-seed', seed),
        ('debug-enabled', u32(1)),
        ('embedded-panic-log-size', u32(PANIC_LOG_SIZE)),
        ('firmware-version', cstr('sweet-shim')),
        ('system-firmware-version', cstr('sweet-shim')),
        # iBoot's SHA-384 of the boot manifest; /sbin/mount -P 1 exits unless
        # it exists. Fixed stand-in value.
        ('boot-manifest-hash', BOOT_MANIFEST_HASH),
        # libimg4 (cryptexd) aborts "failed to get crypto algorithm" without it.
        ('crypto-hash-method', cstr('sha2-384')),
        # MobileGestalt's screen class: 1080x2400 @3x = 360x800 points.
        ('display-scale', u32(3)),
        # XNU derives IOPlatformUUID (gethostuuid) from these on arm.
        ('unique-chip-id', struct.pack('<Q', SWEET_ECID)),
        ('chip-id', u32(0x8015)),
        # Security status as on a dev-fused, undemoted board (tuple 0,0,1,1).
        ('certificate-production-status', u32(0)),
        ('effective-production-status-ap', u32(0)),
        ('certificate-security-mode', u32(1)),
        ('effective-security-mode-sep', u32(1)),
    ], [node('memory-map', [ph()]),
        # Local boot policy (kern_csr.c), SIP relaxed; lp-sip1: unsealed root.
        node('asmb', [ph(), ('lp-sip0', u64(0x6f)), ('lp-sip1', u32(1))])])

    # SWEET SMP: all eight lito cores in physical-core order (0-5 Cortex-A55,
    # 6-7 Cortex-A76), one homogeneous cluster. The kernel defaults to one and
    # uses cpus=N to select an initial prefix (N <= 8). QEMU keeps one CPU.
    cpu_nodes = []
    for core in range(1 if qemu else 8):
        cpu_nodes.append(node(f'cpu{core}', [
            ph(),
            ('device_type', cstr('cpu')),
            ('compatible', cstr('qcom,kryo475') + cstr('ARM,v8')),
            ('reg', u32(core << 8)),  # actual MPIDR Aff1:Aff0, NOT logical ID
            ('cpu-id', u32(core)),    # descriptive: XNU assigns IDs by DT order
            ('cluster-id', u32(0)),   # descriptive; see ml_parse_cpu_topology
            ('cluster-type', u32(0)),  # homogeneous CLUSTER_TYPE_SMP, not AMP
            ('die-cluster-id', u32(0)),
            ('cluster-core-id', u32(core)),
            ('l2-cache-id', u32(core)),  # distinct per-core L2 nodes in live FDT
            ('l3-cache-id', u32(0)),     # shared L3
            ('state', cstr('running' if core == 0 else 'stopped')),
            ('timebase-frequency', u32(timebase)),
            ('clock-frequency', u32(CPU_CLOCK_HZ.get(core, CPU_CLOCK_DEFAULT))),
            ('bus-frequency', u32(100000000)),
            ('memory-frequency', u32(1866000000)),
            ('peripheral-frequency', u32(timebase)),
            ('fixed-frequency', u32(timebase)),
        ]))
    cpus = node('cpus', [ph(), ('#address-cells', u32(1)),
                         ('#size-cells', u32(0))], cpu_nodes)

    gic = node('gic', [
        ph(),
        ('compatible', cstr('arm,gic-v3')),
        ('interrupt-controller', b''),
        ('virtual-timer-intid', u32(QEMU_VTIMER_INTID if qemu else VTIMER_INTID)),
        ('reg', u64(gicd - SOC_BASE, GICD_SIZE, gicr - SOC_BASE, GICR_SIZE)),
    ])
    arm_io = node('arm-io', [
        ph(),
        ('device_type', cstr('sweet-io')),
        ('compatible', cstr('sweet-io') + cstr('arm-io')),
        ('#address-cells', u32(2)),
        ('#size-cells', u32(2)),
        ('ranges', u64(0, SOC_BASE, 0x100000000 - SOC_BASE)),
    ], [gic,
        # watchdogd checks IODeviceTree:/arm-io/wdt for no-pmu.
        node('wdt', [ph(), ('no-pmu', u32(1))]),
        # Main display. Canvas stays at the iPhone X size the userland expects;
        # the panel itself is 1080x2400 (see /sweet-fbcon).
        node('disp0', [
            ph(),
            ('device_type', cstr('display-subsystem')),
            ('compatible', cstr('sweet,display')),
            ('canvas-width', u32(1125)),
            ('canvas-height', u32(2436)),
        ])])

    fbcon = node('sweet-fbcon', [
        ph(),
        ('reg', u64(FB, FB_SIZE)),
        ('width', u32(FB_W)),
        ('height', u32(FB_H)),
        ('stride', u32(FB_STRIDE)),
    ])

    # bsd/dev/sweet_ufs.c: the UFS host ABL leaves running (absolute physical reg).
    ufs = node('sweet-ufs', [
        ph(),
        ('compatible', cstr('qcom,ufshc')),
        ('reg', u64(UFS, UFS_SIZE)),
    ])

    defaults = node('defaults', [ph(), ('no-effaceable-storage', u32(1))])

    # MobileGestalt HomeButtonType = IODeviceTree:/buttons home-button-type
    # (D22AP: 2, no Home button; absent = 0 = Home-button device).
    buttons = node('buttons', [
        ph(),
        ('button-names', cstr('volup') + cstr('voldown') + cstr('hold')),
        ('home-button-type', u32(2)),
        ('opposed-power-vol-buttons', u32(1)),
    ])

    product_props = d22ap_product()
    product = [node('product', [ph()] + product_props)] if product_props else []
    # /product must keep every property the published ADT carries: XNU boots without
    # them but MobileGestalt answers wrong. Count read from the ADT, not hard-coded.
    if product_props and os.path.exists(ADT_LIVE):
        live = _live_product_props()
        assert len(product_props) + 2 == live, f'{len(product_props) + 2} product props, ADT has {live}'

    # Panic log region. /pram reg = <phys size>; it sits just above the
    # dram-size we expose, so XNU maps it but never allocates into it.
    pram = node('pram', [ph(), ('reg', u64(panic_base) + u64(PANIC_LOG_SIZE))])

    # Identity of the iPhone X whose userland runs here: compatible[0] is
    # hw.model/hw.target (D22AP), model is hw.machine/hw.product (iPhone10,3).
    # 'xiaomi,sweet' stays for SweetPlatformExpert matching even on avicii.
    return node('device-tree', [
        ph(),
        ('compatible', cstr('D22AP') + cstr('iPhone10,3') + cstr('xiaomi,sweet') + cstr('qcom,sm7250') + cstr('AppleARM')),
        ('model', cstr('iPhone10,3')),
        ('target-type', cstr('D22')),
        ('target-sub-type', cstr('D22AP')),
        ('manufacturer', cstr('Apple Inc.')),
        ('#address-cells', u32(2)),
        ('#size-cells', u32(2)),
    ], [chosen, defaults, cpus, arm_io, fbcon, buttons, pram] + product + ([] if qemu else [ufs]))


def _arg(name):
    if name in sys.argv:
        i = sys.argv.index(name)
        try:
            return sys.argv[i + 1]
        except IndexError:
            raise SystemExit(f'{name} needs a value')
    return None


if __name__ == '__main__':
    outs = [a for a in sys.argv[1:] if not a.startswith('--')
            and a not in (_arg('--fdt-json'), _arg('--phys-base'))]
    if len(outs) != 1:
        raise SystemExit((__doc__ or '').strip().splitlines()[-1])
    fdt_json = _arg('--fdt-json')
    phys_base = _hexval('--phys-base')
    if phys_base is not None and fdt_json is None and '--qemu' not in sys.argv:
        print(f'note: regbase: no --fdt-json, --phys-base is checked against '
              f'{os.path.relpath(ADT_LIVE)} ({ADT_SRC})', file=sys.stderr)
    root = build(qemu='--qemu' in sys.argv, fdt_json=fdt_json, phys_base=phys_base,
                 allow_high='--allow-high' in sys.argv)
    chosen = [c for c in root.children if c.name == 'chosen'][0]
    print(f'note: /chosen dram-base {struct.unpack("<Q", chosen.prop("dram-base"))[0]:#x} '
          f'dram-size {struct.unpack("<Q", chosen.prop("dram-size"))[0]:#x}', file=sys.stderr)
    blob = adt.serialize(root)
    open(outs[0], 'wb').write(blob)
    if '--dump' in sys.argv:
        adt.dump(adt.parse(blob)[0])
    print(f'{outs[0]}: {len(blob)} bytes', file=sys.stderr)
