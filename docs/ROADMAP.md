# Roadmap: working iOS on avicii and reusable Qualcomm porting work

Evidence cutoff: **2026-11-16 22:15Z**, planning baseline `fork/kern-0146`
(`bf35a26`). Goals: (1) iOS usable day to day from flash without a cable or
routine intervention; (2) reusable source, tools and evidence for other hackios ports.
This is a plan, not a device test report. No phone, VM or build was used for this document.

## Evidence and how to read this snapshot

The working main checkout's `docs/STATUS.md` is newer than the committed copy on
this branch. The citations below name its dated entries and line ranges **as read
at the cutoff**; line numbers can move. The newer entries must accompany this
roadmap when integrated. Do not read the older branch copy as evidence that USB
from flash is still broken. Logs are local artifacts, not promised public downloads.

| ID | Source and specific evidence |
|---|---|
| S1 | `docs/STATUS.md`, “2026-11-16 22:15Z, kernel 0146”, lines 1–19: RAM boot only; 0141 remains flashed; sysctl logs; panic text; timestamps; SSH 14 s; GPU masks absent; `logs/phone/20261116-0146/prev.txt` and `logs/phone/shot-{0131-gles,0141-flash,0146,0146-cpu}.png`. |
| S2 | `docs/STATUS.md`, “2026-11-16 21:45Z, kernel 0141 on boot_a”, lines 21–32: flash USB/SSH, 38 s to USB; reboot to fastboot; `logs/phone/20261116-boot_a-0141/`; key combo untested. |
| S3 | `docs/STATUS.md`, “2026-11-16 21:35Z, kernel 0140”, lines 34–45: panic returns to fastboot with watchdog off; `logs/phone/20261116-usb-kernel-0140-panic/`; local runner evidence. |
| S4 | `docs/STATUS.md`, “2026-11-16 20:45Z, kernel 0138”, lines 47–57: reboot and injected watchdog hang return to fastboot; combined 0134–0137 test. |
| S5 | `docs/STATUS.md`, “2026-11-16 19:37Z, patch 0134”, lines 59–72: PMIC reason works; IMEM-only reset failed; `logs/phone/20261116-0133-reboot-test/ring-post.txt`. |
| S6 | `docs/STATUS.md`, “2026-11-16 (evening), patch 0132”, lines 74–90: global USB init alone fails on flash; `logs/phone/20261116-boot_a-0132-flash/ring-post.txt`. |
| S7 | `docs/STATUS.md`, “2026-11-15 (night)”, lines 92–139: GPU 38–48 fps, kernel/Mesa/EAGL ladder, panel copy, DDR vote constraint, missing app drawable methods. Latest S1 overrides the earlier text/import success implication. |
| S8 | `docs/STATUS.md`, “Host USB link … (2026-11-16)”, lines 141–159: host NetworkManager profile survives enumeration. |
| S9 | `docs/STATUS.md`, “2026-11-14 (evening)”, lines 161–210: userdata root and GUI, touch/power/volume keys, readback hash; `logs/phone/20261114-194619-0110f-touch`; fixed battery, bad clock, no radios/audio. |
| S10 | `docs/STATUS.md`, “2026-11-14, tier-1 job Programs staged”, lines 212–509: historical root/cache/daemon failures, bounded ramdisk experiments and tooling checks, not current phone readiness. Also read the next two entries, “launchd spawns jobs” and “launchd reaches Early boot complete”. |
| P | `docs/IMAGE_PROVENANCE.md`, “boot_a flash — 0141” and “boot_a candidate — 0146”: 0141 image SHA256 `49cae9abdab60f04bce39a1bf424c872626a49541a27a6e1630d70639f0143e7`; candidate 0146 `f5721d9667795f3143154ab1ec23363c2935f4df614d113e61161aaaf92fed37`, explicitly not yet flashed. These blocks are also newer in the main checkout. |
| A | `docs/BOOT_TIME_AUDIT.md` in sibling branch/worktree `codex/boot-audit` (`/home/tadej/ios-nord-codex-i/docs/BOOT_TIME_AUDIT.md`), baseline kern-0144: serial/parallel waits; raw-physio user-pointer defect; runtime fault PC not captured. Its IORTC prediction is now measured/fixed by S1/0146. This file is a separate deliverable, not present on this branch yet. |

