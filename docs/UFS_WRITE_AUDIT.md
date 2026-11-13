# UFS WRITE PATH AUDIT — avicii (SM7250 / lito), high `phys_base`

Scope: every way the sweet UFS **write** path can fail on this SoC, with the payload
in the HIGH bank (`phys_base` `0x180000000`) and an HFSX volume at the very start of
`userdata`. Read-only audit: no device access, no commit, no full kernel build.
Sources read: the series applied to a scratch `xnu-8796.141.3` (`bsd/dev/sweet_ufs.c`
after `0028`, `0030`, `0034`, `0069`), `avicii/shim/ufs.c`, `refs/edi194-ios-fajita`
(byte-identical driver), `refs/dipa-studio-ios-sweet`, `refs/anonbeat1-ios-sweet`
(`0084`/`0085`/`0086`), `refs/ry-diffusion-Bergamota/.../0222`.

Line numbers are the series state *before* `0100`-`0103`.

## What is already proven, so it is not re-litigated here

The first write-heavy boot does **not** start from zero:

* `out-pay/p6` (`docs/IMAGE_PROVENANCE.md:334`) mounted the volume read-write with
  `ufsrw=1 rootrw=1`: the journal was created **through the UFS write path**, the
  volume mounted, and the panic flushed 6392 bytes into the ring. Write DMA,
  WRITE(10), the read-modify-write of partial 4 KiB blocks and the high-address
  PRDT encoding have all executed on this part.
* The shim writes the diag ring (must be > 4 GiB, MMU off, Device memory) —
  `avicii/shim/ufs.c:161`.
* `CAP_64AS` is set on this controller: `cap=0x1587031f` (`docs/STATUS.md:157`),
  bit 24 = 1.

So the defects below are the ones that bite under **sustained load, transients and
resets** — not the very first write.

## Findings

