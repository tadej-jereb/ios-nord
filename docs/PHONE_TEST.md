# PHONE_TEST — the first `fastboot boot` runs on the handset (avicii, 64f70df8)

Lane 6, 2026-11-14, host clock UTC (phone local = UTC+1). Non-destructive throughout:
`adb reboot bootloader`, `adb reboot`, `fastboot boot`, `fastboot reboot recovery`.
No `fastboot flash`, no erase, no `dd`, no partition write. `boot_a`/`boot_b` never named.

The claim this document supports, and nothing wider: **the avicii ABL accepts our header-v1
`Image.gz-dtb` image and executes it, three times out of three**, and the shim inside it runs to
`J ENTRYPA`. What the kernel does after the jump on the `md0` payload is *not* yet visible on the
handset (see §6 — it produced no console bytes at all).

## 1. Device facts (measured)

    adb devices -l
    64f70df8    recovery usb:3-4 product:Nord model:AC2003 device:Nord

    adb shell id
    uid=0(root) ... context=u:r:su:s0            # root adb; no su binary needed
    getprop ro.product.device       Nord
    getprop ro.product.model        AC2003
    getprop ro.build.fingerprint    OnePlus/Nord/Nord:12/RKQ1.211119.001/Q.202212051830:user/release-keys
    getprop ro.boot.slot_suffix     _b
    getprop ro.twrp.version         (empty)

    ls /sbin/twrp            -> No such file or directory
    /tmp/recovery.log        -> exists
    twrp version / dumpsys   -> not found

So: a recovery image with a **root adbd**, a toybox `/sbin`, a `/tmp/recovery.log`, no TWRP binary
and no `dumpsys`. It is not verifiable as TWRP from the device side; `42-log-pull.sh` works on it
because adbd is already uid 0.

Fastboot, after `adb reboot bootloader` (one try, up in ~6 s):

    current-slot        b
    max-download-size   805306368            # 768 MiB
    product             lito
    unlocked            yes
    version-bootloader  (empty)
    partition-size:boot_a  0x6000000         # 96 MiB

## 2. Ring pulls (read-only, raw area kept)

Layout `42-log-pull.sh` reads: last 4100 KiB of `/dev/block/sda16` (103 184 MiB userdata), block
0 = shim header, then the kernel console ring. Both rings survive every reboot in this document.

| tag | path | shim ring | kernel ring |
|---|---|---|---|
| pre | `logs/phone/20261114-092548/ring-pre.txt` (+`.bin`) | 1 750 B, `n=0xa` | 8 394 B, sha256 `5be82cb2…` |
| post #1 (diag8) | `logs/phone/20261114-092548/ring-post.txt` (+`.bin`) | 3 227 B, stage-8 park | 8 394 B, `5be82cb2…` (unchanged) |
| post #3 (0105) | `logs/phone/20261114-094800/ring-post-0105.txt` (+`.bin`) | 1 835 B, `n=0xb` | 8 394 B, `5be82cb2…` (unchanged) |

`ring-pre.txt` sha256 `7198b803a36eeeee30110f119199ae00a972f6a52d599d4a3977601c18892d90`;
`ring-post-0105.txt` sha256 `e1e8bd637ed511a38d7b3b14c7574828b845fdb03a01b4151b06566765e37b54`.
The **kernel half is byte-identical in all three pulls** — see §6.

## 3. The image

    tooling/env.sh
    DTB=src/avicii-soc.dtb OUT=build/phone/shim-out-d0 DIAG_STAGE=0 ./avicii/shim/build.sh
    python3 avicii/tools/mkpayload.py avicii/shim/out/kernel/kernel.development.sweet \
        avicii/adt/avicii-live.adt build/phone/payload-0105.bin \
        --ramdisk build/rd-root.skeleton.img --cmdline "$CMD"
    ./avicii/tools/mkbootimg_v1.sh --kernel build/phone/shim-out-d0/Image.gz-dtb \
        --ramdisk build/phone/payload-0105.bin -o build/phone/rd-root.phone.sx.img

