# avicii recovery, root and backup — run sheet

OnePlus Nord (avicii, SM7250/lito), AC2001/AC2003. Prepared 2026-11-11, for the
bootloader unlock on 2026-11-12. Nothing here flashes the iOS shim yet; this is
the Android-side groundwork plus the backup that has to exist before anything
else is touched.

**Partitions that must survive every flash:** `persist`, `modemst1`,
`modemst2`, `fsg`, `fsc`, `xbl*`, `abl*`, `tz*`, `devinfo`. The iOS root goes
into the existing `userdata`; `super` and the dynamic partitions stay as the ROM
leaves them.

## Slot map and the rule that follows from it

avicii is A/B (`AB_OTA_UPDATER := true`, `vbmeta_system` present, no
`init_boot`, no `vendor_boot` — verified in
https://github.com/LineageOS/android_device_oneplus_avicii/blob/lineage-21/BoardConfig.mk).

- Slot **a** starts on stock OOS. It is expendable: it is where the iOS shim
  and the iOS root go.
- Slot **b** is the fallback. Linux/Magisk in `boot_b` is built and *proven to
  boot* before slot a is touched, and `boot_b` is then frozen.
- `fastboot flash boot` without a suffix writes the **active** slot. With a
  active that is `boot_a`. Always check `fastboot getvar current-slot` before a
  bare `flash`, or name the slot explicitly.

Sideload installs always land in the **inactive** slot, so the ROM install below
has to run with slot a active to write slot b. `fastboot --set-active X` is also
what marks a slot bootable; ABL will bounce to the other slot on its own after a
few failed boots, which is rollback, not a bad flash.

## 0. Preflight on the host

1. `adb`/`fastboot` are installing unprivileged into `tooling/opt` — use
   `tooling/opt/platform-tools/{adb,fastboot}`. Fastboot must be recent enough
   for `--disable-verity` (see §7 for why old builds fail).
2. udev rules are a **root step** (no passwordless sudo here):
   `sudo cp tooling/opt/platform-tools/51-android.rules /etc/udev/rules.d/`
   then `sudo udevadm control --reload-rules && sudo udevadm trigger`. Without
   it `adb devices` shows nothing and `fastboot devices` stays empty.
3. Before every flash: `fastboot getvar product` must say `avicii`,
   `fastboot getvar unlocked` must say `yes`.

## 1. Firmware floor — Android 12

LineageOS 21 for avicii requires **Android 12** stock firmware
(https://wiki.lineageos.org/devices/avicii/install, "Checking the correct
firmware"). If the phone is on OOS 13/14, go back to OOS 12 first (MSM
DownloadTool or the OOS 12 fastboot package) — flashing LOS on newer firmware
fails or crashes later.

## 2. Images to stage

Verified by me on 2026-11-11 (HTTP 206/200, first bytes checked — `ANDROID!`,
`AVB0`, dtbo table magic `d7b7ab1e`):

| what | where | size / md5 |
|---|---|---|
| LineageOS 21 `boot.img` | https://archive.org/download/lineageos_202408/full/avicii/20240619/boot.img | 100663296 B, md5 `3a437aa4f34808a63056d4c0f19710af` |
| `dtbo.img` | …/20240619/dtbo.img | 25165824 B, md5 `1a12260da239c8f6570d7af7aff7d2df` |
| `vbmeta.img` | …/20240619/vbmeta.img | 8192 B, md5 `4e23c5d415e0c2dc08154f5718f109ac` |
| `recovery.img` | …/20240619/recovery.img | 100663296 B, md5 `4a51f2f2a8ad0200af21aca785973627` |
| ROM zip | …/20240619/lineage-21.0-20240619-nightly-avicii-signed.zip | 1267027843 B, md5 `d986dd472a680735cd60710cc2c0a169` |
| TWRP FBEv1 (stock/OOS) | https://dl.twrp.me/avicii/twrp-3.7.1_12-0-avicii.img | sha256 `cd84e2eca353858304cf37f703542ad3a274bd950367e22020c674533d242076` |

Directory listing for the last three LOS 21 builds so a newer nightly can be
picked: https://archive.org/download/lineageos_202408/full/avicii/ (20240605,
20240612, 20240619).

Also on `dl.twrp.me/avicii`: the older `3.7.0_12-0` release, and the `aviciiv2`
(FBEv2) build of both versions.

