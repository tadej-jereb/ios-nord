# Handoff — first XNU payload boot on avicii

For Claude Code. Written 2026-11-13 16:20 by Hermes. Everything below is measured on this
unit today; nothing is inferred from datasheets. Read `AGENTS.md`, `docs/STATUS.md`,
`avicii/CONSTANTS.md` and `docs/KERNEL_CI.md` first. Rung 4 (secondary cores) is closed;
this file is the rung after it.

## One-line problem

The shim builds, the payload loads into the ramdisk, the kernel is a real Mach-O — but a
payload boot leaves **no evidence at all**: the device drops off USB and the UFS ring
records nothing past the ladder. We cannot yet tell "jumped and XNU died" from "loader gave
up". Fixing that blindness is the first task; the boot is the second.

## Blocker to fix before any debugging (do this first)

`dlog_init()` is called at **`avicii/shim/diag.c:774`, inside `diag_run()`**, and `diag_run()`
returns 0 at `diag.c:735-736` for `DIAG_STAGE < 1` — before that line. A payload image must be
built `DIAG_STAGE=0` (at any stage >= 1 `diag_run()` parks and never returns, so
`loader_boot()` is never reached), and at stage 0 the ring is never initialised. Therefore **a payload boot writes nothing to the ring** — every line the loader
prints (`PHYS`, `VIRT`, `ENTRY`, `SEGS`, `BOOTARG`, `JUMP`, `LOADER <why>`) goes to the panel
only, and the panel is erased when XNU takes over.

