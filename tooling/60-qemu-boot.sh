#!/bin/bash
# 60-qemu-boot.sh - boot an XNU payload on QEMU's virt board, on the host.
#
# The point is a kernel loop that costs seconds instead of the ~2 min phone
# cycle (fastboot, watch, reset, recovery, ring pull, photo). It does what
# avicii/shim/loader.c does on the phone (docs/SHIM_BOOT.md): build the ADT with
# --qemu, place the payload segments, the ADT and boot_args at their physical
# addresses, and start the CPU at a 6-instruction stub that jumps to the entry
# with x0 = boot_args. Framebuffer console (patch 0003/0010) is the channel;
# the screen is decoded with the kernel's own iso_font after the run.
#
#   tooling/60-qemu-boot.sh                      # default payload, 45 s
#   tooling/60-qemu-boot.sh --secs 60 --keep     # longer window, keep artifacts
#   tooling/60-qemu-boot.sh --cmdline '-v debug=0x144 ...'
#   tooling/60-qemu-boot.sh --ramdisk r.img --cmdline 'rd=md0 -v debug=0x144'
#   tooling/60-qemu-boot.sh --until 'Waiting on <dict'   # stop at the ladder point
#   tooling/60-qemu-boot.sh --gdb                # halt at entry, stub on a free port from 1234
#   tooling/60-qemu-boot.sh --gdb --gdb-port 1236  # explicit stub port
#   tooling/60-qemu-boot.sh --view               # open screen.png when done
#
# Every run that dumps fb.raw also renders it (python3 stdlib only) to
# screen.png (1080x2400 RGB) and screen-half.png (540x1200, every 2nd pixel:
# the 2x-scaled fbcon font comes back at its native 8x16, still legible).
# --view opens screen.png with xdg-open, else gwenview, else eog.
#
# Every run gets its own directory: --out names it, otherwise it is minted from
# the clock and, if that second is already taken, suffixed -2, -3, ... (mkdir is
# the test-and-set, so two runs started in the same second never share one).
# Inside it everything is private - payload.bin, adt, stub.bin, mon.sock,
# msgbuf.txt, sweetlog.txt, screen.png - nothing is written outside it except a __pycache__
# next to avicii/tools/. Two runs at once need no coordination beyond that and a
# distinct --gdb port, which the script picks and prints. tooling/62-msgbuf-summary.sh
# reads the dir afterwards.
#
# sweetlog.txt/sweetlog.raw are patch 0047's _sweet_log_ring: every byte
# _cnputs() gets, appended *before* the disableConsoleOutput gate.  That is
# where dyld4::console's "dyld cache '...' not loaded: ..." for pid 1 goes when
# the serial, the screen and msgbuf all show nothing (docs/CACHE_TRIM.md 3).
#
# Kernel debug session (the reason to do this at all). QEMU gets
# "-S -gdb tcp::<port>", port 1234 unless that is busy; print the run's own
# "guest:" line for the addresses:
#   tooling/60-qemu-boot.sh --gdb &
#   tooling/opt/llvm/bin/lldb -o 'gdb-remote <port>' \
#       -o 'b *<entry PA>' -o c -o 'b *<mmu-on PA>' -o c <out>/kernel.noctf
# The x86 gdb in /usr/bin has no aarch64 target and rejects the stub; use the
# repo's lldb (18.1.8), on the kernel.noctf copy -- plain kernel.development.sweet
# crashes lldb's CTF reader. Breakpoints must be *physical*: while halted inside
# the stub the kernel VA space is not usable for breakpoint insertion, so a
# symbol breakpoint placed at the stub never fires. See docs/QEMU_AVICII.md 3.
#
# Host only. Never touches the phone, flashes nothing, commits nothing.
#
# RESULT IS NOT A PHONE RESULT. QEMU virt has no UFS, no ICE, no PSCI
# firmware, its own GIC/timer bases and the framebuffer as plain RAM at a
# different physical address; a QEMU boot proves kernel logic, not hardware.
# docs/QEMU_AVICII.md has the full divergence list and what a result here does
# and does not transfer. The ADT is also relocated for the host (dram extended
# so the framebuffer is inside the physmap, fbcon window shrunk to the 32 MB
# the early io_map window can take) - see docs/QEMU_AVICII.md section 4.
#
# Exit: 0 target point reached, 1 usage, 2 panic decoded, 3 still printing when
# --secs ran out, 4 host/setup problem - including `msgbuf=` on the command line
# with a ring that came out 0 B (msgbuf.txt is never left silently empty) - and
# 5 the same for _sweet_log_ring: a non-zero _sweet_log_total with a 0 B
# sweetlog.txt is a harness failure, not a guest that said nothing.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)

KERNEL=${KERNEL:-$repo/avicii/shim/out/kernel/kernel.development.sweet}
# cpu-factor=10: QEMU is ~10x slower than the phone, and the interrupt-masked
# watchdog (osfmk/arm/machine_routines_common.c) panics at 35 ms otherwise.
CMDLINE=${CMDLINE:--v debug=0x144 cpus=1 sweetsmp=0 sweettouch=0 sweetkeys=0 sweetecon=1 cpu-factor=10}
RAMDISK=${RAMDISK:-}
SHARED_CACHE=${SHARED_CACHE:-}
SECS=${SECS:-45}
SMP=${SMP:-1}
OUTDIR=""
GDB=0
GDB_PORT=""
UART0=0
FB=""
KEEP=0
VIEW=0
UNTIL=""
RAMDISK=""

while [ $# -gt 0 ]; do
	case $1 in
	--kernel) KERNEL=${2:?--kernel needs a Mach-O}; shift 2 ;;
	--cmdline) CMDLINE=${2:?--cmdline needs a string}; shift 2 ;;
	--ramdisk) RAMDISK=${2:?--ramdisk needs an image}; shift 2 ;;
	--shared-cache) SHARED_CACHE=${2:?--shared-cache needs an image}; shift 2 ;;
	--mem) MEM=${2:?--mem needs a size}; shift 2 ;;
	--secs) SECS=${2:?--secs needs a number}; shift 2 ;;
	--smp) SMP=${2:?--smp needs a count}; shift 2 ;;
	--until) UNTIL=${2:?--until needs a regex}; shift 2 ;;
	--ramdisk) RAMDISK=${2:?--ramdisk needs an image}; shift 2 ;;
	--shared-cache) SHARED_CACHE=${2:?--shared-cache needs an image}; shift 2 ;;
	--mem) MEM=${2:?--mem needs a size}; shift 2 ;;
	--out) OUTDIR=${2:?--out needs a directory}; shift 2 ;;
	--gdb) GDB=1; shift ;;
	--gdb-port) GDB_PORT=${2:?--gdb-port needs a port number}; shift 2 ;;
	--uart0) UART0=1; shift ;;
	--keep) KEEP=1; shift ;;
	--view) VIEW=1; shift ;;
	-h | --help) sed -n '2,59p' "$0"; exit 0 ;;
	*) echo "error: unknown argument $1" >&2; exit 1 ;;
	esac
