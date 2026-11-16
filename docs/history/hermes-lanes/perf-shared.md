# Shared brief for the performance / battery lanes — read me first, then your lane file

Repo: `/home/tadej/ios-nord`. You are one of eight parallel research lanes, coordinated by Hermes.
iOS 16.7.16 (iPhone X userland) runs on the OnePlus Nord (`avicii`, Qualcomm SM7250 "lito":
2× Kryo 475 Gold A76 + 6× Silver A55, Adreno 620, UFS, PM7250B PMIC) on a patched XNU kernel
(`xnu-avicii/series`). It works but is slow and runs hot: every CPU core and the L3 are pinned
at max clock, nothing ever idles deeply, DDR bandwidth is never voted up, and the battery
gauge is minimal. The GPU bring-up is a separate track in progress (`docs/gpu-research/`).
**Your lane researches one area and writes the plan for it. You do not implement it.**

Read in this order: `AGENTS.md`, `docs/STATUS.md` (first entry), `avicii/CONSTANTS.md` (every
hardware constant with its source; the "CPU", "GPU" and power sections), then your lane file.

Sources of truth (AGENTS.md ground rules apply: vendor dts + live reads only, never a spec sheet;
anything not read from those carries **UNVERIFIED**):
* The phone's live device tree, decompiled: `~/.hermes/cache/scratch/perf-inputs/live.dts`
  (copied from the running Android's `/sys/firmware/fdt`; sha256 starts `de87b3009781a8b1`).
* Vendor dts fragments: `avicii/lito.dtsi`, `avicii/avicii.dtsi`, `avicii/panel.dtsi`,
  `refs/lito-dts/*.dtsi` (`lito-pm.dtsi` = idle states / LPM, `lito-regulators.dtsi`), the dtbs
  in `src/avicii-*.dtb`.
* Vendor kernel source: LineageOS `android_kernel_oneplus_sm8250` branch `lineage-21` on GitHub
  (avicii builds from it). Fetch single files with `curl` from raw.githubusercontent.com into
  `~/.hermes/cache/scratch/<lane>/`, or a shallow sparse clone there. Cite file:line + branch.
* Linux mainline (for comparison only) and Apple's open-source XNU 8796.141.3 at
  `~/xnu-8796.141.3` — **read only**; it is the main agent's build tree, reset between builds.
  To read our patched kernel source, read the patches in `xnu-avicii/patches/` (the `sweet_*.c`
  files are added by them), not the tree.
* Phone evidence already captured: `logs/phone/` (live kernel logs, thread dumps such as
  `bbd-threads-0116-*.txt`, temperature readings in `kern.sweet_cpufreq` outputs). Read only.

Rules that hold for every lane:

* **Read-only research.** Never touch the phone, `adb`, `fastboot`, any partition,
  `xnu-avicii/`, `~/xnu-8796.141.3`, `tooling/71*`/`74*`, `build/`, or CI (`gh workflow run`).
  The main agent is booting test kernels on the one phone; interfering breaks its run.
* You own the one file your lane names and nothing else. Two lanes never write the same file.
  Do not `git add/commit/checkout/stash`; the coordinator commits. Do not edit `.hermes-lanes/`.
* Apple binaries (only lane H needs them): analyse locally, describe in your own words; no
  decompiled or disassembled Apple code in the repo. Raw output stays in
  `~/.hermes/cache/scratch/<lane>/`.
* Run Python that reads downloaded files with `python3 -I`; keep scripts outside download dirs.
* Every number in your report comes from a command you ran or a line you can cite. Mark
  inferences as **inferred**. If blocked, say so and why — a smaller honest result beats a
  padded one.

Every report has the same shape:
1. **Summary** (≤15 lines): the finding, and the expected gain (fps, ms, mW, °C, MB/s — say
   which are measured and which estimated).
2. **What the vendor does**, with citations.
3. **What we do today**, with citations into `xnu-avicii/patches/` and `logs/phone/`.
4. **Plan**: concrete kernel/userland changes in order, each with the registers / RPMh
   resources / SMC calls / boot-args involved, the risk (can it hang or brick? anything
   touching `persist`, `modemst`, `xbl`, `abl`, `tz` or the GPT is out of scope), and how to
   measure that it worked on the phone (which sysctl, log line or timing).
5. **Open questions** that only a run on the phone can answer.