`README.md` and newest `docs/NEXT-2026-11-16.md` supply the map and older
handoff. `docs/SHIM_BOOT.md` supplies header-v1/Image.gz-dtb rules, but its old
“flash boot_b / RAM boot unreliable” advice is superseded by AGENTS and S1/S2.
`docs/fajita-PORTING.md` is a scaffold/boot-ladder reference, not evidence that
avicii peripherals work. `docs/REFS_INDEX.md` is a dated inventory; newer local
rain/hakios clones below extend it. No hardware constant is introduced here;
implementation must cite `avicii/CONSTANTS.md` and vendor DTS/live FDT. Static
DTB memory is a placeholder; RAM must come from the live FDT.

## Where we are

“Works” means the stated narrow behavior was observed, not production readiness.
“Absent” means no demonstrated avicii implementation in the reviewed evidence;
references, source stubs and research alone do not change that state. Patch numbers
are **avicii** numbers unless a reference project is explicitly named. A patch
listed against a partial subsystem does not prove its whole feature.

| Subsystem | State | Evidence / scope and remaining gap | Patches / tools involved |
|---|---|---|---|
| Boot | works | Flash boot on 0141 (S2/P); 0146 fast RAM boot only (S1). Reboot/hang/panic reach fastboot (S2–S5), not automatic recovery into usable iOS. Unplugged repeated starts not established. | 0133–0137, combined kernel 0138, 0139 test, 0145–0146; shim/71 |
| Storage | partial | Root on userdata booted and original write read back hash-identical (S9/P). Raw `/dev/rufsroot0` read hangs (S1); A identifies unsafe raw user-pointer handling, not measured runtime PAN fault. Crash integrity/endurance not proven. | UFS series incl. 0069, 0096, 0106 (md0 size only), 0142; tooling/31–34 |
| Display | partial | Real panel/GUI (S9), GPU scrolling without flicker (S7); text missing (S1); copy-based scanout; off/on path unproven. | 0061, 0107–0108, 0114, 0130–0131 |
| GPU | partial | FD620/Mesa, shader tests and compositing 38–48 fps (S7). A8/LA08 masks missing (S1), app drawable/present unsupported (S7). | 0119, 0122–0127, 0129–0131; Mesa 0001–0008, SweetEAGL/SweetGLES |
| Touch | works | GUI touch observed (S9/log). Edge accuracy, repeatability and resume are still acceptance work. Audit A reports current 5 s background delay/debug off; old 45 s note is historical. | 0109–0111, 0118; `docs/GOODIX_GT9886.md` |
| Keys | partial | Power/volume events work (S9). Vol+/vol− hold-to-fastboot in 0137 still untested (S2). Power key does not prove suspend. | 0109, 0137 |
| USB | works | ECM/SSH from flash on 0141 (S2), RAM on 0146 (S1), host profile S8. Cold PHY/pipe guard matters (S6/S2). Reconnect/soak still needed. | 0072–0077, 0112–0113, 0121, 0132, 0135, 0140–0142 |
| Power / battery | partial | iOS battery service is a static fallback, not telemetry or charging control (S9; `docs/perf-research/F-battery-gauge.md` §1 cites `logs/phone/20261115-ring-0118/ring-post.txt:104`). Suspend/wake and charger policy absent. | 0062 fallback; 0113 RPMh support; gauge research only |
| Thermal | partial | Read-only TSENS reporting source exists (`0118`; `docs/perf-research/E-thermal.md` §current behavior); no demonstrated closed-loop thermal protection in STATUS. Real limits/calibration/control require vendor evidence. | 0115–0116 frequency controls, 0118 readout; no proven governor |
| Wi-Fi | absent | S9 says no Wi-Fi; no later avicii success. WLAN_MAP/ORDER are plans; refs contain candidate transports, not avicii results (comparison below). | No proven avicii WLAN patch; ref topaz 0113–0130; PalanBanana 0083 stub |
| BT | absent | S9; no subsequent avicii pairing/data evidence. Shared radio power does not imply HCI or iOS integration. | No proven avicii patch; hakios BT candidate source only |
| Cellular | absent | S9; no attach/data/voice evidence. MPSS boot for Wi-Fi would not prove cellular. | No proven avicii patch; topaz PAS/QRTR are templates |
| Audio | absent | S9; no output/input/call-routing evidence. DSP boot and codec integration remain. | No proven avicii patch |
| Camera | absent | No avicii capture result in S1–S10; unverified scope/driver path. | No proven avicii patch |
| Sensors | absent | No avicii orientation/proximity/ambient-light result in S1–S10. | No proven avicii patch |
| Apps / userland | partial | SpringBoard/backboardd GUI and SSH run (S7/S9). App lifecycle, browser/TLS, GLES apps and Metal-dependent apps unproven. Clock still wrong in CPU shot (S1); 0146 resource publication is not RTC implementation. Security-off bring-up (README). | 0104 AMFI/platform, 0105 exec diagnostics, 0107–0108, 0129; root/cache tooling |
| Update / install | partial | Image construction, explicit boot_a flash and hashes/undo exist (P/S2); no validated transactional root/bundle update, clean-host install or end-user rollback workflow. | tooling/31–34, 43, 70–75; tooling/macvm; provenance/recovery docs |