done

# A --ramdisk run carries the whole volume inside the payload, so the RAM it needs
# has to be reserved: -m for QEMU, --mem-size for the ADT the kernel reads. 256 MiB
# stays outside both for the framebuffer, the panic log and the stack.
MEM=${MEM:-${QEMU_MEM:-4G}}
case $MEM in
*[Gg]) mem_bytes=$(awk -v n="${MEM%[Gg]}" 'BEGIN{printf "%d", n*1073741824}') ;;
*[Mm]) mem_bytes=$(awk -v n="${MEM%[Mm]}" 'BEGIN{printf "%d", n*1048576}') ;;
*) mem_bytes=$MEM ;;
esac
(( mem_bytes > 0x20000000 )) || { echo "error: --mem $MEM too small" >&2; exit 1; }
printf -v MEM_SIZE '0x%x' $(( mem_bytes - 0x10000000 ))
MEM_BYTES=$mem_bytes

QEMU=${QEMU:-qemu-system-aarch64}
command -v "$QEMU" >/dev/null || { echo "error: $QEMU not in PATH (apt install qemu-system-arm)" >&2; exit 4; }
command -v python3 >/dev/null || { echo "error: python3 not in PATH" >&2; exit 4; }
[ -r "$KERNEL" ] || { echo "error: no kernel at $KERNEL (docs/KERNEL_CI.md section 3)" >&2; exit 4; }
[ -r "$repo/avicii/tools/mkadt_avicii.py" ] || { echo "error: no ADT generator" >&2; exit 4; }
NM=${NM:-$(command -v llvm-nm || echo "$repo/tooling/opt/llvm/bin/llvm-nm")}
[ -x "$NM" ] || { echo "error: llvm-nm not found, needed to locate iso_font" >&2; exit 4; }

stamp=$(date +%Y%m%d-%H%M%S)
if [ -z "$OUTDIR" ]; then
	# mkdir is the test-and-set: a second run started in the same second gets -2.
	OUTDIR=$repo/logs/qemu/$stamp
	n=1
	while ! mkdir "$OUTDIR" 2>/dev/null; do
		n=$((n + 1))
		(( n <= 99 )) || { echo "error: cannot mint a run dir under $repo/logs/qemu" >&2; exit 4; }
		OUTDIR=$repo/logs/qemu/$stamp-$n
	done
else
	mkdir -p "$OUTDIR" || exit 4
	[ -z "$(ls -A "$OUTDIR" 2>/dev/null)" ] ||
		echo "warning: $OUTDIR is not empty; a concurrent run with the same --out will collide" >&2
fi

# A pinned 1234 makes two --gdb runs fight over the one stub socket; take the
# first free port instead (and say which one). --gdb-port / GDB_PORT override.
if [ "$GDB" = 1 ] && [ -z "$GDB_PORT" ]; then
	GDB_PORT=$(python3 - <<'PY'
import socket
for p in range(1234, 1334):
    s = socket.socket()
    try:
        s.bind(("", p))
    except OSError:
        s.close()
        continue
    s.close()
    print(p)
    break
PY
	)
	[ -n "$GDB_PORT" ] || { echo "error: no free gdb port in 1234-1333" >&2; exit 4; }
	[ "$GDB_PORT" = 1234 ] || echo "note: :1234 is taken, gdb stub on :$GDB_PORT" >&2
fi
echo "$CMDLINE" > "$OUTDIR/cmdline.txt"
printf '%s\n' "$KERNEL" > "$OUTDIR/kernel.path"
[ -n "$RAMDISK" ] && printf '%s\n' "$RAMDISK" > "$OUTDIR/ramdisk.path"

# --- 1. ADT for QEMU virt, then relocate it for the host ----------------------
python3 "$repo/avicii/tools/mkadt_avicii.py" "$OUTDIR/adt.raw" --qemu --mem-size "$MEM_SIZE" \
	> "$OUTDIR/adt.raw.log" 2>&1 || { echo "error: mkadt_avicii.py --qemu failed" >&2; cat "$OUTDIR/adt.raw.log" >&2; exit 4; }

python3 - "$repo" "$OUTDIR/adt.raw" "$OUTDIR/avicii-qemu.adt" "$UART0" "$MEM_BYTES" <<'PY' || exit 4
import struct, sys
repo, src, dst, uart0, membytes = (sys.argv[1], sys.argv[2], sys.argv[3],
                                   sys.argv[4] == "1", int(sys.argv[5]))
sys.path.insert(0, repo + "/avicii/tools")
import adt

FB_WINDOW = 0x1000000                     # 16 MiB maps the 10,368,000 B screen
PRAM_SIZE = 0x100000

root, _ = adt.parse(open(src, "rb").read())
chosen = next(c for c in root.children if c.name == "chosen")
fbcon = next(c for c in root.children if c.name == "sweet-fbcon")
pram = next(c for c in root.children if c.name == "pram")
base = struct.unpack("<Q", chosen.prop("dram-base"))[0]
# The framebuffer has to sit above the payload, and a --ramdisk payload is the
# whole volume: derive it from the RAM size instead of pinning 0xa0000000, which
# a 3 GiB ramdisk would run straight through.
FB = membytes - 0x2000000          # absolute: QEMU RAM starts at 0, dram at base
PRAM = FB + FB_WINDOW


def setprop(node, name, blob):
	for p in node.props:
		if p[0] == name:
			node.props[node.props.index(p)] = (name, p[1], blob)
			return
	raise SystemExit(f"error: {node.name} has no {name}")


# dram must span the framebuffer, or pmap_map_bd has no table for it; the panic
# log moves above the framebuffer so the VM never allocates over it.
setprop(chosen, "dram-size", struct.pack("<Q", PRAM + PRAM_SIZE - base))
setprop(pram, "reg", struct.pack("<QQ", PRAM, PRAM_SIZE))
setprop(fbcon, "reg", struct.pack("<QQ", FB, FB_WINDOW))
if uart0:
	# pl011 in virt; inert until pe_serial.c's VMAPPLE_UART branch is built in.
	arm_io = next(c for c in root.children if c.name == "arm-io")
	node = adt.Node()
	node.props = [("name", 0, b"uart0\0"), ("reg", 0, struct.pack("<QQ", 0x08000000, 0x1000))]
	arm_io.children.append(node)
