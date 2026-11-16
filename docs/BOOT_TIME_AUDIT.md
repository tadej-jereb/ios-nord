# Boot-time audit at kern-0144

Static audit, 2026-11-16. Repository baseline `75345b0f8b1ec2651a3e4de7959384983d1d281c`
(`fork/kern-0144`); XNU base `1b191cb58250d0705d8a51287127505aa4bc0789`
(`xnu-8796.141.3`). All **138 series entries applied successfully**, including stage scripts,
with `xnu-avicii/tools/preflight.sh --tree /home/tadej/ios-nord-codex-i/.audit-xnu`.
No kernel build, phone access, or kernel/shim edits were performed. Only this document is delivered.

**Finding:** the best explanation for a repeatable large, successful-boot plateau is the
**30 s IORTC resource timeout**, `iokit/Kernel/IOStartIOKit.cpp:82`, called synchronously by
`bsd/kern/bsd_init.c:688`. SWEET is not excluded by the `#ifndef BCM2837` guard and has no
IORTC resource publisher in its built-in personalities. This is a static prediction, not a
measurement of Claude's timestamped boot. Root matching, UFS retry limits, and previous-log
loading are other serial candidates; the touch delay and GPU boot are background work.

All kernel `file:line` references below refer to the **fully applied scratch XNU tree**, not
to patch-file line numbers. `avicii/`, `tooling/`, and `docs/` references are repository paths.
Times are nominal software ceilings excluding MMIO/SMC/cache/copy/scheduler overhead. A timeout
ceiling is not time necessarily spent. Nested rows are explicitly identified and must not be
summed twice. There is no finite whole-boot worst case if a hardware access never returns.

## Boot dependency map

`kernel_bootstrap_thread` starts IOKit; CPU matching launches `SweetCPU::startAll` on its own
thread (`iokit/Kernel/arm/SweetCPU.cpp:124`). Its completion is a real prerequisite for
`kperf_init_early` (`osfmk/kperf/kperf.c:83` → `ml_wait_max_cpus`). BSD init then calls calendar
initialization, DLIL init, root selection and filesystem mounting before launchd.

For `rd=ufsroot0`, `IOFindBSDRoot` first waits for the IOBSD resource and applies its retry
pacing, then takes the custom UFS branch at `iokit/bsddev/IOKitBSDInit.cpp:773`. That branch
calls `sweet_ufs_init` synchronously: CPU/BCM setup → host takeover → TUR → GPT → BSD nodes →
**previous log read** → start log/sample/key/touch threads → **USB setup** → start GPU thread.
USB setup is serial through `sweet_usb_probe` and `sweet_usb_gadget_start`; only its event and
UDP workers are parallel. GPU and touch are not joined before returning the root device.

The normal phone-image script selects a DIAG_STAGE=0 shim (`tooling/71-phone-image.sh:40`).
The shim's 60 s diagnostic parks and its no-payload 180 s park are not successful payload boots.
Timestamp prefixes in 0144 use `mach_absolute_time()/CNTFRQ_EL0`, not elapsed time since pressing
power; account separately for bootloader transfer/decompression and shim work before interpreting
an absolute first stamp (`bsd/dev/sweet_ufs.c:885`).

## Serial inventory, descending finite ceiling

The first five rows are the top five **bounded serial sites/stages**, including failure-only
paths. They are not a claim that successful boot spends their ceilings. Unbounded dependency
waits are in the next table. Aggregates and their component waits overlap.