## Milestones and acceptance

These are proposed acceptance targets, not measurements or delivery dates.
S = one focused session; M = several sessions; L = multiple driver/workflow stages,
possibly weeks or longer. Whole milestones are larger than their one-session tasks.
Claude owns phone/VM execution; Codex can inspect sources, prepare patches, checks
and docs without either; the owner supplies physical observations, credentials and
explicit write gates. This roadmap itself authorizes no later device write.

All future destructive procedures must be numbered transcripts with one literal
command per line and a gate before each destructive action. Before any such action,
record exact image SHA256, commit, cmdline, target and undo in IMAGE_PROVENANCE.
Only boot_a is an experimental boot partition; boot_b stays bootable LineageOS +
Magisk. No GPT edits and no writes to protected firmware/calibration partitions.
Use sysctl logs, not raw rufsroot0 reads, pending a validated fix.

| Milestone | Checkable exit criteria | Dependencies | Biggest risk | Size / who |
|---|---|---|---|---|
| **M1 — daily-bootable** | Approved 0146-or-later image boots from boot_a **10/10** times, including **3 unplugged cold starts**; screenshots/photos show date/clock, labels and icons with GPU rendering; scripted touch grid and key events pass. Reboot, panic and watchdog tests each reach documented recovery destination with retained logs; owner verifies 0137 hold and that shorter presses do not reset. After deliberate fastboot recovery, documented return to iOS succeeds. Ordinary boot, UI use and a normal restart return to iOS without a cable or intervention; an explicit recovery request/failure may still enter fastboot and use a host. This requires separating normal restart policy from the current always-fastboot bring-up policy. | GPU mask diagnosis; gate/hash before flash; working 0141 fallback retained; test script plus physical cold-start evidence. | Mask fix regresses other surface formats, or unplugged boot relies on ABL/USB state. | M; Codex source/check preparation, Claude phone tests, owner cold starts/key hold and flash gate. |
| **M2 — usable offline** | Time-series artifact records real battery voltage/current/status, calibrated charge estimate with declared error, plug/unplug and bounded charging behavior. **20** screen-off/wake cycles preserve touch/GPU; **8 h** unplugged screen-off test has no reset and measured drain within an owner-agreed budget. **30 min** load test shows vendor-derived thermal limit enforcement. Fixed scripted scroll reaches a 60 fps target: median frame interval ≤16.7 ms, p95 ≤20 ms, with no missing text/tearing. Raw-UFS fix passes read/error/concurrency checks before raw-device tools are enabled. | M1; vendor-backed gauge/charger and thermal constants; trusted readings before policy; display/GPU off and wake; scanout/fences; UFS correctness. | Wrong power sequencing or inherited DDR-vote dependence prevents reliable low-power operation. | L; Codex audits/patches/harness; Claude instrumented phone tests; owner charging/overnight observations and gates. |
| **M3 — connected** | Wi-Fi first: own firmware + board data traced by hash; staged boot logs prove transport/WLFW then scan; **10** WPA2 association/reconnect cycles; DHCP, DNS and HTTPS fetch/hash succeed; **30 min** traffic and sleep/wake reconnect pass without USB. Then BT pair/reconnect **10** times and transfer data; audio playback/recording and BT routing produce reference recordings. Correct wall clock is verified across reboot before TLS results count. | M1 recovery and M2 telemetry/thermal/offline stability; choose lito transport from source evidence, not another board's constants; real clock path; BT HCI/audio DSP/codec work. | Firmware/service ownership and DMA/IOMMU/GLINK path differ from the chosen reference; iOS wireless/audio interfaces add a second integration problem. | L; Codex transport comparison/source work; Claude rung-by-rung tests; owner network/accessory and listening checks. |
| **M4 — community release** | A second person follows a pinned clean-host/VM recipe to produce source-built artifacts and manifest, extracts their own Apple/vendor inputs, completes install and boot_a rollback while retaining boot_b. Archive includes logs/screenshots, current limitations, unbrick/restore procedure, DTS→CONSTANTS→ADT guide, per-subsystem patch series, origin/licence inventory and no Apple binaries. Every source package applies to its pinned base; reproducibility differences are explained rather than claiming bit identity without a comparison. | Start docs/source split now; versioned M1 baseline minimum for an explicitly experimental release, M2/M3 required for a usable-release claim; second tester and licence inventory. | A successful local build depends on unrecorded binaries/VM state or inherited code lacks clear reuse terms. | M/L; Codex packaging/docs/static checks; Claude clean-run evidence; owner chooses licences and recruits tester/approves publication. |
| **M5 — day-to-day acceptance** | Owner's agreed app list launches, saves data, relaunches after reboot and completes its real tasks; network and audio work unplugged for a **24 h** trial with no unexplained reset, data loss or manual recovery. Owner-required cellular voice/SMS/data, camera capture and sensor functions each have logs/screenshots/sample artifacts; any deferred function is explicitly accepted by the owner before calling the device a daily driver. Update failure and rollback preserve user data in a controlled test. Security limitations are documented and reviewed for the intended use. | M1–M3, M4 installation/update evidence; app drawable/present and required Metal path; separate cellular/camera/sensor driver ladders; owner feature priorities. | Proprietary iOS service/GPU/telephony interfaces and security-off behavior prevent required everyday tasks. No evidence yet supports a completion estimate. | L, open-ended; Codex audits/implementation prep; Claude integrations/tests; owner app selection and daily trial. |