open(dst, "wb").write(adt.serialize(root))
open(dst + ".fb", "w").write(f"{FB:#x}\n")
print(f"adt relocated: dram {base:#x}+{PRAM + PRAM_SIZE - base:#x}, "
      f"fbcon {FB:#x}+{FB_WINDOW:#x}, pram {PRAM:#x}+{PRAM_SIZE:#x}"
      + (", uart0 node added (inert on this kernel)" if uart0 else ""))
PY

# --- 2. payload, exactly as the phone gets it --------------------------------
rdarg=()
[ -n "$RAMDISK" ] && rdarg=(--ramdisk "$RAMDISK")
[ -n "${SHARED_CACHE:-}" ] && rdarg+=(--shared-cache "$SHARED_CACHE")
python3 "$repo/avicii/tools/mkpayload.py" "$KERNEL" "$OUTDIR/avicii-qemu.adt" "$OUTDIR/payload.bin" \
	--cmdline "$CMDLINE" "${rdarg[@]}" > "$OUTDIR/payload.log" 2>&1 || {
	echo "error: mkpayload.py failed" >&2; cat "$OUTDIR/payload.log" >&2; exit 4; }
grep -E '^(virt_base|entry|kernel_end|size):' "$OUTDIR/payload.log"

FB=$(cat "$OUTDIR/avicii-qemu.adt.fb")
[ -n "$FB" ] || { echo "error: no framebuffer address" >&2; exit 4; }

FONTVA=$("$NM" --defined-only "$KERNEL" | awk '$3 == "_iso_font" { print $1 }')
[ -n "$FONTVA" ] || { echo "error: kernel has no _iso_font; screen cannot be decoded" >&2; exit 4; }
# Kernel log channel that does not depend on the framebuffer: after the run the
# message buffer is read out of guest RAM into msgbuf.txt (see section 3).
# cpu_ttep is the kernel's own TTBR1_EL1 value (common_start does
# `msr TTBR1_EL1, [cpu_ttep]`), so it is what a kalloc'd `msgbuf=<n>` ring has
# to be translated through.  sweet_log_ring/sweet_log_total are patch 0047's
# console ring: every byte _cnputs() is handed is appended there *before* the
# disableConsoleOutput gate, so it holds what dyld4::console wrote to
# /dev/console and nothing else on this host can see (docs/CACHE_TRIM.md 3).
KSYMS=$("$NM" --defined-only "$KERNEL" | awk '$3 ~ /^_(msgbufp|cpu_ttep|gPhysBase|gVirtBase|disableConsoleOutput|serial_console_enabled|gc_graphics_boot|vc_progress_enable|sweet_log_ring|sweet_log_total)$/ { printf "%s=%s,", substr($3, 2), $1 }')

# --- 3. guest image, run, dump, decode, verdict ------------------------------
python3 -u - "$OUTDIR" "$SMP" "$SECS" "$GDB" "$UNTIL" "$FONTVA" "$KEEP" "$repo" "$FB" "$MEM" "$KSYMS" "$GDB_PORT" <<'PY'
import json, mmap, os, re, socket, struct, subprocess, sys, time

out, smp, secs, gdb, until, fontva, keep, REPO, FB, MEM, KSYMS, gdbport = sys.argv[1:13]
KSYMS = {k: int(v, 16) for k, v in (x.split("=") for x in KSYMS.split(",") if x)}
secs, smp, gdb, keep = float(secs), int(smp), gdb == "1", keep == "1"
fontva, FB = int(fontva, 16), int(FB, 16)
PAGE, STUB_PA, STRIDE, W, H = 0x4000, 0x40200000, 4320, 1080, 2400
CMDLINE_OFF, SEG_TABLE = 0x48, 0x2a8

# markers of the boot ladder, in the order the kernel reaches them. sweet_early_mark
# strings come from patch 0010/0012; the rest are kprintf lines on the same path.
LADDER = [
    (None, r"SWEET EARLY 1: arm_init entered"),
    (None, r"SWEET EARLY 2: PE_init_platform done"),
    (None, r"SWEET EARLY 3: ml_parse_cpu_topology done"),
    (None, r"SWEET EARLY 4: cpu_bootstrap done"),
    (None, r"SWEET EARLY 5: kernel_startup_bootstrap done"),
    (None, r"SWEET EARLY 6: cpu_init done"),
    (None, r"SWEET EARLY 7: entering arm_vm_init"),
    (None, r"SWEET EARLY 8: leaving bootstrap TTBR0"),
    (None, r"pmap_bootstrap done"),
    (None, r"SWEET EARLY 15: arm_vm_init returned"),
    (None, r"SWEET EARLY 16: calling serial_init"),
    (None, r"SWEET EARLY 20: kprintf startup complete"),
    (None, r"machine_init|machine_conf"),
    (None, r"dlil_init"),
    (None, r"Waiting on <dict"),
    (None, r"load_init_program|mounted iOSRoot"),
]
PANIC = re.compile(r"PANIC|panic\(|panic:|Assertion failed|no PTE for", re.I)
target = re.compile(until) if until else None

# mmap both files: a RAMDisk payload is gigabytes and the bytearray copies of it
# do not fit in the tool cgroup
_pf = open(f"{out}/payload.bin", "rb")
payload = mmap.mmap(_pf.fileno(), 0, access=mmap.ACCESS_READ)
magic, ver, nsegs = struct.unpack_from("<8sII", payload, 0)
assert magic == b"SWEETXNU", "not a payload"
virt_base, entry_va, adt_off, adt_size, kernel_end, phys_base, mem_size = \
    struct.unpack_from("<7Q", payload, 0x10)
delta = phys_base - virt_base
adt_pa = kernel_end + delta
ba_pa = (adt_pa + adt_size + PAGE - 1) & ~(PAGE - 1)
top = ba_pa + PAGE

_rf = open(f"{out}/ram.bin", "w+b")
_rf.truncate(top - phys_base)
img = mmap.mmap(_rf.fileno(), top - phys_base)
CHUNK = 1 << 25
for i in range(nsegs):
    vmaddr, vmsize, foff, fsize = struct.unpack_from("<4Q", payload, SEG_TABLE + 32 * i)
    o = vmaddr + delta - phys_base
    # in chunks: a slice of an mmap is a bytes copy, and one 3 GiB segment copy
    # does not fit the tool cgroup
    for a in range(0, fsize, CHUNK):
        n = min(fsize - a, CHUNK)
        img[o + a:o + a + n] = payload[foff + a:foff + a + n]
img[adt_pa - phys_base:adt_pa - phys_base + adt_size] = payload[adt_off:adt_off + adt_size]
ba = struct.pack("<HH4x4Q6QI4xQI", 2, 2, virt_base, phys_base, mem_size, top,
                 FB, 1, STRIDE, W, H, 32, 0, adt_pa - delta, adt_size)
