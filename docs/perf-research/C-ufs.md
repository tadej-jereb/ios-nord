# Lane C — UFS storage speed

Scope: what link speed, queue depth and features our `sweet_ufs.c` actually uses, what the vendor's
driver asks the same controller and device for, and the ordered plan to close the gap. Read-only
research; nothing was run on the phone. Scratch (vendor sources, greps) in
`~/.hermes/cache/scratch/lane-c/`; vendor citations are `drivers/scsi/ufs/<file>:<line>` on
LineageOS `android_kernel_oneplus_sm8250` branch **lineage-21**.

## 1. Summary

- **We run the controller at whatever ABL left and never look**: `0028` sets `IE = 0`, one polled
  command in slot 0, ≤ 1 MiB, clean+invalidate on both sides of each command (`0028:200-226`); no
  UIC/DME command, descriptor read or GCC clock write anywhere in `xnu-avicii/patches/`.
- **The controller is far bigger, and the phone already said so**: `cap = 0x1587031f`
  (`docs/STATUS.md:637`) = 32 slots (`ufshcd.c:3291`), 8 task slots, auto-hibern8, 64-bit DMA, ICE;
  we use 1, polled.
- **The vendor targets HS-G4 rate A ×2 lanes, FAST** (`ufs-qcom.h:42-53`, `ufs-qcom.c:273-278`;
  200/150 MHz, `ufshcd.c:10445-10454`) = 2320 MB/s payload, 452 µs per 1 MiB command. We verify
  neither link nor clocks; each MiB also costs ~1 MiB memcpy + ~2 MiB cache work that cannot overlap
  the DMA (one slot, `0028:375-390`).
- **MEASURED:** `dd` at 99.1–100.0 %CPU for ≥ 25 s of reads
  (`logs/phone/cpu-scroll-20261115-0115-reduce.txt`, 16:05:27–16:05:53); the only other number on
  file is 43.75 MB/s via `adb`, pipe-fed (`docs/IMAGE_PROVENANCE.md:541`).
- **ESTIMATED, replaced by one `dd` run:** 1.5–3× on ≥ 1 MiB reads. Boot ΔT = S × (1/R₁ − 1/R₂);
  with S = 600 MiB and R 100 → 300 MB/s that is **4 s of a ~180 s boot**, so unless R is far below
  100 MB/s this lane is minor.

## 2. What the vendor does

**dts (live, i.e. what ABL actually applied).** `live.dts:5367-5406`: `reg = <0x1d84000 0x3000
0x1d90000 0x8000>`, `reg-names = "ufs_mem","ufs_ice"`, `interrupts = <0 0x109 4>` (GIC SPI 265,
same as `avicii/lito.dtsi:1852`), `lanes-per-direction = <2>`, `dev-ref-clk-freq = <0>` (19.2 MHz),
`spm-level = <3>`, `freq-table-hz` = core_clk 50→**200 MHz**, unipro 37.5→**150 MHz**, ICE
75→**300 MHz** (`live.dts:5379`). There is **no** `qcom,limit-tx-hs-gear`, `qcom,limit-rx-hs-gear`
or `qcom,limit-rate` property in either the live tree or the lineage-21 dts
(`los21-lito.dtsi:1768-1880`), so the gear ceiling is not dts data — it is compiled in. PHY:
`qcom,ufs-phy-qmp-v4-lito`, 2 lanes (`live.dts:5517-5532`). ICE is a separate 32 KiB register block
at `0x1d90000` with its own clock branch (`ufs_ice` in `avicii/lito.dtsi:1823-1847`).

**The gear ceiling is in the driver**, `ufs-qcom.h:42-53`: `UFS_QCOM_LIMIT_NUM_LANES_{RX,TX} = 2`,
`UFS_QCOM_LIMIT_HSGEAR_{RX,TX} = UFS_HS_G4`, `..._PWMGEAR = UFS_PWM_G4`, `..._PWR_HS = FAST_MODE`,
`UFS_QCOM_LIMIT_HS_RATE = PA_HS_MODE_B`, `UFS_QCOM_LIMIT_DESIRED_MODE = FAST`. Rate B is then
**overridden to rate A at G4**: `ufs-qcom.c:273-278` sets `is_rate_B = false` when
`hba->phy_init_g4`, and `phy_init_g4` is forced true for any device whose descriptor says
`w_spec_version >= 0x300` (`ufshcd.c:9426-9435`). Gear is negotiated as
`min(qcom ceiling, device max)` (`ufs-qcom.c:1034-1052`) after reading the device's
`PA_CONNECTEDRXDATALANES` and `PA_MAXRXHSGEAR` (`ufshcd.c:5709-5760`). The result is printed as
e.g. `HS_RA_G4_L2` (`ufs-qcom.c:1104` via `ufs_qcom_get_speed_mode`, `:1084-1109`).