| File:line | Wait / condition | Worst case per site or stated stage | Boot argument and code default | Serial/parallel | Safe to shorten? Evidence/reason |
|---|---|---|---|---|---|
| `bsd/kern/bsd_init.c:913` + `iokit/bsddev/IOKitBSDInit.cpp:695` | Failed local root mount → sleep 2 s → repeat `setconf`; subsequent root discovery sleeps 5 s | **140 s explicit pacing** across 20 retries: 20 × (2+5); further IOBSD/UFS work excluded; 21st failed mount panics | `rd`/`rootdev`; local retry count 20, no timing arg | Serial; failure only | No speed gain on a healthy mount. Fix mount errno. Patch 0096 bounds the formerly indefinite mount loop; STATUS records the historical 7 s HFS retry cadence. |
| `bsd/dev/sweet_ufs.c:961`, `:976` (called at `:1136`) | 0142 loads previous log synchronously before starting logger; header + four 1 MiB reads when valid | **≤120 s** command/retirement budget = 5 × 24 s; stops on first error; normally just read latency | `sweetlog=1`, requires `ufsrw` (default 0); `ufslogsecs` does **not** control this read | Serial; aggregate of UFS command waits | Defer to a worker or make previous-log loading opt-in while retaining ordering before first overwrite. Blindly reducing device timeout risks losing valid logs; 0142 added this to avoid raw reads. |
| `bsd/dev/sweet_ufs.c:788` | Outer TEST UNIT READY loop, up to three `ufs_scsi` calls | **≤72 s** ordinary command/retirement budget = 3 × 24 s; see recursive SSU exception below | `rd=ufsroot0`; no timeout arg | Serial; aggregate | Do not remove transient UNIT ATTENTION handling. Measure attempts; the inner command already retries. Outer retries are a candidate for consolidation after evidence. |
| `iokit/Kernel/IOStartIOKit.cpp:82` (`:77` sets timeout) | Wait for `IORTC` resource before calendar initialization | **30 s**, likely full on this port | None; unconditional except BCM2837 build | Serial, from `bsd_init.c:688` | **Yes for SWEET with no RTC service**, by skipping absent-resource wait or providing a genuine RTC service. `SweetPlatformExpert.cpp`/`KernelConfigTables.cpp` publish no RTC; preserve `clock_initialize_calendar()`. Do not invent a clock value. |
| `iokit/bsddev/IOKitBSDInit.cpp:686` | Wait for IOResources with `IOResourceMatched=IOBSD` before examining `rd` | **30 s per IOFindBSDRoot call** | No timing arg; happens even for `rd=ufsroot0` and `rd=md0` | Serial | Only after confirming resource completion/matching semantics. Can return immediately; a `!BSD` log proves timeout. Removing it globally could race built-in filesystem matching. |
| `iokit/bsddev/IOKitBSDInit.cpp:1040` | Secure-root platform expert lookup when CONFIG_SECURE_BSD_ROOT is compiled | **30 s** | Compile configuration; no timeout arg | Serial after mount | Existing platform expert should match immediately; measure before changing security/root handling. |
| `bsd/dev/sweet_ufs.c:298`, `:300`, `:305` | Slot-0 doorbell clear, up to four attempts | **≤24 s** = 4 × (5 s command + up to 1 s retirement), excluding recursive SSU; per command, nested in rows above | `ufswait=0`, `ufscache=0`; neither changes deadline. Timeout 5 s/retries 3 are constants | Serial on boot/root I/O; shared with background logger | Do not shorten before measuring real I/O and recovery; ordinary fast completions pay no full timeout. `ufswait=1` yields CPU after 50 µs, not an elapsed-boot shortcut. |
| `bsd/dev/sweet_ufs.c:163` | Retire timed-out slot before reusing DMA allocation | **1 s per timed-out attempt**, included above | None | Same caller as command | No blind removal: comment at :154 explicitly prevents late DMA from corrupting a later command/data. |
| `bsd/dev/sweet_usb.c:1222`, `:1268` | DWC3 soft reset; then wait for DEVCTRLHLT clear | **500 ms each** (reset failure returns before run wait) | `sweetusb=1` (probe only); `>=2` starts gadget; `sweetusbinit=11` | Serial during gadget start | Keep condition checks. Shorten ceilings only with cold/flash and RAM-boot evidence; 0132 documents cold endpoint failures. |
| `bsd/dev/sweet_rpmh.c:325` (`RH_TIMEOUT_US` :67) | RPMh TCS ACK/completion and idle | **100 ms per vote**, plus MMIO readback waits below | Boot `sweetddr`/`sweetllcc` absent = no BCM votes; USB `sweetusbrails=1`; cold-power bit 16; touch rails in own thread | Serial for BCM/USB; parallel for touch | No blind shortening: incomplete commands quarantine TCS, and DDR votes must not be released (STATUS/NEXT and perf history). |
| `bsd/dev/sweet_smmu.c:137` | Shared SMMU context-bank TLBSYNC | **100 ms**, first bank initialization only | Indirectly `sweetusb>=2` or touch DMA | Serial if first created by USB; parallel if touch | Must not enable stale translations; improve timeout failure handling rather than deleting poll. |
| `bsd/dev/sweet_usb.c:116` | Cold-power `usb_power_poll`: GDSC, RCG and CBCR predicates | **10 ms per call** | `sweetusb>=2`, `sweetusbinit & 16` (default 11, bit absent) | Serial | Hardware readiness checks; do not shorten without cold-power observations. |
| `bsd/dev/sweet_usb.c:521` | Endpoint command CMDACT clear | **10 ms per command**; five setup commands + initial SETUP STARTTRANSFER on normal ep0 start | `sweetusb>=2`; no independent timeout arg | Serial during setup; parallel when event worker calls it later | 0132 deliberately raised 1 ms to 10 ms. Keep until measured; ENBLSLPM/SUSPHY fix is preferable to masking failures with timeouts. |
| `bsd/dev/sweet_ufs.c:349` | Transient SCSI status retry backoff | **6 ms cumulative** (1+2+3 ms), shares attempt counter with timeouts | None | Same caller; serial in root path | Usually negligible; retain to let NOT READY/UNIT ATTENTION recover. |
| `bsd/dev/sweet_usb.c:327` | Enable GCC branch and poll CLK_OFF | **1 ms per enabled branch**, five enabled entries (sleep, mock_utmi, cfg-noc-axi, aggre-axi, pipe; master/clkref/ahb2phy are not enabled by this loop) | `sweetusb>=2`, `sweetusbinit & 8` (default 11) | Serial | Readiness check, not deliberate pacing. Keep branch-specific failures observable (0135). |
| `bsd/dev/sweet_usb.c:247`, `:250`, `:268`, `:270`, `:273`, `:275`, `:277` | Cold-power reset/PHY/QSCRATCH settling | **1.620 ms total** = 100+100+10+10+1000+200+200 µs | `sweetusbinit & 16`, default off | Serial | Keep source-backed sequencing; negligible against 30 s. Pinned vendor-source ledger is in CONSTANTS.md 0140 section. |
| `bsd/dev/sweet_rpmh.c:95` (`delay` :99) | `rh_sync` register readback after each programming step | **1 ms per call**; multiple per vote, stops at first failure | Same BCM/rail controls as TCS row | Serial or parallel according to caller | Keep write/readback validation; no significant fixed boot cost if first read succeeds. |
| `bsd/dev/sweet_spmi.c:105` (`delay` :118) | Battery SPMI observer transaction complete | **1 ms per byte**; readWord at `SweetBattery.cpp:170` allows four 2-byte samples | `sweetbattery=0` (static fallback), 1 enables real reads | IOKit matching worker; first `poll` is synchronous inside service start (:269), later timer | No gain by default. Do not enable PM6150 assumptions on avicii as an optimization. Preserve lane poisoning on timeout. |
| `bsd/dev/sweet_ufs.c:313`, `:318` | Per-command polling/yield cadence | 1 µs spin steps; if sleepable, 50 µs spin then **200 µs** timed sleeps, capped at deadline | `ufswait=0`; requires `su.ready`, IRQ enabled, noninterrupt, preemption level 0 | Same caller, mutex held; init commands spin because `su.ready=false` | Already optional in 0069. CPU utilization and throughput tradeoff, not a fixed extra 200 µs per I/O. |

