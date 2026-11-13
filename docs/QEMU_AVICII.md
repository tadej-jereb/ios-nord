# QEMU virt — host-side kernel loop

`tooling/60-qemu-boot.sh` boots a payload on QEMU's `virt` board instead of the
phone. One iteration is ~31 s of host time and needs no hands, no reset, no
recovery, no ring pull and no photograph; the console is decoded from the
framebuffer into text automatically. It is the loop for kernel work.

Nothing here touches the phone. `docs/STATUS.md` and the p1-p6 log in
`docs/IMAGE_PROVENANCE.md` stay the record of what runs on hardware.

## 0. What a result here means

A QEMU boot proves kernel *logic*: the same payload layout, the same ADT
reader, the same Mach init, pmap, kprintf, console, AMFI stand-in, HFS and
`mountroot` code run as on the phone. It proves nothing about hardware: there is
no UFS, no ICE/SEP, no PMIC, no panel, no PSCI firmware and one CPU. Section 5
lists every divergence. If a rung involves a device, QEMU can only exercise the
code path *around* the device.

## 1. Usage

    tooling/60-qemu-boot.sh                              # default cmdline, 45 s
    tooling/60-qemu-boot.sh --secs 90 --keep             # longer window, keep ram.bin
    tooling/60-qemu-boot.sh --until 'Waiting on <dict'   # stop at the ladder point
    tooling/60-qemu-boot.sh --ramdisk build/rd-root.skeleton.img \
        --cmdline 'rd=md0 -v debug=0x144 cpus=1 sweetsmp=0 cpu-factor=10'

