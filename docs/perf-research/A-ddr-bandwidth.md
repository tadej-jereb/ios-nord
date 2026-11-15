# Lane A — DDR / interconnect bandwidth votes (RPMh BCM)

Scope: what the vendor does to raise DDR and LLCC frequency, what our kernel does today, and the
smallest change that reproduces it. Everything below is read-only research; nothing was run on the phone.

## 1. Summary

- **Finding:** on lito the DDR and LLCC clocks are set only by RPMh **BCM** votes on the APPS RSC.
  Our kernel never sends one — `grep -rn "bwmon\|memlat\|devbw\|bandwidth" xnu-avicii/patches/*.patch`
  returns nothing, and the one place MC0/SH0 are named (`0122`, GPU HFI table) writes the value **0**
  (release). So DDR/LLCC stay at whatever ABL/the RSC default left them at, for the whole uptime.
- The vote is one 32-bit word per resource: `commit<<30 | valid<<29 | AB<<14 | IB`, AB/IB clamped to
  14 bits (`msm_bus_fabric_rpmh.c:26-38`). Three single-command ACTIVE-TCS writes reproduce the
  vendor's maximum: **SH0 = 16265** (LLCC), **MC0 = 7980** (DDR), **ACV = 8** (APPS active bit).
  Addresses are already known from our own run: `0x50004 / 0x50000 / 0x5007c` (log line cited in §3).
- Mechanically nothing new is needed: `sweet_rpmh.c` already maps DRV2, arms an ACTIVE TCS, sets
  AMC mode, triggers and polls completion; that path is **proven** by the touch L13 vote.
- Frame traffic: 1125×2436×4 = **10 962 000 B (10.45 MiB)** per full-surface pass (computed).
  One pass at the DDR table bottom (762 MiB/s) = 13.72 ms, at the top (7980 MiB/s) = 1.31 ms;
  a two-pass composite = 27.4 ms vs 2.6 ms (computed from `avicii/lito.dtsi:3306-3319`).
- **Estimated gain:** 5–25 ms off a frame *if* DDR/LLCC are currently near the bottom OPP and the
  composite is bandwidth-bound. Against today's **measured** 10 Hz / 100 ms per frame
  (`docs/STATUS.md:48`) that is 5–25 % of frame time, i.e. 10 Hz → 10.5–13 Hz. **ESTIMATED** — the
  memcpy test in §4 turns it into a measurement in one boot.
- Power and temperature cost of the higher OPP is **unmeasured and unmeasurable today** (no battery
  gauge, `docs/STATUS.md:47`). It is a race-to-idle trade, not a guaranteed saving.

## 2. What the vendor does

**The resources.** The live FDT's `ad-hoc-bus` block names one BCM node per resource with the cmd-db
cell id, e.g. `bcm-mc0 { cell-id = <0x1b58>; label = "MC0"; qcom,bcm-name = "MC0"; }`
(`live.dts:12148-12155`), `bcm-sh0` = `0x1b5b` (`:12157-12164`), `bcm-acv` = `0x1b7e` (`:12166-12173`),
`bcm-cn0` = `0x1b7c` (`:12220-12227`). The driver resolves each name through cmd-db and takes the
*aux data* with it: `msm_bus_bcm_init()` → `cmd_db_read_addr(name)` +
`cmd_db_read_aux_data(name, &aux)` where `struct bcm_db { u32 unit_size; u16 width; u8 clk_domain; }`
(`msm_bus_fabric_rpmh.c:55-60, 1168-1190`).

**Which BCM belongs to which path.** The bus fabric in the live FDT attaches BCMs to the *slave*
nodes, and that is the only place the mapping exists:

| path | slave node | bcms |
|---|---|---|
| CPU → LLCC | `slv-qns-llcc`, cell-id `0x302`, buswidth `0x10` | `SH0` (`live.dts:13895-13903`) |
| LLCC → DDR | `slv-ebi`, cell-id `0x200`, buswidth `0x04` | `MC0 + ACV` (`live.dts:13925-13929`) |