Ordinary UFS initialization also reads GPT header/entries at `sweet_ufs.c:421`, `:440` (two
commands, ≤48 s combined ordinary command budget). The TUR+GPT aggregate is ≤120 s on a path
that reaches both; it overlaps the TUR/command rows and is not an extra wait site. Filesystem
reads add workload-dependent command waits, not a prescribed delay.

## Unbounded waits and stock matching/debugger paths

| File:line | Wait / default / reachability | Serial/parallel | Safe to shorten? |
|---|---|---|---|
| `bsd/net/dlil.c:2708` | `dlil_init` msleep, timeout NULL, until both created input/detacher threads have run once; called at `bsd_init.c:758` | Serial scheduler dependency, **no finite timeout** | No arbitrary skip: later network init assumes workers ready. Timestamp the entry/exit; worker idle sleeps (:3021, :3119, :3156, :3259, :3295, :3579, :4287, :4412, :4503, :4646, :9522, :9537) are parallel and not boot delay constants. |
| `osfmk/arm/machine_routines_common.c:1290` | `ml_wait_max_cpus` mutex sleep until `ml_set_max_cpus`; `kperf.c:83` calls it | Serial dependency on CPU startup thread | Do not skip; `iokit/KernelConfigTables.cpp:49` records the historical unmatched-CPU indefinite sleep and current Kryo475 match fix. |
| `iokit/bsddev/IOKitBSDInit.cpp:900` | Generic root `waitForService`: 60 s in DEVELOPMENT/RELEASE, 120 s DEBUG; do/while retries when target policy permits; iOS target panics on missing media (:928) | Serial, **bypassed by custom ufsroot0 branch** and md0 success | Not the source of a normal ufsroot0 root-device plateau. `rd=ufsroot0` calls BSD driver directly instead of matching IOMedia. No `rootwait` duration arg here. |
| `iokit/bsddev/IOKitBSDInit.cpp:878`, `:992` | Platform `waitQuiet()` for `io` debug flags: before root for `0x01000000`, after custom root for tree/service/memory logging flags | Serial if enabled; default call uses infinite timeout | Do not enable for timing runs. After-root call is reachable even for ufsroot0. `debug=0x144` is a different namespace from `io=`. |
| `iokit/Kernel/IOService.cpp:5506`, `:5577`, `:6526` | `waitForState`/`waitQuiet` and matching notifier sleep; finite deadline only if caller supplies one. waitQuiet extension logic :5549 onward; DriverKit check-in at :4244 is 120 s | Caller-dependent; config threads normally parallel, root resource callers serial | These are condition waits, not mandatory kext-loading sleeps. Identify pending service/resource; don't globally shorten matching. DriverKit check-in is not needed for SWEET built-in drivers or before launchd. |
| `iokit/Kernel/IOService.cpp:1154`, `:1778` | Busy-state propagation and arbitration assert_wait/thread_block | IOKit worker or requesting thread; no fixed duration | Dependency locks, not timing knobs. A stalled start() may propagate through waitQuiet; don't remove synchronization. |
| `bsd/dev/sweet_ufs.c:344`, `:346`, `:217` | NOT READY 2/04/02 invokes START STOP UNIT via `ufs_scsi` **before** retry-limit check; if SSU itself returns that sense it can recurse without bound | Serial on root/log/device caller | Separate bug: make activation nonrecursive, bounded and restore LUN safely. Finite UFS ceilings above assume SSU terminates; this is not established as the dd incident. |
| `bsd/dev/sweet_ufs.c:558`, `:1043` | Root/raw I/O and logger contend for one UFS mutex; previous-log loader (:961) also holds it | Serializes all disk requests, including background log flushes | Must serialize slot 0/bounce ownership. Bounded batching or async request service can improve fairness; dropping lock is unsafe. |
| `bsd/kern/bsd_init.c:902`, `:981` | Failed network-root / network imageboot sleeps 60 s then doubles indefinitely (integer width limits notwithstanding) | Serial failure path; not local UFS | Not reached on normal port boot; fix configuration/error instead. |
| `pexpert/arm/pe_init.c:585` | `PE_i_can_has_debugger` only returns `debug_enabled` and optional flags; **no sleep/poll** | No wait | Do not attribute 30 s to this getter. `/chosen/debug-enabled` and `debug=` affect callers, not a timer here. |
| `osfmk/arm64/sweet_reset.c:295` | Panic display busy-wait before reset, default 3 s via `sweetpanicwait=3`; inactive when reset mode is 0 | Serial **panic only** | Not a successful-boot delay. Keep distinct from watchdog bite and panic-log I/O. |
| `osfmk/kern/debug.c:329`, `:398`; `pexpert/arm/pe_identify_machine.c:389` | `debug` default 0, DB_HALT=1 enables halt behavior; panic debug scripts can busy-wait DT delay_us; panic/debugger paths can stop indefinitely | Failure/explicit-debug paths, not successful bootstrap | `debug=0x144` does not contain DB_HALT. No periodic boot wait merely from PE_i_can_has_debugger. Do not remove panic/debug controls to explain a healthy plateau. |
| `pexpert/arm/pe_serial.c:1133`, `:1136` | UART transmit-ready timed wait (default 1.5 ms per wait at :1122); force-poll transmission also polls readiness | Per-console caller if a registered serial interface exists | No usable UART on this phone. Check selected console before blaming serial waits; ring/framebuffer output is work, not this UART wait. |

