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

Usage: mkadt_avicii.py OUT.adt (--fdt-json FILE | --qemu) [--dump]
"""
import hashlib, json, os, struct, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import adt  # noqa: E402

# Fallback dram only for --qemu (no live FDT there) and for a sanity cross-check
# of what the JSON says. 0xb0000000 is above every low-bank XPU carve-out, as on
# sweet; avicii's own numbers are whatever the live FDT reports.
DEFAULT_PHYS_BASE = 0xb0000000
DEFAULT_MEM_SIZE = 0x4d000000
# Smallest dram we believe from an FDT; below this the JSON is probably empty.
MIN_MEM_SIZE = 0x10000000
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
FB_W, FB_H, FB_STRIDE = 1080, 2400, 4800
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


def dram_from_json(path):
    """Topmost contiguous usable extent of the live memory map, panic log excluded.

    `memory` are the /memory@... reg entries, `reserved` the /reserved-memory
    children - everything the kernel must not hand out. The topmost extent is
    used for the same reason --highmem existed on sweet: the low bank is full of
    fixed carve-outs, the upper bank is clean and never xpu-protected.
    """
    doc = json.load(open(path))
    mem = [(_int(e['base']), _int(e['size'])) for e in doc.get('memory', [])]
    mem = [(b, s) for b, s in mem if s]
    if not mem:
        raise SystemExit(f'{path}: no usable "memory" entries')
    holes = [(_int(e['base']), _int(e['size'])) for e in doc.get('reserved', [])]
    # Region under 0x80000000 is device/XPU territory, never dram.
    holes.append((0, 0x80000000))
    usable = _subtract(mem, holes)
    usable = [(b, s) for b, s in usable if s >= MIN_MEM_SIZE]
    if not usable:
        raise SystemExit(f'{path}: no usable extent of at least {MIN_MEM_SIZE:#x} bytes left')
    base, size = max(usable, key=lambda e: e[0] + e[1])
    if base < 0x100000000:
        print(f'note: dram starts below 4 GiB ({base:#x}); '
              'the panic log and pmap assume highmem', file=sys.stderr)
    for rbase, rsize, what in ((FB, FB_SIZE, '/sweet-fbcon'),
                               (UFS, UFS_SIZE, '/sweet-ufs')):
        if rbase < base + size and rbase + rsize > base:
            print(f'note: {what} at {rbase:#x} overlaps dram {base:#x}+{size:#x}',
                  file=sys.stderr)
    return base, size


def build(seed=None, qemu=False, fdt_json=None):
    """qemu=True: same tree, but with QEMU virt's GIC addresses and CNTFRQ (tools/qemu-sweet.py)."""
    if fdt_json:
        phys_base, mem_size = dram_from_json(fdt_json)
    elif qemu:
        phys_base, mem_size = DEFAULT_PHYS_BASE, DEFAULT_MEM_SIZE
    else:
        raise SystemExit('error: --fdt-json FILE is required for the phone '
                         '(the live FDT is the only source of the memory map)')
    # Carve the panic log off the top so the kernel never allocates over it.
    panic_base = phys_base + mem_size - PANIC_LOG_SIZE
    mem_size -= PANIC_LOG_SIZE
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
    outs = [a for a in sys.argv[1:] if not a.startswith('--') and a not in (_arg('--fdt-json'),)]
    if len(outs) != 1:
        raise SystemExit((__doc__ or '').strip().splitlines()[-1])
    fdt_json = _arg('--fdt-json')
    root = build(qemu='--qemu' in sys.argv, fdt_json=fdt_json)
    blob = adt.serialize(root)
    open(outs[0], 'wb').write(blob)
    if '--dump' in sys.argv:
        adt.dump(adt.parse(blob)[0])
    print(f'{outs[0]}: {len(blob)} bytes', file=sys.stderr)
