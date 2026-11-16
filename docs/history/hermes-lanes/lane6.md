# Lane 6 — PHONE (real hardware; the only lane allowed to touch the phone)

Read `.hermes-lanes/shared.md` first for the repo rules, then this. You get the phone
exclusively; no other lane touches it. Everything below is non-destructive by construction:
`fastboot boot` and `adb reboot` only — **never `fastboot flash`, never `dd`, never `fastboot
erase/write`**. `boot_a` is never written; `boot_b` (LineageOS + Magisk) stays the fallback and
`persist`/`modemst1/2`/`fsg`/`xbl`/`abl`/`tz` are not named.

State measured by the coordinator at 10:20: `adb devices` → `64f70df8  recovery`; `fastboot
devices` → empty; `fastboot getvar` hangs waiting for a device. So the phone is in TWRP, not in
fastboot.

## What this lane is for

The rung QEMU has reached is the skeleton ramdisk: `md0` → `hfs: mounted RD-root` →
`exec launchd` → `dyld: Library not loaded: /usr/lib/libSystem.B.dylib` on a kernel carrying
`0104`, `CS_KILLED` before it. The phone is the same bytes on real hardware (different GIC,
timer, real UFS, real ABL). The point is to find out whether the avicii ABL accepts our header-v1
image at all, and whether the boot stops on the same line. That is the whole claim; do not
overstate it.

## Steps, in order

1. **Ring first, zero risk.** `tooling/42-log-pull.sh -s 64f70df8 -o logs/phone/<stamp>/ring-pre.txt`
   (read-only, needs the TWRP root shell). Keep the raw bin. If there is no valid ring header,
   record that and move on — do not chase it.
2. **Record the device facts**: `adb -s 64f70df8 shell getprop ro.product.device`,
   `ro.build.fingerprint` if reachable, `adb shell dumpsys twrp` version or `twrp version`
   alternative. Then `adb -s 64f70df8 reboot bootloader`, wait for `fastboot devices`, and record
   `fastboot getvar current-slot`, `max-download-size`, `product`, `unlocked`, `version-bootloader`.
   If fastboot never appears after two tries, stop and report blocked — do not loop.
3. **Pack the image** in `build/phone/`: `avicii/tools/mkpayload.py --ramdisk
   build/rd-root.skeleton.img` for the payload, then the proven header-v1 packer
   (`avicii/shim/build.sh` / `avicii/tools/mkbootimg_v1.sh`, `Image.gz-dtb`, board DTB from
   `src/avicii-board.dtb` or as `docs/SHIM_BOOT.md` names it, `--header_version 1`,
   `header_size` 1648). `--verify` must PASS. Record sha256 and size. Re-read `docs/STATUS.md`
   for the exact shape that was proven on the ring — do not invent a new layout.
4. **Gate before boot**: image size must be under `max-download-size` (print both). Then, and only
   then, `fastboot boot build/phone/rd-root.phone.img`.
5. **Read the result**: wait ~60 s, then pull the ring again (`42-log-pull.sh`) — after a
   `fastboot boot` the phone may sit in the kernel with no adb, so a re-plug or a return to TWRP
   may be needed; the ring lives at the end of `userdata` and survives. Record the last console
   lines: `hfs: mounted`, `load_init_program`, `exec launchd`, and the stop line, and say whether
   it matches the QEMU line byte for byte.
6. **Leave the phone reachable**: end in TWRP (`adb`) or in fastboot, say which. A plain reboot
   is always a valid exit.

## Owns

`tooling/70-phone-boot.sh` (new, your wrapper — do not edit `60`/`61`/`62`), `docs/PHONE_TEST.md`
(new), `build/phone/*`, `logs/phone/*`. Nothing else. Never touch `build/rd-root.img`,
`build/rd-root.stage`, `build/rd-root.progs.*`, `build/ios16-root.img`.

## Report

Device facts, both ring pulls with paths, the image sha256/size and `max-download-size`, the boot
command verbatim, and the stop line with the QEMU comparison. Anything you could not establish,
say so plainly.
