# Perf lane A — DDR and interconnect bandwidth votes

Read `perf-shared.md` first. **Owns:** `docs/perf-research/A-ddr-bandwidth.md`.

**Question:** CPU compositing at 1125×2436 reads and writes ~11 MB per full frame several times
over, and nothing in our kernel ever asks RPMh for more DDR or interconnect bandwidth. How does
the vendor raise DDR / LLCC / CNOC frequency, and what is the smallest thing our kernel can do
to get the same?

Determine:
1. The RPMh BCM resources involved (`MC0`, `SH0`, `ACV`, `CN0`, … — cmd-db names; the GPU layer
   already resolves cmd-db, see `sweet_gpu.c` `cmddb_find` in `xnu-avicii/patches/0122-*`) and
   how a vote is encoded (BCM vote: AB/IB, unit, `vote_x`/`vote_y`, commit bit), from the vendor
   `drivers/soc/qcom/msm_bus/msm_bus_rpmh.c`/`msm_bus_bimc_rpmh.c` or `drivers/interconnect/`,
   and `drivers/soc/qcom/rpmh*.c`.
2. Which RSC/DRS our kernel can write from EL1 (the APPS RSC, its TCS layout and addresses from
   the live dts `rsc@18200000` or equivalent), and whether `sweet_rpmh.c` (see the series) can
   already send BCM votes or only regulator votes.
3. The DDR frequency table for this phone (LPDDR4X, from the dts `ddr-freq`/`qcom,bw-tbl` /
   `suspendable_ddr_bw_opp_table` / `ddr_bw_opp_table`) and the vote the vendor uses for display
   + CPU at 60 fps (`devbw`, `bwmon`, `memlat` governors: what they vote under load).
4. Whether the L3 (already at max via OSM) and LLCC need anything else.
5. A measurement: how to test bandwidth before/after on the phone (a memcpy benchmark binary on
   the iOS side, or timing `kern.sweet_*`); estimate the gain for the backboardd frame cost.
