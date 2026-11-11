# Working on ios-avicii

Port of [`dipa-studio/ios-sweet`](https://github.com/dipa-studio/ios-sweet) (Apple XNU +
iOS 16.7.16 userland, iPhone X 20H392) to the **OnePlus Nord** (`avicii`, SM7250/lito,
ARMv8.2 Kryo 475: 2x A76 MPIDR 0x600/0x700 + 6x A55 0x000-0x500).

Bootloader unlock: **2026-11-12** (planned). Nothing is flashed before that.

## Read first, in this order

1. `docs/STATUS.md` — where the work actually is, what is proven, what is next.
2. `avicii/CONSTANTS.md` — every hardware constant with its dts citation. Do not use a
   number that is not in this file and cited.
3. `docs/SHIM_BOOT.md` — OnePlus boot image rules (header v1 only, `Image.gz-dtb`).
4. `docs/fajita-PORTING.md` — the completed OnePlus 6T port of the same base tree. It is
   the map for the whole boot ladder, including the walls it already hit.
5. `docs/REFS_INDEX.md` — which fork holds which subsystem work.

## Ground rules

- The vendor's published dts and live sysfs reads are the only sources of truth. Never
  fill a constant from a spec sheet. Unverified values carry an `UNVERIFIED` marker.
- Read RAM from the **live FDT** (`/sys/firmware/fdt`). The memory node in every static
  DTB is a placeholder (`reg = <0 0 0 0>`).
- Preserve the device: `persist`, `modemst1/2`, `fsg`, `xbl`, `abl`, `tz` are never
  touched. The iOS root goes into the existing `userdata` partition — no GPT edits.
- Experiments go to `boot_a` only. `boot_b` keeps a bootable LineageOS + Magisk as both
  fallback and dump/log host. Every destructive step gets a gate and a `sha256` record in
  `docs/IMAGE_PROVENANCE.md` before it runs.
- Procedures are numbered transcripts: one literal command per line, no prose inside a
  block, a gate before every destructive action.
- No serial port exists on this phone. The log ring in `userdata` (pulled via TWRP or USB
  ECM) is the only channel; `tooling/42-log-pull.sh` fetches it.

## Layout

    avicii/          constants, shim, ADT generator, tools, future patches
    docs/            reference notes, transcripts, provenance
    refs/            read-only clones of the other ports (never commit into them)
    tooling/         host scripts; `opt/` holds the unprivileged toolchain
    src/             downloaded stock images (not in git)
    logs/            build and boot logs

## Base tree and why

`sweet` (SM7150) rather than `topaz` (SM6225): avicii is ARMv8.2 with a 2x A76 + 6x A55
mix, so sweet's 16K-granule, native-LSE, native-PAN machine config runs unchanged and
topaz's LSE/LDAPR emulation and Gold-cluster hand-off patches are not needed.