| # | Sev | Where | What can fail | Fix |
|---|-----|-------|---------------|-----|
| S1 | **HIGH** | `bsd/dev/sweet_ufs.c:221-225` (timeout branch), reused bounce at `:440`/`:452` | On timeout the code writes `UTRLCLR` and returns. The host retires the slot on its own, but the **device may still own the bounce buffer** until it does; `strategy`'s next chunk (or the next command) rebuilds UCD, PRDT and bounce under it. A late DMA lands the previous command's data in the next one's window → foreign bytes inside a file, with a GOOD status on both. Reads hide it (the late write goes into a buffer that is re-read anyway); **writes do not**. Same defect class already recorded downstream (`refs/ry-diffusion-Bergamota/xnu/patches-12377/0222-…:40-46`). | `0100`: bounded wait for retirement before the slot is reused, `UTRLCLR` only if it never retires, IS drained. |
| S2 | **HIGH** | `:251-254` (no sense decode), `:629-630` (TUR retried 3×, reads only) | A CHECK CONDITION is flattened to `EIO` with no sense key, and nothing is retried except the init TUR. Unit attention `6/29` after ABL, `NOT READY` and `BUSY` are all normal right after a flash/boot; on the very first RW attempt they turn `journal_create` → `do_jnl_io` into a mount failure exactly like the `0x1e` seen at p5. | `0100`: decode RESPONSE UPIU (status 7, residual 12, fixed sense 34/36/46), retry only BUSY / TASK SET FULL / NOT READY / UNIT ATTENTION, 3 tries with 1-3 ms backoff. Safe: every command here is idempotent (same LBA, same window). |
| S3 | **HIGH** | `:250-256` | SCSI status GOOD with a **nonzero residual** (RESPONSE UPIU bytes 12-15) is treated as success. A short write leaves the tail of the range on the old contents and reports completion to the buffer cache — silent corruption that no later check catches. For the journal that is a torn commit. | `0102`: parse the residual, `EIO` when `len && resid`, print transferred-of-total. |
| S4 | MEDIUM | `:357-388` (`ufs_take_over_host`), `:626-631` | Nothing ever sends START STOP UNIT / sets the power condition; the driver inherits whatever power mode ABL left. A LU in a power save state answers **every** command, writes included, with `CHECK CONDITION 2/04/02`, and the 3× TUR loop has no way out of it (sweet needed a dedicated port, `refs/anonbeat1-ios-sweet/xnu/patches/0085`). | `0101`: on `2/04/02` send SSU POWER CONDITION ACTIVE to the UFS Device well-known LU `0xd0` before the retry. |
| S5 | MEDIUM | `:296-300` (`ufs_sync_cache`), `:551-557`, `:440-461` | The write path never flushes the device cache: `ufs_sync_cache()` is reachable only from a `DKIOCSYNCHRONIZE` ioctl and from the ring thread (`:766-779`, `:822`), and FUA is never set on WRITE(10). Nothing in HFS (or VFS) issues that ioctl, so a journal commit only lives in UFS device DRAM — and every boot here ends in a panic reset. The commit survives on FIFO luck, not on order. Note that nothing in this tree calls `buf_markfua()` either (there is no `DK_FEATURE_FUA`), so `B_FUA` alone would be dead: the trigger has to be a boot-arg. | `0103`: FUA bit (`WRITE(10)` byte 1, bit 3) with `ufsfua=1` (every write) or on a `B_FUA` buffer, plus `ufssync=1` for a SYNCHRONIZE CACHE after each write as the FUA-free alternative. All opt-in, off by default. |
| S6 | LOW | `:186-197`, `:199-203` | With `ufscache=1` the request UPIU is cleaned only for `16 + cdb_len` bytes. The `bzero` at `:157` dirties lines that are then never written back, so the device can read the *previous* command's bytes in the CDB tail padding. Harmless for WRITE(10), latent for any longer CDB. The write direction itself is handled correctly (`dma_clean` on the bounce, no bogus post-invalidate). | Not patched: `ufscache` defaults to 0 and the padding is unused. |
| S7 | LOW | `:219-225`, `su.ready` | `HCE` / device presence is checked once at attach only. If the controller stalls, every command costs the full 5 s deadline forever and `su.ready` keeps the FS hammering. | Partly covered by `0100` (retire + diagnostic IS/HCS print). |
| S8 | INFO | `:281-286` | An out-of-range or oversize write returns `EPERM`, indistinguishable from a read-only volume in the mount log. | Not patched (cosmetic). |
| S9 | INFO | `:743`, `:811` | The ring reserves the **last 4 MiB + 4 KiB of the partition** and writes there regardless of the volume. Safe today (volume 16 GiB in a 101 GiB `userdata`) but silent if the volume is ever grown to the partition size — the alternate volume header and allocation file tail sit exactly there. | Not patched (config invariant, worth a line in `docs/IOSROOT.md`). |
| S10 | INFO | driver-wide | ICE (`0x1d90000`) is never programmed or checked (`avicii/CONSTANTS.md:170,280` asks for an explicit decision). Consistent today because reads prove the LU is not being encrypted, and writes use the same path, so the state is symmetric. | Not patched. |

## The six questions, one by one

1. **DMA width for writes.** No defect. The PRDT upper word is filled for both
   directions (`:180`), as are `ucdba/ucdbau` (`:172-173`) and `UTRLBAU` (`:379`), so
   `0034` is not read-only in effect: its check (`:369-373`) runs at attach and refuses
   the whole driver when the allocation sits above 4 GiB on a host without `CAP_64AS`.
   `CAP_64AS` is set here anyway (`docs/STATUS.md:157`), and p6 wrote through the same
   high addresses. Residual risk is the sweet-type "high DMA read timeout"
   (`refs/anonbeat1-ios-sweet/.../0086`) — also applies to writes, and buys a `ufsdma32`
   escape hatch that avicii does not carry. Consider porting it as a fallback boot-arg,
   nothing more.
2. **Cache maintenance.** Default (`ufscache=0`) is correct for writes: `dma_sync` is
   `flush_dcache64` (clean+invalidate, `phys` = TRUE) before and after, which is a clean
   before DMA on the data and a proper invalidate on the response. `kernel_map` memory
   from `kmem_alloc_contig` is cacheable, so the maintenance is needed and present. The
   `ufscache=1` write path cleans the bounce (`:200`) and must not invalidate it after
   (`:246-248`) — correct. Only S6 is thin. The shim is MMU-off Device memory and needs
   none of this; do not copy its lack of maintenance into the kernel.
