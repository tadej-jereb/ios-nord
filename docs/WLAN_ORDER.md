# WLAN bring-up ladder (avicii, WCN3990 over SNOC)

Companion to `docs/WLAN_MAP.md`. Numbered milestones, each one boot-arg level, each independently
testable, each with the point at which the phone is provably still recoverable.

One monotonic gate: `sweetwifi=<N>`, where `sweetwifi=N` runs milestones W1..WN and nothing more.
`wifi`/`modem` from the topaz series are folded into it.

**The series this is ported from never powers the chip.** On topaz the WLAN sits inside the modem and
rides the modem's rails; the word "regulator" does not appear anywhere in 0113-0130. On avicii the five
PMIC rails are ours (W4 below), which is why W4 has no topaz counterpart at all.

---

## 0. Rules that hold for the whole ladder

1. **No boot-arg, no Wi-Fi code.** `start()` maps nothing and touches nothing. The stock boot and the
   `sweetwifi=0` boot must be behaviourally identical before W1 is merged.
2. **Panics stay visible.** Never boot a Wi-Fi milestone with `sweetfb_noconsole=1`. Bergamota lost two
   boots to panics that looked like freezes behind that flag, then found the panic was an
   `ml_io_unmap` on a `KMA_PERMANENT` mapping [see `WLAN_MAP.md` §4, finding 1].
3. **Write-combined carve-out mappings must come from `ml_io_map_unmappable()`**, never
   `ml_io_map_wcomb()`; `ml_io_unmap()` refuses a permanent VM entry [`WLAN_MAP.md` §4, finding 1].
4. **Nothing is written to a partition.** rmtfs stays read-only in RAM. No milestone below can corrupt
   EFS, `persist`, `modem` or the GPT.
5. **Each milestone logs `step N: …`, flushes, and pauses before the first new hardware access** so the
   last line names the step that stopped the phone. `sweetwifistep=N` (stop cleanly before step N) is
   mandatory from W6 on.
6. **One new mechanism per milestone.** Never a register poke and a protocol step in the same rung.
7. **0128 (`iokit-quiesce`) lands before the first netif** (W15). Without it IOKit never quiesces,
   configd's InterfaceNamer never reports quiet, and `wifid` hangs boot [V `0128:37-38`].
8. **Rails come back down in reverse order on every failure path**, and the failure path is entered
   from the same place that logs it.

---

## Recovery floor

The phone is in a known-good state before W1 only if all of these hold, re-checked before every rung
that touches hardware:

- `fastboot` reachable from the host, and a known-good boot image on the host, not only on the phone
  (bootloader unlock is tomorrow; this is the first thing done after it);
- `sweetwifi` one level lower reproduces the previous rung's pass line, tested once after each merge;
- the USB console reaches the host and the persistent log survives a freeze ([V] Bergamota recovered
  every freeze that way, e.g. `WIFI_IOS26.md:370`).

**Earliest point the phone can be left unbricked if it goes wrong: before W1.** Gate closed, nothing
mapped, nothing powered, nothing of the modem started — identical to the pre-Wi-Fi boot. That floor is
re-established before every rung by the one-level-lower check above, so it is also the stop point for
every rung: drop the number, reboot, done.

---

## Ladder

### W1 — Harness and read-only probes
- **Gate:** `sweetwifi=1`. **Touches nothing writable.**
- **Increment:** map and print, read-only: the live FDT reserved-memory entries (the `pil_wlan_fw_region`
  reg, and a free DDR window), the SMEM partition table with the apps↔modem item list, `smp2p_wlan_1_in`
  host ids if the node exists, the `apps_smmu` `SMR`/`S2CR` state for SID `0xC0`, the IPCC client/signal
  ids, and the five rail phandles with their RPMh resources.
- **Pass:** resolves every [U] in `WLAN_MAP.md` §5 — MSA base/size as the FDT actually has it, the WLAN
  FW path inside the `modem` FAT image, the SMP2P ids, the rail APIDs.
- **Fails as:** a map of a wrong address → freeze (unclocked/protected block, `WLAN_MAP.md` §4, finding 2)
  → plain reboot.
- **Unbricked at:** the floor itself. Everything up to W5 also costs only a reboot.

### W2 — GLINK + QRTR, passive
- **Gate:** `sweetwifi=2`. **Touches:** SMEM FIFOs (intent writes only into our own TX FIFO).
- **Increment:** GLINK VERSION/ACK on the modem channel, IPCRTR HELLO, QRTR router; log every
  `NEW_SERVER`. No WLFW traffic.