**Claimed only, not verified by download:** `vbmeta`/`boot` etc. are only
reachable through the archive.org mirror because the official build API returns
an empty list (`https://download.lineageos.org/api/v2/devices/avicii/builds` →
`[]`). The mirror URLs come from the ROM thread
(https://xdaforums.com/t/rom-official-14-oneplus-nord-avicii-lineageos-21.4652409/).
The md5 values above are archive.org's own item metadata, not a maintainer
signature; there is nothing better to compare against. `super_empty.img` sits in
the same directory if the ROM complains about the super layout. Alternative ROM
if the mirror dies: RisingOS
Revived A15 thread
https://xdaforums.com/t/rom-unofficial-android-15-risingos-revived-avicii-stable.4751516/
— its only download is a Google Drive link
(`1-sFsYp9TukvlVfL5l1Vu64Hnl2LNFmJQ`, resolves HTTP 200, filename unchecked).

## 3. Boot TWRP temporarily and take the backup

TWRP 3.7.1_12 official for avicii (maintainer rany2). Pick `-avicii` (FBEv1) on
stock OOS; `-aviciiv2` is the FBEv2 build for FBEv2 custom ROMs.

```sh
cd tooling/opt/platform-tools
./fastboot boot twrp-3.7.1_12-0-avicii.img
```

`fastboot boot` on avicii is what twrp.me documents and what the PitchBlack
thread tells people to do, but it is a *forum/page claim* — verify it yourself
before you rely on it. If it fails with `unknown command`, the fallback is to
put TWRP in the recovery partition of the **active** slot (a):

```sh
./fastboot flash recovery twrp-3.7.1_12-0-avicii.img   # writes recovery_a
./fastboot reboot recovery
```

Do **not** use "Advanced → Flash Current TWRP" while a slot must keep its own
boot image: it writes TWRP's ramdisk into `boot`, i.e. over the shim or over the
fallback.

In TWRP, adbd is root. Check `adb shell id` says uid 0, then (absolute paths,
the shell is still inside `tooling/opt/platform-tools`):

```sh
cd /home/tadej/ios-nord
./tooling/opt/platform-tools/adb push tooling/40-backup-by-name.sh /sdcard/
./tooling/opt/platform-tools/adb shell sh /sdcard/40-backup-by-name.sh
sh tooling/41-backup-pull.sh            # host side, md5-verifies, refuses on mismatch
cp -a backup/ /somewhere/off-machine/   # one copy off this disk
```

The manifest records `userdata` and `super` with their sizes instead of dumping
them. `persist`, `modemst1/2`, `fsg`, `fsc` are only restorable onto *this*
handset — see `docs/IMAGE_PROVENANCE.md` for the restore rules.

## 4. Build slot b as the fallback (a stays active)

4.1 Flash the LOS `dtbo` and `vbmeta` to the **active** slot, which is where
the temporarily booted Lineage Recovery reads them from:

```sh
./fastboot flash dtbo dtbo.img
./fastboot flash vbmeta vbmeta.img
```

LineageOS's own vbmeta for avicii is already built verification-disabled:
`BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS += --set_hashtree_disabled_flag` and
`--flags 2` in the device tree, i.e. flags = 3 (bit 0 = hashtree off, bit 1 =
verification off; `libavb/avb_vbmeta_image.h`). No extra flags needed here, and
the OTA payload writes the same kind of vbmeta into slot b.

4.2 Put Lineage Recovery in `recovery_a` and sideload. Sideload writes the
inactive slot, b:

```sh
./fastboot flash recovery recovery.img
./fastboot reboot recovery
adb sideload lineage-21.0-20240619-nightly-avicii-signed.zip
```

4.3 The payload normally switches the active slot to b itself. Confirm it, then
make it stick and let it boot:

```sh
./fastboot getvar current-slot          # expect b; if it still says a:
./fastboot --set-active=b
./fastboot reboot
```

`--set-active` marks b bootable. If the phone bounces back to a after two or
three tries, that is ABL's retry counter, so read the boot reason rather than
re-flashing blindly.

## 5. Root slot b with Magisk (canary)

Magisk v30.x canary on the **ROM's** boot image, never a patched image from a
different build. Canary APK comes from the canary channel of
https://github.com/topjohnwu/Magisk (release APK, not the repo zip):

```sh
adb push boot.img /sdcard/                      # boot.img from the LOS zip
# Magisk app: Install -> Select and Patch a File -> /sdcard/boot.img
adb pull /sdcard/Download/magisk_patched-*.img
adb reboot bootloader
./fastboot flash boot_b magisk_patched-*.img
./fastboot reboot
adb shell su -c id                              # expect uid=0(root)
```

Keep the patched image: `boot_b` is now the fallback and the only way back to a
booting Android. Re-verify with two clean reboots before going on. If Magisk
boot-loops, re-flash the unpatched `boot.img` to `boot_b` (same command) — the
ROM's vbmeta is verification-disabled, so an unsigned boot is fine.

## 6. Frozen-slot discipline

- Nothing in the iOS work touches `boot_b`, `dtbo_b`, `vbmeta_b`.
- iOS boot tests: `fastboot --set-active=a`, shim goes to `boot_a`.
- Rollback: `fastboot --set-active=b` (see `docs/IMAGE_PROVENANCE.md`).

## 7. vbmeta fallback — exact form, and what OnePlus needs

Only needed when an unsigned image has to boot while verification is still on:
a stock OOS vbmeta, a vbmeta from another package, or after ABL reports
`dm-verity corrupt`. Run it against the **slot you are changing**, by explicit
suffix, because a bare `vbmeta` resolves to the active slot:

```sh
./fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img
# slot-pinned, the form used here:
./fastboot --disable-verity --disable-verification flash vbmeta_a vbmeta.img
```

What OnePlus needs to make that work:

- **Unlocked bootloader.** Rewriting the flags invalidates the vbmeta signature;
  on a locked avicii ABL keeps enforcing it and drops to the other slot.
- **Current platform-tools.** Older fastboot rejects both options outright
  (`unrecognised option '--disable-verity'`, seen in
  https://xdaforums.com/t/solved-vbmeta-flashing-and-disable-verity-verification-command-problem.4396799/);
  the flags are handled by fastboot itself and rewrite the header flags byte of
  the blob before writing.
- **A vbmeta from the same package as the boot image.** avicii's `vbmeta` is
  8 KiB and carries the chain descriptor for `vbmeta_system`; a 4 KiB blob from
  another device/firmware gives the classic
  `skip copying ... avb footer (partition size: 0)` and then
  `remote: 'image verification error'`. Verify the blob starts with `AVB0`.
- **Flags both ways, and they mean specific bits:** `--disable-verity` ORs
  `0x01` (hashtree) and `--disable-verification` ORs `0x02` (verification) into
  the flags byte at `vbmeta_offset + 123` of the blob you hand it, and does not
  re-sign it (`system/core/fastboot/fastboot.cpp`, `rewrite_vbmeta_buffer`). Bit
  1 is the one that stops ABL hashing `boot`, and it also stops it following the
  `vbmeta_system` chain — so leave `vbmeta_system` alone, its signed contents
  stay valid.
- **Because the blob is now unsigned, the bootloader must be unlocked** and
  nothing may re-verify it later: flashing a stock vbmeta again re-enables
  verification, so an unsigned `boot` on that slot then refuses to start.
- **Re-read after flashing:** `./fastboot reboot bootloader` before booting, so
  the next boot parses the new vbmeta rather than one ABL may still hold from
  this fastboot session.
- **Both slots, consistent.** A verified slot still boots only if its own
  vbmeta matches its own boot. When you go back to a verified slot, flash that
  slot's stock vbmeta (or the matching ROM package's) again.

Reminder that the LOS package needs none of this: its vbmeta already carries
flags = 3 (step 4.1).

## 8. Log pulls

`tooling/42-log-pull.sh` boots nothing; it reads the last 1025 blocks of
`userdata` where the ios-sweet kernel keeps its ring (mechanism copied from
upstream `tools/sweet-log-pull.sh` + `tools/sweet-log.py`,
https://github.com/dipa-studio/ios-sweet/tree/main/tools, kernel patch 0047;
a local copy is in `refs/dipa-studio-ios-sweet/tools/`, which is gitignored).
It needs a rooted adb shell, so boot TWRP temporarily first
(`fastboot boot twrp-...img`, a active), then:

```sh
sh tooling/42-log-pull.sh -o logs/boot-07.txt
```

No `SWEETLOG` header means the kernel never flushed, userdata was reformatted,
or the ring moved — the raw 4 MiB area is kept for inspection.

## 9. Link status, as checked 2026-11-11

| link | result |
|---|---|
| twrp.me page for avicii | **resolved**, HTTP 200, support "Current", maintainer rany2, FBEv1+FBEv2 builds |
| dl.twrp.me/avicii/twrp-3.7.1_12-0-avicii.img | **resolved** to a real boot image (HTTP 206, `application/octet-stream`, magic `ANDROID!`) *when a Referer is sent*; without Referer the same URL returns the HTML landing page. eu.dl.twrp.me behaves the same. `.sha256` fetched: `cd84e2eca3…` |
| archive.org LOS 21 files | **resolved**, correct magics, sizes from the item metadata |
| download.lineageos.org/api/v2/devices/avicii/builds | resolves but returns `[]` — that is why the mirror is used |
| XDA 4774602 (TWRP 3.7.1, A14/15/16 claim) | page CURL-blocked (403), read through r.jina.ai. Links are claims: `drive.google.com/file/d/1FlsE0xtpwzU1OxYUUDeIU-21pScR9Hsp` and `https://hardik.integritybox.online/0:/recovery.img` |
| hardik.integritybox.online/0:/recovery.img | **did not resolve** for me: HTTP 500 on HEAD. Unverified |
| XDA 4652409 (LOS 21) | page 403 via curl, read via mirror; the archive.org links it lists all resolve |
| RisingOS Revived A15 thread | page 403 via curl; only download is `drive.google.com/file/d/1-sFsYp9TukvlVfL5l1Vu64Hnl2LNFmJQ`, HTTP 200 as a Drive page, filename/size unchecked |
| `fastboot boot` working on avicii | claimed by twrp.me instructions and the PitchBlack thread; not yet observed on this unit |