`IOKitBSDInit.cpp:612` (NVRAM), `:307` (network stack resource), and `:1040` (30 s platform
expert lookup in secure-root handling) are stock conditional paths, not unconditional SWEET
root waits. The secure-root path at `IOKitBSDInit.cpp:1030` is compile-conditional on CONFIG_SECURE_BSD_ROOT; when enabled its platform-expert lookup can itself wait 30 s and should be timestamped. There is no SWEET-specific early return in this function.
`AppleARMSMP.cpp`'s infinite waitForMatchingService calls are not selected by the SWEET CPU
personality. Kernel startup's idle-thread `thread_block` (`startup.c:877`) is not a boot barrier.

## Background workers and driver-local polls

These can run before launchd but do not sleep the BSD boot thread. Keep them separate from the
serial table even when their CPU/DMA/lock use can slow it indirectly. GPU waits have no global
boot delay argument: `sweetgpu=0` by default; levels 1..11 select successively deeper bring-up,
and all bring-up is in `gpu_thread` (`sweet_gpu.c:4174`, created :4208).

| File:line | Wait / what it waits for | Worst case / cadence | Controls and defaults | Serial/parallel; safe to shorten? |
|---|---|---|---|---|
| `iokit/Kernel/arm/SweetCPU.cpp:151`, `:160` | All CPU nubs registered | 10 s deadline, 1 ms IOSleep steps, then panic | `cpus` local diagnostic default 1; actual count is parsed topology; `sweetsmp=1` | Own CPU-start thread, but serial dependency through ml_wait_max_cpus. Keep predicate; failure timeout is not mandatory pacing. |
| `iokit/Kernel/arm/SweetCPU.cpp:174`, `:181` | Each selected CPU initialized and SGI enabled | 5 s **per CPU**, in sequence; then panic | `sweetsmp=0` skips processor_start loop; registration still awaited | Same dependency; no benefit on immediate completions. First failure panics, so 5N is a loose ceiling, not N consecutive failed CPUs. |
| `bsd/dev/sweet_touch.c:1188`, `:1189` | Delayed touch bring-up | 5 s default, unsigned arg seconds | `sweettouch=1`, `sweettouchdelay=5` | Parallel touch thread (:1335); can lower after bus stability evidence, but won't remove 5 s from launchd's serial path. Historic 45 s in STATUS is superseded. |
| `bsd/dev/sweet_touch.c:362` | Log flush + debug pause at every gsi_step | 200 ms per executed step **plus full panic-flush I/O budget** | `sweettouchdebug=0` | Parallel; safe to leave off now default. Steps include per-transfer doorbell (:596), so enabling it can be extremely expensive, not just a startup pause. |
| `bsd/dev/sweet_touch.c:1251`, `:1257`, `:1259` | Rail settle, reset pulse, controller-ready settle | 10 + 2 + 300 ms | Touch enabled; rail/1v8 choices are separately gated (`sweettouchrails=2`, `sweettouch1v8=1`) | Parallel. 300 ms deliberately exceeds vendor 5+95 ms; reduce only after validation; 10 ms is explicitly conservative, not DT timing. |
| `bsd/dev/sweet_touch.c:399`, `:405` | GPI command reaches desired context state | 250 ms per command | Touch GSI path | Parallel; keep bounded hardware handshake. |
| `bsd/dev/sweet_touch.c:625`, `:637` | GSI TX/RX read pointer catches doorbell | 100 ms per transfer | Touch GSI path | Parallel; not fixed pacing; keep until failure/completion measured. |
| `bsd/dev/sweet_touch.c:175`, `:181` | GENI clock/reset/status clear | 5 ms per invocation | Touch enabled | Parallel; readiness check, no unconditional wait. |
| `bsd/dev/sweet_touch.c:256`, `:261`, `:263` | GENI ABORT_DONE, then idle | Up to 5+5 ms | FIFO transfer failure path | Parallel; preserves bus ownership, don't remove. |
| `bsd/dev/sweet_touch.c:808`, `:817`, `:864` | FIFO transfer completion and NACK drain | 20 ms outer loop; nested NACK completion up to 5 ms per error branch, followed by abort on failure | Legacy FIFO path | Parallel; outer 20,000 iterations are not a strict 20 ms wall deadline when nested work executes. Preserve bounded drain; GSI path supersedes unusable avicii FIFO. |
| `bsd/dev/sweet_touch.c:687`, `:697`, `:706`, `:712` | 1v8 PMIC read/write completion | 1 ms each | `sweettouch1v8` branch | Parallel; keep completion checks. |
| `bsd/dev/sweet_touch.c:1308` via helper :166/:170/:171 | Touch event polling | 10 ms per loop | `sweettouch=1` | Parallel; lowering raises load, not launchd speed. :1313 is thread-termination block, not boot pacing. |
| `bsd/dev/sweet_keys.c:80`, `:89`, `:99`, `:157` | Three SPMI key reads; timed worker sleep | 1 ms per read; 20 ms poll sleep | `sweetkeys=1`; `sweetkeysfb=1` adds a 3 s **hold predicate** (:112), not sleep | Parallel; keep transaction checks; no serial 3 s delay. |
| `bsd/dev/sweet_usb.c:508`, `:510`, `:1085`, `:1114` | USB event/log worker timed sleeps | 1 ms event; 100 ms log | `sweetusb>=2`, `sweetusblog=1` | Parallel, no wait-for-host boot barrier; log worker retries later until configured. Reducing raises load. |
| `bsd/dev/sweet_ufs.c:1035` | Persistent log worker tsleep | `ufslogsecs=10`; accepts 1..60, else resets to 10 | `sweetlog=1` and writable UFS | Parallel; shorter interval increases disk/mutex load. Flush uses same command timeouts; initial prev-load is serial, not this sleep. |
| `bsd/dev/sweet_sample.c:73`, `:77` | Process sampling thread | 90 s first delay, 120 s between 40 samples | `sweetsample="SpringBoard,backboardd"`; '-' disables sampling (:70) | Parallel; not startup delay. |
| `bsd/dev/sweet_gpu.c:167`, `:173` | gpu_wait register predicate | Call-site timeout ms; 100 µs polling | `sweetgpu` stage | Parallel; keep hardware predicates. |
| `bsd/dev/sweet_gpu.c:183`, `:275` | GPU branch enabled / GMU RCG update done | 10 ms per call | GPU power/clock stages | Parallel; hardware checks, not full guaranteed latency. |
| `bsd/dev/sweet_gpu.c:247`, `:248` | CX power domain up | 50 ms | GPU bring-up | Parallel; keep readiness. |
| `bsd/dev/sweet_gpu.c:681`, `:682`, `:1607`, `:1608` | GMU/core SMMU TLBSYNC | 1 ms each | GPU SMMU stages | Parallel; keep translation consistency. |
| `bsd/dev/sweet_gpu.c:949`, `:950` | HFI reply | 1 s per message | GPU HFI levels | Parallel; retain until firmware response latencies measured. |
| `bsd/dev/sweet_gpu.c:1064`, `:1065`, `:1091` | GPU OOB grant and settle | 500 ms grant; 100 µs fixed delay | GPU OOB stages | Parallel; hardware sequencing. |
| `bsd/dev/sweet_gpu.c:1142`, `:1143`, `:1168`, `:1169`, `:1185` | RSCC ACK/idle, GMU firmware up, HFI start | 10+10 ms; 500 ms; 50 ms | GPU GMU stages | Parallel; predicates exit early; keep until profiled. |
| `bsd/dev/sweet_gpu.c:1290`, `:1310` | TZ PAS SMC resume/busy | 200,000 resumptions, 20 busy replies × 30 ms = 600 ms explicit backoff per call; **SMC duration unbounded** | Zap stages | Parallel; don't call finite iteration count a wall-clock timeout. |
| `bsd/dev/sweet_gpu.c:1354`, `:1355`, `:1508` | CP consumed ring / idle, zap settle | 2 s per kick; 20 ms settle | GPU CP/shader stages | Parallel; keep synchronization; tests are stage-dependent. |
| `bsd/dev/sweet_gpu.c:1944`, `:1946` | Runtime GPU context-bank invalidate sync | 2 ms | GPU runtime interface | Parallel/caller; not launchd startup path. |
| `bsd/dev/sweet_gpu.c:2479`, `:2496`, `:2516`, `:2522` | Runtime fence / ring-space polls | 200 µs steps; default fence patience 5 s, ring-room 2 s; callers :2587 2 s, :2705 1 s, :4054 1 s | User API deadlines; no boot delay arg | GPU self-tests/clients, not a BSD boot join. Keep correctness; avoid stalled client indefinite asks. |
| `bsd/dev/sweet_gpu.c:3054`, `:3057`, `:3058` | Open waits for GPU bring-up | 1,200 × 100 ms = 120 s | GPU nodes (level 11) | Blocks **opener**, not BSD initialization; userland after launchd may wait. |
| `iokit/Kernel/arm/SweetBattery.cpp:255`, `:277` | Timer rearm | 30 s between samples | `sweetbattery=0`; 1 real mode | Parallel event source, no startup sleep; first poll immediate. |
| `iokit/Kernel/arm/SweetFramebuffer.cpp:215`, `:687` | Vsync timer / SwapWait | ~16.667 ms timer; 50 ms pending-frame wait | `sweetfb_hz=10` default copy throttle; `sweetfb_swapwait=1` swap wait | Parallel timer / post-launchd client wait; not pre-launchd latency. |
| `osfmk/arm64/sweet_wdt.c:72` | Watchdog pet delayed thread_call | Half bark interval; test stops at 60 s | `sweetwdt=0`, accepted 1..26; `sweetwdt_test=0` | Parallel. Bite policy is not a deliberate boot wait. |
| `osfmk/arm64/sweet_panic_test.c:36` | Delayed panic test | Configured seconds | `sweetpanic_test=0` | Parallel test-only; leave off for normal boot. |