**Power-mode change** — the exact sequence we would have to reproduce (`ufshcd.c:5784-5897`):
`PA_RXGEAR` ← gear, `PA_ACTIVERXDATALANES` ← lanes, `PA_RXTERMINATION` ← 1 for FAST,
`PA_TXGEAR`, `PA_ACTIVETXDATALANES`, `PA_TXTERMINATION` ← 1, `PA_HSSERIES` ← rate,
then for G4 only: peer-get `RX_HS_ADAPT_INITIAL_CAPABILITY` → `PA_PEERRXHSADAPINITIAL` and
`PA_TXHSADAPTTYPE = PA_INITIAL_ADAPT` (0x01), else `PA_NO_ADAPT` (0x03) (`:5838-5858`); the six
`PA_PWRMODEUSERDATA*` timeout values (`:5860-5871`); and finally one `DME_SET(PA_PWRMODE)` with
`pwr_rx << 4 | pwr_tx` (`:5880-5881`, `ufshcd.c:5510-5514`). Attribute ids and mode values:
`unipro.h:100-159` (`PA_PWRMODE 0x1571`, `PA_RXGEAR 0x1583`, `PA_TXGEAR 0x1568`,
`PA_HSSERIES 0x156A`, `PA_MAXRXHSGEAR 0x1587`, `PA_CONNECTEDRXDATALANES 0x1581`) and
`unipro.h:196-209` (`FAST_MODE 1`, `SLOW_MODE 2`, `FASTAUTO 4`, `SLOWAUTO 5`, `UNCHANGED 7`;
`PA_HS_MODE_A 1`, `PA_HS_MODE_B 2`).

**Clocks.** `ufshcd_init_clocks()` sets every clock in `freq-table-hz` to its **max** at probe
(`ufshcd.c:10422-10457`), i.e. 200/150/300 MHz; scaling down afterwards is the devfreq path
(`ufs-qcom.c:2456-2483`, gear floor G2 at `:2498-2506`). Programmable divider tables (needed if we
ever have to set them ourselves): UFS PHY AXI RCG at GCC+`0x77024`, 200 MHz = GPLL0_OUT_MAIN/3
(`refs/lito-dts/gcc-lito.c:755-784`); UNIPRO RCG at GCC+`0x77084`, 150 MHz = GPLL0_OUT_MAIN/4
(`:838-852`); ICE RCG at GCC+`0x7706c`, 300 MHz = GPLL0_OUT_MAIN/2 (`:786-800`); GCC itself is
`qcom,gcc@100000`, `reg = <0x100000 0x1f0000>` (`avicii/lito.dtsi:1662-1664`), so the absolute
addresses are `0x177024`, `0x177084`, `0x17706c`.

**Timers and features the vendor enables after the link is up** (`ufshcd.c:9557-9594`): device
power mode ACTIVE via START STOP UNIT (`:10592-10640`), `ufshcd_wb_config()` (WriteBooster,
`:7251-7291`: gated on the device's `EXT_UFS_FEATURE_SUP` WB bit plus `b_wb_buffer_type`/
`wb_config_lun`, enabled with QUERY FLAG SET `fWriteBoosterEn`), then
`ufshcd_set_auto_hibern8_timer()` with a **1 ms** idle timer (`:3058-3073`,
`FIELD_PREP(TIMER,1) | FIELD_PREP(SCALE,3)`, register `REG_AUTO_HIBERNATE_IDLE_TIMER` = `0x18`,
`ufshci.h:51`). Interrupt aggregation is available but only used for the SCSI path
(`REG_UTP_TRANSFER_REQ_INT_AGG_CONTROL` = `0x4C`, `ufshci.h:61`).