3. **512-byte logical sectors over 4 KiB blocks.** No defect in the write direction.
   `blocks` is `ceil((skip + want)/4096)` with `want = MIN(count - done, BOUNCE_SIZE - skip)`
   (`:438-439`), so `blocks <= 256` always and the bounce cannot overrun; the aligned
   self-correction after `done += want` is sound. The RMW read (`:448-450`) covers both
   partial ends before the merge. The journal does *not* drive the unaligned case:
   `joffset 0x402008` truncates to sector 8208 = byte 4202496 = block 1026 exactly, so
   journal I/O arrives 4 KiB-aligned (`Jnl: b(1,8)` at p5: 8 sectors at blkno 8). The
   RMW path is exercised by 512-byte metadata writes, and p6 proved it works.
   The partition bound re-check (`:281-286`) keeps the RMW from stepping outside
   `userdata`, which matters because the merge writes whole blocks, not the bp range.
4. **ICE.** No corruption path found, only an unchecked assumption (S10). If ICE were
   encrypting, reads would already be garbage — the volume mounts, so the LU is in
   bypass and writes inherit it.
5. **SDM845 assumptions.** `UTRLCLR` written as `~1u` is correct on Qualcomm, whose
   register is inverted — the shim says so explicitly (`avicii/shim/ufs.c:133`), so this
   is not a defect. `NUTRS` = 32 slots here, driver uses slot 0 only. PRDT `dbc` is 18
   bits, `PRDT_CHUNK` 256 KiB matches it. No doorbell/UTRD-count assumption breaks on
   lito. The lito-specific gaps are the power-mode handling (S4, `lito.dtsi` `ufs-luns`
   + `qcom,ice`) and the lane/gear assumptions, which reads already validate.
6. **Failing write → error or wedge.** The error does reach the buffer cache
   (`buf_seterror` + `buf_biodone`, `:465-469`), and `strategy` stops at the first
   failing chunk. What is missing is recovery, not reporting: S1 (window left with the
   device), S2 (no sense, no retry), S7 (no host re-check). A single transient on a large
   write therefore fails a whole 1 MiB bp and, with the journal, the mount.

## Patches

Four, numbered after the highest existing (`0096`), each `git apply --check` and then
`git apply` tested in order on a clean `xnu-8796.141.3` with the whole series applied,
`check-hunk-counts.py` clean:

* `0100-sweet-ufs-write-retire-retry.patch` — S1 + S2 (sense decode, retire, bounded retry)
* `0101-sweet-ufs-write-power-mode.patch` — S4 (SSU to the well-known LU on `2/04/02`)
* `0102-sweet-ufs-write-short-transfer.patch` — S3 (residual check)
* `0103-sweet-ufs-write-durability.patch` — S5 (FUA / per-write SYNCHRONIZE CACHE, opt-in)

`series` has them appended after `0099`. Nothing here is on by default except the
retry/sense/residual fixes; `ufsfua=1` and `ufssync=1` are boot-args for the RW
attempts that matter.

`0097-sweet-ufs-gpt-bound-check` and `0098-sweet-ufs-io-limits` were added to the
working tree while this audit was running; the four patches here were regenerated on
top of them and apply after them. `0103` also updates `0098`'s `DKIOCGETFEATURES`
comment, which claimed "no FUA" and would otherwise have gone stale.

## Not verifiable without the device

* Whether this UFS device accepts FUA and how much it costs (UFS supports it; the
  per-write flush variant `ufssync=1` exists as the portable fallback).
* What the device actually answers on a stalled window, and whether the lito host honours
  `UTRLCLR` while the device still owns the bounce buffer. `0100` waits a bounded second
  and clears afterwards; the real value may want raising for a slow device.
* Whether the sense key/ASC/ASCQ offsets (34/36/46/47) land where the device puts the
  fixed-format sense data — they follow the UFS 3.1 RESPONSE UPIU layout and the
  downstream `0084` patch, but only a device can confirm the content.
* ICE state for LU 0, and whether ABL ever leaves it enabled on a `fastboot flash
  userdata`.
* Nothing was compiled into a kernel: the changed functions were syntax-checked
  standalone (`clang -fsyntax-only -Wall -Wextra`, clean) and the series was only
  apply-tested.
