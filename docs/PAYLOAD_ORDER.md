# Flash order for the payload/shape series (S1–S6)

Companion to `avicii/build/README.md`. Images are in `avicii/build/out/`. Host work only —
this file is the order to flash, the expected outcome of each step and the one thing to change
if a step fails.

The series separates *packer shape* from *payload*. Stock is S1 (control), the footer is S2
(gate), our packer at stock weight is S3/S4, the park payload is S5/S6. Order matters: if S2 is
refused, the fault is in the footer/vbmeta region and the payload questions are moot.

## What "refused" and "accepted" look like here

- **Refused** — the fixed signature: ~6 s after the reboot the screen stays dark and the phone
  reappears as a fastboot device (or `fastboot devices` shows it again). Everything so far has
  failed this way.
- **Accepted, payload runs** — the 6 s point passes and the phone does **not** come back as
  fastboot. S5/S6 have a two-instruction park payload, so "accepted" looks like a **dark screen
  and a phone that stays gone** for 90 s. That is success, not a hang. Only a long power +
  volume-up reset brings it back.
- **Refused differently** — fastboot returns in under 2 s, or the phone never reappears at all
  after a reset. Treat as a separate finding and write down the timing.

## Hard rules for every step

1. `adb kill-server` before touching fastboot. A live adb server re-grabs the USB interface
   the moment the phone falls back and will race the failure window.
2. `fastboot getvar current-slot` before every flash; name the slot (`boot_b`) explicitly.
   Never a bare `fastboot flash boot`.
3. Verify the file before flashing it:
   `sha256sum avicii/build/out/S<N>.img` must equal the value printed in the step.
4. **One test image per boot.** Restore the fallback (below) between steps, confirm Android and
   root, then flash the next. Never chain two series images without a restore.
5. Observe the full 90 s. Do not judge before it, do not interrupt a boot that is still in the
   window.
6. Stop at the first result that differs from the expectation. The series is only worth anything
   while each step is attributable to one variable.
7. Append a provenance block (`docs/IMAGE_PROVENANCE.md` template) for every flash, with the
   result and the sha256. Nothing gets flashed twice without a new block.

## Restore between steps (the fallback)

`boot_b` is the only bootable Android on this phone; `backup/64f70df8/boot_b.img`
(sha256 `39ed8eeaf9053a9a53028b3b2ba03f45ab288df38e8f9430ca0a6fda545b1ef0`) is the copy.

Between every two steps, in this order:

    adb kill-server
    fastboot getvar product
    fastboot getvar serialno
    sha256sum backup/64f70df8/boot_b.img
    fastboot flash boot_b backup/64f70df8/boot_b.img
    fastboot reboot
    adb wait-for-device
    adb shell getprop ro.boot.slot_suffix
    adb shell su -c id

`ro.boot.slot_suffix` must be `_b` and `su -c id` must return `uid=0`. Only then is the next
step allowed. If the restore does not boot, stop the series — the phone, not the image, is now
the variable, and `docs/RECOVERY.md` "Rollback to the fallback slot" applies.

If ABL rolls back on its own, `current-slot` says `b` after the failed boot and the phone is
already on the fallback: skip the flash, still do the two `adb shell` confirmations.

## The order

### S1 — control, byte-identical stock copy

    adb kill-server
    fastboot getvar product
    fastboot getvar current-slot
    sha256sum avicii/build/out/S1.img
    fastboot flash boot_b avicii/build/out/S1.img
    fastboot reboot

sha256 `183795b7a887d4f4c69e5b29cf65f3345ae6cea634ebdb2db49edc9cbaa45239`

Expected: Android boots normally, within the usual LineageOS time, `su -c id` works. This image
is stock byte for byte, so it also proves the flash procedure and the slot.

**If it fails:** the phone or the procedure is the problem, not the images. Re-run the restore,
re-check `product`/`serialno`, and stop.

### S2 — stock bytes, footer rebuilt by our avbtool (the gate)

Same four gates, then `fastboot flash boot_b avicii/build/out/S2.img`, `fastboot reboot`.