**Failure handling** (the part we must imitate, not copy): UIC commands have a **500 ms** timeout
(`ufshcd.c:233`); link startup is retried `DME_LINKSTARTUP_RETRIES = 3` (`:252`, used `:6202-6226`)
with a full HCE stop/start between tries (`ufshcd_hba_execute_hce`, `:6072-6117`: HCE 1→0→1, 1 ms
wait, 10 × 5 ms poll); the last resort is `ufshcd_host_reset_and_restore()` (`:8518-8534`). Note
`ufshcd.c:8604` **BUG_ON**s when an embedded device fails recovery — a kernel that cannot report
must not do that.

## 3. What we do today

**Host.** `0028:306-332` (`ufs_take_over_host`): requires `HCE&1`, `HCS_DP`, `HCS_UTRLRDY`, refuses
if `UTRLDBR != 0`, writes `REG_IE = 0`, `REG_UTRLRSR = 0`, `REG_UTRLBA/U`, `REG_UTRLRSR = 1`, then
verifies the base address and run bit read back. Registers it knows: `0x20 IS`, `0x24 IE`,
`0x30 HCS`, `0x34 HCE`, `0x50/0x54 UTRLBA`, `0x58 UTRLDBR`, `0x5c UTRLCLR`, `0x60 UTRLRSR`
(`0028:85-93`), plus `0x00 CAP` for the 64AS check (`0034:7,15,24`). It never reads
`0x08 VER`, `0x18 AHIT`, `0x4C UTRIACR`, `0x90-0x9C UIC`, or `0xE4 HW_VERSION`.

**Command path.** One 32-byte UTRD in slot 0, one 1 KiB UCD (`cmd[512] + resp[512] + prdt[4]`), one
1 MiB bounce buffer, all in one contiguous `kmem_alloc_contig` (`0028:104-123`). Per command:
`bzero` the UTRD and the whole UCD, fill the COMMAND UPIU by hand at `cmd[0..15]` (transaction
`0x01`, flags `0x40` read / `0x20` write, LUN, tag, 4-byte BE length), `memcpy` the CDB at
`cmd[16]`, DW0 = `(1<<28) | (DD<<25) | (1<<24)`, DW2 = `0x0f` (OCS invalid), response UPIU at
offset 512 B / length 512 B, up to 4 PRDT entries of 256 KiB each (`PRDT_CHUNK`,
`PRDT_DATA_BYTE_COUNT_MAX` is 256 KiB, `ufshci.h:470`), `utrd->prdt = (1024/4) << 16 | n` — dword
offset in the high half, **entry count** in the low half (same encoding as Linux,
`ufshcd.c:5092-5107`). Then `flush_dcache64(..., TRUE)` on UTRD, UCD and the **full transfer
length**, `dsb`, ring the doorbell, and poll `UTRLDBR & 1` with `delay(1)` under a 5 s deadline
(`0028:163-235`).

**The cache cost.** Both `dma_sync()` calls flush the *transfer length*, not the descriptor block
(`0028:153-157, 200-226`): before the doorbell (wasted — the device overwrites the buffer) and
after completion (needed, but implemented as clean+invalidate of the whole range). Then the data is
`memcpy`'d out of the bounce buffer (`0028:386`). So per MiB delivered: 1 MiB clean + 1 MiB
clean/invalidate + 1 MiB memcpy of CPU-side traffic, serialized with the device by
`lck_mtx_lock(&sweet_ufs_lock)` around the whole I/O loop (`0028:375-390`).

**Transfer size.** READ(10)/WRITE(10) of at most `BOUNCE_SIZE / UFS_BLOCK = 256` blocks
(`0028:237-250`, `0030:73-92`), i.e. 1 MiB; `DKIOCGETMAXBLOCKCOUNTREAD` = `BOUNCE_SIZE/secsize`
and, since `0098:1-30`, `DKIOCGETMAXBYTECOUNT{READ,WRITE} = 1 MiB` and
`DKIOCGETMAXSEGMENTCOUNT = 256` pages — before `0098` the segment count was **1**, i.e. one page
per I/O.

