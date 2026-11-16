# Perf lane C — UFS storage speed

Read `perf-shared.md` first. **Owns:** `docs/perf-research/C-ufs.md`.

**Question:** app launch and boot read a lot from the root in `userdata`. What link speed,
queue depth and features does our `sweet_ufs.c` use, compared with the vendor, and what would
the vendor's settings gain?

Determine:
1. What our driver negotiates today: read the UFS patches in the series (`0028`, `0030`, `0034`,
   `0069 sweet-ufs-faster`, `0097`–`0102`) — HS gear, rate A/B, lanes, power mode (FAST/FASTAUTO),
   number of outstanding commands, transfer size limits, interrupt vs polling.
2. What the vendor does: live dts `ufshc@1d84000` (or the lito address) and `ufs_phy`
   properties (`lanes-per-direction`, `limit-tx-hs-gear`, `limit-rx-hs-gear`, `limit-rate`,
   clocks and their max frequencies, `ice` inline crypto), and vendor `drivers/scsi/ufs/ufs-qcom.c`
   / `ufshcd.c` (power-mode change, clock scaling, `write booster`, auto-hibernate).
3. The device's capabilities: the UFS chip on this phone (vendor/model if the live dts or our logs
   show it, e.g. `logs/phone/*` UFS probe lines), its max gear, WriteBooster support.
4. Plan: ordered changes with risk (a bad power-mode change can wedge the link — say how the
   driver recovers), and a measurement: `dd` read speed on the phone over SSH and boot-to-SpringBoard
   time from `logs/phone/live-*.txt`.