`bsd/dev/sweet_cpufreq.c:302` (10 ms per CPU domain), `:320` (reschedule after CPU binding),
`:428` (up to 100 × 1 ms binding retries) belong to sysctl report/bind handlers, not
`sweet_cpufreq_init` at :167. They do not run just because boot calls that init function.
`gpu_log` at `sweet_gpu.c:134` has **no sleep or panic-log flush** in this applied tree;
historical per-step GPU pacing must not be imported from another fork. Likewise no driver
startup waits appear in SweetKeyStore/SweetEntitlements/SweetSurface/SweetHID/SweetWatchdog.

## Shim waits, including excluded diagnostic paths

| File:line | What / bound / control | Serial/parallel | Safe to shorten? |
|---|---|---|---|
| `avicii/shim/ufs.c:131`, `:132` | Poll UFS slot: 19,200,000 ticks (~1 s at the cited timer rate), then clear slot; used by UFS/diaglog helpers | Serial when DIAG_LOG or probe path used | Keep hardware timeout; every command is conditional, not 1 s fixed. Clock rate provenance: CONSTANTS.md §1. |
| `avicii/shim/diaglog.c:130`, `:141` | Optional DIAG_LOG init: GPT lookup, zero diagnostic ring in 16-block writes, sync/header work; each uses above 1 s timeout | Serial before loader if compiled `DIAG_LOG=1` (`shim.c:398`) | Can omit diagnostic logging for a measured production path after preserving observability; do not confuse this region with kernel log. No independent sleep; wall time is I/O workload. |
| `avicii/shim/shim.c:427`, `:110` | No-payload park 180 s then reset(20); exception reset(40) at :166; terminal WFE if reset returns | Serial **nonboot/error only**, no runtime arg | Never part of successful payload jump at :417. Changing this cannot speed successful boot. |
| `avicii/shim/shim.c:206`, `:237`, `:260`, `:275`, `:322` | Legacy test_smp 500 ms; GIC RWP ≤1,000,000 reads; IRQ windows 20+300 ms per source; redistributor wake ≤100,000 reads | Diagnostic only; legacy tests below unconditional no-payload reset are unreachable in normal shim_main | Not a payload delay; iteration polls have no known millisecond bound. |
| `avicii/shim/diag.c:194`, `:208`, `:217` | Diagnostic park 60 s, reset attempt then terminal WFE | DIAG_STAGE 1..8, not normal stage 0 | Cannot shorten into a successful boot: rung intentionally parks. History STATUS corrects former ticks/ms bug. |
| `avicii/shim/diag.c:426`, `:523`, `:527` | Secondary spin ≤0x4000000 iterations; boot CPU observation until 50 ms then total 200 ms | Diagnostic rung 4; CPU observer serial, secondaries parallel | Excluded by DIAG_STAGE=0, not normal boot. |
| `avicii/shim/tel_spmi.c:102`, `:123`, `:170` | SPMI transaction polls up to 2000 × 1 ms = 2 s per read/write; final 30 ms settle | Diagnostic telemetry stages 7/8 | Not successful stage-0 payload path; keep telemetry behavior isolated. |
| `avicii/shim/tel_gpio.c:66`, `:69` | GPIO blink phases 100+100 ms | Diagnostic telemetry | Same exclusion. |
| `avicii/shim/tel_haptic.c:88`, `:119`, `:180`, `:182`, `:195`, `:197`, `:206`, `:208` | GENI completion polls up to 20,000 × 1 ms = 20 s (:88), transfer IRQ polls up to 20,000 × 1 ms (:119); reset/settle 2+6+1+10 ms; buzz 300 ms and gap 200 ms | Diagnostic telemetry | Same exclusion; no launchd time to recover. |
| `avicii/shim/tel_imem.c:32`, `:40`; `shim.c:99` | Timer busy-wait helpers implement the diagnostic durations above | Caller serial | Do not double count helper and call site. |