**Optional speed knobs that exist and are off.** `0069` adds `ufscache=1` (clean descriptors instead
of flushing everything) and `ufswait=1` (block the thread with
`assert_wait_deadline_with_leeway` for 200 µs slices after 50 µs of spinning instead of `delay(1)`),
both defaulting to 0 (`0069:24-25, 83-110, 130-134`). Neither is a queue-depth or link change.
Write paths added later: `0100` (retire retry), `0101` (START STOP UNIT power condition ACTIVE on
2/04/02), `0102` (short-transfer detection), `0103` (durability).

**Phone evidence.** The only UFS register values we have are the rung-2 probe table —
`version=0x300`, `cap=0x1587031f`, `hcs=0x10f` with DP set (`docs/STATUS.md:637`); `hcs`
bits `[10:8] = 1` is `PWR_LOCAL` (`ufshci.h:178`), which is exactly the value Linux accepts as a
*successful* power-mode change (`ufshcd.c:5456-5462`), so the bootloader's last change went
through. Nowhere in `logs/phone/` is the negotiated gear, rate, lane count and clock rate printed
(`grep -rn "SWEET UFS" logs/phone` yields the takeover/capacity lines only), and the UFS sysfs dump
taken from Android is empty (`logs/dumps/run-20261112-195027/30-ufs-attr-probe.txt`, 0 bytes), so
**we do not know the device vendor/model either**; all we know is the medium size, `sda` =
121 421 824 KiB = 115.8 GiB (`.../30-partitions.txt`), i.e. a 128 GB-class part.

## 4. Plan

Ordered, cheapest and least risky first. P0–P4 never send a UIC command and cannot wedge the link;
P5 is the only link-level change and is boot-arg gated.

### P0 — Instrument (one boot, zero risk)

Print at attach, before anything else, so one boot on the phone answers §5:

| what | how |
|---|---|
| host state | `0x00 CAP`, `0x08 VER`, `0x18 AHIT`, `0x30 HCS`, `0x34 HCE`, `0x4C UTRIACR`, `0xE4 HW_VERSION`, `0x10/0x14 DEV_ID/PROD_ID` |
| link state | UIC `DME_GET` for `PA_PWRMODE 0x1571`, `PA_RXGEAR 0x1583`, `PA_TXGEAR 0x1568`, `PA_HSSERIES 0x156A`, `PA_ACTIVERXDATALANES 0x1580`, `PA_CONNECTEDRXDATALANES 0x1581`, `PA_MAXRXHSGEAR 0x1587` |
| clocks | `ml_io_map(0x100000, 0x1f0000)`, read `0x177024` (AXI RCG), `0x177084` (UNIPRO RCG), `0x17706c` (ICE RCG) and print raw |
| device | READ CAPACITY(10) (`0x25`); QUERY REQUEST UPIU (`0x16`) READ DESCRIPTOR `idn 0x00`, length `0x59`, then print `MANF_NAME 0x14`, `PRDCT_NAME 0x15`, `MANF_ID 0x18`, `SPEC_VER 0x10`, `UFS_FEAT 0x1F`, `WB_TYPE 0x54` (`ufs.h:185-232`) |

UIC mechanics: `0x94 = attr << 16`, `0x90 = 0x01` (`UIC_CMD_DME_GET`, `ufshci.h:317`), poll
`IS & UIC_COMMAND_COMPL (0x400)` with a 500 ms deadline (`ufshcd.c:233`), result code in `0x98`
low byte, value in `0x9C` (`ufshci.h:72-75`). Query byte layout: transaction code `cmd[0]=0x16`,
`cmd[1]=0x40` (R), opcode `cmd[12]=0x01`, idn `cmd[13]=0x00`, length `cmd[18..19]` BE16
(`ufs.h:99, 489-499`). Interrupts stay disabled; the completion is polled like everything else.

Risk: none — read-only registers, no doorbell except for the two SCSI/query commands the driver
already issues. This is the change that makes every later estimate a measurement.

### P1 — Stop cleaning the bounce buffer before a read (biggest CPU win per line changed)

In `ufs_scsi()`, when `len && !write`: skip the pre-command flush of the bounce range entirely
(`0028:202-204`); a read target's contents are irrelevant. Keep the post-completion sync but make
it `invalidate_dcache64()` where available instead of `flush_dcache64(..., TRUE)`. Effect: 3 MiB
of CPU-side traffic per MiB becomes ~1–2 MiB. Risk: none to the link; a missing invalidate shows up
as stale data, which the HFS mount and `fsck` catch. This is what `ufscache=1` was reaching for but
does not do for reads (`0069:69-76` cleans only when `write`).