* kernel: `avicii/shim/out/kernel/kernel.development.sweet`, 17 206 080 B,
  sha256 `534248682bbc5cbb29e38033be872b3edfbbb84d45476f6cb12ad8e31779cf1e` (carries `0105`;
  `strings` finds `SWEET EXEC: %s failed errno %d` and `sweetexeclog`)
* ramdisk: `build/rd-root.skeleton.img`, 33 554 432 B — the 32 MiB HFS+ skeleton, packed as payload
  segment 10 at pa `0x1824c8000`, size `0x2000000`
* ADT: `avicii/adt/avicii-live.adt` (dram-base `0x180000000`, dram-size `0xfff00000`)
* shim: `build/phone/shim-out-d0/Image.gz-dtb`, 422 836 B, `DIAG_STAGE=0` (see §7)
* cmdline (inside the payload, offset 0x69048 of the boot image, verbatim):
  `rd=md0 sweettouch=0 sweetkeys=0 sweetfb_console=1 sweetecon=1 keepsyms=1
  launchd_log_serial=1 launchd_disable_all_timeouts=1 sweetexeclog=1 rootrw=1 -v debug=0x144`
  — `rootrw=1` added after the QEMU tier-2 work proved a read-only `md0` breaks `confstr`/`access(W_OK)`
  and kills every job that wants a temp dir (tccd: `brk #1`, 80/80). The phone's root is read-only too.
  Changing the cmdline changes the payload bytes, so re-record the payload and image sha256 on the next
  build.
* **image**: `build/phone/rd-root.phone.sx.img`, **100 663 296 B (96 MiB)**,
  sha256 `604d979a84ac000d9fc5d49d5b72adced463dbf34d71fa919a68fb21d1ae01f2`
* payload: `build/phone/payload-0105.bin`, 50 168 168 B, sha256 `bca71df5019035e826fec4a75e909980304120b5ef27629524303dc8bb071d23`
* `mkbootimg_v1.sh --verify`: `PASS: header v1, stock avicii geometry, gzip+DTB kernel`;
  header_size 1648, pagesize 4096, os_version 0x1c000185, AVB footer present,
  `kernelsection` gunzips to 835 584 B with the 406 620 B `src/avicii-soc.dtb` appended
* check that the packed bytes really carry 0105 (both run against the file, not the source):
  `grep -c 'SWEET EXEC: %s failed errno %d' build/phone/payload-0105.bin` -> 1,
  `grep -c sweetexeclog` -> 2, payload magic at 0x69000 is `SWEETXNU`

Gate before the boot:

    image             build/phone/rd-root.phone.sx.img
    bytes             100663296
    max-download-size 805306368
    headroom          704643072
    verdict           PASS

## 4. The boot command, verbatim

    fastboot -s 64f70df8 boot build/phone/rd-root.phone.sx.img

    Sending 'boot.img' (98304 KB)                      OKAY [  2.241s]
    Booting                                            OKAY [  0.084s]
    Finished. Total time: 2.424s

`build/phone/rd-root.phone.sx.img` (the 0105 image) at 09:49:18 UTC. The two earlier images were
booted with the same command line: `rd-root.phone.diag8.img` (09:30:07, stage-8 shim) and
`rd-root.phone.img` (09:34:23, `DIAG_STAGE=0`, pre-0105 kernel, sha256
`cf23fcc5d9c4ba20f79d4ec7f71b06770dea053f0b33c9347705011ce14deb18`). All three printed
`Booting OKAY` — the ABL parses and runs the v1 image.

## 5. What the shim ring says (this boot, real evidence)

    [3294 ] L SEGS n=0x000000000000000b end=0x00000001844c8000
    [3297 ] L BOOTARG pa=0x00000001844cc000 top=0x00000001844d0000
    [3299 ] L JUMP 0x000000018148c488
    [3300 ] L XNU jumping (fbcon clears screen)
    [3302 ] J ENTRYPA 0x000000018148c488