| option | meaning |
|---|---|
| `--kernel PATH` | Mach-O to boot, default `avicii/shim/out/kernel/kernel.development.sweet` |
| `--cmdline S` | boot-args, default `-v debug=0x144 cpus=1 sweetsmp=0 sweettouch=0 sweetkeys=0 sweetecon=1 cpu-factor=10` |
| `--secs N` | wall-clock ceiling, default 45 (a full run to the mountroot wall is 31 s) |
| `--until RE` | stop as soon as the screen matches RE |
| `--ramdisk IMG` | append IMG as a RAMDisk segment, `rd=md0` it (`mkpayload.py --ramdisk`) |
| `--smp N` | CPUs for QEMU; see section 5, only `1` works today |
| `--gdb` | halt at the stub, `-gdb tcp::1234`, no timeout |
| `--uart0` | add an `/arm-io/uart0` ADT node (inert on today's kernel, section 4) |
| `--keep` | keep `ram.bin` |
| `--out DIR` | artifact directory, default `logs/qemu/<stamp>` |

Exit: `0` target point reached, `1` usage, `2` panic decoded, `3` still printing
when `--secs` ran out (normal for a run without `--until`), `4` host/setup
problem.

Artifacts in the output directory: `screen.txt` (the screen as text),
`result.json` (`status`, `deepest_marker`, `seconds_to_point`, `panic_at`,
`panic_line`, `qemu_exceptions`), `fb.raw` (the raw screen), `pram.txt`,
`regs.txt`, `qemu.log` (every exception with ESR/FAR/ELR), `qemu.cmd` (the exact
QEMU line), `avicii-qemu.adt`, `cmdline.txt`.

`cpu-factor=10` is not decoration: QEMU is far slower than the phone, and the
interrupt-masked watchdog (`osfmk/arm/machine_routines_common.c`) panics at
35 ms of IRQs-off otherwise — a real TCG timeout, hit at 6.3 s in one run of
four before the factor was added.

## 2. How it works

The shim's job on the phone (`avicii/shim/loader.c`) is reproduced by the host:

1. `mkadt_avicii.py --qemu` builds the ADT; the script then relocates it for the
   host (section 6).
2. `mkpayload.py` packs the kernel segments, the ADT and boot_args, exactly as
   for a phone image, with the same cmdline width limit.
3. The script lays the payload out at its physical base, builds `boot_args`
   (Revision/Version 2, video = the framebuffer, `deviceTreeP`, cmdline) and a
   6-instruction stub (`ldr x0, =boot_args; ldr x1, =entry; br x1`).
4. QEMU starts the CPU at the stub (`-device loader,addr=...,cpu-num=0`
   equivalent) with `-M virt,gic-version=3 -cpu cortex-a76 -m 4G`.
5. After `--secs`/`--until`/panic it stops the VM over QMP, dumps the
   framebuffer and the panic-log region and decodes the screen with the
   *kernel's own* `_iso_font` — no OCR, the glyph bitmaps come out of the image.

## 3. Debug session

QEMU is started with `-S -gdb tcp::1234` by `--gdb`, and the exact line is saved
as `qemu.cmd`. `--gdb` also writes `kernel.noctf` next to the artifacts: LLDB 18
crashes in its CTF reader on the kernel's `__ctf` section, so the section name
is renamed in that copy (file only, the payload is untouched).

    tooling/60-qemu-boot.sh --gdb &
    tooling/opt/llvm/bin/lldb -o 'gdb-remote 1234' \
        -o 'b *<entry PA>' -o c -o 'b *<mmu-on PA>' -o c <out>/kernel.noctf

The run prints both addresses itself:

    guest: phys_base=0x90000000 entry=0x9148c488 boot_args=0x924cc000 ...
    gdb:   kernel.noctf is the symbol file; breakpoints by physical address
           (entry=0x9148c488, mmu-on=0x9148e440)

`entry` is the payload entry; `mmu-on` is the instruction after the
`msr SCTLR_EL1` in `start_first_cpu` (found by scanning the entry's segment for
the encoding, best effort on a rebuild).

What is verified with QEMU 8.2.2 and the repo's lldb 18.1.8:

- the stub listens on :1234, lldb connects, registers, single-step and
  `memory read` of kernel VAs all work;
- a breakpoint at a **physical** address is hit (`entry`, `mmu-on`);
- `/usr/bin/gdb` cannot be used — it is x86-only and rejects the stub's
  aarch64 target description (`cuda-gdb` likewise).

What does **not** work, verified:

- a breakpoint on a kernel **VA/symbol** placed while the guest is halted in the
  stub never fires. The stub resolves addresses through the current MMU state
  (off), the insert write does not reach the RAM the guest will fetch from, and
  lldb does not retry. `--gdb` with `b panic` at the stub silently never stops.
- a `brk` written with `memory write` *does* execute (the run's `qemu.log` shows
  `Taking exception 7 [Breakpoint] ... ELR <addr>` at exactly that address) but
  QEMU does not report it to the debugger, so it is not a usable breakpoint
  either.

Consequence: today a session is useful in the identity-mapped window (stub →
`arm_vm_init`), where physical breakpoints and single-step work, and for
inspecting state after a stop. Symbol breakpoints later in the boot need a
`gdb-multiarch` (`apt install gdb-multiarch`, needs root) — that gdb implements
`Z0` properly and re-inserts on continue. Until then, use the panic line, the
screen and `qemu.log` (which names ESR/FAR/ELR for every fault) for later code.

## 4. Serial: what works

**There is no serial console today, and the reason is in the kernel, not in the
harness.** `serial_init()` (`pexpert/arm/pe_serial.c`) can register a PL011
driver, but that whole branch sits behind `#ifdef VMAPPLE_UART`, and
`pexpert/pexpert/arm64/SWEET.h` does not define it. `strings` on the kernel
finds no `uart0`, no `dockchannel-uart`, no `gpio`/`aux`: *no* serial driver is
compiled in. Patch 0003 only adds the framebuffer console, and 0003 is what
prints — so the framebuffer is the only channel, on the phone and here.

`--uart0` already emits the node the missing branch would look for
(`/arm-io/uart0`, `reg = <0x08000000 0x1000>` — soc-base relative, so
`0x01000000 + 0x08000000 = 0x09000000`, the virt PL011). Confirmed inert:
`serial.txt` stays 0 bytes with the node present. The one kernel-side change
that lights it up:

    # pexpert/pexpert/arm64/SWEET.h, with the other board defines
    #define VMAPPLE_UART

That is safe for the phone because registration is ADT-gated: without a
`uart0` node the driver is never registered, so the phone ADT needs no change.
The register writes are PL011 (`DR`, `FR`, `IBRD`/`FBRD`, `CR`) and QEMU's
pl011 ignores the divisor, so the 38400-baud constants from the vmapple port do
not matter for the host. Needs a CI kernel build (`docs/KERNEL_CI.md`).

Second-best channel, already working without a patch: the panic log. Every
`kprintf` byte goes to the buffer behind `/pram`, so `pram.txt` is *plain text*,
straight from RAM, no glyph decode. It is empty for panics that happen before
`machine_init()` calls `debug_log_init()` — i.e. the early ones — which is why
the fb decode matters and stays the primary channel.

## 5. Divergences — what does not transfer

| divergence | consequence |
|---|---|
| no UFS | no `ufsroot0`; `mountroot` waits forever at `Waiting on <dict ... Apple_HFS>` unless a ramdisk is passed |
| no ICE/SEP, no AKS hardware | AMFI/CS results are the built-in stand-ins; the `launchd` `CS_KILLED` panic (section 7) may be an artifact of that, not a phone bug |
| single CPU (`smp=1`) | `-smp 2` + `sweetsmp=1` stalls right after `serial_init`: the `--qemu` ADT has exactly one `cpu0` node, so the kernel waits for CPUs the ADT never names. `sweetsmp=1` is untested until an ADT with more cpu nodes exists |
| no PSCI firmware | the kernel's `hvc`/`smc` CPU_ON path is never exercised with `smp=1`; `sweetsmp=0` on the phone also skips it |
| GIC base, redistributor base, `CNTFRQ` (62.5 MHz), virtual-timer INTID 27 | virt numbers, not lito's (0x17a00000 / 0x17a60000 / 19.2 MHz / INTID 19). A GIC or timer port bug can pass here and fail on the phone |
| framebuffer at `0xa0000000` as plain RAM | on the phone it is the `cont_splash_region` carve-out above the kernel's dram; here it is below it and inside the extent, so a mapping the phone would refuse can succeed |
| no eMMC/USB/i2c/panel/PMIC | no `SWEET UFS`, no USB probe, no touch/keys, no backlight, no battery — every rung that reports through them is invisible |
| dram extent stretched to the framebuffer | the VM may allocate *over* the framebuffer on a long run (section 6); the phone's dram never contains it |
| `cpu-factor=10` | timings here are QEMU-TCG timings; the same code takes a different time on hardware, and anything timing-sensitive is only indicative |

## 6. The ADT is relocated for the host

`mkadt_avicii.py --qemu` alone is not bootable past `serial_init`, and both
failures were found by running it:

1. fallback dram `0x90000000+0xf000000` ends at `0x9f000000`, 1 MiB *below* the
   framebuffer at `0xa0000000`. `fbcon_probe()` → `ml_io_map_wcomb()` →
   `pmap_map_bd` has no PTE there:
   `SWEET EARLY PANIC: pmap_map_bd_with_options: no PTE for vaddr=0xfffffe000c000000 ... start=0xa0000000`.
2. the early `io_map()` bump allocator only has page tables for 32 MiB past
   `virtual_space_start`. Framebuffer (35 MiB) + 1 MiB panic log overflow it:
   the same panic with `start=0xa2400000`.

So the script rewrites the ADT it just generated: `dram-size` stretched so the
framebuffer is inside the physmap, `/sweet-fbcon` window cut to 16 MiB (the
screen is 10,368,000 B, so there is 60 % headroom), `/pram` moved above the
framebuffer. It prints what it did. `mkadt_avicii.py` is untouched; if the
generator ever fixes this itself, the patch step can go.

## 7. Where it gets to

Single CPU, default cmdline, mountroot wall — reproducible, 4 runs:

| run | to `Waiting on <dict ... Apple_HFS>` |
|---|---|
| 1 | 30.59 s |
| 2 | 30.45 s |
| 3 | 30.48 s |
| 4 | 30.40 s |

With `--ramdisk build/rd-root.skeleton.img` it passes the wall and reaches the
very end of kernel boot, then panics in userland bootstrap:

    SWEET EARLY PANIC: unexpected SIGKILL of launchd (CS_KILLED) with reason
    namespace 9 code 0xe description none

at 30.56 s and 30.75 s. That is *past* the phone's p6 rung (p6 stopped at
`load_init_program: opening of /sbin/launchd failed, errno 2` because that volume
was empty). Whether the `CS_KILLED` is a real defect or an AMFI-stand-in artifact
of the missing ICE is open; it is the same code path that works on the phone
once the volume has a userland.