M4 is fourth in the release sequence, but documentation and generic patches can ship
incrementally after M1. M5 prevents a community demo being mistaken for the owner's
first goal. Cellular, camera and sensors are explicit backlogs, not quietly counted
as delivered by Wi-Fi. Boot-to-SSH is a developer metric; M1 also measures visible UI.

## Wi-Fi path decision before implementation

Use local source as candidate evidence, with per-clone commit pins in the eventual
comparison. Do not browse/run/download firmware to complete this roadmap.

- **PalanBanana `xnu/patches/0083-sweet-wifi-wcn3990.patch`:** REFS_INDEX calls it
  a SNOC mapping skeleton refusing startup without QRTR. Useful topology, not a driver.
- **Topaz 0113–0130:** `docs/WLAN_MAP.md` maps PAS/SMEM/GLINK/QRTR, host services,
  WLFW/BDF, CE/HTC/WMI/HTT and station/PMK; `docs/WLAN_ORDER.md` proposes gated rungs.
  Topaz has integrated-modem WLAN; avicii is the separate SNOC shape. Claims that
  upper layers copy unchanged and that MPSS is mandatory are prior static conclusions
  to revalidate against lito vendor code/live service discovery before selecting a path.
  Firmware paths, board data, rails, carveouts and doorbells remain unverified until
  matched to this device. Firmware must come from the owner's existing stock inputs,
  never by modifying modem/calibration partitions; rmtfs must remain read-only.