sha256 `7b91cdc630561fce7ddc8086482acfabe280ed1dcd2803374e8684b5283fec97`

Only bytes `46198784..100663296` (the vbmeta blob and the zero fill) differ from S1; the whole
body is stock's.

- **Boots** → our footer is not the refusal cause. Continue. S3/S5 are the payload and shape
  steps and now mean something.
- **Refused** → the fault is in our footer/vbmeta and the payload is irrelevant.
  **Single fix:** stop the series and hand back to the packer side with this fact; the next image
  to build is S2 with stock's two vbmeta props (`com.android.build.boot.os_version`,
  `…boot.fingerprint`) and stock's `vbmeta_size` of 704 instead of our 512. Do not guess further
  down the series.

### S3 — stock sections through our packer, kernel at its natural length

sha256 `45e7deacb39c4d387355c06d641499c23456bba2a8704c81017f1ac0434f6a20`

Stock kernel, stock ramdisk, stock dtb, stock header, our footer. Delta to stock: `kernel_size`
43876358 instead of 43876368 (10 trailing zero bytes trimmed) and the 20-byte `id` — nothing else.

- **Boots** → our packer produces an image the ABL executes.
- **Refused after S2 booted** → the refusal is in the produced image, and the only produced
  difference is a 10-byte shorter section and a different sha1 `id`.
  **Single fix:** the `id`. Copy stock's 20 bytes at `0x240` over ours and reflash; if that boots,
  `id` is the whole gate.

### S4 — same as S3 with the kernel back at the stock length

sha256 `005b6af0e5df9f6ce7eb1202e3cc6a4867f1e9593087985bf4596bbfcc15b232`

Byte-identical to S2 except the 20-byte `id`. Every section size and offset is the stock value.

- **Boots after S3 failed** → 10 bytes of section length is enough to be refused.
- **Boots after S3 booted** → the ABL tolerates the size deviation; S3's result is cosmetic and
  S5/S6 are judged on their own.
- **Refused after S2 booted** → `id` is confirmed as the only remaining delta and the fix is the
  same one-byte-range transplant as S3.

### S5 — park shim at stock weight

sha256 `f024b50b3471ce36ec62f09539ab3c6b29bd996bc9be99883c7136c5e78a61e3`

First step that is not stock payload. Kernel section is the 354 KiB shim gzip+DTB zero-padded to
43876368, ramdisk is the shim's 98 bytes, dtb section and all header fields are stock's. Image is
44.3 MB of body — stock's weight and stock's offsets.

Expected: the 6 s point passes, phone stays dark, no fastboot device for 90 s. Reset, restore.

- **Parks** → the shim's code is reached from a stock-shaped image. The payload is not the
  refusal cause on its own.
- **Refused** → either the shim payload or the trailing-zero padding in the kernel section is
  refused.
  **Single fix:** compare with S6. If S6 parks and S5 does not, the padding is the trigger; the
  next build pads the kernel *after* the gzip stream only with the DTB (already the case) and
  drops the zero fill, i.e. S5 reduces to S6 and weight is no longer worth chasing.

### S6 — park shim, natural small image

sha256 `599f878e9b93c7e3b00d95fc4bd0404d6d8c5fce788b7d8db75b21a62e6380b6`

Unpadded 354519-byte kernel section, 98-byte ramdisk, stock dtb and header, 774144-byte body.

Expected: same park signature as S5.

- **Parks** → the smallest, cheapest image we have executes. Every later shim iteration starts
  from S6's shape rather than from the old v1 image.
- **Refused while S4 booted** → the shim payload itself is refused, independent of weight and
  padding, with a stock-shaped body around it.
  **Single fix:** bisect the payload, not the packer — the packer is cleared by S4. First
  candidate is the 98-byte ramdisk: replace it with the stock 1900641-byte ramdisk and reflash.

## After the series

Whichever image parks first defines the shape of every subsequent shim build. Record the outcome
per step in `docs/IMAGE_PROVENANCE.md` and in `docs/STATUS.md`, including the steps that were
refused — the refusals are the measurement.