Loader segment copies, framebuffer paints, cache maintenance, GPT scans, and firmware copies
are computation/I/O workload rather than deliberate waits. They can still matter: timestamp
both sides of a slow stage instead of assuming the entire gap is a delay() call.

## Why the raw rufsroot0 dd wedges

**Primary static defect: raw user memory is treated as a kernel pointer.** It is not a
partition-end arithmetic loop. The fault is `bsd/dev/sweet_ufs.c:569` (read memcpy), reached
through `sweet_ufs_read` at :694. The symmetric raw-write defect is at :578.

1. `physio` sets `B_PHYS|B_RAW` (`bsd/kern/kern_physio.c:152`), sets `b_datap` to
   `uio_curriovbase` (:175), and wires user pages with `vslock` (:191). Wiring pages does
   **not** map their user virtual address into kernel space. It then calls strategy (:199).
2. Strategy calls `buf_map` (`sweet_ufs.c:553`). `buf_map_range_internal` in
   `bsd/vfs/vfs_bio.c:1167` returns `b_datap` unchanged for a **non-B_CLUSTER** buffer.
   The raw physio buffer is such a buffer; buf_map does not magically perform vmapbuf.
3. After the device read completes, `memcpy(vaddr + done, bounce + skip, want)` at
   `sweet_ufs.c:569` writes directly to that user VA, **while holding sweet_ufs_lock**
   (:558 through :593). ARM PAN is set (when compiled available) in `osfmk/arm/arm_init.c:521`; legitimate copyio
   temporarily enables user access at `osfmk/arm64/copyio.c:86`. Plain memcpy has neither
   that protection handling nor a copyio recovery entry.