- **Rain:** local `xnu/patches/0118-topaz-modem-glink-qrtr.patch`,
  `0900-en0-Apple80211-for-wifid-over-the-Topaz.patch`, and
  `1017-rain-wifi-no-scans-while-joined.patch` provide transport/iOS bridge/reconnect
  lessons. They do not validate lito addresses or avicii firmware.
- **Helium hakios:** local `wifi/lx/ath10k/host.c` explicitly describes an **SM8150
  SNOC** platform; compare its LinuxKPI/ath10k and bootstrap patch against lito.
  Its README reports initial Wi-Fi/web success on its target and failure after
  off/on (`failed to power on device: -19`); reconnection must be its own acceptance gate.
- **Oosexgang hakios:** `drivers/wifi/hakios.wlfw.c` explicitly targets a **WCN6750 /
  ath11k** exchange. Reuse protocol architecture and Apple80211 integration selectively,
  not that chip's firmware or tables. `drivers/bluetooth/hakios.bt.c` is a later BT
  investigation source, not proof of compatible avicii HCI transport.

First deliverable: an evidence matrix comparing hand-written topaz/rain transport
with hakios LinuxKPI/ath10k, ending in a source-backed choice and missing-live-evidence
list. First device exit: firmware/service discovery with untouched persistent storage,
not a Wi-Fi icon. Then progress one gated mechanism at a time to real IP traffic.

## Community contribution plan

Offer source proposals to maintainers; this document sends no messages or submissions.
Keep board constants/ADT profiles distinct from generic logic. Preserve attribution
and list upstream dependencies so consumers need not import the entire avicii series.

| Candidate contribution | Generic portion / avicii boundary | Proposed recipients and package |
|---|---|---|
| 0142–0145 log access, timestamps and panic capture | Console/sysctl/reset-flush logic generalizes; persistent UFS layout, lock behavior and panic paths need per-port checks. Include the raw-UFS limitation and missing-log cases from A. | dipa ios-sweet, fajita, raphael, rain/topaz; small diagnostic series plus sample current/previous logs and reader documentation. |
| 0146 IORTC wait removal | Resource-publishing pattern for ports without RTC; **not a clock driver**. Existing rrrd-jpg 0086 is prior art (S1), so credit it and offer a regression check rather than claiming invention. | ios-sweet/fajita/rain/topaz; one patch with before/after timestamps and calendar caveat. |
| 0133–0137 recovery/watchdog/keys | Reset policy and hold logic generalize; PON/APID, watchdog layout and key wiring must be board parameters from vendor/live sources. 0137 still needs phone validation. | fajita, rain, sweet, hakios; separate reset, watchdog and key patches with test args and negative tests. |
| 0132/0135/0140/0141 cold USB | DWC3 cold-vs-fastboot guard and readiness method; lito clocks, PHY tuning, rails and sequencing stay board-specific. Credit rain and anonbeat1 lineage. | anonbeat1 sweet, rain, topaz, fajita; staged patches plus cold/RAM logs and DTS citation ledger. |
| Mesa 0001–0008 and SweetEAGL/SweetGLES | Darwin build/import formats, CPU-written IOSurface semantics, GL dispatch/TLS and flush/fence lesson can be shared; kernel BO/import ABI must be documented. Hold mask-correctness claims until M1. | raphael, fajita, Bergamota/Chlorophyll, ios-sweet; separate Mesa, EAGL and bundle packages with tiny format/drawable tests. |
| UFS raw-device correctness follow-up | A proposes bounded kernel staging + uiomove/copyio, preserving PAN and locks; not implemented here. Error/EOF/boundary/concurrent-log tests are generic. | sweet and all inherited-UFS forks; audit first, validated fix later as its own series. |
| Host tools and build recipe | Source pinning, image verification, log summary, provenance, root/cache ownership checks, macvm recipe; strip paths/tokens/device identifiers and retain safe slot policy. | shared Qualcomm-XNU tooling repo, ios16-xnu-bringup, all named ports; scripts and fixtures with explicit licences. |
| DTS→XNU guide | Trace vendor DTS/live FDT → CONSTANTS → ADT → driver; placeholder RAM, SMMU SMR reuse, RSC ownership and boot-header traps; board-specific examples clearly labelled. | shared docs repo and links from sweet/fajita/topaz/rain/hakios; no borrowed constants presented as defaults. |