ba += payload[CMDLINE_OFF:CMDLINE_OFF + 608] + b"\0\0\0\0" + struct.pack("<QQ", 0, mem_size)
assert top < FB, f"payload ends {top:#x} above the framebuffer {FB:#x}"
assert len(ba) == 736, f"boot_args {len(ba)} != 736"
img[ba_pa - phys_base:ba_pa - phys_base + len(ba)] = ba
img.flush()
img.close()
_rf.close()

# QEMU's generic loader device read is capped just under 2 GiB (it fails a 3 GiB
# file with rc=0x7ffff000), so a RAMDisk root is loaded in parts.
LOAD_CHUNK = 0x60000000
loaders = []
if top - phys_base <= LOAD_CHUNK:
    loaders.append((f"{out}/ram.bin", phys_base))
else:
    _sf = open(f"{out}/ram.bin", "rb")
    _src = mmap.mmap(_sf.fileno(), 0, access=mmap.ACCESS_READ)
    for n, a in enumerate(range(0, top - phys_base, LOAD_CHUNK)):
        part = f"{out}/ram.bin.{n}"
        with open(part, "wb") as pf:
            for c in range(a, min(a + LOAD_CHUNK, top - phys_base), CHUNK):
                pf.write(_src[c:min(c + CHUNK, a + LOAD_CHUNK)])
        loaders.append((part, phys_base + a))
    _src.close()
    _sf.close()
# x0 = boot_args, then branch to the entry (pair of literal loads into x0/x1)
open(f"{out}/stub.bin", "wb").write(
    struct.pack("<4I2Q", 0x58000080, 0x580000a1, 0xd61f0020, 0xd503201f, ba_pa, entry_va + delta))

pram = None
sys.path.insert(0, REPO + "/avicii/tools")
import adt                                    # noqa: E402
root, _ = adt.parse(open(f"{out}/avicii-qemu.adt", "rb").read())
pram = struct.unpack_from("<Q", next(c for c in root.children if c.name == "pram").prop("reg"))[0]

mon = f"{out}/mon.sock"
# DISPLAY=none is the headless loop (the screen comes back as fb.raw +
# screen.txt). DISPLAY=gtk opens a window on $DISPLAY, DISPLAY=vnc:N serves the
# same screen over VNC - both keep the decoded artifacts.
disp = os.environ.get("DISPLAY", "").strip()
if not disp or disp == "none":
    disp_args = ["-nographic"]
elif disp.startswith("vnc:"):
    disp_args = ["-display", f"vnc:{disp[4:]}"]
else:
    # ":0" and friends are X displays, not QEMU display names - QEMU's own name
    # for a host window is gtk, and it reads $DISPLAY itself.
    disp_args = ["-display", "gtk" if disp.startswith(":") else disp]
cmd = ["qemu-system-aarch64", "-M", "virt,gic-version=3", "-cpu", "cortex-a76",
       "-smp", str(smp), "-m", MEM, *disp_args,
       # guest RAM in a shared memfd: file-backed, so a 3 GiB RAMDisk payload
       # becomes reclaimable page cache instead of anonymous RSS (the tool
       # session runs under a few-GiB memory cgroup that OOM-kills anon RAM)
       "-object", f"memory-backend-memfd,id=mem,size={MEM},share=on",
       "-numa", "node,memdev=mem",
       "-serial", f"file:{out}/serial.txt", "-qmp", f"unix:{mon},server,nowait",
       "-d", "int,guest_errors", "-D", f"{out}/qemu.log", "-no-reboot",
       *[x for part, addr in loaders
         for x in ("-device", f"loader,file={part},addr={addr:#x},force-raw=on")],
       "-device", f"loader,file={out}/stub.bin,addr={STUB_PA:#x},force-raw=on",
       "-device", f"loader,addr={STUB_PA:#x},cpu-num=0"]
if gdb:
    cmd += ["-S", "-gdb", f"tcp::{gdbport}"]
    # lldb 18 crashes in SymbolFileCTF on the kernel's __ctf section: hand out a
    # copy with that section renamed (file only, not the payload).
    kbuf = bytearray(open(open(f"{out}/kernel.path").read().strip(), "rb").read())
    ncmds = struct.unpack_from("<I", kbuf, 16)[0]
    off = 32
    for _ in range(ncmds):
        cmd_, size = struct.unpack_from("<II", kbuf, off)
        if cmd_ == 0x19:
            so = off + 72
            for i in range(struct.unpack_from("<I", kbuf, off + 64)[0]):
                if kbuf[so + i * 80:so + i * 80 + 16].lower().startswith(b"__ctf"):
                    kbuf[so + i * 80:so + i * 80 + 16] = b"__xtf" + b"\0" * 11
        off += size
    open(f"{out}/kernel.noctf", "wb").write(bytes(kbuf))
    # The stub cannot write a kernel VA while the guest is halted at the stub
    # (MMU off), so symbol breakpoints do not stick yet. Print the physical
    # address of the instruction after "msr sctlr_el1" - break there, and the
    # guest is past the MMU. Recovers later if found: the PA is best effort.
    mmu_pa = None
    for i in range(nsegs):                             # the segment holding the entry
        vmaddr, vmsize, foff, fsize = struct.unpack_from("<4Q", payload, SEG_TABLE + 32 * i)
        if vmaddr <= entry_va < vmaddr + fsize:
            hits, last = [], None
            for k in range(0, min(0x2400, fsize), 4):
                word = struct.unpack_from("<I", payload, foff + entry_va - vmaddr + k)[0]
                if word & 0xffffffe0 == 0xd5181000:    # msr SCTLR_EL1, xN
                    last = k
                    if word == 0xd5181000:             # ... x0 = the real enable
                        hits.append(k)
            # the EL2 trampoline writes SCTLR from x1 first; prefer x0, else the last
            k = hits[0] if hits else last
            if k is not None:
                mmu_pa = entry_va + delta + k + 4
            break
open(f"{out}/qemu.cmd", "w").write(" ".join(cmd) + "\n")
print(f"guest: phys_base={phys_base:#x} entry={entry_va + delta:#x} boot_args={ba_pa:#x} "
      f"adt={adt_pa:#x} pram={pram:#x} smp={smp}")
if gdb:
    print(f"gdb: kernel.noctf is the symbol file; breakpoints by physical address "
          f"(entry={entry_va + delta:#x}" + (f", mmu-on={mmu_pa:#x}" if mmu_pa else "") +
          f"); stub on :{gdbport}; see the header of this script")

