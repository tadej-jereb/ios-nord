# Track D — display, GPU, memory and daemon work

Static audit against `fork/kern-0150` (`0b457c4`). No phone, VM, builds, mounts or device writes.
All code-derived behavior, estimates and proposals below are **UNVERIFIED** on avicii;
vendor DTS statements describe the published configuration, not necessarily the live selection.
Paths are relative to the worktree except `build/` and `refs/`, read from the main checkout.

## Display

**UNVERIFIED current implementation:** selector 12 records display-off, fades pixels to black,
and leaves the panel powered; its off branch still rearms the vsync timer
(`xnu-avicii/patches/0079-sweet-display-power.patch:9`, `:38`, `:53`, `:63`).
Dirty-frame suppression already exists, so a static screen does not necessarily incur a
full copy each timer tick (`xnu-avicii/patches/0056-sweet-fb-throttled-present.patch:33`).
SwapWait waits for a shown frame with a deadline and skips sleeping while off; preserve
that contract and wake existing waiters on power changes
(`xnu-avicii/patches/0130-avicii-fb-swapwait-until-shown.patch:45`, `:65`).

The panel uses DCS brightness control, range 1–2047, and declares ULPS
(`avicii/panel.dtsi:903`, `:904`, `:905`, `:908`; also `avicii/CONSTANTS.md:95`
for its PMIC reset pin). The DTS off sequence contains display-off 0x28 followed by
sleep-in 0x10, with encoded delay bytes 0x0a and 0x78 (`avicii/panel.dtsi:193`).
**UNVERIFIED:** interpreting those delay units and successfully resuming this bootloader-owned
DSC/DSI path needs vendor driver verification; do not send the bytes from an arbitrary MMIO helper.
The published default mode is 60 Hz (`avicii/panel.dtsi:80`); changing software notification
frequency is not changing panel refresh (`xnu-avicii/patches/0056-sweet-fb-throttled-present.patch:25`).

**UNVERIFIED proposal:** first stop the software display timer after fade completion while off,
and rearm it under the same workloop gate on display-on. Add timer/copy/off-residency counters.
Next implement an asynchronous DSI off/on state machine using the selected panel's vendor
commands, preserving reset/rails and splash restore ordering. Physical panel sleep can save
more than black pixels, but no watt figure is defensible before measuring. Do not gate panel
rails or change refresh timing until resume is proven. Lowering active software vsync without
client pacing can cause stutter; leave active animation cadence unchanged.

## GPU