Fix: initialise the ring in `shim_main()` (or make stage 0 keep the ladder's logging) so the
loader path is recorded, and log `loader_boot()`'s return string. Then the next boot is
diagnosable instead of blind. Until this exists, any conclusion about the jump is guesswork.

## What is proven today

Kernel (CI, run `43446209320`, artifact `xnu-kernel-sweet`):

| field | value |
|---|---|
| file | `avicii/shim/out/kernel/kernel.development.sweet` |
| size / sha256 | 17 188 784 B / `c5565e1da46b75e4f871d1fdf57d5cb06b020469b204fd1d8492697c07f4c231` |
| type | Mach-O 64-bit arm64 executable, `NOUNDEFS|PIE` |
| load commands | `LC_UNIXTHREAD`; **no** `LC_DYLD_CHAINED_FIXUPS`, **no** `LC_DYLD_INFO` |
| `__TEXT` vmaddr | `0xfffffe0007004000` |

Series: 87/87 patches apply in series order on the runner (dry run `43444382512`, success).
`make install` still aborts in xnu's `lldbmacros` Python (`ImportError: attempted relative
import`) — cosmetic for us; `Collect` now takes the kernel from the object dir.

Payload (`avicii/shim/out/payload.bin`, sha256 `c2ed4d25ee638c8d4a7f627a138dd6ff58d4c2e36f72424f0981863f7ce6d955`):

    magic SWEETXNU  nsegs 10
    virt_base  0xfffffe0006000000   entry 0xfffffe000748c488
    adt_off    0xfd0ba0  (12772 B)  kernel_end 0xfffffe00084c4000
    phys_base  0x180000000          mem_size   0xfff00000
    cmdline    sweetsmp=0 sweettouch=0 sweetkeys=0 sweetfb_console=1 sweetecon=1 debug=0xc keepsyms=1

`fixups: 0` from `mkpayload.py` is **expected**, not a bug: the kernel carries no chained
fixups, so there was nothing to rewrite. Do not chase it.

Images booted:

| image | sha256 | stage | result |
|---|---|---|---|
| `out-payload/p1/shim-boot.img` | `7016db31210b92bc2999bf98a499b0c814e6ac58568e9e9d985a16edc2dc8614` | 8 | full ladder green (`probe mask=0xfe`, D5 `mismatch=00`), then `park` + self-reset -> Android. Loader never ran: at stage 8 `diag_run()` never returns. |
| `out-payload/p2/shim-boot.img` | `4dcef756e4f29de3282521333674411ed3383a3bf5a0e61947df04bc1dac8629` | 0 | no park line, **device off USB for 5+ min** (no adb, no fastboot, nothing on `lsusb`), stage-0 has no reset path. Consistent with a taken jump; unproven. |

Ring from p1 (`logs/ring-p1.bin`) is the last usable evidence and shows the ladder, not the loader.

## The loader's contract (read this before hypothesising)

`avicii/shim/loader.c`, `loader_boot()`:

1. Payload is read from the FDT `/chosen` `linux,initrd-start/-end`. If either property is
   missing: `no initrd in /chosen`. With the payload in the ABL ramdisk, ABL must set both.
2. Magic must be `SWEETXNU`, version 1, `adt_off` 8-aligned, `rd_start` 8-aligned.
3. `pa = va + (phys_base - virt_base)`; ramdisk must not overlap
   `[phys_base, phys_base + mem_size)` -> otherwise `ramdisk overlaps kernel memory`.
4. Copies each of the 10 segments to `vmaddr + pa_of_va_base`, zeroing `vmsize - file_size`.
5. ADT is copied to `kernel_end + pa_of_va_base`; boot_args go in the next 16K page; then
   `dsb sy; ic iallu; dsb sy; isb` and `((xnu_entry_t)entry_pa)(ba_pa)` — **only x0
   (boot_args) is set**, MMU and caches off. If the kernel returns: `xnu returned`.

## Hypotheses, ordered, each with a discriminator

1. **No ring on the payload path** (above). Discriminator: after the fix, the ring names
   `LOADER <why>` or shows `PHYS`/`SEGS`/`JUMP`. Everything else is blocked on it.
2. **`linux,initrd-start` absent in `/chosen`** on this ABL. The ladder's D5 already proves
   the FDT is readable; the initrd properties are not exercised anywhere. Discriminator:
   dump `/chosen` from the ring before the jump (same fix as (1)).
3. **phys_base 0x180000000 is the high bank.** The live map has three extents
   (`0x80000000+0x3bb00000`, `0x180000000+0x100000000`, `0xc0000000+0xc0000000`); the ADT
   publishes only the high one with `mem_size 0xfff00000`. The 16.6 MB copy is legal there,
   but XNU's early pmap then believes the kernel-managed RAM starts at 6 GiB. Discriminator:
   A/B against `phys_base = 0x90000000` (`mkadt_avicii.py`'s `DEFAULT_PHYS_BASE`, used for
   qemu) — one boot each, compare the ring.
4. **Jumped but XNU died before its console init.** Discriminator: the panel. Magenta only =
   never reached fbcon (loader or earliest kernel). Text/panic/Apple logo = the jump worked
   and the failure is inside XNU.
5. **`debug=0xc` is not an XNU boot-arg** — it comes from the sweet console patches. Also
   `-v` is *missing* from the payload cmdline, so there is no verbose output at all. Add
   `-v debug=0x144` and compare (see `docs/fajita-PORTING.md` for the flags the 6T used —
   same base tree, a working port: copy its cmdline verbatim as one A/B).
6. **Entry register expectations.** Only x0 is set. If avicii's XNU expects a second
   argument (`x1` = cpu id / 0) or a valid stack, it dies at the first C statement with no
   output. Note `refs/edi194-ios-fajita/shim/loader.c` has the *same* tail — `dsb sy; ic
   iallu; dsb sy; isb` then `((xnu_entry_t)entry_pa)(ba_pa)` — and that loader boots this
   base tree on a OnePlus 6T, so the jump mechanics are proven; the difference to hunt is in
   what goes into `boot_args` and the ADT, not in the jump itself. Diff the two `boot_args`
   fills line by line.

## Reproduction, literal

    cd /home/tadej/ios-nord
    gh run download 43446209320 -R tadej-jereb/ios-nord -n xnu-kernel-sweet -D avicii/shim/out/kernel
    cd avicii/shim
    ../tools/mkadt_avicii.py out/avicii.adt --fdt-json ../../logs/mem-live.json
    python3 ../tools/mkpayload.py out/kernel/kernel.development.sweet out/avicii.adt out/payload.bin --cmdline "<flags>"
    DTB=$PWD/hybrid/sections/dtb-stock DTB_FILE=$PWD/hybrid/sections/dtb-stock DIAG_STAGE=0 DIAG_LOG=1 OUT=$PWD/out-payload/p3 ./build.sh $PWD/out/payload.bin
    ../tools/mkbootimg_v1.sh --verify out-payload/p3/shim-boot.img
    cd /home/tadej/ios-nord
    export ADB_VENDOR_KEYS=$HOME/.android/adbkey
    adb reboot bootloader
    fastboot devices
    fastboot boot avicii/shim/out-payload/p3/shim-boot.img

Recovery and ring pull (device is currently **dead off USB** after `p2`; hold power ~30 s):

    adb devices
    size=$(adb shell 'su -c "blockdev --getsize64 /dev/block/sda16"' | tr -d '\r')
    adb exec-out "su -c 'dd if=/dev/block/sda16 bs=4096 skip=$((size/4096-1025)) count=1024'" > logs/ring.bin

`adb devices` answers `unauthorized` until `ADB_VENDOR_KEYS=$HOME/.android/adbkey` is
exported. Landing point is not deterministic: recovery gives root adbd without `su` (plain
`exec-out dd`), Android+Magisk needs `su -c`.

Payload images are large (96 MB) but `fastboot boot` handles them (2.4 s).

## Definition of done

Ring (or fbcon) shows the loader's `PHYS`/`VIRT`/`ENTRY`/`SEGS`/`BOOTARG`/`JUMP`, and XNU
prints something of its own afterwards — banner or panic — with that output captured in
`logs/` and the cause of any panic named. Record both images' sha256 in
`docs/IMAGE_PROVENANCE.md`, update `docs/STATUS.md`, one commit.

## Rules that do not bend

- `fastboot boot` only in this task; nothing is flashed; `boot_b` stays the fallback;
  experiments go to `boot_a` if a flash ever becomes necessary.
- `persist`, `modemst1/2`, `fsg`, `xbl`, `abl`, `tz` are never touched; no GPT edits.
- Every destructive step gets a gate and a sha256 line in `docs/IMAGE_PROVENANCE.md`.
- Numeric constants come from `avicii/CONSTANTS.md` (cited) or from the live FDT — never
  from a spec sheet.
- Procedures are numbered transcripts, one literal command per line.

## Side lane (optional, blocked)

A macOS VM exists for building XNU without CI (`/home/tadej/quickemu/STATE.md`): quickemu
Ventura, driven headless through the QEMU monitor (`/home/tadej/.hermes/cache/scratch/vm.py`).
It boots the recovery kernel and then idles at a fixed kernel offset under both KVM and TCG.
Not needed while CI works — CI now produces the kernel reliably.