Earlier rungs all pass: `arm_init`, `ml_parse_cpu_topology`, `cpu_bootstrap`,
`kernel_startup_bootstrap`, `cpu_init`, `arm_vm_init` (pmap, bootstrap TTBR0
teardown, physmap), `serial_init` + fbcon, platform expert, `AppleCLCD`, MAC
framework, `dlil_init` (including the thread-scheduling wait that one CPU broke
on the phone, see `docs/IMAGE_PROVENANCE.md` p3/p4), `mbinit`, interface attach,
`mountroot`.

## 8. Timing against the phone

| | to the same point |
|---|---|
| QEMU, mountroot wall (p4 equivalent) | 30.5 s |
| QEMU, launchd panic (past p6) | 30.6 s |
| phone, one p-rung cycle: `fastboot boot`, 60 s watch, power+volup reset, recovery, `su`/`dd` ring pull, photo | 125 s (measured cadence, `docs/IMAGE_PROVENANCE.md` 206→212, 22:18:01 → 22:20:06) |
| whole harness, wall clock | ~32 s (1.5 s ADT/payload/image, 30.5 s QEMU) |

**Speed-up: ~4x per iteration**, and the 4x is the smaller half of it. The
phone's 125 s is 60 s of *blind* waiting plus ~65 s of hands-on reset, recovery
and ring pull; the QEMU run ends itself at the point, decodes the console to
text, keeps the register state and every exception with ESR/ELR, and runs
unattended. Artifacts are comparable between runs (same kernel, same ADT, same
cmdline), which the phone cycle never is.

Honest limits: ~31 s is QEMU-TCG on one core, not a fast loop by absolute
standards — `-smp 2` would cut it and does not work yet (section 5). A boot that
ends in the mountroot wait is 30 s of mostly `mountroot` retry, so shorter
`--secs` values do not shorten the interesting part.

## 9. Next

1. `gdb-multiarch` (root) — restores symbol breakpoints; then re-test `b panic`
   at the stub and drop the physical-address caveat in section 3.
2. `#define VMAPPLE_UART` in `SWEET.h` + a CI kernel; `--uart0` is already in
   place and `serial.txt` should start filling. Serial output is worth more than
   the glyph decode for every later rung.
3. More `cpu0` nodes for `--qemu` in the ADT generator (selftest asserts the
   count), then prove `-smp 2`.
4. Decide the `launchd` `CS_KILLED` question: reproduce on the phone with the
   same skeleton ramdisk via `fastboot boot`, or with a populated volume.