Publish README/status snapshot, recovery/install/build guides, relevant provenance
records, GOODIX/USB notes, GPU/performance findings and the boot audit once merged.
Replace obsolete slot commands in the published guide rather than forwarding history
as instructions. Include tested commit/kernel/userland/bundle combinations and known
failures. Publish extraction scripts and sanitized measurements, not Apple cache dumps,
disassemblies containing copied proprietary code, credentials or personal root images.

### Licence/source inventory gate

This is a repository inventory and a release work item, not a completed permission
review. `git ls-files '*LICENSE*' '*COPYING*'` at this baseline returns no tracked
licence files. `tooling/gpu/sweeteagl/sweeteagl.c` and patch 0142 have no licence grant
in their opening headers. Public visibility is not evidence of permission for all
new code; obtain an explicit owner licence for original scripts/docs/userland and
record inherited authors/origins before offering packages.

- XNU changes: retain upstream Apple notices and APSL 2.0 source/licence material;
  inventory each borrowed patch and its origin. Do not assume every file in a mixed
  kernel tree has identical terms. Ship source patches with applicable notices.
- Mesa/libdrm/third-party dependencies: inventory actual pinned files and notices
  (including any GPL-derived Linux compatibility/ath10k code), then choose compatible
  distribution boundaries. Do not label a mixed package simply MIT/APSL.
- Local `refs/oosexgang-hakios-xnu-kernel/LICENSE` explicitly divides XNU/driver
  derivatives (APSL 2.0) from its original non-kernel material (MIT), and points to
  NOTICE for third-party components. Helium NOTICE likewise points to
  THIRD_PARTY_LICENSES/COMPLIANCE. These are reference-project claims to check per
  imported file, not a grant covering this repository or all LinuxKPI content.
- **Never redistribute Apple binaries:** no IPSW/userland, dyld caches, Apple SDK/KDK
  payloads or populated root/boot images containing them. Recipients supply their
  own inputs. Vendor GPU/radio/DSP firmware and board/calibration data also stay out
  unless a specific redistribution grant is verified; default package is extraction
  scripts, input hashes, manifest and source. Review artifact contents, not filenames.

## Top 10 next tasks (one session each)

Commands below are **read-only first commands**, run from this roadmap's worktree
unless absolute paths are given; they neither operate the phone/VM nor start builds.
They begin scoped follow-up work, not full driver projects. “Done” is the session's
artifact; future writes/tests require the existing project gates. Do not assign new
patch numbers until the active kernel lane has reserved them.