font_seg = None
for i in range(nsegs):
    vmaddr, vmsize, foff, fsize = struct.unpack_from("<4Q", payload, SEG_TABLE + 32 * i)
    if vmaddr <= fontva < vmaddr + fsize:
        font_seg = payload[foff + fontva - vmaddr:foff + fontva - vmaddr + 4096]
if font_seg is None:
    sys.exit("error: _iso_font is not inside the payload")
cmap = {0: " "}          # blank cell; 0x00 must not claim it before 0x20 does
for ch in range(32, 256):
    bits = 0
    for gy in range(16):
        bits = (bits << 8) | font_seg[ch * 16 + gy]
    cmap.setdefault(bits, chr(ch) if ch < 127 else "?")


def qmp(f, name, **kw):
    f.write(json.dumps({"execute": name, "arguments": kw} if kw else {"execute": name}) + "\n")
    f.flush()
    return json.loads(f.readline())


def dump_msgbuf(f):
    """Kernel message buffer -> msgbuf.txt, console flags -> console_flags.json.

    Every printf lands here even when the console is paused or graphical (the
    high-framebuffer layout of a --ramdisk run shows only the progress bar and
    serial gets nothing but the panic).

    Two rings come out of the same QMP connection: this one (msgbuf.txt, the
    kernel's printf ring) and patch 0047's _sweet_log_ring (sweetlog.raw exact
    bytes / sweetlog.txt text), which holds every byte _cnputs() was handed -
    including the /dev/console writes of dyld for pid 1 that no other channel
    on this host shows.  console_flags.json records what each read did.

    Statics (msgbufp, the console flags) live in the kernel image and map
    linearly from gVirtBase.  The ring does not always: the default 128 KiB
    ring is the kernel's static msgbufc[] in .data, but `msgbuf=<n>` makes the
    kernel allocate a new one, which lands in kernel_map - VAs around
    0xfffffe20xxxxxxxx, a page-granular mapping ~128 GiB above the linear
    window.  `va - gVirtBase + gPhysBase` then points outside guest RAM and
    reads zeros (run 20261114-120631: msgbuf=1048576 honoured, 373 788 B
    logged, msgbuf.txt 0 B).  So the ring is read through the kernel's own
    page tables: common_start does `msr TTBR1_EL1, [cpu_ttep]`, i.e. that
    global holds the level-0 table's physical address, and every 16 KiB page
    of the ring VA is translated and read on its own (a 1 MiB kernel
    allocation is not one physical run, so one pmemsave would not do).

    A 0 B dump while `msgbuf=` is on the command line is a harness failure,
    not an empty log: it is reported on stderr and the run exits 4.
    """
    flags = {}
    try:
        def sva2pa(va):
            return va - virt_base + phys_base
        for sym, n in (("disableConsoleOutput", 4), ("serial_console_enabled", 1),
                       ("gc_graphics_boot", 4), ("vc_progress_enable", 4),
                       ("gPhysBase", 8), ("gVirtBase", 8), ("msgbufp", 8)):
            if sym in KSYMS:
                flags[sym] = int.from_bytes(grab(f, f"k_{sym}.bin", sva2pa(KSYMS[sym]), n), "little")

        def k2p(va):
            if virt_base <= va < kernel_end:
                return sva2pa(va)
            return va - flags["gVirtBase"] + flags["gPhysBase"]

        # --- the ring, through the kernel's own TTBR1_EL1 --------------------
        # sweet runs a 16 KiB granule (see docs/STATUS.md machine config); the
        # 4 KiB walk is only a second try in case that ever changes.
        LEVELS = {"16k": (((47, 0x1), (36, 0x7ff), (25, 0x7ff), (14, 0x7ff)), 14),
                  "4k": (((39, 0x1ff), (30, 0x1ff), (21, 0x1ff), (12, 0x1ff)), 12)}
        tt_cache, tt_root = {}, None
        if "cpu_ttep" in KSYMS:
            ttb = int.from_bytes(grab(f, "k_cpu_ttep.bin", sva2pa(KSYMS["cpu_ttep"]), 8), "little")
            # cpu_ttep is the L0 table arm_vm_init installs; a boot that shows it
            # empty can be walked with the live value instead (-gdb run:
            # `lldb -o 'register read ttbr1_el1'`), MSGBUF_TTBR1=0x...
            over = os.environ.get("MSGBUF_TTBR1", "").strip()
            if over:
                flags["msgbuf_ttep_override"] = over
                ttb = int(over, 16)
            flags["msgbuf_ttep"] = ttb
            tt_root = ttb & 0x0000ffffffffffff   # drop CnP/ASID

        def tt_page(pa):
            if pa not in tt_cache:
                tt_cache[pa] = grab(f, "k_tt.bin", pa, 0x4000)
            return tt_cache[pa]

        def xlate(va, levels, page_shift):
            """VA -> PA through the current TTBR1 tables; None if unmapped."""
            amask = 0x0000ffffffffffff
            tmask = amask & ~((1 << page_shift) - 1)   # a table is one granule: 2048x8 B (16k) or 512x8 B (4k)
            pa = tt_root & tmask
            for i, (shift, mask) in enumerate(levels):
                e = ((va >> shift) & mask) * 8
                tbl = tt_page(pa)
                if e + 8 > len(tbl):
                    return None
                d = int.from_bytes(tbl[e:e + 8], "little")
                if not d & 1:                     # invalid
                    return None
                if i and d & 3 == 1:              # block descriptor (L1/L2)
                    bmask = amask & ~((1 << shift) - 1)
                    return (d & bmask) | (va & ((1 << shift) - 1))
                pa = d & tmask                    # next-level table
            return pa | (va & ((1 << page_shift) - 1))

        def ring_bytes(bufc, size):
            """size bytes at kernel VA bufc, page by page -> (bytes, how)."""
            if tt_root is None:
                return None, "no cpu_ttep"
            for name, (levels, pshift) in LEVELS.items():
                step = 1 << pshift
                base = bufc & ~(step - 1)         # page-align: translate, then cut
                off0 = bufc - base
                npages = (off0 + size + step - 1) // step
                pas = []
                for p in range(npages):
                    pa = xlate(base + p * step, levels, pshift)
                    if pa is None:
                        break
                    pas.append(pa)
                if len(pas) != npages:
                    continue
                buf, i, runs = bytearray(), 0, 0
                while i < len(pas):
                    j = i
                    while j + 1 < len(pas) and pas[j + 1] == pas[j] + step:
                        j += 1
                    buf += grab(f, "k_ring.bin", pas[i], (j - i + 1) * step)
                    runs += 1
                    i = j + 1
                return bytes(buf[off0:off0 + size]), \
                    f"ttbr1-walk/{name}/{len(pas)}p/{runs}run"
            return None, "unmapped"

        def trace(va, levels, pshift):
            """The walk's working: (level, table PA, index, descriptor) per level."""
            amask = 0x0000ffffffffffff
            tmask = amask & ~((1 << pshift) - 1)
            pa, out = tt_root & tmask, []
            for i, (shift, mask) in enumerate(levels):
                idx = (va >> shift) & mask
                tbl = tt_page(pa)
                d = int.from_bytes(tbl[idx * 8:idx * 8 + 8], "little")
                out.append(f"L{i}:tbl={pa:#x},i={idx},d={d:#x}")
                if not d & 1 or (i and d & 3 == 1):
                    break
                pa = d & tmask
            return "; ".join(out)

        def scan_ring(size, bufx):
            """Last resort: find the ring in guest RAM, 16 KiB page by page.

            The ring's VA range is contiguous but its physical pages are not
            (a 1 MiB kmem_alloc is a run of single pages - run 20261114-125638
            read the head contiguously and got 34 KB of log followed by other
            pages' contents), so the head is found by its first record and each
            following page by the text that must continue it: a page's first 48
            bytes are the last 48 bytes of the page before it.  One pass over
            RAM indexes every 16 KiB page that starts with printable text.
            """
            step = 0x4000
            head = re.compile(rb"\[ *\d+\.\d{6}\]:")
            tsre = re.compile(rb"\[ *(\d+\.\d{6})\]:")
            lo, hi = (kernel_end + delta) & ~(step - 1), phys_base + mem_size
            chunk, pages, cands = 0x8000000, [], []
            pa = lo
            while pa < hi:
                n = min(chunk, hi - pa)
                blob = grab(f, "k_scan.bin", pa, n)
                for off in range(0, len(blob) - 64, step):
                    if not 0x20 <= blob[off] <= 0x7e:
                        continue                # a log page starts with text
                    m = tsre.search(blob[off:off + 0x1000])
                    if m is None:
                        continue                # no kprintf record: not a log page
                    pages.append((float(m.group(1)), pa + off))
                    if len(cands) < 8 and m.start() == 0:
                        cands.append(pa + off)  # a page that starts a record
                if n <= step:
                    break
                pa += n - step
            pages.sort()
            for start in cands:
                # everything from the write pointer on is zeros (never written),
                # so only the pages covering [0, bufx) have to be chained
                need = min(size, bufx) or size
                out, cur, seen, ok = bytearray(), start, set(), True
                while len(out) < need:
                    if cur in seen:
                        ok = False
                        break
                    seen.add(cur)
                    page = grab(f, "k_page.bin", cur, step)
                    if not any(32 <= b < 127 for b in page[:64]):
                        ok = False
                        break
                    out += page
                    if len(out) >= need:
                        break
                    ts = [float(x) for x in tsre.findall(page)]
                    if not ts:
                        ok = False
                        break
                    # the ring's next page is the one whose first record comes
                    # right after this page's last one; other logs in RAM (the
                    # 128 KiB static ring) sit far away in time
                    nxt = [(t, p) for t, p in pages
                           if p not in seen and ts[-1] <= t <= ts[-1] + 5.0]
                    if not nxt:
                        ok = False
                        break
                    cur = min(nxt)[1]
                if not ok:
                    continue
                body = (bytes(out[:need]) + b"\0" * (size - need))[:size]
                text = body[:min(bufx, 0x10000)]
                printable = sum(1 for b in text if b in (9, 10, 13) or 32 <= b < 127)
                if not text or printable / len(text) < 0.95:
                    continue                    # not a log: kernel data can start with '['
                if len(head.findall(body[:min(bufx, 0x40000)])) < 4:
                    continue
                return start, body
            return None

        hdr = grab(f, "k_msgbuf_hdr.bin", k2p(flags["msgbufp"]), 24)
        magic, size, bufx, _bufr, bufc = struct.unpack("<iiiiQ", hdr)
        flags.update(msgbuf_magic=magic & 0xffffffff, msgbuf_size=size, msgbuf_bufx=bufx,
                     msgbuf_bufc=bufc)
        ring, how = ring_bytes(bufc, size)
        if ring is None or not any(ring):
            # keep the walk's working: a failed translate has to be debuggable
            if tt_root is not None:
                flags["tt_trace"] = (trace(bufc, *LEVELS["16k"]) + " | "
                                     + trace(bufc, *LEVELS["4k"]))
            hit = scan_ring(size, bufx)
            if hit is not None:                 # already stitched page by page
                ring, how = hit[1], f"ram-scan/{hit[0]:#x}"
                flags["msgbuf_ram_scan_pa"] = hit[0]
        if ring is None or not any(ring):
            lin = grab(f, "k_msgbuf_ring.bin", k2p(bufc), size)   # the old guess
            flags["linear_ok"] = bool(any(lin))
            if any(lin):
                ring, how = lin, "linear"
            else:
                flags["msgbuf_ring_pa"] = k2p(bufc)
        if ring is not None and any(ring):
            if how.startswith("ttbr1-walk"):
                flags["msgbuf_ring_pa"] = xlate(bufc, *LEVELS[how.split("/")[1]])
            flags["msgbuf_ring_via"] = how
            open(f"{out}/msgbuf.txt", "wb").write((ring[bufx:] + ring[:bufx]).replace(b"\0", b""))
        else:
            flags["msgbuf_ring_via"] = how

        # --- patch 0047: _sweet_log_ring (what dyld said) --------------------
        # dyld4::console writes pid 1's reason to /dev/console -> console_write
        # -> _cnputs, which returns at once while disableConsoleOutput is set:
        # no serial, no screen, no msgbuf.  0047 appends those bytes to a 4 MiB
        # static ring first, so the only record of why dyld rejected the cache
        # is in guest RAM.  Ring offset of byte n is n % size, and _sweet_log_total
        # counts every byte ever appended, so a wrapped ring starts at
        # total % size.  Reading it is the same problem as a ring VA: try the
        # linear map (it is a .bss static like the console flags) and fall back
        # to the kernel's own page tables.
        sl_size = 4 << 20                     # SWEET_LOG_SIZE in patches/0047
        if "sweet_log_ring" not in KSYMS or "sweet_log_total" not in KSYMS:
            flags["sweetlog_via"] = "no symbol"
        else:
            ring_va, total_va = KSYMS["sweet_log_ring"], KSYMS["sweet_log_total"]
            flags["sweetlog_ring_sym"], flags["sweetlog_total_sym"] = ring_va, total_va
            flags["sweetlog_ring_pa"] = ring_va - flags["gVirtBase"] + flags["gPhysBase"]
            total = int.from_bytes(grab(f, "k_sweetlog_total.bin", k2p(total_va), 8), "little")
            flags["sweetlog_total"] = total
            flags["sweetlog_ring_size"] = sl_size
            if total:                          # 0 = nothing ever reached _cnputs
                want = min(total, sl_size)
                blob = grab(f, "k_sweetlog.bin", ring_va - flags["gVirtBase"] + flags["gPhysBase"], want)
                how = "linear"
                if not any(blob):              # not where the linear map says
                    blob, how = ring_bytes(ring_va, want)
                    if blob is not None and any(blob):
                        flags["sweetlog_ring_pa"] = xlate(ring_va, *LEVELS[how.split("/")[1]])
                    else:
                        if tt_root is not None:
                            flags["sweetlog_tt_trace"] = trace(ring_va, *LEVELS["16k"])
                        blob = None
                if blob is not None:
                    body = blob[:want]
                    if total > sl_size:        # ring wrapped: reorder from the oldest byte
                        off = total % sl_size
                        body = body[off:] + body[:off]
                    flags["sweetlog_via"] = how
                    flags["sweetlog_bytes"] = len(body)
                    flags["sweetlog_wrapped"] = total > sl_size
                    txt = body.replace(b"\0", b"")       # text form: no NUL padding
                    sl_lines = txt.split(b"\n")
                    flags["sweetlog_not_loaded"] = sum(1 for l in sl_lines if b"not loaded:" in l)
                    flags["sweetlog_dyld_reject"] = sum(
                        1 for l in sl_lines if b"dyld cache" in l and b"not loaded:" in l)
                    flags["sweetlog_head"] = txt.split(b"\n")[0][:120].decode("latin-1")
                    flags["sweetlog_printable"] = round(
                        sum(1 for b in txt[:0x4000] if b in (9, 10, 13) or 32 <= b < 127)
                        / max(1, len(txt[:0x4000])), 3)
                    open(f"{out}/sweetlog.raw", "wb").write(body)   # exact bytes
                    open(f"{out}/sweetlog.txt", "wb").write(txt)
                else:
                    flags["sweetlog_via"] = how + " (total %d B, unreadable)" % total
            else:
                flags["sweetlog_via"] = "total 0"
    except Exception as e:                     # never lose the run over the log
        flags["error"] = repr(e)
    for tmp in os.listdir(out):
        if tmp.startswith("k_") and tmp.endswith(".bin"):
            os.unlink(f"{out}/{tmp}")
    n = os.path.getsize(f"{out}/msgbuf.txt") if os.path.exists(f"{out}/msgbuf.txt") else 0
    sl = os.path.getsize(f"{out}/sweetlog.txt") if os.path.exists(f"{out}/sweetlog.txt") else 0
    cmd_line = open(f"{out}/cmdline.txt").read() if os.path.exists(f"{out}/cmdline.txt") else ""
    failed = n == 0 and "msgbuf=" in cmd_line
    if failed:
        flags["msgbuf_dump_failed"] = True
        print(f"error: msgbuf= is on the command line but msgbuf.txt came out 0 B - the "
              f"ring was not readable (size {flags.get('msgbuf_size')}, bufx "
              f"{flags.get('msgbuf_bufx')}, bufc {flags.get('msgbuf_bufc')}, via "
              f"{flags.get('msgbuf_ring_via')}, error {flags.get('error')}); "
              f"see {out}/console_flags.json", file=sys.stderr)
    # the ring holds bytes but none came out: a harness failure, not a silent guest
    if flags.get("sweetlog_total") and not sl:
        flags["sweetlog_dump_failed"] = True
        print(f"error: _sweet_log_total says {flags['sweetlog_total']} B but sweetlog.txt "
              f"came out 0 B (ring {flags.get('sweetlog_ring_sym')}, pa "
              f"{flags.get('sweetlog_ring_pa')}, via {flags.get('sweetlog_via')}, trace "
              f"{flags.get('sweetlog_tt_trace')}); see {out}/console_flags.json", file=sys.stderr)
    open(f"{out}/console_flags.json", "w").write(json.dumps(
        {k: (hex(v) if isinstance(v, int) and v > 0xffff else v) for k, v in flags.items()},
        indent=1) + "\n")
    return n, failed, sl