with `L SEG 10 dst=0x00000001824c8000 fs=0x0000000002000000 vs=0x0000000002000000` — the 32 MiB
ramdisk copied in. So the shim found the boot_args/FDT, copied 11 payload segments, and jumped.
`CHOSEN linux,initrd-{start,end}` show ABL loaded the 50 168 168 B ramdisk section at `0xb4e26000`.

## 6. Where it stops — and the honest problem

The kernel console ring **did not advance by a single byte** on either `md0` boot:
`sha256(kernel half) = 5be82cb26bea12dfeeb959c19485da28d432d0dc8d3e0dbe4718f54987afdbfa` in the
pre-boot pull and in both post-boot pulls, `total 8394 bytes, flush #4294967295` each time. The
text in it is from an **earlier** boot whose payload had 10 segments (`n=0xa`, no ramdisk) and
whose root was the UFS volume, and it ends at:

    BSD root: ufsroot0, major 1, minor 0
    jnl: b(1, 0): journal start/end pointers reset! (s 0x200 e 0x200)
    hfs: mounted iOSRoot on device b(1, 0)
    SWEET: root volume is not authenticated (error 25); continuing unsealed
    devfs_kernel_mount: kernel_mount failed: 2
    load_init_program: attempting to load /usr/appleinternal/sbin/launchd.development
    VM Swap Subsystem is ON
    load_init_program: attempting to load /sbin/launchd

`load_init_program: attempting to load /sbin/launchd` is the last console line on the handset so
far. No `exec launchd`, no `SWEET EXEC:` line, no panic line.

**There are zero `SWEET EXEC:` lines in the ring.** The reason is not "no failures" — it is that
the ring writer is initialised by the UFS driver (`SWEET UFS:` … `SWEET LOG: console log to the
last 4100 KiB …`), and this boot left no kernel bytes at all, so the kernel did not reach UFS
attach. On real hardware with the `md0` payload it stops *earlier* than QEMU's
`hfs: mounted RD-root`; it is not comparable to QEMU's dyld line yet. Where exactly it dies is not
in any ring, and there is no serial port on this phone.

> **Superseded by §10 (lane 7).** "XNU writes nothing" was true of the *ring*, not of the kernel:
> on the 10:13:49 UTC boot the panel reached `dyld: Library not loaded` while the kernel half of the
> ring still did not advance. The ring writer is UFS-initialised; the console on this build is
> fbcon-only. The stale UFS-boot lines below are unchanged and still stale.

QEMU, same rung, for the comparison asked for: md0 → `hfs: mounted RD-root` →
`load_init_program` → `exec launchd` → `dyld: Library not loaded: /usr/lib/libSystem.B.dylib` on a
`0104` kernel. The handset has not reproduced that line, and the 0105 `SWEET EXEC` list that QEMU
prints (64 lines, all errno 2, first `launchd.development`) has no hardware counterpart in this
ring. A "does it match byte for byte" answer would be an invention; the truthful answer is **no
data yet**.

## 7. Trap found: `build.sh` defaults to `DIAG_STAGE=8`, which never boots the payload

The first image was packed with `build.sh` defaults. It ran the full diag ladder and then:

    [674   ] - END park 60 s, then self-reset
    [677   ] - END log: tooling/42-log-pull.sh, docs/DIAG.md
    [66022 ] - END 60 s park over: PSCI reset

i.e. the stage-8 shim **parks 60 s and resets itself instead of jumping to XNU** (its ring is
`logs/phone/20261114-092548/ring-post.txt`). That image proves ABL acceptance but says nothing
about the kernel. The payload path needs `DIAG_STAGE=0`.

The same ring is also the best hardware constants dump we have: real `/memory` nodes
(`0x80000000`+`0x3bb00000`, `0x180000000`+`0x100000000`, `0xc0000000`+`0xc0000000`,
total `0x1fbb00000`), `cntfrq 0x124f800`, shim loaded at `0xa7e80000`.

## 8. ABL fallback behaviour (a bootloader fact QEMU cannot show)