DTS bin-0 clocks are 625/500/400/275 MHz, with initial index 3
(`avicii/CONSTANTS.md:316`; `arch/arm64/boot/dts/vendor/qcom/lito-gpu.dtsi:191` at
[pinned Lineage commit 9ea68e4](https://github.com/LineageOS/android_kernel_oneplus_sm7250/blob/9ea68e4dee77be15d37a9044ecae6754fb2ca454/arch/arm64/boot/dts/vendor/qcom/lito-gpu.dtsi#L191)
(sha256 `a699812de8fcf441ea16e29a3fb4bc2241672428a8bf7ea08e60feb01bbb1c9e`)).
**UNVERIFIED correction:** the kernel HFI table reverses that order, reserving index 0 as off;
`g_speeds[1]` is 275 MHz, selected by `sweetgpu_speed=1` by default
(`xnu-avicii/patches/0122-avicii-gpu-a620-gmu-boot.patch:720`, `:741`, `:775`).
Do not confuse bring-up stage `sweetgpu=11`, DTS index 3, and HFI speed index 1.
Already at the lowest published active clock, a lower active clock is not supported by this evidence.
The kernel requests an OOB GPU keep-powered handshake and verifies GX status
(`xnu-avicii/patches/0122-avicii-gpu-a620-gmu-boot.patch:790`).

**UNVERIFIED proposal:** account submit/wait time and idle residency first. Only then serialize
submit, GPU-idle fence, GMU slumber request, acknowledgement, and wake/reinitialization under a
single GPU power lock. Keep timeout rollback and default-off boot argument. Directly clearing GX
GDSC is not a usable idle protocol: outstanding DMA, SMMU mappings, ring and firmware context
must survive or be reconstructed. GX register locations are published in the vendor GDSC table
(`avicii/CONSTANTS.md:318`); that table alone does not prove a working transition sequence.
Expected gain is idle GPU leakage/clock power, unknown magnitude; risk is a full device hang.

## DDR, LLCC and CPU L3

**UNVERIFIED recorded results:** keep the bootloader's DDR vote: the repository records
3850 MiB/s with it, 370 MiB/s after release, and about 15% regression with the port's own
vote (`docs/STATUS.md:36`). Never propose or run its release. The existing BCM sysctl accepts
writes, including zero/release; therefore it is not a harmless measurement interface
(`xnu-avicii/patches/0128-avicii-rpmh-ddr-llcc-bcm-votes.patch:138`, `:151`, `:225`).
**UNVERIFIED:** adding a lower independent vote cannot be assumed to lower a higher inherited
floor. Do not promise DDR battery gains from a lower `sweetddr` number. Leave `sweetddr` off;
measure bandwidth demand and power first. Future changes must preserve the inherited vote and
identify separate owned voters before any tuning.

CPU L3 and LLCC are different resources: the L3 devfreq node has a shared perf register and
separate CPU/CDSP voters (`avicii/lito.dtsi:1778`, `:1790`; `avicii/CONSTANTS.md:50`), whereas
SH0 is an RPMh BCM name in the port's LLCC vote path
(**UNVERIFIED code mapping:** `xnu-avicii/patches/0128-avicii-rpmh-ddr-llcc-bcm-votes.patch:126`, `:185`).
**UNVERIFIED proposal:** use track B's already-existing L3 cap interface for one-variable tests;
never identify SH0 with CPU L3 or lower it alongside CPU caps without a separate comparison.

## Read-only root-image launchd inspection

Source: `build/ios16-root.img`, inspected with `7z x -so`, no mount or root modification.
**UNVERIFIED completeness:** 7z returned exit 2 / Headers Error while the inspected plist
payloads parsed. For example photoanalysisd member SHA256 is
`2abdcd02bd5efa0efdeff04656c2aff22110d0f6ce2ef7dfc5b521a2822445be`.
This does not prove every root-image member is readable or that a job runs.
Citation notation `root!PATH:N` below means line N in canonical XML from
`plistlib.dumps(plistlib.loads(7z_stdout))` (Python default sorted keys), not a binary-plist byte line.
All conclusions from these plists are **UNVERIFIED** runtime behavior. Presence is not proof that
a job loads, loops, or consumes CPU. Exact source records:

| Candidate / dependency | Evidence in canonical XML (`root!iOSRoot/System/Library/LaunchDaemons/`) | Decision and risk |
|---|---|---|
| photoanalysisd | `com.apple.photoanalysisd.plist:17` AllowBattery=false; `:19` CPUIntensive=true; `:26` interval 7200; `:30` PreventsDeviceSleep=true; `:36` screen-sleep required | First optional A/B candidate if actually active; loses photo analysis. Zero gain if dormant. |
| mediaanalysisd | `com.apple.mediaanalysisd.plist:17`, `:19`, `:28`, `:36` similar maintenance task; `:169` preheat permits battery; `:207` RunAtLoad=false | Optional second candidate; loses media features. Battery flags alone do not exclude every task. |
| softwareupdateservicesd | `com.apple.softwareupdateservicesd.plist:7` PathState keepalive; `:108` StartInterval=86400 | Optional for a fixed experimental image; update checks lost. |
| wifid | `com.apple.wifid.plist:7` KeepAlive=true; `:32` RunAtLoad=true; `:34` DT gates wlan/marconi-wifi | Profile first; possibly already gated out. Clients may retry more if removed. |
| CommCenter | `com.apple.CommCenter.plist:11` KeepAlive=true; `:50` DT gate baseband | Profile first; disabling can break UI/service dependencies. |
| nanoregistryd | `com.apple.nanoregistryd.plist:9` PathState keepalive | Optional only after profiling; pairing services affected. |
| powerd | `com.apple.powerd.plist:10` KeepAlive=true; `:29` real powerd program | Preserve for battery, policy and notification integration. |
| thermalmonitord | `com.apple.thermalmonitord.plist:9` conditional KeepAlive | Preserve; no evidence that removing thermal policy is safe. |

Reproduce a cited plist's line numbers on the host (numbered transcript, read-only source):

1. Decode one plist to canonical XML on stdout:

```sh
7z x -so /home/tadej/ios-nord/build/ios16-root.img iOSRoot/System/Library/LaunchDaemons/com.apple.photoanalysisd.plist | python3 -c 'import sys,plistlib; print(plistlib.dumps(plistlib.loads(sys.stdin.buffer.read())).decode(),end="")' | nl -ba
```

**UNVERIFIED implementation proposal:** record CPU time deltas/PIDs and launch counts, then
prepare a root-overlay allow-list excluding exactly one confirmed costly optional job. Gate
any root update with an owner-approved image hash/provenance record, preserve its original
plist and rebootable rollback image. Do not delete plists or unload core services en masse.
No root change or `launchctl` mutation was executed by this audit.

## Top items and future on-phone checks

All gains here are **UNVERIFIED estimates**, not percentages of battery life.

| Item | Gain / risk / effort | Exact read-only check after future instrumented kernel is installed |
|---|---|---|
| Stop software display wakeups while off | Removes almost all off-state display-timer callbacks after fade; unknown watts / wake/UI regression / S–M | `sysctl kern.sweet_power_stats` (proposed): off display callback delta approaches zero; on resumes, no SwapWait timeouts. |
| Profile optional daemon A/B | Only confirmed job CPU/wakeups; can be zero / client retries / S | `ps -A -o pid,time,comm` twice over the same window; compare per-PID CPU-time deltas and track A power samples. |
| GPU slumber with reliable resume | Unknown idle GX power / hang, lost context / L | `sysctl kern.sweet_gpu_power` (proposed): slumber residency grows, resume failures and fence timeouts stay zero. |

1. Existing-kernel display/log baseline, on Claude's phone only, not run here:

```sh
sysctl -b kern.sweetlog
```

Expected existing evidence: `SWEET FB: display off`/`on`, and swap-rate records when animations
submit frames (`xnu-avicii/patches/0079-sweet-display-power.patch:73`,
`xnu-avicii/patches/0114-avicii-fb-swap-rate.patch:26`). This does not measure physical panel sleep.

2. Existing-kernel process census, repeated before/after identical dwell windows:

```sh
ps -A -o pid,time,comm
```

**UNVERIFIED tool availability:** verify target `ps` supports these columns before collecting;
use cumulative CPU-time deltas and launchd job state, not host-extraction assumptions.
