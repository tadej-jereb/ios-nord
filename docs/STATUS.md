# Status — 2026-11-14 (evening), iOS 16.7 runs on the OnePlus Nord: GUI, keys and touch

The phone boots the real iOS 16.7.16 (20H392) root from `userdata` and shows the iOS GUI on its
panel, with working touch, power and volume keys. Every boot is a `fastboot boot` from RAM;
`boot_a`/`boot_b` were never written (LineageOS stays on `boot_b`). Image hashes, run dirs and
panel photos for each step are in `docs/IMAGE_PROVENANCE.md` (the table from "Phone boots on
the written root" on); the touch bring-up log is `logs/phone/20261114-194619-0110f-touch`.

Rebuild the working image: `tooling/71-phone-image.sh --preset touch --kernel avicii/shim/out/kernel-0110f`
(add `--boot` with the phone in recovery or fastboot).

How it got here, in order — each step was a wall a log named:

- **The real root boots in QEMU.** `build/ios16-root.img` as a 16 GiB `md0` did not mount
  (`hfs_mountfs: buf_meta_bread failed with 22`): memdev kept the size as a 32-bit page count
  shifted in 32 bits. **`0106`** widens it; run `logs/qemu/20261114-fullroot-d2`: mounts,
  `Early boot complete`, 160 Programs exec, no panic. This satisfied the userdata gate.
- **userdata written** (owner approved): `adb shell -T 'dd …' < build/ios16-root.img`, 42 MB/s,
  read back sha256-identical. `adb exec-out … <` does **not** forward stdin on adb 34.0.4.
- **fstab:** `/dev/ufsroot0 /private/var` made `mount-phase-2` re-mount the root → EBUSY →
  panic. Commented out on the phone and in the host image (now sha256 `a2e11e3e…ea0c`);
  `33`/`33b` write a comment-only fstab, `34` flags a second mount of the root.
- **launchd_cache_loader** aborts `Unable to find AMFI`: boot-arg `launchd_unsecure_cache=1`
  (same as the sweet port).
- **First boot of a fresh root** spends ~15 min building the LaunchServices database
  (SpringBoard blocked in `_LSContextInitCommon`); later boots reach SpringBoard in ~3 min.
- **GUI frames:** **`0107`** (empty `IOAcceleratorES`) and **`0108`** (SweetSurface wraps client
  memory), both from the fajita port; and `sweetfb_console=1` must never be on a GUI cmdline
  (`AppleCLCD::present()` drops every frame — `71` now refuses it).
- **Keys (`0109`):** volume PPIDs/offsets from the live FDT `gpio_keys` (PM8150L@4 gpio 5,
  PM7250B@2 gpio 3).
- **Touch (`0110`, `0111`):** SE7's I2C firmware has the FIFO interface disabled, so the GT9886
  is reached through gpi_dma1 with a stage-1 apps_smmu bank for SIDs 0x36/0x23; the 3.0 V rail
  (L13) is voted on HLOS's own RSC window (DRV2, 0x18220000 — sweet's 0x18200000 is DRV0 and
  reset the SoC) with the in-place cmd-db; the 1.8 V enable (PM8150L GPIO 1) is driven over SPMI;
  the chip protocol follows OnePlus's own GT9886 driver (ID 0x452C, frames 0x4100). Details in
  `docs/GOODIX_GT9886.md` §0.

Open, in rough order:

- Touch defaults: the working settings are still boot-args (`sweettouchrails=2
  sweettouch1v8=1`), touch starts 45 s after boot, and every bring-up step flushes the log with a
  200 ms pause. Make them defaults and drop the debug pacing. Accuracy at edges/corners not yet
  reported.
- No serial and no USB link: every log is a reboot to recovery. USB ECM/SSH (patches `0072`–`0077`
  exist, untested on avicii) would end that.
- Clock is 1969 (no RTC read), battery is a fixed 100 %, no Wi-Fi/BT/modem/audio, no GPU
  (CPU rendering at 10 Hz).