| # | Task / session exit | Size / owner / dependency | Exact first command |
|---|---|---|---|
| 1 | Diagnose missing A8/LA08 text: trace GL texture upload/import and swizzles, compare CPU/GPU shot evidence, deliver one falsifiable cause and minimal format-test proposal (or a small fix if established). | S; Codex, then Claude validation; S1 shots/logs | `rg -n 'A008\|LA08\|A8\|TexImage\|TexSubImage\|swizzle' tooling/gpu/sweeteagl tooling/gpu/mesa-patches` |
| 2 | Validate candidate flash baseline: reconcile exact 0146 image/hash/args with P, prepare numbered gated transcript; Claude later records flash USB/UI timing and rollback result. This session exits with the reviewable transcript if owner approval is pending. | S; Claude + owner flash gate; current P and recovery path | `sed -n '680,706p' /home/tadej/ios-nord/docs/IMAGE_PROVENANCE.md` |
| 3 | Close 0137 evidence gap: prepare short-press/long-hold/normal-event test matrix; owner performs holds in Claude's test session, capture log and destination. | S; Codex preparation, Claude + owner's hands; recoverable baseline | `sed -n '1,180p' xnu-avicii/patches/0137-avicii-keys-fastboot-combo.patch` |
| 4 | Turn M1 into a repeatable checklist/harness design: label 10 boot trials and 3 unplugged cold starts, collect UI/text/touch/key/log evidence; specify unattended reboot policy separately from fastboot recovery. | S; Codex design, Claude/owner execution; tasks 1–3 | `sed -n '1,200p' tooling/75-phone.sh` |
| 5 | Scope raw-UFS fix: translate audit A into bounded staging/copyio design, exact lock/error/EOF checks and read-only regression cases; keep raw reads disabled until validated. | S; Codex; audit A, 0142 logging | `sed -n '/^## Why the raw rufsroot0 dd wedges/,$p' /home/tadej/ios-nord-codex-i/docs/BOOT_TIME_AUDIT.md` |
| 6 | Gauge/charger first rung: reconcile F research with CONSTANTS/vendor sources, define read-only voltage/current/status implementation and Linux comparison plan; separate true charge estimate from stale SDAM/fixed 100%. No charger writes in this rung. | S; Codex; existing source/live captures | `sed -n '1,130p' docs/perf-research/F-battery-gauge.md` |
| 7 | Power/thermal first rung: map screen-off→GPU/display quiesce→wake ordering, TSENS trust/limits and DDR dependencies; propose one measured off/on test, no unsupported timeout or DDR-vote removal. | S; Codex; M1 and telemetry plan | `sed -n '1,130p' docs/perf-research/E-thermal.md` |
| 8 | Frame-time experiment design: identify CPU panel-copy cost and raphael scanout/fence prerequisites; deliver instrumentation points and a tearing/text correctness test before a zero-copy patch. | S; Codex; text fix and M1 | `rg -n 'SwapWait\|present\|glFinish\|glFlush' xnu-avicii/patches/0130-avicii-fb-swapwait-until-shown.patch tooling/gpu/sweeteagl` |
| 9 | Wi-Fi transport/firmware decision matrix: pin topaz/rain/helium/hakios candidates, distinguish ath10k SNOC from ath11k WCN6750, list missing lito evidence and a read-only firmware manifest/discovery rung. | S; Codex; no claim of working radio | `sed -n '1,145p' docs/WLAN_MAP.md` |
| 10 | Prepare first community source release inventory: map generic patches to recipients, licence/origin gaps and allowed artifacts; reconcile macvm/README/workflow pins and draft clean-host build/install/rollback checklist for a second tester. | S; Codex; no build/VM use in this session; M4 outline | `git ls-files docs tooling/macvm tooling/gpu xnu-avicii/patches .github/workflows/xnu.yml` |

Delegation accounting: task E's USB clocks and F/G's watchdog/keys are already in
combined kernels 0138 onward; H's runner is in the baseline and measured in S3/S1.
Do not redo them as missing implementations. G still needs physical validation.
D's syntax-check work must be reconciled with its own branch before treating a
Linux PASS as a compile; I is the audit A consumed here. Task files were read from
absolute `/home/tadej/ios-nord/docs/codex-tasks/` because they are uncommitted.
A fast-boot follow-up should instrument the remaining ABL/shim interval separately;
0146 has already removed the demonstrated 30 s kernel wait. Do not sum background
touch/GPU delays or timeout ceilings into measured boot time.

## Open questions for the owner (maximum five)

1. Which apps and cellular/camera/sensor functions are mandatory for your daily-driver
   acceptance, and which may be explicitly deferred?
2. What unplugged standby drain and active-use runtime should M2 target, measured
   against this handset's current battery rather than a nominal capacity?
3. Should the first public release target the M1 experimental baseline, or wait for
   M2/M3, and who can be the independent avicii installer/tester?
4. Which licence do you want for original non-XNU tools, docs and GPU userland, and
   can the inherited-code attribution/licence gaps be resolved before publication?
5. What security posture and supported update/rollback behavior are required before
   you use this security-off bring-up with everyday accounts and data?