### P2 — 4 MiB transfers instead of 1 MiB

`BOUNCE_SIZE` 1 MiB → 4 MiB (`PRDT_MAX` becomes 16), READ(10)/WRITE(10) count up to 1024 blocks
(READ(10)'s 16-bit count allows 65535, so 1024 is free), `DKIOCGETMAXBYTECOUNT* = 4 MiB`.
The UCD grows to 1024 + 16×16 = 1280 B, still inside the 12 KiB the allocation reserves between
`DMA_UCD` and `DMA_BOUNCE` (`0028:120-123`). Benefit is the per-command fixed cost (bzero of
1088 B, three `dsb`s, doorbell, poll turnaround) — small at 452 µs of DMA per MiB, so this only
matters *after* P1/P3. Risk: 4 MiB of contiguous DMA, and the guard in `0034:24` already
refuses to run if the allocation lands above 4 GiB on a host without 64AS (this host has it,
`cap` bit 24). Keep the 1 MiB default behind a boot-arg until it has booted twice.

### P3 — 4 request slots, one UCD + one bounce slice each

Grow the allocation to `N × (UTRD + UCD + 4 MiB)` (N = 4), ring `UTRLDBR` with `(1<<N)-1` for a
batch of independent LBAs, and wait for the whole mask to clear, harvesting OCS per slot. This is
what makes the CPU cost overlap the DMA — the real fix for a `dd` at 100 %CPU. Ordering is safe:
`OUT_OF_ORDER_DATA_DELIVERY` is **not** set in `cap` (bit 25 clear), so completions arrive in order
anyway, and each slot's OCS is read from its own UTRD. Risk: a slot leak wedges the mask forever →
per-slot 5 s deadline plus a `UTRLCLR` write, `~(1 << slot)` — the same encoding `0028:211-218`
uses as `~1u` for slot 0, and the one Linux uses (`ufshcd.c:1246-1252`).

### P4 — Interrupt instead of poll

Enable `IE = UTP_TRANSFER_REQ_COMPL (0x1)` (`ufshci.h:138`) and register GIC SPI **265**
(`avicii/lito.dtsi:1852`) as a level-high handler that clears `IS` (write-1-to-clear) and wakes the
sleeping thread from the `0069` `ufswait` path. Boot-arg `ufsirq=1`, default off until proven.
Risk: an unhandled/mis-acknowledged IRQ storm — mitigate by keeping the poll loop as the timeout
fallback (poll every 200 µs even when sleeping) and by never enabling IE when the handler did not
install.

### P5 — Verify, then (only if needed) move the link to HS-G4A ×2

Step 1 is P0's output. Decide from the numbers:

| negotiated | payload, 2 lanes | 1 MiB command |
|---|---|---|
| HS-G3 rate B | 580 MB/s | 1808 µs |
| HS-G3 rate A | 1160 MB/s | 904 µs |
| HS-G4 rate B | 1160 MB/s | 904 µs |
| **HS-G4 rate A (vendor target)** | **2320 MB/s** | **452 µs** |

(computed: 2 lanes × line rate × 8/10 line coding; G4A = 11.6 Gbps/lane.) If P0 shows G4A already,
there is nothing to gain here and P5 is dropped. If it shows G3, the change is the
`ufshcd.c:5784-5897` sequence above, preceded by `DME_HIBER_ENTER`/`EXIT` and issued with **no
request outstanding** (quiesce the queue first — the driver's mutex already gives us that).

Risk: **this is the one change that can wedge the link**, and a wedged link means the root never
mounts, i.e. no ring log and no diagnosis. Recovery, in the order the driver should try it:
1. `DME_GET(PA_PWRMODE)` read-back — accept the new mode only if it matches; otherwise keep using
   the mode read at attach, which by definition works (`hcs[10:8] = PWR_LOCAL`, `docs/STATUS.md:637`).
2. `DME_HIBER_ENTER` (0x17) then `DME_HIBER_EXIT` (0x18) — resynchronises the UniPro state machine
   without touching the PHY.
3. Clear `HCE` (0x34 bit 0), set it again, poll up to 50 ms for `HCS` `DP|UCRDY` (Linux: 1 ms wait
   plus 10 × 5 ms, `ufshcd.c:6104-6117`).
4. `DME_LINK_STARTUP` (0x16) up to 3 times (`ufshcd.c:6202-6226`).
5. Give up loudly: `printf("SWEET UFS: link lost, mode %x/%x")` and return `EIO` so the mount fails
   visibly instead of hanging; `ufspwrmode=0` on the next boot reverts to "leave it alone".
Never `BUG_ON` (Linux does, `ufshcd.c:8604`) — this phone has no serial, and a panic costs a
reboot round trip.
Also, only if P0 shows the GCC divider below max: program the RCGs at `0x177024`/`0x177084` to
200/150 MHz (`gcc-lito.c:755-784`, `838-852`). Write-only-if-wrong, log the before/after value.

### P6/P7 — WriteBooster, ICE (not boot-read wins)

WriteBooster only helps writes (the ring log's 2 MiB every 10 s and the journal), needs a QUERY
FLAG path the driver does not have yet (`0025`-style SCSI/UPIU plumbing, `ufs.h:478-499`), and is
gated on the device descriptor (`ufshcd.c:7251-7291`). ICE (`0x1d90000`, `cap` bit 28) is idle and
irrelevant while the volume is unencrypted — do nothing.

### How to measure it on the phone

1. **Read throughput, the number we are missing.** Over the USB ECM/SSH link the project already
   has (`0072`-`0077`, sshd seen in `logs/phone/live-20261115-0114-ssh.txt`):
   `time dd if=/dev/rufsroot0 of=/dev/null bs=1m count=1024` — the character device goes through
   `physio` → `sweet_ufs_strategy` (`0028:462-466`) and bypasses the buffer cache, so it measures
   the driver, not HFS. Repeat with `bs=4k` for the metadata-size case, and with `count` large
   enough to clear the 1 MiB bounce reuse. Record `real`, `user`, `sys` and the `ps` %CPU of the
   `dd` process (the `logs/phone/cpu-scroll-*` sampler already does this).
2. **Boot read volume S**, which is what turns MB/s into seconds. Add a 64-bit byte counter in
   `sweet_ufs_strategy` and print it once, 60 s after attach (or on the first `SIGINFO`-like hook).
   Until then S is unknown and every boot-second claim is a model.
3. **Boot-to-SpringBoard** stays a stopwatch + panel photo, as in `docs/STATUS.md:25-26` (first boot
   after a fresh root ~15 min for the LaunchServices DB, later boots ~3 min); the kernel console
   carries no timestamps, so do not pretend the ring can produce it.
4. Success criteria: `dd bs=1m` ≥ 2× the P0 baseline with `%CPU` unchanged or lower, `bs=4k`
   latency lower, and boot-to-SpringBoard not worse.

## 5. Open questions only a phone run answers

1. **What is the link actually at?** Gear, rate, active lanes, and whether `PA_PWRMODE` says FAST —
   P0 prints it. Everything about P5 hangs on this, and so does the whole ceiling table.
2. **What is `core_clk`/`core_clk_unipro` right now?** ABL sets them; nothing in our tree does, and
   nothing re-reads them. If they are at 50/37.5 MHz the link cannot sustain G4 no matter what the
   gear says, and clock programming jumps to first place.
3. **Which chip is it, and what does it support?** Vendor/model, `w_spec_version` (3.0 vs 3.1),
   WriteBooster buffer type. The Android sysfs dump that should have carried this is empty.
4. **What is today's real read rate?** `dd bs=1m` on the char device. If it is already ~600 MB/s,
   the whole lane is worth < 2 s of boot and should be closed; if it is ~50 MB/s, P1–P3 are the
   single biggest boot win available.
5. **Is ABL's auto-hibernate timer non-zero?** `AHIT` at `0x18`. A 1 ms timer (Linux's default,
   `ufshcd.c:3069-3073`) costs a hibern8 exit on every burst — which would hurt 4 KiB HFS metadata
   reads far more than 1 MiB sequential ones.
6. **How much does boot actually read?** S from the counter in §4 — the only way to convert MB/s
   into boot seconds honestly.