- Not flashed: making it boot without a computer means writing `boot_a` (owner's decision).
- `master` is ahead of the fork; kernel CI builds from `kern-0108-surface`.

# Status — 2026-11-14, tier-1 job Programs staged, and a failed exec now names itself (QEMU)

The silence after 34.87 s had two stacked causes: no daemon binaries in the root, and a failed
`exec` printing nothing at all. Both are now addressed — and the second is what makes the next
wall name itself instead of hiding.

- Staged (lane 2): `tooling/61-mkrd-root.sh --programs FILE`. Input `avicii/rd-root/tier1.txt`,
  12 entries verbatim → 9 Mach-O plus 294 files from the 3 recursed dirs (`SystemConfiguration`
  63, `UserEventPlugins` 103, `Lockdown` 128) = **303 staged, 12 213 650 B, 49 files 0755**. A path
  neither DMG has is fatal; Mach-O → 0755, else 0644; every file `cmp`'d against its DMG source,
  then re-asserted in the built image.
- Job table (lane 1, `avicii/rd-root/jobs-boot.tsv`, 532 rows): 532 table entries, **530** after
  the tweak, 488 with their plist staged, and **68** that launchd starts at boot without a client
  — 48 `RunAtLoad`, 10 `KeepAlive`, 10 `KeepAlive{SuccessfulExit:false}`, less `ClarityBoard`
  (`_LimitLoadToClarityMode`). Two corrections to the entry below: the tweaked table holds **530**
  jobs, not 528 (532 − 2 CommCenter; the 795 217 B byte count was right), and the two CommCenter
  `LaunchDaemons` plists are **still staged**, so that removal is table-only and they can load from
  the directory anyway. Also: `syslogd`, `sntpd`, `dhcp6d` are `Disabled:true`; `notifyd`,
  `securityd`, `mDNSResponder`, `diagnosticd` are on-demand, so a missing binary of those shows up
  as a hung Mach lookup, not as an `exec`.
- Image: `build/rd-root.progs.img`, 3 103 784 960 B, sha256
  `4352d893ff2cb5f8db3522d770df4d0b347380ae293aa2c0c0c28e83bfc9b0c8`; staging
  `build/rd-root.progs.stage`, 915 files. Gates: `34-check-bootstrap.sh` absent 0 / mismatch 0,
  `fstool check` clean (0 errors / 0 warnings), `fsck: ** The volume RD-root appears to be OK`,
  303/303 program paths `0:0` with 0 mode mismatches. `build/rd-root.img` and `build/rd-root.stage`
  untouched.
- Kernel: `xnu-avicii/patches/0105-sweet-exec-fail-log.patch` (sha256 `ef8e7815…ffc7`), one
  `printf("SWEET EXEC: %s failed errno %d\n", …)` in a helper at the single `bad_notrans:` exit of
  `exec_activate_image()`, behind `TUNABLE(bool, sweet_execlog, "sweetexeclog", false)`, plus the
  one-line `const char *excpath = NULL` the print needs. No existing boot-arg printed a failed exec
  (`exec_activate_image()` had zero `printf`; `execfailurecrashes` only adds crash reports). CI run
  `43579858647` on `tadej-jereb/ios-nord`, success, `97 patches applied in series order`, nothing at
  the new hunks. Kernel `avicii/shim/out/kernel/kernel.development.sweet`, 17 206 080 B, sha256
  `534248682bbc5cbb29e38033be872b3edfbbb84d45476f6cb12ad8e31779cf1e`; the pre-0105 kernel is kept at
  `avicii/shim/out/kernel/prev-20261113/`.
- Run A, flag off — `logs/qemu/20261114-103415-lane2`, same image, `--secs 300`, no panic:
  distinct Programs executed **3 → 8**. `UserEventAgent` 33.93, `logd` 34.57, `lockdownd` 34.69,
  `usermanagerd` 34.76, `notifyd` 34.77, `keybagd` 34.78, `configd` 34.79; `xpcproxy` 68 → 69;
  last timestamp 35.710722, still `timeout_printing`.
- Run B, the one this entry is judged on — `logs/qemu/20261114-103445-kern0105`, cmdline
  `rd=md0 sweettouch=0 sweetkeys=0 sweetfb_console=1 sweetecon=1 keepsyms=1 launchd_log_serial=1
  launchd_disable_all_timeouts=1 sweetexeclog=1 -v debug=0x144 cpu-factor=10`. Produced by kernel
  sha256 `5342486…cf1e` on image sha256 `4352d893…b0c8` (both re-checked after the run). **First
  line after 34.87 s:**
  `[   35.163515]: SWEET AKS: keybagd sel 0 arg0 0 in 0/0 out 0/0 -> 0x0`, then
  `[   35.331968] memorystatus_update(enter): pid 71 …`, then the 69th `exec xpcproxy` at
  35.332655. `Early boot complete` 31.853877, 77 exec lines, no panic, `timeout_printing`.
- What the exec log bought: **64 `SWEET EXEC:` lines, every one `errno 2`**, naming exactly the
  Programs the image does not carry — `sharingd`, `backboardd`, `amfid`, `SpringBoard`,
  `identityservicesd`, `CommCenter`, … `/usr/appleinternal` does not exist at all. The ring ends at
  `[   38.101006]: SWEET EXEC: /System/Library/CoreServices/OTACrashCopier failed errno 2` and
  prints nothing for the remaining 262 s; `bufx=53251` of 0x20000, so it did not wrap and nothing
  was lost. Launchd is waiting on daemons it cannot spawn, not crashing.
- Next wall, named: **tier 2** — the Programs lane 1's `jobs-boot.tsv` already lists, plus the
  bundle `Info.plist`/resources for the 26 that live inside frameworks (the cache does not carry
  those). The ramdisk ceiling is the limit, not the kernel: 3.10 GiB of a ~3.3 GiB budget.
- Harness (lane 4): `tooling/62-msgbuf-summary.sh` judges a run from `msgbuf.txt` (never
  `screen.txt`); `60` now mints `<stamp>-N` run dirs and a per-run gdb port, so two boots can run
  at once. 62 also had to be fixed before it could be trusted: it read `Early boot complete` only
  at a line start, and the kernel spliced that marker onto a truncated `so_gencnt` fragment in
  Run A, so it reported `NOT REACHED` for a run that had reached it. It now scans every line and
  labels the hit `line` / `inline` / `spliced, no own timestamp (between T1 and T2)`; Run A
  reports `32.388308` (lower bound of 32.388308..32.433246) and the two older baselines are
  byte-identical to before, 31.700474 and 31.055028. `exec` extraction got the same treatment
  afterwards (match anywhere in the line, one count per occurrence, name stops at whitespace or
  `[`), and all four runs' counts are unchanged — 69/68/0/69 xpcproxy — so the counts above stand.
- Phone (lanes 6 + 7, finished): non-destructive only, nothing flashed, no `dd`; the handset ends in
  recovery on authorized adb. **The ABL accepts our header-v1 image: 4/4 boots**, each printing
  `Sending 'boot.img' (98304 KB) OKAY` / `Booting OKAY`. Last image
  `build/phone/rd-root.phone.sx.l7.img`, 100 663 296 B, sha256 `b1e095c4…22c2cc`, differing from
  lane 6's `604d979a…a01f2` in 64 bytes at `0x3042188` (AVB salt) with identical sections. Gate:
  96 MiB vs `max-download-size` 805 306 368; slot `b`; `product lito`; recovery is root adbd.
- **The shim runs and jumps on hardware**: `L SEG 10 dst=0x1824c8000`, `L SEGS n=0xb
  end=0x1844c8000`, `L JUMP 0x18148c488`, `J ENTRYPA 0x18148c488`, with a fresh `kaslr-seed` per
  boot — so the ring's append path works and the loader is not what is failing.
- **`DIAG_STAGE` was already 0 in the booted image** — proven from the artifact, not assumed: its
  kernel section gunzips to exactly `build/phone/shim-out-d0/Image` (835 584 B, `3e3a84e5…`),
  `diag.o` is 1136 B of stubs against 32 600 B for stage 8, and an explicit reconstruction is
  byte-identical (`12312b04…`). The caveat still stands for future builds: `avicii/shim/build.sh`
  defaults to `DIAG_STAGE=8`, which parks 60 s and `PSCI reset`s instead of jumping.
- **The panel is the console, and it stops one rung behind QEMU**: `dyld: Library not loaded:
  /usr/lib/libSystem.B.dylib`. That line is the *predicted no-cache stop* — the boot image packed
  `build/rd-root.skeleton.img`, built `--no-cache` (`logs/61-mkrd-root-skeleton.log` says so;
  `payload-0105.log` reads `shared_cache: None`), and 96 MiB cannot carry a 2.6 GiB cache. QEMU with
  the cache maps it fine: `20261114-094151` has **zero** `Library not loaded`, reaches
  `Early boot complete` and spawns 68 `xpcproxy`. The `check_np` failures are normal on first launch
  (empty shared region → `KERN_INVALID_ADDRESS` → `ENOMEM`) and the 43 `not in trust cache` lines
  `goto root_check` rather than failing, with no `owned by uid` / `not SIP-protected` /
  `vnode_lookup` line after them. So there is no shared-region kernel bug to fix; the handset has to
  be given a root that contains the cache. The handset **sits** on that line; the ABL falls back to
  fastboot at **+127 s**, and `fastboot reboot recovery` restores recovery in ~12 s (adbd is
  `unauthorized` until the RSA prompt is tapped on the panel).
- **Why the ring misses it:** the kernel half of the ring is byte-identical before and after the
  boot — 8394 B, sha256 `feb2f633…ee07d4a` on both pulls — because the ring writer is
  `SweetUFS`-initialised and an `rd=md0` boot never attaches UFS. Console on hardware is therefore
  **fbcon-only** for this build, and ring silence is not early death. (The `141f4853…` figure in an
  earlier revision of this entry came from a text-slice convention and does not reproduce from the
  raw pulls; use `feb2f633…` over the 8394 bytes.)
- Not established: whether `devfs_kernel_mount: kernel_mount failed: 2` is on the panel for this
  boot — that line in the ring is stale UFS-boot content, and no ring byte changed. Needs an eye on
  the screen.

- Toolchain: `fstool` 0.5.4's hard-link `chown` bug is **fixed and installed**. Root cause: `chown`/`chmod`
  on a hard-linked file wrote the `hlnk` placeholder record (whose BSDInfo fields are the chain's
  prev/next CNIDs) instead of the shared `iNode<N>` record the mounted view reads, so it returned
  `rc=0` and changed nothing. Fixed binary `tooling/opt/fstool/bin/fstool` sha256
  `f837e4d1baa236a00ddce44b2c8adbfd7905daa11585d85bada4152aaac40c79`, old one kept as
  `bin/fstool.prev-45edb6ce` (`45edb6ce…`), `.sha256` updated, fix-only patch at
  `tooling/opt/fstool/fstool-0.5.4-hardlink-chown.patch`; full suite green in a 12 GB scope (48
  binaries, 2165 passed, 0 failed, 7 pre-existing ignores — note 5 test files are `target_os=macos`
  and compile to 0 tests here). Proof: 86 names (43 cache files + 43 `private/var/db/.rdcache`
  partners) moved to `501:501` and back to `0:0`, `nlink 2` throughout, surviving unmount+remount,
  with the whole-volume owner map byte-identical otherwise, `fsck` OK, `fstool check` 0/0.
  Correction to the older entry below: the **image** already carried the cache as `0:0` because `61`
  runs `fstool create` under `fakeroot`; the `1000:1000` was the *staging tree*. What the fix buys is
  a real `chown` after the fact — needed to reproduce the phone's `0:80` — and one caveat: fstool's
  FUSE layer caches sibling link names, so a hard-link chown must be verified after a remount, not in
  the same session.
- Rebuild with that binary: `build/rd-root.progs.v2.img`, 3 103 784 960 B, sha256
  `b8f0bbab8dac2e4bd33558da79f586d309a561647ae0bd4f28fd266885d0636e`, gates `absent 0 / mismatch 0`,
  `fstool check` 0/0, `fsck` OK; `build/rd-root.progs.img` (`4352d893…`) left untouched. Its boot
  `logs/qemu/20261114-113410-v2-cachechown`: early boot 32.025554, 69 xpcproxy, `configd`,
  `lockdownd`, `logd`, `UserEventAgent`, `notifyd` exec, none lost against the baseline, no panic.


- **Tier 2 boots and kills the ENOENT wall** (`build/rd-root.tier2.img`, 3 270 508 544 B, sha256
  `ce8eb192f1232a3e1a2bdf6fa3f51a3889928a2e4554a54cc9ec58fb705b4886`, 393 staged entries, 112 exec
  0755, set in `avicii/rd-root/tier2.txt`). `QEMU_MEM=8G` moves the guest dram to **5 735 MiB**
  (`dram 0x90000000+0x16f100000`), which is what lifted the ceiling — not the kernel. Run
  `logs/qemu/20261114-115454-lane9`: **0 `SWEET EXEC` failures out of 227 execs**, and real services
  now exec — `containermanagerd` 157.04, `passd` 157.19, `tccd` 157.41, `SpringBoard` 159.26,
  `biomed` 160.33, `nfcd` 164.43, `UserEventAgent` 165.13, `fairplayd.H2` 167.18 — 106 `xpcproxy`,
  last line at 293.044 s, no panic. Not cut, for the record: `launchd.development` and
  `HorizonSetup` do not exist in either DMG (`/usr/appleinternal` is absent from 20H392), `sntpd`
  absent, `AppleCredentialManager.framework` ships without an `Info.plist`.
- **Next wall, named: dyld4 aborting on garbage.** 53 of 80 crash reasons are one dyld pc inside the
  shared cache (`0x1a9b70ee4`) with `reason ns 6 code 0x9: file does not start with MH_MAGIC[_64]:
  0xFF000000 0xFF000000` (SpringBoard, nfcd, UserEventAgent); `tccd` additionally dies `sig 5` brk in
  its own text, `passd` SIGABRTs right after its AKS calls succeed. Those 4 bytes appear in **no**
  staged file, so the suspect is what dyld read, not a missing path. Because every service dies,
  launchd throttles each at ~10 s and **no `Boot task` line is ever printed** — the boot tasks have
  not been reached yet.
- Two candidate causes tested, one dead: `maxmem=5800` (`logs/qemu/20261114-123417-maxmem`) so the
  VM's free pool stays below the framebuffer (`0x1fe000000`) and panic log (`0x1ff000000`) left the
  crash count at **exactly 53**, with `fb.raw` byte-identical to the lane-9 run — the
  framebuffer-page-overlap theory is **falsified** (the boot-arg was verified live: `arm_init`
  parses `maxmem`, `arm_vm_init` shrinks the pool, top `0x1fa800000`). The surviving candidate is
  the **early console**: patches `0010`/`0012` write to a hard-coded physical `0xa0000000`
  (`EARLY_FB`, the stage-0 band, and `sweet_early_clear_row` painting `0xff000000`), while the
  ramdisk is mapped at `0x924c8000` and extends far past that address — i.e. the kernel paints over
  its own root image, including cache subcache `.33` at file offset `0x19b3000`. **Tested: it is the
  cause.** The same boot with `sweetecon=0` (`logs/qemu/20261114-130037-econ0`) has **0** MH_MAGIC
  crashes against 53, with the kernel logging normally (131 072 B ring, 1616 timed lines, 174 s
  window, 272 execs), and the corpse loop moving to `tccd`/`passd`/`assistantd` instead. Caveat
  stated honestly: the ring's window began at 127.5 s, so `SpringBoard`/`nfcd`/`UserEventAgent`
  never appear in it — they did not crash, but they were not observed launching cleanly either; a
  220 s run is confirming that. The durable fix is to place the ramdisk above the band
  (`0xa0200000`), not to leave `sweetecon=0` on. **Fixed**: `avicii/tools/mkpayload.py` (+49/−7) now
  places the ramdisk at `RAMDISK_CLEAR` = `0xa1000000` whenever `kernel_end` is below
  `RAMDISK_FLOOR` = `0xa0200000`, with a `--ramdisk-addr` override, 16 KB alignment and kernel-overlap
  errors, and the ADT `/chosen/memory-map RAMDisk` gets the address actually used. Why not the floor:
  the band is 2400 rows × 4320 B = 10 MB (`0xa09e3400`), so `0xa0200000` still paints the volume
  header at image offset `0x400`; `0xa1000000` is the 16 MB-clear target. Proven at `sweetecon=1`
  (`logs/qemu/20261114-133508-econ1-hole`): **0 MH_MAGIC crashes**, 0 `0xFF000000` tokens, no panic,
  ramdisk PA `0xa1000000` VA `0xfffffe0017000000` size `0xc2f00000`, top `0x163f00000` under fbcon.
  Honest caveat: both 220 s runs wrapped the ring and the first exec wave (~32 s) is outside the
  window, so "SpringBoard/nfcd/UserEventAgent survive" rests on the baseline's 5 s retry cadence
  being absent from the identical interval, not on visible exec lines.
- Harness, two real defects found by that run, both now fixed: the 128 KiB ring **wraps** under the storm
  (log started mid-record at 157.000176 s and the early boot was gone, so `62`'s `early boot: NOT
  REACHED` was an artifact), and `msgbuf=1048576` was honoured by the kernel
  (`msgbuf_size 0x100000`, `bufx 0x5b41c`) but `dump_msgbuf()`'s `k2p()` read zeros, writing a 0 B
  `msgbuf.txt`. `62` now reports `ring: FULL - RING WRAPPED` with the `window`/`MISSING` split and
  marks every count `window only` (verified on the lane-9 run; five reference runs byte-identical,
  counts unchanged), and an empty dump reads `EMPTY DUMP - 0 B` instead of `NOT REACHED`. `60` now
  translates the ring **per 16 KiB page** through the page tables (`_cpu_ttep`, 16K and 4K shapes,
  block descriptors, `MSGBUF_TTBR1=` override) with a RAM-scan fallback, records what it did in
  `console_flags.json`, and exits **4** when `msgbuf=` is set and the dump comes out empty. Still
  open there: the walk's `_cpu_ttep` is not the live `TTBR1_EL1` (trace
  `L0:tbl=0x1553d4000,i=1,d=0x0`), so a 1 MiB ring needs `--gdb` + `register read ttbr1_el1` and
  `MSGBUF_TTBR1=` before it can be read directly.


- **Trimmed dyld cache for the phone's fastboot budget: two attempts, both rejected for one
  measurable reason.** `docs/CACHE_TRIM.md` is the rule set recovered by disassembling the shipped
  `usr/lib/dyld` (dyld-1067, `llvm-objdump`), which is what makes it usable: `preflightCacheFile`
  (`0x3a48c`) enforces **1 ≤ mappingCount ≤ 8 per file** at `0x3a600`, mappings ascending in VM and
  contiguous in file, `[R|X][R|W]*[R]`, signature as the file tail with
  `codeSignatureOffset+Size == st_size`, and `F_ADDFILESIGS_RETURN` validated by the kernel. Attempt
  1 (single file, 143 mappings) failed the count; attempt 2 (15 files, Apple's split shape, 289 MB)
  passed every rule for main and `.01`–`.12` but its `.41.dylddata` had **32 mappings** → rejected.
  Both rejections are **silent by design**: the only print is `dyld cache '%s' not loaded: %s` gated
  on `cacheFileFound`, and sub-cache error messages are discarded, so a sub-cache failure prints
  `… (null) (null)` to `/dev/console` — which is disabled on these runs (`disableConsoleOutput: 1`).
  Patch `0047` does append those bytes to `_sweet_log_ring` (`0xfffffe0007c525f8`, 4 MiB) before the
  gate, so the reason is in guest RAM and simply is not dumped yet. Follow-ups: re-split the data
  sub-caches to ≤8 mappings per file (gaps are ≥ 0.73 MiB, so the shapes fit; +8…108 MiB depending on
  how many files) and dump `_sweet_log_ring` in `60`. Also queued in that doc: `dynamicDataOffset` is
  0 in our rebuild and collides with the main header VA, and `reuseExistingCache` expects
  `dyld_data    v0` config data there or the `DyldCache` ctor halts.
- **The silence is broken and it corrects the guess above.** `60` now dumps patch `0047`'s
  `_sweet_log_ring` to `sweetlog.txt` / `sweetlog.raw` (`_sweet_log_ring` `0xfffffe0007c525f8`,
  `_sweet_log_total` `0xfffffe0007c525f0`, PA `0x91c525f8`, read `linear`; counters in
  `console_flags.json`, exit 5 if it reports bytes but dumps none; `62` prints
  `sweetlog: N B … dyld rejected the cache Nx`). First real use, run
  `logs/qemu/20261114-141314-lane4-sweetlog2` with `cachetrial2`, gives dyld's own words:
  `unable to create a validated cs_blob object: 85` then `dyld cache '(null)' not loaded: code
  signature registration for shared cache failed`. So the rejection was the **kernel refusing the
  ad-hoc signature at `F_ADDFILESIGS_RETURN`**, not the `mappingCount ≤ 8` rule — that chain remains
  a static reading only. Also established: the sweetlog ring is *not* a superset of msgbuf — it
  lacks 82 early kernel lines and carries userland output (`Darwin Ignition Sequence`,
  `libignition: …`) that msgbuf never had.
- Lane 8c rebuilt the cache against the recovered rules anyway: 19 files, 55 mappings, max 8 per
  file, `dynamicDataOffset` `0x9a0b8000`, image `build/rd-root.cachetrial3.img` 290 455 552 B sha256
  `e4a8e9cde65728c5b5deed586c10a80593632be42d3451d579f046725c56d91f`, 514 850 816 B of headroom,
  all offline checkers PASS (`validate3.py` on `cachev3`, and it reproduces `cachev2`'s two rejects).
  Unproven: kernel acceptance of the dyn-config mapping at `SR+0x9a0b8000`, 55 mappings in one
  syscall, and everything after the map.
- `cachetrial3` booted (`logs/qemu/20261114-142450-l8cache3`) and is rejected at **the same line,
  errno 85**, as `cachetrial2`: `unable to create a validated cs_blob object: 85` →
  `code signature registration for shared cache failed`, on the **main** file, before any sub-cache
  and before dyld's first `map()` print (zero `map(` lines, zero `not in trust cache`; the one
  `trust cache` hit is the unrelated early `SWEET: trust caches unavailable`). So lane 8c's ≤8-mapping
  work is not implicated and has not been exercised yet: the wall is **stock XNU's
  `ubc_cs_blob`/`cs_blob_create_validated` refusing an ad-hoc cache blob**, which happens before sweet
  AMFI's `vnode_check_signature` hook (patch `0036`) ever runs. Next: make the blob pass, or patch the
  kernel to accept it — being worked as a kernel-source question, and any `0106` patch will be held for
  review before CI.
- **The cache's signature is now accepted — the wall moved one layer up.** After a re-signing pass
  (CD version `0x64` → the `≥ 0x70` XNU wants) `cachetrial3` came back as `sha256 d32ff8d7…dc1d1a`
  (290 455 552 B) and in `logs/qemu/20261114-144000-l8cache3b` the kernel accepts it: **no
  `EBADEXEC`, no `validated cs_blob` failure**, and dyld maps **all 19 files** —
  `map(…)`/`not in trust cache` count 19, one each for main, `.01`–`.12`, `.41`, `.43`–`.46` and
  `.42.dyldlinkedit`. What still fails is dyld's *own* lookup:
  `Library not loaded: /usr/lib/libSystem.B.dylib … (no such file, not in dyld cache)` at 30.6 s, so
  pid 1 exits before spawning anything (`xpcproxy` 0 vs baseline 68). `not in dyld cache` is a lookup
  miss, not a mapping failure — so the remaining suspect is the rebuilt `dylibsTrie`/image index, not
  the trim's mapping shape or the signature.
- **Two cache bugs found and fixed, and the cache now maps completely — then dyld write-faults.** The
  trie was in a node layout dyld cannot parse (child lists terminated with `0x00` instead of a
  `childrenCount` byte, so dyld read `/` as "47 children"; `imagesText` also used a 40-byte stride for
  a 32-byte struct) — and the builder's checker shared the wrong convention, so it passed. Fixed and
  re-signed (the header edit invalidates the signature: CD `0x64` → `0x20400`), `kcheck`/`csck`
  (page hashes, 0 bad)/`triecheck`/`validate3` all pass, `libSystem.B` → index 32, `libobjc` → 0,
  37↔37 bijection. Image `build/rd-root.cachetrial3.img` `4dd9068132a9…7d63b504f0`. Boot
  `logs/qemu/20261114-152352-l8cache3d`: **19 `map(` lines, no EBADEXEC, no `not loaded:` at all** —
  then `pid 1 exited -- exit reason namespace 2 subcode 0xb` 0.1 s later, two EL0 **write** aborts in
  `qemu.log` (`FAR 0x1e1d345c8` inside `.45.dylddata` at file offset `0x2b05c8`, in-file and valid, then
  `FAR 0x201e1d34628` in an unmapped hole). So the trim's remaining problem is the data mapping's
  protection/population, not the index — being chased offline against Apple's mapping records and the
  kernel's `vm_shared_region` map path.

- **The two remaining crash loops are symbolized, and neither is a kernel bug.** Correction to how we
  read these logs: the `pc` in a `CRASH` line is **slid** — unslid = `pc − 0x32a3c000` (patch `0043`
  says so) — and `ns 2` is `OS_REASON_SIGNAL` (`bsd/sys/reason.h`), not `EXC_BAD_ACCESS`, so
  `code 0xb` = SIGSEGV and `code 0x6` = SIGABRT. No `.symbols` sidecar ships in the RAMDisk cache
  (`RAMDISK_ROOT.md:88`: the 592 MB file was left out), so symbolication went through the cache's
  `imagesText` table plus each image's own symtab.
  - `containermanagerd`: unslid `0x186e626cc` = CoreFoundation `+0x7a6cc`, instruction
    `add x8,x0,#8; ldar x8,[x8]`, i.e. `CFDateFormatterCreate` returned **NULL** and the caller
    dereferences it at `+8`; the chain comes from `_CFDateFormatterCreateISO8601Formatter+0x328`,
    which null-checks the format string but never the formatter. Cause: the root has **no `/usr/share`
    at all** and `libicucore` hardcodes `/usr/share/icu/`. Test: stage `/usr/share/icu` (+ `zoneinfo`).
  - `passd`: unslid `0x1c2617198` = `libsystem_kernel +0x7198` = `___pthread_kill+0x8` (`svc #0x80`),
    chain `abort+0x7c → libc++abi → std::terminate → libdispatch → PassKitCore+0x19e18`, i.e. an
    uncaught exception during PassKitCore's first-use init. The reason was not captured because
    `sweetscan` defaults to `backboardd,SpringBoard`. Test: `sweetscan=passd` and read its `STR` lines.
  - They are unrelated causes that merely share the same skeletal rootfs.

- **tccd's `brk #1` is `confstr` failing, and the obvious fix did not work.** Symbolized: `pc − mh =
  0x2E390` is `brk #1` (`0xd4200020`) after `__os_crash("confstr failed to get directory")` inside
  `-[TCCDServer setupTemporaryDirectoryForName:]`, reached from a `cbz` that tests
  `confstr(_CS_DARWIN_USER_TEMP_DIR)`'s return; 66/66 crashes at the same instruction, `far` is
  `mh + 0x154000` (past its `__LINKEDIT`, and unstable) so it is noise from patch `0043`, and tccd is
  past AMFI, dyld, ObjC and `_set_user_dir_suffix` — `sandbox_init` is *after* the crash point.
  `61` gained a default-off `--vardirs` that stages `private/var/folders` (0755 0:0),
  `private/var/mobile` (0700 501:501), `private/var/mobile/tmp` (1777 501:501) and `private/var/root`
  (0700 0:0); the built `build/rd-root.tier2b.img` (sha256 `6f159a3c…0961af`) was booted once
  (`logs/qemu/20261114-143327-vardirs`) and **tccd still crashes 80/80 at `0x2E390`** — base
  directories are not what `confstr` needs. Also unchanged there: `assistantd` 9 / `passd` 8 at the
  same cache `abort()` pc, `SpringBoard`/`nfcd`/`UserEventAgent` still never exec, and
  `containermanagerd` joined the corpse loop (sig 11, `far 0x8`). Next lever is the *resolved*
  per-user path — libsystem's `DIRHELPER_USER_DIR_*` environment overrides on the job plist — under
  test, rather than more static tree.
- **The `confstr` wall was a read-only root, and fixing it moves the ladder by a whole stage.**
  Lane 2 verified against this root's own libsystem that no `DIRHELPER_USER_DIR_TEMP/_CACHE/_LIBRARY`
  strings exist at all — `confstr` reads `TMPDIR` and then `P_tmpdir`, each gated by `access(W_OK)`.
  On a **read-only** `md0` that access check cannot pass, so `confstr` returned 0 no matter what the
  tree contained or which env var was set. With `rootrw=1` (patch `0031`'s boot-arg, already in this
  kernel) in `logs/qemu/20261114-150056-tccdenv-rw`: **0 `CRASH tccd`** (was 80/80), tccd spawns at
  34.1 s in `user/501` and is still alive at 150 s, `Read-only file system` errors 4 → **0**, and
  **71 distinct exec names vs 7** — `SpringBoard` 32.6 s, `UserEventAgent` 36.5, `nfcd` 37.8, plus
  `backboardd`, `runningboardd`, `notifyd`, `logd`, `amfid`, `configd`, `CommCenter`. `61` also gained
  a default-off `--jobenv LABEL:VAR=VALUE`. Remaining crashes in that run: `containermanagerd` 48
  (`sig 11`, `far 0x8`, pc `0x19d5e66cc`) and `passd` 40 (`ns 2 code 0x6`). Caveat: that boot moved two
  variables (job `TMPDIR` env **and** `rootrw=1`), so a pristine-plist `rootrw=1` boot is queued to
  prove the env is redundant. Consequence for the phone: its `md0` root is likewise read-only, so this
  affects hardware too, not just QEMU.

## Gate: "the same root has booted in QEMU" — options, none chosen

`docs/IMAGE_PROVENANCE.md:416` asks for the same root to have booted in QEMU; QEMU's dram is
3.74 GiB (`dram 0x90000000 + 0xef100000`) against a 16 GiB image, so it cannot be met as written.
`build/ios16-root.img` sha256 `8654ec2b…70a0` before and after this analysis; `fsck.hfsplus -n`
says the volume appears OK. The decision between these is the owner's:

- **A — root on QEMU's UFS through the phone's own driver** (`-device ufs` + `patches/0028`,
  `rd=ufsroot0 ufsroot=userdata`). Highest fidelity: same 16 GiB bytes, same driver. Cost: a
  `/sweet-ufs` ADT node (`mkadt_avicii.py:62,409` omits it and the kernel has **no PCI
  enumeration**, so the BAR must be pinned by hand), a host-bring-up path the driver lacks
  (`0028:309-311` only checks `hce/hcs`; QEMU's model comes out of reset), a GPT-wrapped disk with
  a partition *named* `userdata`, plus a kernel rebuild.
- **A2 — virtio-blk / AHCI / NVMe.** The kernel has no storage family and no PCI at all (0 symbols
  for `IOMedia`, `IOBlockStorageDevice`, `AppleAHCI`, `AppleNVMeController`, `IOPCIDevice`). New
  driver + `IOKitBSDInit` hook + CI kernel; proves the bytes on a device the phone does not have.
- **B — the RAMDisk as it stands** (`build/rd-root.img`, boots today). Proves the file set, not the
  volume: HFS+ unjournaled 2.88 GiB on `md0` vs HFSX journaled 16 GiB on UFS. Free. Variant B′
  (rebuild that RAMDisk by reading `ios16-root.img`) narrows "same files" but still not the volume.
- **C — reword the gate** (one clause, `:416`), e.g. "the same root *tree* has booted in QEMU".
  Nothing to build; risk moves to the phone, mitigated by `36` → `READY TO BOOT`, fsck OK, the
  1 GiB rollback `build/final-1g.img`, and the fact that the console ring lives in the last 1025
  blocks of `userdata`, which a 16 GiB root write never reaches.
- **D — the real 16 GiB image as `md0` with a bigger guest**: `60-qemu-boot.sh --ramdisk
  build/ios16-root.img --mem 20G`. No code change (19G is the floor; 20G leaves 1.74 GiB dram).
  Unverified: memdev/mockfs at 16 GiB, and the volume's own `fstab` names `/dev/ufsroot0`. Costs
  ~20 GiB guest RAM in one scope and ~48 GiB of run-dir writes, minutes per run.
  **Now measured and it fails**: `logs/qemu/20261114-fullroot-d1` (orphaned run, `--mem 22G`,
  `rootrw=1`) mounts nothing — `BSD root: md0` then
  `hfs_mountfs: buf_meta_bread failed with 22` / `hfs_mount: hfs_mountfs returned error=22 for device
  unknown-dev`, retried every 7 s to 170 s. So D is not a working route as stated; the first metadata
  read returns `EINVAL`, a different wall from the dram ceiling, and nobody has investigated it.


# Status — 2026-11-14, launchd spawns jobs after "Early boot complete" (QEMU)

The jobs handoff is closed and removed. The 270 s of silence after `Early boot complete` was not a
hang: the RAMDisk root had no job table and no job plists, so launchd had nothing to spawn.

- Fix: `tooling/61-mkrd-root.sh` has a new step after the cache that stages
  `/System/Library/xpc/launchd.plist`, the 491 `/System/Library/LaunchDaemons/*.plist`, the one
  `/Library/LaunchDaemons/*.plist`, and the empty scan directories `NanoLaunchDaemons`,
  `NanoLaunchDaemonsAltAccount`, `DeveloperModeLaunchDaemons` (`LaunchAgents` was already there).
- Which table: the **tweaked** one. `61` replays the two edits of
  `refs/ios-sweet/sweet-root-tweaks.py` on the DMG copy (7 `_PanicOnCrash` -> `_PanicOnCrasX`,
  2 CommCenter jobs removed, 528 jobs left, 795 217 B), so it equals the table in
  `build/ios16-root.img`. The stock table was not booted. The job plists are byte copies.
- Build: `34-check-bootstrap.sh` absent 0 / mismatch 0, 612 files, `fsck_hfs` clean,
  `build/rd-root.img` 3 090 153 472 B, sha256
  `0e247ac47216a7c21167e00d66ad388351676163aeecc3c2489c190e8aec725a`.
- Result, `logs/qemu/20261114-094151` (`msgbuf.txt`, 300 s, 45.7 KB against 14 KB before):
  after `Early boot complete` at 31.70 s launchd opens its listeners (tcp 49152, 62078), spawns
  **68 `xpcproxy`** (pids 3-70) between 32.18 s and 33.32 s, and two of them reach their job:
  `exec keybagd` (34.516 s), `exec usermanagerd` (34.548 s), then
  `SWEET AKS: keybagd sel 0 arg0 0 in 0/0 out 0/0 -> 0x0` at 34.87 s. **No panic.**
- Next wall: nothing is logged from 34.87 s to 300 s. The other 66 `xpcproxy` have no Program to
  exec - this root carries only the 21 boot-table binaries - and a failed exec in `xpcproxy`
  prints nothing to the kernel log. That is silence *with* the plists staged, and its cause is
  the minimal set, not launchd: the RAMDisk rung cannot go further without daemon binaries
  (`logd`, `notifyd`, `configd`, ... each with its frameworks already in the cache). The phone
  image has all of them.
- Harness: the memory scope does not need sudo. `systemd-run --user --scope -p MemoryMax=12G -q --
  /bin/sh -c '... ./tooling/60-qemu-boot.sh ...'` gives the same cap and leaves the run
  artifacts owned by the user, so the `chown` step drops out.
- Phone: untouched. No `dd`, `build/ios16-root.img` not opened.
- Next: `HANDOFF-HERMES-DAEMONS.md` (five parallel lanes: job map, tier-1 daemons on the RAMDisk,
  exec-failure log, run summary + parallel-safe harness, `userdata` gate options).

# Status — 2026-11-14, launchd reaches "Early boot complete" (QEMU)

The `/etc` handoff was closed in the same session it was written. launchd no longer exits with
`unable to resolve 'mobile'`: the RAMDisk root was missing the BSD root links.

- Cause: `build/rd-root.stage/` top level was only `dev private sbin System usr`, so `/etc/passwd`
  did not exist even though `private/etc/passwd` lists `mobile:501`. libinfo's file module reads
  through `/etc`, so `getpwnam("mobile")` failed and launchd exited `namespace 7 subcode 1`.
- Fix: `tooling/61-mkrd-root.sh` now makes the three root links (`etc -> private/etc`,
  `var -> private/var`, `tmp -> private/var/tmp`) beside the five cryptex roots. Rebuild is
  unchanged: `./tooling/61-mkrd-root.sh`, `34-check-bootstrap.sh` still absent 0 / mismatch 0,
  `fsck_hfs` clean, `build/rd-root.img` sha256
  `c2021b9a442c2d3b283ef78eff32a33661b9d37ef8a9f7d24c1df72a465e80a9`.
- Result, `logs/qemu/20261114-092612` (`msgbuf.txt`, 90 s) and `-092833` (300 s): all 43 cache
  subcaches map, `SWEET Sandbox: launchd op 4`, `SWEET NET: launchd lo0 add address 127.0.0.1`,
  the whole boot-task ladder runs, and launchd prints
  `[Event: boot] Early boot complete. Continuing system boot.` at 31.05 s. **No panic.**
- Next wall: silence after that line — 270 further seconds produce no kernel or launchd message
  and no panic. Whatever launchd does after "continuing system boot" (job spawn, `/dev/console`,
  the data-volume task) is the rung to instrument next; `msgbuf.txt` is the channel and
  `logs/qemu/20261114-092833/` is the baseline to diff against.
- Not yet reproduced on hardware: the phone still has the 16 GiB image written by nothing (no
  `dd` yet) and `build/ios16-root.img` sha256 `8654ec2b…` unchanged.

# Status — 2026-11-14, dyld shared cache maps (QEMU)

The dyld wall (`Library not loaded: /usr/lib/libSystem.B.dylib
… (no such file, no dyld cache)`) is closed in QEMU, run `logs/qemu/20261114-070727`.

- Cause: the kernel refused the cache, it did not fail to find it. Without trust caches XNU
  maps a shared cache only when it is owned by uid 0 (`bsd/vm/vm_unix.c` `root_check`), and
  `build/rd-root.img` carried the cache hard links as `1000:1000` (`tooling/61` built it
  unprivileged; fstool cannot chown a hard link). Kernel log:
  `map('dyld_shared_cache_arm64'): owned by uid=1000 instead of 0`.
- Fix: `tooling/61-mkrd-root.sh` runs `fstool create` under `fakeroot`, so every record,
  hard links included, is created `0:0`; its probe now asserts the cache is `0:0`. New
  `build/rd-root.img` sha256 `5e48f808e018b07bb2d113463606abdc19284523b9291e49f1df5a24269cfa6c`.
- The phone image is not affected: `build/ios16-root.img` (populated as root by `tooling/33`)
  has the cache at `0:80`; read-only loop check, sha256 unchanged.
- Now: all 43 cache files map, libSystem loads, launchd runs to `lo0 127.0.0.1` and exits
  `namespace 7 subcode 0x1: unable to resolve 'mobile': 114 - The specified username does not
  exist`. `rd-root.img` has no `/etc`, `/var`, `/tmp` symlinks (the phone image has all three).
- Kernel log channel: `tooling/60-qemu-boot.sh` now writes `msgbuf.txt` (the kernel message
  buffer read from guest RAM) and `console_flags.json` after every run. The framebuffer
  console is blank in the high-framebuffer `--ramdisk` layout (`gc_graphics_boot=1`,
  `disableConsoleOutput=1`: the kernel boots graphical, only the progress bar draws); with the
  old layout (`--mem 2592M`, fb `0xa0000000`) text renders. Use `msgbuf.txt`, not `screen.txt`.

# Status — 2026-11-13, first userland rung

The loader blindness, the jump and the boot chain are
closed; `docs/IMAGE_PROVENANCE.md` is the boot log of record for p1-p6. The wall is the empty
root volume: the kernel mounts it and panics on the missing `/sbin/launchd`. Populate the
image (`tooling/33b`, no sudo) and validate it (`tooling/34-check-bootstrap.sh`) before the
next boot.

Second wall, settled on the host: launchd's exec was killed `CS_KILLED` by AMFI's platform
check (namespace 9, 0xe) — the kernel is a macOS-config build and refuses an iOS platform
binary without the simulator's `no-sandbox` entitlement. Patch `0104`
(`sweet_ios_exec_platform=0` to turn it off) makes the exec reach dyld; the QEMU run now
stops at the missing dylib cache. `docs/AMFI_LAUNCHD.md`.

# Status — 2026-11-11 (evening), host preparation

Bootloader unlock is planned for **2026-11-12**. Until then: no device writes, only host-side
preparation, reference harvest and the dump/backup tooling that runs the moment the phone is reachable.

## Decided

- Base tree: `dipa-studio/ios-sweet` (SM7150, ARMv8.2, 16K granules, native LSE/PAN).
  Rejected `ios-topaz` (ARMv8.0, needs LSE emulation + Gold-cluster hand-off).
- Reference port with the same bootloader family: `edi194/ios-fajita` (OnePlus 6T).
- Boot chain: header **v1** with `Image.gz-dtb`; `boot_a` carries experiments, `boot_b` keeps
  a bootable LineageOS + Magisk as fallback and as the dump/log host.
- iOS root: the existing `userdata` partition, HFS+ case-sensitive journaled, no GPT change.

## Root image: everything unprivileged is done (2026-11-12)

The 16 GiB volume `build/ios16-root.img` is fsck-clean, HFSX, journaled and empty;
its baseline sha256 is recorded in `build/ios16-root.img.sha256.pre-populate`.
Filling it is now a single root command, `tooling/33-populate-root.sh`.

- `tooling/32-build-apfsfuse.sh` builds apfs-fuse from a pinned commit into
  `tooling/opt/apfs-fuse` - unprivileged, re-runnable, verified with `--check`
  (mount + unmount of a real DMG, no loop device, no root).
- `tooling/33-populate-root.sh --dry-run` reaches the loop mount and stops:
  144 341 files / 11.30 GB measured through the DMG mounts, 68.5 % of the volume.
- Verified: apfs-fuse build and all three DMG mounts, image header/fsck/sha gate,
  `00-check-host.sh` exit 0, `31-mkiosroot.sh --phase-image` unaffected.
- Unverified: the `sudo` half (modprobe, loop mount, rsync, links, tweaks, fsck)
  - no sudo password on the build host. Transcript: `docs/ROOTFS_READY.md`.

## Proven on paper (cited in `avicii/CONSTANTS.md`)

SoC 0x190/0x1b8, MPIDR split, GIC 0x17a00000/0x17a60000 (same as sweet), timer virtual INTID 19
(same as sweet — Spacewar's 27 does not apply), UFS 0x1d84000/PHY 0x1d87000/ICE 0x1d90000,
TLMM 0xf000000, PS_HOLD 0xc264000, IMEM restart 0x146ab65c, apps RSC 0x18200000/TSC 0x18200d00,
splash 0xa0000000 +0x2300000, panel AMS644VK04 1080x2400 DSC **command mode**, TE gpio 10,
panel reset PM8150L GPIO3, FTS @0x49 / GT9886 @0x5D on qupv3_se7 with gpio 9/8, rails L13+S4,
WCN3990 icnss 0x18800000 + WLFW carve-out + IPA, SPMI arbiter 0xc440000.

## Open, and blocking the first boot

- Touch supplier (FTS vs Goodix) — live i2c read only.
- RAM ranges and the high bank — live FDT only.
- Whether `fastboot boot` accepts an unsigned recovery on this ABL revision (fajita precedent
  says yes, verify on the unit).
- Widevine L3, no SEP, no cellular — accepted for bring-up.

Resolved 2026-11-11 by the stock image: boot geometry and board DTB (header v2 / page 4096 /
kernel 0x8000 / ramdisk 0x1000000 / tags 0x100; board DTB from `dtbo.img` entry `board-id 8 0`,
`dtsi_no 0x5141`). Shim rebuilt against the real DTB and `--verify` PASSes at 356 KiB.
v2 is stock-accepted on this ABL, so v1 is a deliberate conservative choice, not a
requirement — see `docs/SHIM_BOOT.md`.

## Host tasks delivered (2026-11-11, all present in the repo)

| Task | Output |
|---|---|
| host deps + unprivileged toolchain | `tooling/00-host-deps.sh`, `tooling/10-user-toolchain.sh`, `tooling/env.sh`, `docs/TOOLCHAIN.md` |
| reference harvest | `refs/*`, `docs/REFS_INDEX.md` |
| iOS root image pipeline | `tooling/30-fetch-ipsw.sh`, `tooling/31-mkiosroot.sh`, `docs/IOSROOT.md` |
| shim/ADT/pack retarget | `avicii/shim/build.sh`, `avicii/tools/{extract-dtb.py,mkbootimg_v1.sh,mkadt_avicii.py}`, `docs/SHIM_BOOT.md` |
| constants + live dump | `avicii/CONSTANTS.md`, `avicii/tools/dump-live.sh` |
| recovery, backups, provenance | `docs/RECOVERY.md`, `tooling/4*.sh`, `docs/IMAGE_PROVENANCE.md` |
| WLAN map | `docs/WLAN_MAP.md`, `docs/WLAN_ORDER.md` |
| USB SMMU + FTS adapt notes | `docs/USB_SMMU.md`, `docs/FTS_TOUCH.md` |
| stock avicii image for header values | `src/los21-boot.img`, `src/dtbo.img` -> `src/avicii-board.dtb` |

## Tomorrow, in order

1. `bash tooling/00-host-deps.sh` (root), re-login, `source tooling/env.sh`.
2. Unlock: OEM toggle, `adb reboot bootloader`, `fastboot oem unlock`, confirm on device.
3. Flash LineageOS + Magisk to `boot_b`, boot it, then `tooling/40-backup-by-name.sh` + pull.
4. `avicii/tools/dump-live.sh` and fill every `UNVERIFIED` cell in `CONSTANTS.md`.
5. Only then the first diag shim on `boot_a`.
## Fixed after the first consolidation pass (2026-11-11 late)

- `mkadt_avicii.py` unpacked ADT props as 2-tuples; `adt.parse` yields `(name, flags, value)`.
  `/product` now lands in the ADT (63 props) and the no-`/product` warning is gone.
- `mkadt_avicii.py` looked for `d22ap.adt` under `avicii/build`; path is now `../../build/ipsx`
  (and `D22AP_ADT=` overrides).
- `mkpayload.py` only understood `LC_UNIXTHREAD`; `LC_MAIN` is now accepted too, and the
  `__TEXT` lookup skips `__PAGEZERO`.
- New `avicii/tools/im4p-adt.py`: unwraps the IPSW `DeviceTree.d22ap.im4p` (BER + LZFSE) into
  the ADT and validates `/product`. Needs `/usr/bin/python3` (the `lzfse` module lives there).
- Proven end to end with a synthetic Mach-O: `fdt-mem` -> `mkadt` -> `mkpayload` -> `build.sh`
  -> `--verify` PASS, image 417,792 B with a 62,912 B payload ramdisk. A real XNU kernel is
  still only obtainable from the macOS CI run.

---

# 2026-11-12, device day — unlock, LOS, root, backups

Bootloader is **unlocked** (`flash.locked=0`, `verifiedbootstate=orange`, `getvar unlocked: yes`).
LineageOS 21 + Magisk v31.1 is on slot **b**, root over adb. Nothing is bricked; `b` restores from
`backup/64f70df8/boot_b.img` in one command.

Verified today: 41 partitions dumped with size+md5 (`tooling/44-backup-stream.sh`), 83 live dump
files (`avicii/tools/dump-live.sh`), `logs/mem-live.json`, `avicii/adt/avicii-live.adt`.
`tooling/42-log-pull.sh` fixed to go through `su`. `mkbootimg.py` now accepts an empty `--dtb` for
v2, matching the stock image (`dtb_size=0`, tree from `dtbo`).

Plan changes, all verified, all recorded in `docs/SHIM_BOOT.md`:

- **Slot `a` is unusable as a test slot** (no system metadata) → experiments go to `boot_b`.
- **`fastboot boot` does not work** on this ABL (4/4 fallbacks, both header versions) → flash only.
- A fallback from a payload-less shim is the shim's own reset, not a rejection.
- **Touch is Goodix GT9886 @ 0x5D** (driver bound); FTS @ 0x49 unbound. FTS docs = fallback only.
- Panel is command-mode DSC and shows **no console text**; the UFS ring is the only observer, and
  it is empty because the crash precedes its init.

Blocker: the shim dies ~6 s in, before its first C statement (`for(;;) wfe`-only build also fails).
Bisect images `bisect-N` are being produced (N1 = header+park, MMU off → N5 = console clear).
Next: flash them in order with a restore between each.

Measurement and telemetry, independent of the packer: `docs/TIMING.md` +
`tooling/50-boot-timing.sh` decide refused-vs-died on a millisecond plateau with
the stock control, and `docs/TELEMETRY.md` + `avicii/shim/tel_*.c`
(`DIAG_STAGE=6/7/8`) leave evidence that survives a refusal (IMEM record, then
TLMM/SPMI, then the motor). Rebuilt images and their sha256: `out-telem/`.

Complementary line, 2026-11-12 late: `avicii/build/` holds a six-image controlled series (S1 stock
control, S2 footer-only, S3/S4 our packer at stock shape, S5/S6 park payload) that separates packer
shape from payload; flash order, expectations and the single fix per failure are in
`docs/PAYLOAD_ORDER.md`. Measured while building it: the stock image carries a **real dtb section**
(`dtb_size 406620` at `0x1f00000`, blob at `0x2bab000`), and our packer reproduces stock byte for
byte up to `original_image_size` except the sha1 `id`.

Second complementary line, 2026-11-12 late: `docs/HYBRID.md` + `avicii/shim/hybrid/` — 8
build-and-verify-checked images that start from byte-identical agreement with stock's first
page and localise the entry convention. Measured while building it: stock's `code0` branches
to **+0x2480000** (`imm26` counts words, so the earlier "+0x92000" reading was 4x short) and
stock's `os_version` `0x1c000185` is **14.0.0 / 2024-05**, not 12.0.0/2023-09.


---

# 2026-11-12 late — the ladder runs, and two doc claims are wrong

**`fastboot boot` works on this ABL.** The earlier "4/4 fallbacks, flash only" was not a `boot`
limitation: every one of those images carried a dtbo *overlay* in the dtb section and ABL refused
them ~6 s. With the stock SoC base tree in the section, `fastboot boot` sends 98 MiB in 2.2 s and
the code runs. The whole ladder ran this way, ~20 boots, nothing flashed, `boot_b` never touched.

Root cause of every refusal to date: `mkbootimg_v1.sh` defaulted `DTB_FILE` to
`src/avicii-board.dtb`, which is the dtbo overlay (620 fragments, no `qcom,msm-id`). ABL needs the
base tree: `src/avicii-soc.dtb`, 406620 B, `48b0902a…`, extracted from `src/los21-boot.img`
`0x2bab000`. `--verify` now fails on a missing `qcom,msm-id` or any `__overlay__`, and T1 vs stock
differs in `kernel_size`/`ramdisk_size` only — every other header field is stock's. Proven on
hardware: T1 (park at 0x80000) and L0 (park inside `shim_main`) both hold >200 s / >60 s with no
USB re-enumeration, where a refusal re-enumerates in ~6 s.

## Rungs 1, 2, 3, 5 green (ring reads)

| rung | result |
|---|---|
| 1 GIC | `pidr2=0x3b` arch nibble 3, `typer=0x7b041d`, gicv3 ok, itlines sane |
| 2 UFS | `version=0x300` (HCI 3.0), `cap=0x1587031f`, `hcs=0x10f` **DP set**, PHY answers (`+0x160=0x7f`, `+0x16c=0xa`) |
| 3 splash | base `0xa0000000`, size `0x2300000`, `region matches`, painted 97 ms, screen turns magenta off ABL scan-out |
| 5 memory | three extents as tabled, `dram reaches above 4 GiB`, `RESULT mismatch=00` |
| 4 SMP | all seven secondaries 0x100-0x700 released, `probe mask=0xfe` (each slot holds its own index) and, with the real entry, `ack mask=0xfe` with live spin counts — every core runs our code |

Rung 4 is closed (2026-11-12 23:31 / 23:37, `out-diag/l16` and `l17`). Two bugs in the shim, both
host-visible, and neither in PSCI:

1. The entry was built as `kimg_base + (sym - _start)`. `(uintptr_t)sym` is *already* a runtime
   address (`adr`/`adrp` under `-fno-pic`) and `kimg_base` is `_head`, not `_start`, so every
   release landed `0x80000` low in the zero padding before `.text` and took `udf #0` at its first
   fetch. PSCI returned 0 for all seven every time; the "release is fatal" signature was the caller
   wedging on the faulted core, not the core dying in our code. `out-diag/l6` had it right by
   accident (bare symbol) and its ack mask of 0 was the second bug.
2. The ack mask was read before `sec_stop = 1`, while `diag_secondary()` stores `sec_spin[]` only
   after its loop exits — a perfect release still printed `mask=0`.

`CurrentEL` at the caller is `0x4` (EL1), so the EL2-vector hypothesis is dead: PSCI starts a
secondary at the caller's EL, and the EL1 `vbar_el1` install in `sec_stub` was correct all along.
stage4 now refuses to release if the entry is outside `[_start, _bss_start)`.

## Four bugs the ladder found in the shim, all fixed

1. `dlog_init` returned 5 when the header read-back mismatched — the read-back lies on this medium
   while Linux reads the same block fine. Now a warning (`dlog_warn()`, panel `LOG warn rc=`).
2. `GICD_PIDR2` was `0xfe8` (4 KiB-frame offset) in a 64 KiB frame, which is RAZ — now `0xffe8`.
3. `HCI_VERSION`/`HCI_CAP` were swapped vs UFSHCI (CAP 0x00, VER 0x08, as `ufs.c` has it) and the
   version test compared a major/minor-packed VER against 0x10000.
4. `park()`'s deadline was `60 * freq` with `freq` in ticks/ms → every "60 s" park was 58 ms; now
   `60000 * freq`, measured 60 s. `smc` never resets at EL2, `hvc` does — reset is HVC-then-SMC.

Console: `FB_STRIDE` was 4800 B for a 1080-px row (4320 B), shearing every scanline 120 px. Fixed
and confirmed on the panel with a bar ruler (`ruler stride=0x10e0`, bars straight, glyphs resolve).

## Next

**The ladder is green; the next rung is the XNU payload on this shape** (`fastboot boot`, nothing
flashed, `boot_b` untouched), then the iOS root in `userdata`. Stage-4 images `l16`/`l17` stay in
`out-diag/` as the SMP reference: `l17` (`ack mask=0xfe`, real entry) is the one to reuse when the
shim has to bring secondaries up for real.

Notes for whoever continues: after a ring write LineageOS usually lands in **recovery**, where adbd
is root without `su` (pull with `adb exec-out dd`, skip `size/4096-1025`), but it landed on **Android
with Magisk** twice tonight — `adb devices` answers `unauthorized` there until `ADB_VENDOR_KEYS` is
exported, then `su -c` is root and the same `dd` goes through `adb exec-out "su -c '…'"`. Do not
assume the recovery. `park()` needs the power button only if the HVC reset itself fails.