That matches the two devbw clients in `avicii/lito.dtsi` — `cpu_cpu_llcc_bw` with
`qcom,src-dst-ports = <MSM_BUS_MASTER_AMPSS_M0 MSM_BUS_SLAVE_LLCC>` over `llcc_bw_opp_table`
(`:3286-3293`) and `cpu_llcc_ddr_bw` with `<MSM_BUS_MASTER_LLCC MSM_BUS_SLAVE_EBI_CH0>` over
`ddr_bw_opp_table` (`:3321-3328`), both `qcom,active-only` + `governor = "performance"`.

**The vote encoding.** `#define BCM_TCS_CMD_COMMIT_SHFT 30`, `VALID 29`, `VOTE_X 14`, `VOTE_MASK
0x3FFF`, `VOTE_Y 0`, `cmd->data = BCM_TCS_CMD(commit, valid, vec_a, vec_b)`
(`msm_bus_fabric_rpmh.c:26-38, 254-276`). `valid` is cleared when both votes are 0, i.e. "release".
`commit` is set on the **last command of each VCD**, and a VCD is the BCM's `clk_domain` from cmd-db
aux (`:443`). Before each batch the driver sends `rpmh_invalidate()` then
`rpmh_write_batch(ACTIVE / WAKE_ONLY / SLEEP)` (`:595-670`); a single-BCM request is legal on its own:
`bcm_commit_single_req()` builds one command with `commit = true` and
`rpmh_write(..., RPMH_ACTIVE_ONLY_STATE, &cmd, 1)` (`:726-740`).

**The units.** Clients vote bytes/s: `devfreq_devbw.c:46-63` does `vectors.ib = freq * MBYTE` where
`freq` is the OPP value from the dts table. The driver then divides by `unit_size`
(`msm_bus_arb_rpmh.c:553-554`) and clamps to `0x3FFF`. Because `MHZ_TO_MBPS(mhz, w)` (`lito.dtsi:17`)
is `mhz·10^6·w / 2^20`, the table integers *are* MiB/s: `MHZ_TO_MBPS(2092,4) = 7980`,
`MHZ_TO_MBPS(1066,16) = 16265`. Both reproduce the dts comments exactly (checked with `python3 -I`),
and 16265 sits just under the 14-bit ceiling 16383 — so **inferred**: `unit_size` = 1 MiB and the
field carries the table integer as-is.

**The DDR table** (LPDDR4X, `ddr_bw_opp_table`, `avicii/lito.dtsi:3306-3319`): 200 MHz → 762,
300 → 1144, 451 → 1720, 547 → 2086, 681 → 2597, 768 → 2929, 1017 → 3879, 1353 → 5161, 1555 → 5931,
1804 → 6881, 2092 → 7980 (MiB/s). LLCC (`llcc_bw_opp_table`, `:3263-3272`): 150 MHz → 2288 …
1066 → 16265. `suspendable-*` variants add a `0` entry for the sleep set (`:3340-3354`).

**What the vendor votes at load.** It does not vote a constant; two mechanisms raise the level:
(a) `qcom,arm-memlat-mon` latency monitors with a per-CPU-clock floor — A55 group tops out at
1728000 kHz → `MHZ_TO_MBPS(1017,4)` DDR (`lito.dtsi:3483-3494`), A76 group at 2350000 → 1804 and
3000000 → 2092, and LLCC 2350000 → 933, 3000000 → 1066 (`:3544-3599`); (b) hardware counters,
`qcom,bimc-bwmon4@90b6400` (CPU→LLCC, IRQ 581) and `bimc-bwmon5@90cd000` (LLCC→DDR, IRQ 263), which
re-vote from measured bytes (`lito.dtsi:3295-3304, 3330-3338`). So at any high CPU clock the vendor's
floor is the table maximum: **7980 DDR / 16265 LLCC**. Our cores are pinned at fmax
(`0115`, `0116`), i.e. the vendor's own rule would have us at both maxima permanently.

**ACV.** The apps RSC sets bit `BCM_TCS_CMD_ACV_APPS = 0x8` whenever the aggregated bandwidth is
non-zero, and clears it when zero — with a comment that the bit is per-RSC until cmd-db maps ACV per
master (`msm_bus_arb_rpmh.c:23, 473-495`). It is written as `vec_a = 0, vec_b = mask`.