4. An unprotected kernel access to user VA is a fatal kernel fault, not an EFAULT return:
   `osfmk/arm64/sleh.c:1563` explicitly routes a no-recovery user fault against kernel_map
   and describes the resulting panic. Completion at :600 and mutex unlock are not reached.
   This explains a system-wide apparent hang/reset from a tiny raw read at any valid offset;
   the near-end location merely exposed it.

This is a demonstrated source defect and the strongest static cause of the reported incident.
No captured fault PC/ESR or reproduction was available to this audit, so the exact runtime
transition from fault/panic to watchdog reset remains unverified. A stuck device command or
recursive SSU would require log evidence; do not claim a measured PAN exception from this audit.

### Arithmetic and alternative hypotheses checked

| Check | Result in applied tree |
|---|---|
| Exact dd address | `26413169 × 4096 = 108188340224`; `108196737024 / 4096 = 26415219` device blocks. Read ends at 108188344320, **in bounds**. |
| Task's “last 4100 KiB” description | The literal command starts **8200 KiB** before the partition end (8,396,800 B), not 4100 KiB. Kernel log header is at partition block `26414194` = `nblocks−1025`; the stated read is 1025 blocks before that header and exactly at the **shim diagnostic header** (`avicii/shim/diaglog.c:137`: last−1025−1024). Do not silently change the incident command to match the description. |
| Bounds | :535/:546 uses 64-bit offset and subtraction after `off > part_bytes`; this request passes. Invalid ranges return EINVAL and still reach buf_biodone, not an infinite loop. Negative/overflowed block numbers deserve separate hardening, but this value cannot trigger that. |
| 512 vs 4096 | Default `su.secsize=DEV_BSIZE` (:781), normally 512. physio (:172) produces `211305352` logical sectors; strategy ×512 recovers exact byte offset; /4096 at :561 recovers relative device LBA 26413169. Block-size changes also feed the same physio argument. There is no 8× error for this request. |
| READ(10) 32-bit LBA | :372 returns EINVAL for `lba>UINT32_MAX`. Actual command LBA is `su.first_block+26413169`; GPT validation (:469) checks last_usable but does not explicitly enforce UINT32_MAX. The live first LBA was not supplied to this audit; this read fits READ(10) whenever first_block ≤ 4268554126. If not, :372 returns EINVAL rather than hanging; no truncation loop occurs. Read helper should additionally validate last LBA (`count−1`) as write helper does, but not the cause here. |
| Bounce split | :563/:564 gives skip=0, want=4096, blocks=1; done increments by 4096 (:585), exits. General bounded chunks ≤1 MiB, PRDT ≤256 KiB pieces (:256); no zero-progress loop here. |
| Log-thread collision / locks | Logger takes the same mutex (:1043) before bounce writes; append (:854) is atomic ring accounting plus copies and takes **no mutex**. No UFS→log-lock→UFS ABBA cycle is present. Command sleeps hold the UFS mutex intentionally (:312); no completion worker must acquire it because polling owns completion. |
| Missing panic evidence | A memcpy fault owns UFS mutex, so `sweet_log_panic_flush` **try-locks and returns** (:1093); it cannot persist its panic text in this case. It does not recursively wait on its own lock. 0143 can append panic text to RAM, but that alone cannot make the locked disk flush succeed. |
| 0142 workaround | `kern.sweetlog_prev` loads via direct `ufs_read_blocks` into a kernel array (:978/:983); `SYSCTL_OUT` safely copies to user. It avoids this raw physio buffer defect, but does not repair /dev/rufsroot0. |