After every `fastboot boot` the handset dropped off USB entirely and then **came back in fastboot,
not recovery and not a booted system**: 09:30:07 → recovery adb 09:32:19; 09:34:23 → fastboot
09:46:29; 09:49:18 → fastboot 09:53:18. `fastboot reboot recovery` then returned it to recovery in
12 s. So a `fastboot boot` here is safe to repeat: the fallback is always the bootloader, and
neither slot is touched.

## 9. Re-running it

    tooling/70-phone-boot.sh --image build/phone/rd-root.phone.sx.img     # ring pre, gate, boot, ring post
    tooling/70-phone-boot.sh --pull                                       # ring only (phone on adb)
    tooling/70-phone-boot.sh --image ... --reboot-only                    # stop in fastboot

If the phone is in fastboot and no adb is available, take the ring after
`fastboot reboot recovery` and label it with the boot time — the ring survives.

## 10. Lane 7 — the payload boot reaches dyld **on the panel** (fbcon-only console)

Boot 2026-11-14 **10:13:49 UTC** (= 11:13:49 CET; the panel observation is what the human
called "the 11:15 boot"). One boot in this lane, `fastboot boot` only, `boot_a`/`boot_b` untouched.

**Result, and it is a hardware first: the handset reached dyld.** The last line on the panel
after the jump was

    dyld: Library not loaded: /usr/lib/libSystem.B.dylib