def grab(f, name, pa, size):
    path = f"{out}/{name}"
    qmp(f, "pmemsave", val=pa, size=size, filename=path)
    return open(path, "rb").read()


def decode(raw):
    """Screen bytes -> text lines, via the kernel's own font.

    FB fg is 0xffffffff and bg 0xff000000; on the little-endian dump the low
    byte alone tells them apart (0xff vs 0x00), so a row of pixel flags is one
    strided slice - the per-pixel struct unpack is too slow for the poll loop.
    """
    lines = []
    for r in range((H - 32) // 32):
        rows = [raw[(r * 32 + gy * 2) * STRIDE:(r * 32 + gy * 2 + 1) * STRIDE:4]
                for gy in range(16)]
        if len(rows[0]) < W:
            break
        row = []
        for c in range(W // 16):
            bits = 0
            for gy in range(16):
                byte = 0
                line = rows[gy]
                for gx in range(8):
                    if line[c * 16 + gx * 2] == 0xff:
                        byte |= 1 << gx
                bits = (bits << 8) | byte
            row.append(cmap.get(bits, "\u00b7"))
        lines.append("".join(row).rstrip())
    return lines


result = {"status": "boot", "kernel": open(f"{out}/kernel.path").read().strip(),
          "cmdline": open(f"{out}/cmdline.txt").read().strip(), "smp": smp, "secs": secs}
if os.path.exists(mon):
    os.unlink(mon)
t0 = time.monotonic()
p = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
to_point = None
deepest = -1
try:
    if gdb:
        print(f"halted at entry; gdb stub on :{gdbport}. Ctrl-C here when done.")
        p.wait()
        result["status"] = "gdb"
    else:
        f = None
        deadline = t0 + secs
        while True:
            time.sleep(0.2)
            if f is None:
                try:
                    s = socket.socket(socket.AF_UNIX)
                    s.connect(mon)
                    f = s.makefile("rw")
                    f.readline()
                    qmp(f, "qmp_capabilities")
                except OSError:
                    f = None
            if p.poll() is not None:
                result["status"] = "qemu_exited"
                break
            if f is not None:
                # the whole screen: it is 10 MiB and fbcon wraps at the bottom
                text = "\n".join(decode(grab(f, "poll.raw", FB, STRIDE * H)))[:200000]
                for i, (_, pat) in enumerate(LADDER):
                    if re.search(pat, text) and i > deepest:
                        deepest = i
                        if to_point is None:
                            to_point = time.monotonic() - t0
                if PANIC.search(text):
                    result["panic_at"] = round(time.monotonic() - t0, 2)
                    break
                if target and target.search(text):
                    if to_point is None:
                        to_point = time.monotonic() - t0
                    break
            if time.monotonic() >= deadline:
                result["status"] = "timeout_printing"
                break
        result["seconds_to_point"] = None if to_point is None else round(to_point, 2)
        if f is None:                          # guest exited: reconnect to dump
            s = socket.socket(socket.AF_UNIX)
            s.connect(mon)
            f = s.makefile("rw")
            f.readline()
            qmp(f, "qmp_capabilities")
        raw = grab(f, "fb.raw", FB, STRIDE * H)
        if os.path.exists(f"{out}/poll.raw"):
            os.unlink(f"{out}/poll.raw")
        lines = decode(raw)
        open(f"{out}/screen.txt", "w").write("\n".join(lines) + "\n")
        if pram is not None:
            buf = grab(f, "pram.bin", pram, 0x100000)
            text = buf[0x28:].split(b"\0")[0]
            open(f"{out}/pram.txt", "wb").write(text) if text else None
            result["pram_bytes"] = len(text)
        regs = qmp(f, "human-monitor-command", **{"command-line": "info registers"})["return"]
        open(f"{out}/regs.txt", "w").write(regs if isinstance(regs, str) else json.dumps(regs))
        msgbuf_bytes, msgbuf_failed, sweetlog_bytes = dump_msgbuf(f)
        result["msgbuf_bytes"] = msgbuf_bytes
        result["sweetlog_bytes"] = sweetlog_bytes
        if msgbuf_failed:
            result["msgbuf_dump_failed"] = True
        qmp(f, "quit")
finally:
    if p.poll() is None:
        p.kill()
    p.wait()

text = open(f"{out}/screen.txt").read() if os.path.exists(f"{out}/screen.txt") else ""
for i, (_, pat) in enumerate(LADDER):          # final screen is authoritative
    if re.search(pat, text) and i > deepest:
        deepest = i
if PANIC.search(text):
    result["status"] = "panic"
    m = [l for l in text.splitlines() if PANIC.search(l)]
    result["panic_line"] = m[0].strip() if m else ""
result["deepest_marker"] = LADDER[deepest][1] if deepest >= 0 else None
result["qemu_exceptions"] = open(f"{out}/qemu.log").read().count("Taking exception")
open(f"{out}/result.json", "w").write(json.dumps(result, indent=2) + "\n")

print(f"\n--- screen (non-blank lines) ---")
shown = [f"{i:02d}|{l}" for i, l in enumerate(text.splitlines()) if l.strip(" .\u00b7")]
print("\n".join(shown[-40:]) or "(blank)")
print(f"--- end screen ---")
print(f"status={result['status']} deepest={result['deepest_marker']} "
      f"seconds_to_point={result['seconds_to_point']} "
      f"panic_at={result.get('panic_at')} exceptions={result['qemu_exceptions']}")
print(f"artifacts: {out}")
try:
    _fl = json.load(open(f"{out}/console_flags.json"))
except (OSError, ValueError):
    _fl = {}
print(f"sweetlog: {result.get('sweetlog_bytes', 0)} B of {_fl.get('sweetlog_total', 0)} "
      f"appended, via {_fl.get('sweetlog_via')}, dyld rejected the cache "
      f"{_fl.get('sweetlog_dyld_reject', 0)}x -> {out}/sweetlog.txt")
if not keep:
    for tmp in ("ram.bin",):
        try:
            os.unlink(f"{out}/{tmp}")
        except OSError:
            pass
payload.close()          # still needed above for the font segment
_pf.close()
code = {"panic": 2, "timeout_printing": 3}.get(result["status"], 0)
if result.get("msgbuf_dump_failed") and code != 2:   # panic stays the headline
    code = 4
if _fl.get("sweetlog_dump_failed") and code == 0:    # ring held bytes, dump did not
    code = 5
sys.exit(code)
PY
rc=$?

# --- 4. fb.raw -> screen.png / screen-half.png (stdlib zlib, no PIL/numpy) ----
if [ -r "$OUTDIR/fb.raw" ]; then
	python3 - "$OUTDIR" <<'PY' || echo "warning: PNG render failed" >&2
import struct, sys, zlib

out = sys.argv[1]
W, H, STRIDE = 1080, 2400, 4320           # a8r8g8b8 LE: bytes B,G,R,A
raw = open(f"{out}/fb.raw", "rb").read()


def png(path, w, h, rows):
	def chunk(tag, data):
		return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))
	body = bytearray()
	for row in rows:
		body += b"\0" + row                   # filter type 0
	with open(path, "wb") as f:
		f.write(b"\x89PNG\r\n\x1a\n")
		f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
		f.write(chunk(b"IDAT", zlib.compress(bytes(body), 6)))
		f.write(chunk(b"IEND", b""))