- **Pass:** `WLFW service 0x45 up: inst … node … port …` (topaz's exact line, `0119:18`) and steady rx/tx
  with no drops.
- **Fails as:** no HELLO → the doorbell is wrong, check the IPCC pair; or a hang → reboot.
- **Unbricked at:** yes. The modem is untouched; FIFO state dies with the next modem boot.

### W3 — SMP2P wlan in-item registration
- **Gate:** `sweetwifi=3`. **Touches:** our SMP2P in-item header + one kick.
- **Increment:** register the inbound item with `master-kernel` and `wlan` entries **before** any start
  (anonbeat1's found ordering, `anonbeat1-NOTES.md:1219`), direction `<in out>`, then one kick.
- **Pass:** our header keeps the entries we wrote, valid=2, remote does not claim the item.
- **Fails as:** valid=0 or the remote rewriting our names = direction swapped [V
  `anonbeat1-NOTES.md:1212-1214`].
- **Unbricked at:** yes, reboot.

### W4 — PMIC rails and the reference clock (no topaz counterpart)
- **Gate:** `sweetwifi=4`. **Touches:** RPMh regulators and the CXO branch, chip still unpowered.
- **Increment, in ath10k's order** (`snoc.c:1022-1048`: pwrseq → regulators → clocks; avicii has **no**
  `qcom,pwrseq`, so by `snoc.c:1804-1820` all five rails are driver-owned, PalanBanana's rule
  `0083.patch:177-178`):
  1. `vdd-cx-mx` = `L1A` — first, it powers part of the SoC;
  2. `vdd-1.8-xo` = `L14A`;
  3. `vdd-1.3-rfa` = `L2C`;
  4. `vdd-3.3-ch1` = `L11C`, then `vdd-3.3-ch0` = `L10C`, at the DT's own config ranges
     (`qcom,vdd-3.3-ch*-config = <3000000 3312000>` [V `lito.dtsi:3783-3785`]);
  5. `cxo_ref_clk_pin` (**not** `rfclka2` — that waits for W12).
- **Pass:** five rails read back enabled at the requested voltage, clock vote accepted.
- **Fails as:** a rejected voltage = a wrong APID (go back to W1); a hang = a bad regulator node. These
  are LDO settings, so a legal-but-wrong voltage damages nothing.
- **Unbricked at:** yes — rails drop on reboot. **This is the first rung that changes the power state of
  hardware the stock stack also owns**, so it runs with the recovery floor freshly re-checked.

### W5 — MSA handover (first TZ-mediated step)
- **Gate:** `sweetwifi=5`. **Touches:** SCM hyp-assign of the `pil_wlan_fw_region` window to VMIDs
  `0x18`/`0x19`.
- **Increment:** bound-check against the **live** FDT value (not topaz's `0x51900000` constant), then
  assign in `w_on_msa_info()`'s shape (`0122:331-338`).
- **Pass:** every segment "assigned", none "out of the MSA window, skipped".
- **Fails as:** SCM error → log, drop rails, abort. A wrong window silently corrupts DDR the modem later
  reads; treat a single "skipped" as a stop.
- **Unbricked at:** yes, but this is the first rung whose failure can be silent. Do not proceed on a
  partial pass.

### W6 — WLFW handshake to CAP
- **Gate:** `sweetwifi=6`, stop-step armed.
- **Increment:** IND_REGISTER (fw_ready + msa_ready enable, client id `0x4b4e454c`), **host_cap** with
  `daemon_support = 0` (avicii has no `snoc-host-cap-skip-quirk`), MSA_INFO carrying the DT base/size,
  MSA_READY, CAP.
- **Pass:** `wlfw: cap ok` with the CAP TLVs parsed.
- **Fails as:** cap error → dump the response (0124 already does), retry ≤5×; a PD restart is handled by
  `0124`'s re-handshake.
- **Unbricked at:** yes — the PD is restartable, a stuck handshake is a reboot.

### W7 — BDF through WLAN_CFG / WLAN_MODE
- **Gate:** `sweetwifi=7`.
- **Increment:** board-data segments from the board file, CAL_REPORT, wait FW_READY, WLAN_CFG, WLAN_MODE
  mission.
- **Pass:** `*** WLAN FIRMWARE READY ***` then `*** WLAN ON (mission mode) ***` (`0122`).
- **Fails as:** a firmware assert on a bad CE config in WLAN_CFG — the tables are `host_ce_config_wlan`
  (`0123:185-190`) and must be checked against WCN3990 before this rung, not after.
- **Unbricked at:** yes, but from here the WLAN PD stays up for the rest of the session, so every later
  failure is "modem alive, reboot to clear" rather than "nothing happened".

### W8 — SMMU identity, CE rings, polled
- **Gate:** `sweetwifi=8`.
- **Increment:** `smmu_identity()` with avicii's SID `0xC0`/mask `0x1` (reusing an existing SMR if the
  bootloader left one, `0123:109`), then CE rings from the pool at `0x18800000+0x240000` (shadow
  `+0x32000`) — **polled, no interrupts**.
- **Pass:** `smmu: … identity (sid c0 mask 1) … -> OK` (topaz's own read-back), rings configured, RRI
  base written.
- **Fails as:** S2CR not as written → stop; a CE write while the PD is down hangs the SNOC bus → freeze.
- **Unbricked at:** yes, reboot. W7 must be green first or the CE block is unclocked.

### W9 — CE interrupts
- **Gate:** `sweetwifi=9`. Take the 12 CE SPIs from `lito.dtsi:3762-3771` and switch the rings from
  polled to interrupt-driven.
- **Why separate:** W8 polled is a working baseline; a broken IRQ path must not be able to make it look
  broken.
- **Unbricked at:** yes.

### W10 — HTC READY + WMI READY (0128 merged here)
- **Gate:** `sweetwifi=10`.
- **Increment:** HTC READY on ep0, connect HTT_DATA and WMI_CONTROL, SETUP_COMPLETE_EX; SERVICE_READY →
  INIT (host-memory chunks) → READY. Merge 0128 in this image.
- **Pass:** `WMI READY`.
- **Fails as:** init rejected = bad resource config; log it, drop rails, no harm.
- **Unbricked at:** yes.

### W11 — HTT setup, then a passive scan
- **Gate:** `sweetwifi=11`.
- **Increment:** the **full** `ath10k_htt_setup()` (RX ring, frag-desc bank, aggr) *before* the scan,
  then a passive scan only.
- **Pass:** non-zero beacons and BSS count. Bergamota got `0 beacons` across 26 channel visits when they
  scanned first and `12 networks` once the RX ring existed [`WLAN_MAP.md` §4, finding 3] — this rung is
  where that is paid for in advance.
- **Fails as:** commands accepted, COMPLETED reason 0, zero frames → the RX path is not configured; go
  back to the HTT half, do not advance.
- **Unbricked at:** yes.

### W12 — RF reference clock vote (`rfclka2`)
- **Gate:** `sweetwifi=12`. Only if W11 shows a dead or idle receiver (noise floor ~-118 dBm with ~0 %
  rx_clear).
- **Pass:** rx_clear and rx_frame rise on 2.4 GHz.
- **Unbricked at:** yes.

### W13 — Assoc to an open network, then DHCP
- **First transmitting rung.** Use the user's own hotspot.
- **Pass:** assoc response, then an IP on the existing `ue0`/configd plumbing.
- **Fails as:** firmware asserts on wrong WMI sequences (empty HT rate sets, keepalive > 0xffff); each
  sequence is reviewed against ath10k before it boots.
- **Unbricked at:** yes.

### W14 — WPA2-PSK 4-way with a wifid-supplied PMK
- **Gate:** `sweetwifi=13`. Uses `topaz_wlan_join_pmk()` (0130) so the passphrase never leaves the phone;
  `topaz_wlan_join()` stays as the CLI fallback.
- **Unbricked at:** yes.

### W15 — netif `en0`, Settings, wifid
- **Gate:** `sweetwifi=14`. Requires 0128 (landed at W10) and the ADT `wlan` node.
- **Fails as:** **boot stall**, not brick — wifid waits for a quiet IOKit that never comes. Reboot with
  the gate one lower.
- **Unbricked at:** yes, by dropping the gate.

---

## Ordering rules that are not negotiable

1. W4 (rails) before W8 (CE) — the block is unpowered and unclocked until then.
2. W5 (MSA assign) before W6 (MSA_INFO) — `msa_info` hands over a window the WLAN VM must already own.
3. W7 (mission) before W8 (CE) — the PD has to be running.
4. W11's HTT half before W11's scan half. The single most expensive lesson in the references.
5. 0128 before W15, shipped at W10 so it cannot be forgotten.
6. Direction of `qcom,smem` is `<in out>`; if the remote claims our item, stop and re-read the DTS rather
   than trying the other order twice.
7. Rails down in reverse on every abort, before the log line that reports the abort.

## What would make this order wrong

- If the live FDT shows no writable out item under `smp2p_wlan_1_in`, W3 changes shape and the kick must
  come from the IPCC side alone. Resolve at W1, before W3.
- If the `modem` FAT image holds no `wlanmdsp.mbn`, the firmware source changes (W7's board data and the
  TFTP path), not the order.
- If `apps_smmu` already holds a valid SMR for `0xC0` from the bootloader, W8 must reuse that slot.
- If stock's own driver leaves a rail on at handover, W4's read-back will show it; the correct behaviour
  is then to adopt the existing state rather than re-enable blind.