which is **the predicted no-cache stop, not QEMU's current rung**. Correction added after the fact: the
boot image packed `build/rd-root.skeleton.img`, built with `--no-cache`
(`logs/61-mkrd-root-skeleton.log`: "cache omitted (--no-cache): dyld will stop with 'Library not
loaded'"; `payload-0105.log`: `shared_cache: None`), so the phone is one rung **behind** QEMU. QEMU
with the cache present maps it fine — `logs/qemu/20261114-094151` has zero `Library not loaded`,
reaches `Early boot complete`, and spawns 68 `xpcproxy`; in `20261114-103445-kern0105` the only
`shared_region` lines are two `check_np` (normal on first launch: empty region →
`KERN_INVALID_ADDRESS` → `ENOMEM`) and 43 `not in trust cache` warnings that `goto root_check` and
do not stop the map, with no `owned by uid`, `not SIP-protected` or `vnode_lookup` failure after
them. So the panel line proves the chain runs to dyld on hardware; it does not (yet) reproduce the
rung QEMU is on, because a 96 MiB boot image cannot carry a 2.6 GiB cache.

`DIAG_STAGE=0` is what changed it, and it was already in the artifact — this lane did **not**
need to fix the build (§7's trap had been hit and corrected by lane 6). Proof, from the file:

* the image's kernel section gunzips to exactly `build/phone/shim-out-d0/Image`
  (835 584 B, sha256 `3e3a84e5dae8168c6ffbb5e34420c0d8e722fab8e595500dbe7385d4fff11183`);
* that shim's `diag.o` is 1 136 B with only `diag_active/diag_run/diag_secondary/diag_stage_name`
  stubs, against 32 600 B for `shim-out-diag8/diag.o`, and the string `park 60 s, then self-reset`
  that stage 8 prints is absent (it is present in the stage-8 `Image`);
* an explicit `DIAG_STAGE=0` rebuild into `build/phone/shim-out-d0b`
  (`DTB=$PWD/src/avicii-soc.dtb OUT=$PWD/build/phone/shim-out-d0b DIAG_STAGE=0 ./avicii/shim/build.sh`)
  reproduced `Image.gz-dtb` **byte-identically** (`12312b049e21464069e34d03672985790c2e64d229a6a1b1e70d82766868288d`),
  so the existing image is a stage-0 build and the build is deterministic.

The image booted in this lane is a repack of those same sections (fresh AVB salt only):

    build/phone/rd-root.phone.sx.l7.img   100663296 B
    sha256 b1e095c4f39e169f6663e83535360b0ddb4e6ef60a8dbc64884206ffcd22c2cc
    gate: 100663296 <= max-download-size 805306368, PASS (704643072 B headroom)

It differs from lane 6's `604d979a…` image in **64 bytes at 0x3042188 only** (the AVB footer
digest; avbtool salts at random). Kernel, ramdisk, header and `id` are byte-identical.

## 11. The ring cannot carry this boot's evidence — and why

| pull | path | kernel half | shim half |
|---|---|---|---|
| t0, 10:08 UTC | `logs/phone/20261114-110843/ring-t0.txt` (+`.bin`) | 8 394 B, `feb2f633…07d4a` | `n=0xb`, `J ENTRYPA` (from lane 6's 09:49 boot) |
| post, 10:22 UTC | `logs/phone/20261114-1125-post/ring-post-boot.txt` (+`.bin`) | 8 394 B, `feb2f633…07d4a` — **unchanged** | **new**: kaslr-seed `0x1cf4391270287d68`, fresh rng-seed, `J ENTRYPA 0x18148c488` |

Method for the hash above (state it, because three different "kernel half" sha256s exist in the
repo for the same bytes): read the `SWEETLOG` header at block 1025 (`version 1`, `ring 4194304`,
`total 8394`, `flush #4294967295`) and sha256 the `total` bytes it describes:
`feb2f633b0453738d08d806448f90ac41989159f6b728cdf2a1d0f2f5ee07d4a`. The whole decoded file is
`e1e8bd63…` (same as lane 6's `ring-post-0105.txt`). `141f4853…d615` (STATUS) and
`5be82cb2…` (§6) do not reproduce from these two raw pulls under this or the obvious
alternatives — the content is the same 8 394 bytes; the numbers are stale conventions, not
different data.

Interpretation, exactly:

* **The shim's ring path works and this boot wrote to it** — different `kaslr-seed`/`rng-seed`
  from lane 6's pull prove the shim half is from 10:13:49, not stale. So the ring append itself
  is fine.
* **The kernel half did not move**, while the kernel demonstrably ran to dyld. The ring writer is
  initialised by `SweetUFS` (`SWEET UFS:` … `SWEET LOG: console log to the last 4100 KiB …`), and
  the `rd=md0` boot never attaches UFS, so nothing is flushed. **On this build the kernel console
  is fbcon-only** (`sweetfb_console=1`, `L XNU jumping (fbcon clears screen)`). Ring silence is
  therefore *not* evidence of early death, and any future `md0` verdict has to be read off the
  panel or off a kernel-side flush that does not depend on UFS.
* The `devfs_kernel_mount: kernel_mount failed: 2` line in the ring is **stale** (UFS boot); this
  lane cannot claim it appeared on the 10:13 panel. QEMU prints no such line, so if it *does*
  show on a future panel run it is a real hardware divergence worth chasing.

## 12. What the panel does while it waits (and the ABL fallback, timed)

* It **sits on the dyld line**. No auto-reboot, no panic text, no return to recovery on its own;
  the panel keeps that last line indefinitely.
* It leaves USB entirely for about two minutes, then **the ABL fallback brings it back in
  fastboot** — measured this lane: boot 10:13:49 → `fastboot devices` empty → fastboot again at
  10:15:56 (**+127 s**) → `fastboot reboot recovery` 10:17:36 → `adb devices` recovery 10:17:48.
  So expect roughly **2–4 minutes of blank USB, then fastboot**; `fastboot reboot recovery`
  restores recovery in ~12 s. Slot `b`, `product lito`, neither slot written.
* Recovery's adbd came back **`unauthorized`**: the RSA prompt was on the panel and needs a tap
  before `adb`/`42-log-pull.sh` works. `unauthorized` means "waiting for the human", not "no adb".
* `tooling/70-phone-boot.sh` used to report "phone is back in fastboot" 2 s after `fastboot boot`
  because the bootloader's USB interface lingers. It now settles 20 s before polling and has
  `--recover` (fastboot → recovery → ring) for exactly this sequence.