### Proposed fix, text only

Implement a real raw-character-device read/write path around `uio` rather than sending user VAs
through the existing memcpy-based strategy. Transfer bounded kernel staging chunks with
`uiomove`/copyio; retain the existing synchronous kernel-buffer strategy for filesystem buffers.
For reads, hold UFS mutex through device read and bounce→private kernel staging copy, then
release it before `uiomove` to user memory. For writes, fill private staging from the uio before
acquiring UFS mutex, then perform aligned write or partial-block read/merge/write under the lock.
A per-request kernel buffer avoids logger bounce reuse during user copies and avoids user page
faults while owning the disk lock. Propagate short copies/EFAULT, exact uio offsets/residuals,
ufsrw permissions, bounds, FUA and sync semantics. A prepared IOMemoryDescriptor/kernel mapping
for B_PHYS buffers is another viable implementation, with explicit lifetime/unmap handling;
`buf_map` alone is not that mapping. Do not disable PAN or replace the mutex with an unlocked copy.

Separately harden read last-LBA validation, explicit zero/count/overflow handling, EOF semantics,
and nonrecursive SSU retry accounting. These are worthwhile correctness fixes, not evidence for
an arithmetic cause of the given command. Claude should validate raw read at a small safe offset
and near-end offset, cross-4K and >1 MiB splits, error/residual behavior, and concurrent logging;
this audit issues no device commands or write tests.

## Matching the timestamped run

Look first for the gap around calendar initialization (30 s IORTC), then `!BSD` (a separate
30 s matching timeout), the gap between UFS partition announcement (:813) and `SWEET LOG:
previous boot` (:969/:994), and USB `soft reset` / ep0 / `running` messages. Repeated
`cannot mount root` every ~7 s points to 2+5 s retry pacing, not a healthy-boot mandatory delay.
Touch's `starting in 5 s` and GPU logs overlap BSD startup; do not sum them into launchd time.
Before adding instrumentation, preserve timestamps for `dlil_init`/CPU dependency completion
if an otherwise unexplained scheduler gap remains. The static inventory alone cannot allocate
all ~46 s precisely, and no hardware timeline is claimed here.