**The transport.** `rsc@18200000` has three 64 KiB DRV blocks, `qcom,drv-id = <2>`,
`qcom,tcs-offset = <0xd00>`, `qcom,tcs-config = <2 2 0 3 1 3 3 1>` → ACTIVE 2 / SLEEP 3 / WAKE 3 /
CONTROL 1 (`live.dts:5488-5496`; CONSTANTS.md:75-77). TCS stride `672`, command stride `20`, MSGID
`0x30` / ADDR `0x34` / DATA `0x38`, `TCS_AMC_MODE_ENABLE BIT(16)`, `TCS_AMC_MODE_TRIGGER BIT(24)`,
msgid `= len(8) | RESP_REQ(0x100) | WRITE(0x10000)` (`rpmh-rsc.c:38-71, 326-360`). Display has its
own RSC at `0xaf20000` (`live.dts:6316-6319`) — irrelevant to us, our framebuffer is CPU-driven.

## 3. What we do today

- `sweet_rpmh.c` is created by `xnu-avicii/patches/0062-sweet-touch-power-battery.patch:111` and
  addresses DRV2 only. `0111-avicii-rpmh-drv2-cmddb.patch:19-24` fixes `RH_RSC_PA 0x18220000`,
  `RH_TCS_PA 0x18220d00`, `RH_DICT_PA 0x80860000` (in-place cmd-db), `RH_DRV 2`.
- It speaks **regulator only**: `rh_lookup()` rejects anything whose cmd-db slave is not 4 or whose
  address is not `4xxxx` — `if (slave != RH_VRM || (addr >> 16) != RH_VRM || (addr & 15u))`
  (`0062:301`), and `rh_send()` writes exactly three commands with a PMIC5-LDO policy
  `offsets {0,8,4} / values {mv,7,1}` (`0062:334-397`). So MC0 (`0x50000`, ACCL type 5 = BUS) is
  rejected by the lookup, and there is no code path that writes a raw BCM word.
- Proven on the phone: `SWEET RPMH: rsc=0x18220000 tcs=0x18220d00 DRV=2 … config=0x800c8104 TCS=8
  ncpt=16` → `TCS0 ACTIVE 3008 mV mode=7 enable=1` → `TCS0 done=1 irq=0 idle=0x1 cmd-status=0x10101/…`
  (`logs/phone/20261114-194619-0110f-touch/ring-pre.txt:2705-2717`). The AMC enable/trigger/poll
  sequence works on this silicon.
- The GPU layer already resolves the four bus resources for its HFI table —
  `cmddb_find("SH0"/"MC0"/"ACV"/"CN0")` (`0122-avicii-gpu-a620-gmu-boot.patch:767-768`) — and the
  phone printed the addresses: `SWEET GMU: [HFI] votes … bus SH0 0x50004 MC0 0x50000 ACV 0x5007c
  CN0 0x50074` (`logs/phone/20261115-145855-usb-kernel-0123-gpu9/ring-pre.txt:239`). But the data
  written there is `0x40000000` = commit + valid = 0, i.e. **release** (`0122:772`).
- L3 needs nothing: it is `qcom,devfreq-fw` voted by the OSM domains themselves and every core is at
  fmax (`0115`, `0116`, CONSTANTS.md:50). LLCC has no separate control in our kernel — the SH0 vote is
  the only lever, and it is unused.

## 4. Plan

Ordered; each step is independently testable and none can brick (RPMh votes are volatile state —
a wrong value is lost on reboot; nothing touches `persist`, `modemst`, `xbl`, `abl`, `tz` or the GPT).

**Step 1 — print the ground truth (no writes).** Add `kern.sweet_ddr` (CTLTYPE_STRING, RD, same idiom
as `kern.sweet_cpufreq`, `0116:311`) that walks the cmd-db for `MC0/SH0/ACV/CN0` and prints addr,
`slave`, `unit_size`, `width`, `clk_domain` from the aux blob (`RH_DB_HEADER`-relative offsets already
computed in `rh_lookup`, `0062:274-320`), plus the DRV2 `config` register. *Risk:* read-only, none.
*Success:* one log line per resource; `unit_size` confirms or refutes the 1 MiB inference in §2.