def rgb(line, step):
	px = line[0::4 * step], line[1::4 * step], line[2::4 * step]   # B, G, R
	n = len(px[0])
	o = bytearray(3 * n)
	o[0::3], o[1::3], o[2::3] = px[2], px[1], px[0]
	return o


h = min(H, len(raw) // STRIDE)
if h == 0:
	sys.exit("fb.raw is empty")
full = [rgb(raw[y * STRIDE:y * STRIDE + 4 * W], 1) for y in range(h)]
png(f"{out}/screen.png", W, h, full)
half = [rgb(raw[y * STRIDE:y * STRIDE + 4 * W], 2) for y in range(0, h, 2)]
png(f"{out}/screen-half.png", W // 2, len(half), half)
print(f"screen: {out}/screen.png ({W}x{h}), {out}/screen-half.png ({W // 2}x{len(half)})")
PY
fi

if [ "$VIEW" = 1 ]; then
	if [ ! -r "$OUTDIR/screen.png" ]; then
		echo "warning: --view: no screen.png to open" >&2
	elif command -v xdg-open >/dev/null; then
		xdg-open "$OUTDIR/screen.png" >/dev/null 2>&1 &
	elif command -v gwenview >/dev/null; then
		gwenview "$OUTDIR/screen.png" >/dev/null 2>&1 &
	elif command -v eog >/dev/null; then
		eog "$OUTDIR/screen.png" >/dev/null 2>&1 &
	else
		echo "warning: --view: no xdg-open, gwenview or eog" >&2
	fi
fi

case $rc in
0) echo "ok: reached the target point, no panic (logs/qemu, result.json)" ;;
2) echo "panic decoded - see screen.txt / result.json" ;;
3) echo "still printing when --secs ran out - raise --secs to see further" ;;
4) echo "error: msgbuf= was asked for but the kernel ring could not be read (0 B dump)" ;;
5) echo "error: _sweet_log_total is non-zero but sweetlog.txt came out 0 B (ring unreadable)" ;;
esac
exit $rc