**Step 2 — a raw BCM writer.** In `sweet_rpmh.c`: (a) relax `rh_lookup` to accept `slave == 5` and
`addr >> 16 == 5` with no 16-byte alignment check; (b) add `sweet_rpmh_bcm(name, u32 value)` that
reuses the existing TCS pick/arm/poll/cleanup code but writes **one** command —
`MSGID = 0x10108`, `ADDR = cmd-db address`, `DATA = 0x60000000 | (value & 0x3FFF)` (commit + valid +
the table integer), `WAIT = 1`, then `CONTROL = AMC_EN`, `CONTROL = AMC_EN|TRIGGER`, poll
`CMD_STATUS == 0x10101`, clear CONTROL/ENABLE/WAIT and the IRQ bit. Boot-arg `sweetddr=<MiB/s>`
(0 = off, default), `sweetllcc=<MiB/s>`, `sweetacv=0|1` (default 1). *Risk:* a TCS timeout leaves the
slot quarantined for the boot (already implemented, `0062:379-427`); a bogus value can hang DDR → the
boot stalls and the phone needs a reset — recoverable, never persistent.

**Step 3 — vote and watch.** Boot with `sweetddr=7980 sweetllcc=16265`. Expected log:
`SWEET RPMH: MC0 vote 7980 done=1 cmd-status=0x10101` (three lines). *Success criterion:* `done=1` on
all three, no `timeout`, GUI still renders. *Risk to watch:* a commit on MC0 alone — the vendor's own
`bcm_commit_single_req` does exactly this (`msm_bus_fabric_rpmh.c:726-740`), but not for MC0+APPS; if
`done=0`, fall back to one TCS carrying all three commands with `commit` only on the last, and to
grouping by `clk_domain` from step 1.

**Step 4 — measure the bandwidth, not the feeling.** Add `kern.sweet_bwtest` (int, RW): on write,
allocate two 8 MiB buffers, run `bcopy` over them 8 times, time with `mach_absolute_time` →
`absolutetime_to_nanoseconds`, print MiB/s, free. Run it twice per boot — `sweetddr=0` then
`sweetddr=7980` — and compare. This is the whole point of the lane: it converts §1's estimate into a
number. Cross-check with the real traffic counter if wanted: `bimc-bwmon5` at `0x90cd000`,
`MON2_BYTE_CNT` `+0x2D0` / `MON2_WIN_TIMER` `+0x2D4`, timer 19.2 MHz (`live.dts:7424-7432`,
`bimc-bwmon.c:53-54`) — needs the GCC bimc-bwmon clocks enabled first, so treat as optional.

**Step 5 — frame cost.** In `sweetfb`, count presents and expose `kern.sweet_fb_fps` (frames in the
last second). Compare 10 Hz baseline (`docs/STATUS.md:48`) before/after step 3 on the same boot phase
(same point in SpringBoard idle, same page). *Success:* the memcpy number moves and the fps moves in
the same direction; if memcpy moves and fps does not, the frame is CPU-bound and this lane is done.

**Step 6 — only if step 4 shows a real delta.** Make it dynamic instead of permanent: raise the vote
on the first present after a 100 ms gap and drop it to the 547 MHz level (`2086`) after 500 ms idle,
driven from the existing `sweetfb` present path. This is the power/temperature story; it needs a
battery gauge to be judged, which does not exist yet, so it must not be the first step.

## 5. Open questions only a phone run can answer

1. **What OPP does the RSC actually hold with no vote?** If ABL/RSC leave DDR at NOM, the whole gain
   collapses to the tail case and step 6 gets more interesting than step 3. Only the step-4 memcpy
   answers it.
2. **Is `unit_size` really 1 MiB for MC0/SH0**, and is `width` equal to the node's buswidth (4 / 16)?
   The 7980/16265 numbers say yes; the aux blob is the authority.
3. **Does this firmware honour a lone `commit` on MC0?** `bcm_commit_single_req` is a vendor pattern
   but ACV is normally in the same batch.
4. **Does the APPS ACV bit (`0x8`) matter here**, or is it dead RPM-era state? Test with
   `sweetacv=0` — if the vote has no effect either way, drop the command.
5. **Does a higher DDR OPP make the phone hotter or cooler** at idle-heavy SpringBoard? Unmeasurable
   without a gauge; the touch/CPU rails are already fixed.
6. **Does the GMU's own (zero) bandwidth table starve the GPU path** once the GPU comes up
   (`docs/gpu-research/`)? Same three BCMs, different writer.
