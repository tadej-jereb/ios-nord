# WLAN port map: ios-topaz 0113-0130 → avicii WCN3990 over SNOC

Scope: exactly what the topaz integrated-modem WLAN series contains, what survives on a standalone
WCN3990 behind SNOC, what needs new addresses/IRQs/registers, what is modem-specific.

Method: all 18 patches read in full from `refs/topaz-patches/` (branch `topaz` of `MakrSas/ios-topaz`,
`xnu/patches/`). Verdicts per patch. Every claim is marked **[V]** (verified — quoted from the patch,
the local DTS, or a reference doc) or **[U]** (unverified — needs a live dump).

Local DTS facts below cite `avicii/lito.dtsi` (the SM7250/lito SoC file).

---

## 0. The structural fact that decides the whole port

Topaz is **SM6225**, and its WLAN is **inside the modem DSP**: "topaz (SM6225): boot the modem DSP
(MPSS). It runs the WCN3988 WLAN firmware, so this is Wi-Fi step 1." [V `0113:28-29`].

So on topaz there is no Wi-Fi chip on a bus. The copy engines live in the modem's own register window
(`CE_PA (0x0C800000ull + 0x240000)`, `0113`-era → `0123:155`) [V], the SMMU stream is the modem's
(`WLAN_SID 0x1A0`, `0123:62`) [V], and the MSA region is a hardcoded constant the driver *tells* the
firmware about (`WLFW_MSA_BASE 0x51900000u /* DTB wlan_msa_region, inside "PIL Reserved" */`,
`0122:106`) [V].

Avicii is the other shape: a **separate WCN3990 on SNOC** with its own copy engines, own SMMU stream
and a DT-fixed MSA region:

```
icnss: qcom,icnss@18800000 {
        compatible = "qcom,icnss";
        reg = <0x18800000 0x800000>, <0xb0000000 0x10000>;
        reg-names = "membase", "smmu_iova_ipa";
        iommus = <&apps_smmu 0xC0 0x1>;
        interrupts = <GIC_SPI 132 ...> /* CE0 */ ... <GIC_SPI 87 ...> /* CE11 */;
        qcom,wlan-msa-fixed-region = <&pil_wlan_fw_mem>;
```
[V `lito.dtsi:3756-3774`]

**Consequence:** the *upper* half of the topaz series (HTC/WMI/HTT/MLME/WPA2) is chip-level and was
written against WCN3990 itself ("ath10k ce.c, WCN3990: 64-bit descriptors", `0123:153`;
"ath10k values for wcn3990", `0123:~700`) [V] — it ports nearly untouched. The *lower* half (PAS, SMEM,
SMP2P doorbell, SMMU, CE base, MSA source) is where every number changes, and the right reference for
those is not topaz at all but `ry-diffusion/Bergamota` on beryllium, which is the same WCN3990 on the
same `membase 0x18800000` [V `refs/bergamota/WIFI_BT_PLAN.md:137-139`].

Avicii is closer to beryllium than to topaz on every transport detail except one: avicii still needs
the **modem** booted, because WLFW is a service *of the modem* on both chips (topaz: `QMI_SVC_WLFW
0x45` on the modem's QRTR, `0118:64`; avicii: the same service reached over `glink_modem`,
`lito.dtsi:2631-2641`, whose `qcom,remote-pid = <1>` is the modem) [V].

---

## 1. Per-patch verdicts

Legend: **DIRECT** = transport-agnostic, take unchanged. **ADAPT** = logic survives, every
address/IRQ/register must be replaced. **REWRITE** = modem-specific mechanism, re-derive. **DROP** =
not wanted.

| # | File | What it does | Verdict | Why |
|---|---|---|---|---|
| 0113 | `iokit/Kernel/arm/TopazModem.cpp` (new, 652 l), `SweetFramebuffer.cpp`, `conf/files.arm64` | SCM/PIL boot of MPSS (pas-id 4): .mdt init_image → mem_setup → segment copy → auth_and_reset; SMEM partition table + SMP2P parse; APCS doorbell | **ADAPT** | PAS harness and the `smc()` wrapper are exactly what lito needs (lito's modem is the same `qcom,pil-tz-generic` + `qcom,pas-id = <4>`, `lito.dtsi:2862,2880`), but SMEM base, carveout, mailbox and item numbers are topaz's |
| 0114 | `SweetFramebuffer.cpp`, `hid/SweetHID.cpp` | iPhone X 1125x2436 canvas realignment | **DIRECT** | screen geometry, no transport |
| 0115 | `bsd/dev/sweet_ufs.c`, `TopazModem.cpp` | read-only GPT partition reader (LUNs 0-5); modem firmware from `modem_a` | **ADAPT** | the reader is generic; avicii's partition is `modem` with no A/B suffix, and the WLAN file is inside its FAT image [U] |
| 0116 | `TopazModem.cpp` | `PIL_IS_SUPPORTED` failure made informational | **DIRECT** | pure control flow |
| 0117 | `TopazModem.cpp` | hash segment read from its own `.bNN` file | **ADAPT** | same split-hash model, different file names/extents |
| 0118 | `TopazModem.cpp` | GLINK over SMEM FIFOs (items 478/479/480, bit 12), QRTR router, IPCRTR, HELLO/NEW_SERVER | **ADAPT** | whole engine is reusable; item numbers [U] and the doorbell must move from the APCS block to IPCC |
| 0119 | `TopazModem.cpp` | log each arriving QRTR service + 3 s summary | **DIRECT** | logging |
| 0120 | `SweetFramebuffer.cpp` | `sweetfb_console=1` pins the kernel console on the panel | **DIRECT** | needed, but see §4 finding 1 — it hides panics |
| 0121 | `TopazModem.cpp` (2174 l) | host services: pd-mapper (`wlan/fw` → `msm/modem/wlan_pd`), TFTP server, rmtfs, QMI TLV helpers, hyp-assign | **ADAPT** | state machines are generic; firmware paths, rmtfs region and PD names are topaz's |
| 0122 | `TopazModem.cpp` | WLFW QMI client to mission mode; MSA assign with WLAN VMIDs; BDF in 6 KB segments | **ADAPT** | message set is ath10k `qmi.c` verbatim and is right for WCN3990; MSA base/size, host-cap use and board-file source differ |
| 0123 | `TopazModem.cpp` (1049 l) | WLAN SMMU identity CB, 12 polled copy engines, HTC, WMI TLV, passive scan | **ADAPT** | the meatiest port; SID, SMMU base, CE base and the added IRQs all change |
| 0124 | `TopazModem.cpp` | redo the handshake on a WLFW server-port change; retry CAP 5x, dump its error | **DIRECT** | robustness, chip-independent |
| 0125 | `TopazModem.cpp` | HTT setup (RX ring, frag-desc bank, aggr), 64-bit WCN3990 forms | **DIRECT** | `0125:38` "ath10k htt.c ath10k_htt_setup, 64-bit, WCN3990" |
| 0126 | `TopazModem.cpp` | radio C API for the rest of the kernel, BSS with raw IEs | **DIRECT** | no transport |
| 0127 | `SweetBusy.cpp` (new), `SweetFramebuffer.cpp`, `files.arm64` | `sweetbusy=N` dumps IOServices keeping IOKit busy | **DIRECT** | diagnostic |
| 0128 | `IOService.cpp`, `IOStartIOKit.cpp` | drop the registry-root busy hold so IOKit quiesces | **DIRECT, mandatory** | without it configd's InterfaceNamer never says "quiet" and wifid hangs boot [V `0128:37-38`] |
| 0129 | `TopazModem.cpp` (1271 l) | station: auth/assoc, in-kernel WPA2-PSK 4-way, HTT data TX/RX, Ethernet bridge | **DIRECT** | pure 802.11 + crypto + ath10k HTT TX, no bus |
| 0130 | `TopazModem.cpp` | `topaz_wlan_join_pmk()`: join with a wifid-supplied PMK | **DIRECT** | API shim |

### 1.1 What this means in counts

- DIRECT: 0114, 0116, 0119, 0120, 0124, 0125, 0126, 0127, 0128, 0129, 0130 — 11 of 18.
- ADAPT: 0113, 0115, 0117, 0118, 0121, 0122, 0123 — 7 of 18.
- REWRITE: none as a whole patch, and exactly one whole *mechanism*: power sequencing (§2.9) has no topaz
  code at all. The rest of the rewrites are inside 0113/0118/0122/0123 and are listed in §2.
- DROP: none. Nothing in the series is modem-only in a way that has no SNOC equivalent.

---

## 2. The transport boundary, itemised

Every one of these is a place the port is not a copy. Left column is quoted topaz code; right column
is what avicii needs and where it comes from.

### 2.1 Firmware load (0113, 0115, 0117)

```c
#define PAS_ID_MODEM        4
#define MODEM_POOL_BASE     0xE0000000ull
#define MODEM_POOL_SIZE     0x00400000ull
#define SMEM_PA             0x46000000ull
#define TCSR_MUTEX_PA       0x00340000ull
#define APCS_PA             0x0F111000ull
#define APCS_IPC            8
#define MPSS_SMP2P_BIT      14
#define ITEM_SMP2P_OUT      428
#define ITEM_SMP2P_IN       435
```
[V `0113:71-99`]

| topaz | avicii | Source |
|---|---|---|
| `SMEM_PA 0x46000000` | `0x80900000`, 0x200000 (`smem_region@80900000`) | [V] `lito.dtsi:363-366` |
| `TCSR_MUTEX_PA 0x340000` | TCSR `syscon@1f40000`, hwlock 3 (`smem: hwlocks = <&tcsr_mutex 3>`) | [V] `lito.dtsi:2607-2623` |
| `APCS_PA 0x0F111000`, `APCS_IPC 8` | **IPCC** `qcom,ipcc@408000`; SMP2P kick is an IPCC client/signal pair, not an APCS bit | [V] `lito.dtsi:2232`; [U] client/signal ids |
| `PAS_ID_MODEM 4` | 4 — unchanged (`qcom,pas-id = <4>`) | [V] `lito.dtsi:2880` |
| `ITEM_SMP2P_OUT/IN 428/435` | same *shape* (`qcom,smem = <in out>`), numbers differ | [U] |
| `MODEM_POOL 0xE0000000` | must be outside xnu RAM and below 4 GiB for TZ; free window to be picked from the live FDT | [U] |
| `modem_a` + hardcoded extents | `modem` partition, WLAN file inside its FAT image | [U] |

The `scm_assign()`/`scm_call()` wrapper, the MDT header parsing and `MDT_TYPE_HASH` split (0117) are
transport-agnostic [V] and are the parts worth taking.

### 2.2 SMP2P / doorbell (0113, 0118)

```c
smp2p_kick(void)
{
        *(volatile uint32_t *)(apcs + APCS_IPC) = 1u << MPSS_SMP2P_BIT;
}
```
[V `0113:365-368`]

Avicii's GLINK node already names the IPCC path for the modem:

```
glink_modem: modem {
        qcom,remote-pid = <1>;
        mboxes = <&ipcc_mproc IPCC_CLIENT_MPSS IPCC_MPROC_SIGNAL_GLINK_QMP>;
```
[V `lito.dtsi:2629-2634`]

So GLINK's **doorbell** (`GLINK_IRQ_BIT 12`, `0118:30`) becomes an IPCC send, and the SMP2P kick
likewise. This is the same divergence anonbeat1 hit on SM7325 and recorded: "**Mailbox differs:**
SM7325 uses **IPCC** (`qcom,ipcc@408000`), not khaje's apcs_glb. The SMP2P 'kick' must use the IPCC
protocol (client/signal ids) instead of APCS_IPC. This is the main lower-half divergence to reverse."
[V `docs/anonbeat1-NOTES.md:1147-1149`]

anonbeat1 also established the **direction** convention the topaz code silently relies on: `qcom,smem
= <617 616>` is `<inbound outbound>` and their first six patches had it swapped; topaz's
`<435 428>` is in 435 / out 428, matching Linux `SMP2P_INBOUND=0/OUTBOUND=1`
[V `docs/anonbeat1-NOTES.md:1212-1214`].

### 2.3 SMMU (0123)

```c
#define SMMU_PA             0x0C600000ull
#define WLAN_SID            0x1A0
#define WLAN_SID_MASK       0x1
#define CB_CLONE_SCTLR      0x000000e0u         /* CFCFG|CFIE|CFRE, M=0: no translation */
```
[V `0123:60-66`]

`smmu_identity()` pokes SMR/S2CR/CBAR/SCTLR directly to make one stream **untranslated** [V
`0123:80-140`].

Avicii: `WLAN_SID 0xC0`, mask `0x1` [V `lito.dtsi:3761`], `apps_smmu` at a different base [U]. The
topaz SMR/S2CR/CB-clone *sequence* is reusable; the numbers are not. The DTS also asks for
`qcom,iommu-dma = "fastmap"` [V `lito.dtsi:3767`], which is the Linux spelling of the same intent.

### 2.4 Copy engines (0123)

```c
#define CE_PA               (0x0C800000ull + 0x240000)
#define CE_COUNT            12
#define SHADOW_PA           (0x0C800000ull + 0x32000)
```
[V `0123:155-157`]

The **offset within the WLAN block (0x240000) and the shadow-register offset (0x32000) are
chip-relative and correct for WCN3990**; only the block base changes. Bergamota, on the same chip and
the same membase: "Copy engines: WCN3990 `ce0_base_address = 0x00240000` [V ath10k hw.c] relative to
the WLAN membase, which is **0x18800000 (size 0x800000)** here …; so CE0 = 0x18a40000. Topaz's
constants `0xC800000 + 0x240000` and shadow regs at `+0x32000` translate by comparison."
[V `refs/bergamota/WIFI_BT_PLAN.md:137-140`]

Avicii's membase is the same 0x18800000 [V `lito.dtsi:3758`], so CE0 = 0x18a40000 on both. The 12 IRQs
are already in the DTS and topaz never uses them (it polls):

```
interrupts = <GIC_SPI 132 ...> /* CE0 */, <GIC_SPI 81 ...> /* CE1 */, <GIC_SPI 415 ...> /* CE2 */,
             <GIC_SPI 416 ...> /* CE3 */, <GIC_SPI 417 ...> /* CE4 */, <GIC_SPI 86 ...> /* CE5 */,
             <GIC_SPI 94 ...> /* CE6 */, <GIC_SPI 96 ...> /* CE7 */, <GIC_SPI 82 ...> /* CE8 */,
             <GIC_SPI 119 ...> /* CE9 */, <GIC_SPI 120 ...> /* CE10 */, <GIC_SPI 87 ...> /* CE11 */;
```
[V `lito.dtsi:3762-3771`]

Also: `ce_attr[]` is `host_ce_config_wlan` for a 12-CE target [V `0123:185-190`] — it must be checked
against WCN3990's own table before use, not assumed.

### 2.5 MSA region (0122)

```c
#define WLFW_MSA_BASE       0x51900000u         /* DTB wlan_msa_region, inside "PIL Reserved" */
#define WLFW_MSA_SIZE       0x00100000u
```
[V `0122:106-107`]

Avicii fixes this in the DTS instead:

```
pil_wlan_fw_mem: pil_wlan_fw_region@8ba00000 {
        compatible = "removed-dma-pool";
        no-map;
        reg = <0x0 0x8ba00000 0x0 0x200000>;
};
```
[V `lito.dtsi:414-419`], referenced by `qcom,wlan-msa-fixed-region = <&pil_wlan_fw_mem>` [V
`lito.dtsi:3774`].

So the base/size is 0x8ba00000 / 0x200000 (2 MiB vs topaz's 1 MiB) and `msa_info` must carry *that*,
not a constant. The `w_on_msa_info()` bound check (`addr < WLFW_MSA_BASE || addr + size >
WLFW_MSA_BASE + WLFW_MSA_SIZE`, `0122:334-338`) [V] must follow the DT value or it will reject the
firmware's own layout.

### 2.6 VMIDs and client identity (0122)

```c
#define WLFW_CLIENT_ID      0x4b4e454c          /* ath10k ATH10K_QMI_CLIENT_ID */
#define VMID_WLAN           0x18
#define VMID_WLAN_CE        0x19
```
[V `0122:108-111`]

All three are chip- and driver-level, unchanged by board [V]. `WMID_HLOS 3` / `VMID_MSS_MSA 15` are
generic [V `0121:1967-1968`].

### 2.7 host_cap

Topaz sends it: `wm_u32(&m, 0x10, 0); /* daemon_support = 0 */` with "rejected (not fatal)" handling
[V `0122:404-415`]. Beryllium *skips* it via `qcom,snoc-host-cap-skip-quirk` [V
`WIFI_BT_PLAN.md:131`]. Avicii's icnss node has **no** such quirk (`grep -c snoc-host-cap-skip` = 0)
[V], so avicii keeps topaz's behaviour — the one place avicii is easier than beryllium.

### 2.8 Firmware paths (0115, 0121)

```c
#define FW_DIR              "/usr/share/firmware/topaz/modem/"
```
[V `0113:32`], and the pd-mapper table:

```c
        { "kernel/elf_loader", "msm/modem/wlan_pd" },
        { "tms/servreg",       "msm/modem/wlan_pd" },
        { "wlan/fw",           "msm/modem/wlan_pd" },
```
[V `0121:1545-1547` — the first key is `kernel/elf_loader`]

The `wlan_pd` name is the modem's WLAN protection domain on both chips [V] — keep the names, change
the *source* paths to the avicii firmware mount.

### 2.9 Power sequencing is missing entirely (REWRITE, nothing to take)

No patch in 0113-0130 mentions a regulator, a supply or a clock: on topaz the WCN3988 is inside the
modem and the modem's own rails already power it. On avicii the chip has five PMIC rails of its own
[V `lito.dtsi:3778-3782`] and they are driver-owned, because avicii has no `qcom,pwrseq` (Linux only
keeps the first rail ours when a pwrseq *is* present, `snoc.c:1804-1820` [V
`refs/palanbanana/0083.patch:177-178`]). The order is fixed by ath10k: pwrseq → regulators → clocks
[V `snoc.c:1022-1048`, quoted in `0083.patch:173-176`], and PalanBanana records that the widely assumed
"vddio first" order is refuted [V `refs/palanbanana/NOTES.md:53`].

So this must be written from `snoc.c`, not ported. It is ladder rung W4.

---

## 3. PalanBanana 0083 and NOTES.md: what was established, where it stopped

PalanBanana's 0083 is a 258-line skeleton, `Wcn3990Controller` in `iokit/Kernel/arm/` [V
`refs/palanbanana/0083.patch`]. It is the *same target* (Poco F1, WCN3990 over SNOC) and the same
conclusion, and it stops before any register access.

It establishes, in its own header, the layer split and its sources:

> "SWEET: WCN3990 Wi-Fi controller, SNOC + QMI model (ath10k snoc.c / qmi.c). … Status: skeleton,
> dormant. start() maps the SNOC block and performs no register access. sweetwifi=1 checks the QMI
> transport first, and the kernel has none (QRTR is not in XNU), so no rail is enabled and the driver
> refuses to start."
[V `0083.patch:2-11`]

and the rail list, with the "first rail" note and the pwrseq/regulator count rule:

> "/* snoc.c:48-54 ath10k_regulators. Voltages 미확정 (device tree). */
> static const char * const kRegulators[] = {
>         "vdd-0.8-cx-mx",  /* first rail: powers part of the SoC (snoc.c:1814-1818) */
>         "vdd-1.8-xo", "vdd-1.3-rfa", "vdd-3.3-ch0", "vdd-3.3-ch1", };"
[V `0083.patch:71-77`]

> "Regulator count (snoc.c:1804-1820): with pwrseq present only the first rail is ours; without
> pwrseq all five are enabled."
[V `0083.patch:95-101`]

The dead end is explicit and is the reason the series is dormant:

> "/* qmi.c:1098 qmi_handle_init() runs on the QRTR socket. QRTR does not exist in XNU, so this is
> always false until a transport is provided. */
> return false;"
[V `0083.patch:157-160`]

> "SWEET WIFI: sweetwifi=1 refused: no QMI/QRTR transport in this kernel; no rail enabled"
[V `0083.patch:109`]

NOTES.md records the refutation that matters most for the port — the earlier GENI-FIFO model was
wrong:

> "GENI FIFO model: removed. Refuted, since ath10k uses SNOC + QMI."
[V `refs/palanbanana/NOTES.md:57`]

> "0083 Wi-Fi (`Wcn3990Controller`) | SNOC+QMI 구조 완료, stub 상태 | QRTR (deferred)"
[V `NOTES.md:21` — "SNOC+QMI structure done, stub state; QRTR deferred"]

Also useful, and independent of topaz: it confirms the rail **names** against `snoc.c:48-54` and
records the "vddio first" order as refuted [V `NOTES.md:53`].

**Where they stopped:** at "the QMI transport does not exist". They wrote the power and QMI function
shells against `qmi.c` line numbers (`qmiServerArrive` → qmi.c:808, `qmiMsaReady` → qmi.c:918,
`qmiWlanEnable` → qmi.c:515) [V `0083.patch:42-44`] and never implemented one. They also left
`snocMap()` mapping **IOKit index 0** with the index marked 미확정 ("undetermined") because IOKit has
no by-name lookup [V `0083.patch:162-168`].

---

## 4. Bergamota: structural order and failure modes

Bergamota (`ry-diffusion/Bergamota`, beryllium/SDM845, WCN3990) is the only source that actually ran
this to a working scan on this chip. Its order is a *dependency* order, stated as such:

> "Wi-Fi dependency chain on SDM845" — §1.1 memory map, §1.2 MSS boot, §1.3 SMEM/SMP2P/GLINK/QRTR,
> §1.4 host services, §1.5 WLFW QMI and WLAN data path
[V `WIFI_BT_PLAN.md:33-153`]

and the WLFW chain in §1.5 is, in order: hyp-assign the MSA region to VMIDs 0x18/0x19 → `msa_ready` →
`cap` → MSA_READY … BDF_DOWNLOAD → CAL_REPORT → FW_READY → WLAN_CFG → WLAN_MODE [V
`WIFI_BT_PLAN.md:127-129`].

Observed boot order from its log, which is the ladder that actually worked: MBA copy → SCM hyp-assign →
QDSP6 boot → SMP2P READY → rmtfs → TFTP → pd-mapper → WLFW → FW READY → CE → HTC READY → WMI READY →
scan [V `WIFI_IOS26.md:295-1214`].

The failure modes, verbatim, because each cost them a boot:

1. **Hidden panic looks like a freeze.** "All these images carry `sweetfb_noconsole=1`, which keeps
   panics off the screen … and panics never reach the USB console … A data abort in the copy … would
   look exactly like this." [V `WIFI_IOS26.md:377-378`]. Verdict after the probe: "The carve-out is
   readable and writable and the whole MBA was copied; the panic is the `ml_io_unmap` after the copy."
   [V `WIFI_IOS26.md:417-419`]. Fix: use `ml_io_map_unmappable()` — "`ml_io_map_wcomb()` =
   `io_map(..., unmappable=false)`, which allocates the kernel VA with `KMA_PERMANENT`, and
   `ml_io_unmap()` = `pmap_remove` + `kmem_free`, which refuses a permanent entry" [V
   `WIFI_IOS26.md:419-421`]. **Lesson: keep panics visible (no `sweetfb_noconsole=1`).**
2. **Unmapped writes to a carve-out hang the bus, not the phone**: "A freeze rather than a reset points
   to a bus access that never completed (a block that is unclocked, unpowered or protected without an
   error response)" [V `WIFI_IOS26.md:313-315`].
3. **Scan before HTT setup delivers nothing.** "Every command was accepted … but **no MGMT_RX event**
   came." [V `WIFI_IOS26.md:1079`]. After CHAN_INFO proved the RF hears traffic ("rx_frame / cycles
   1-55 % on ch 1"), the reading: "the firmware hands **no** management frame to the host. So the zero
   beacons … are a **delivery** problem, not RF" [V `WIFI_IOS26.md:1151-1156`]. Only after
   `ath10k_htt_setup()` (RX ring, frag bank, aggr) did results arrive: "**FIRST WI-FI SCAN RESULTS: 12
   networks**" [V `WIFI_IOS26.md:1187`].
4. **Missing RF reference clock vote.** `rfclka2` was skipped by their driver; voting it changed the
   receiver from dead to busy [V `WIFI_IOS26.md:1133-1140`]. WLAN RF needs it even though BT works
   without it.
5. **Modem stability over hours** is the residual risk, and EFS is kept read-only in RAM by policy
   [V `WIFI_IOS26_PHASE2.md:113-116`].

---

## 5. Avicii-specific facts the port still needs

| Fact | Status | Where it comes from |
|---|---|---|
| `pil_wlan_fw_region` base/size | **dts-cited**: `0x8ba00000` / `0x200000`, `removed-dma-pool no-map` [V `lito.dtsi:414-419`] | confirm the live FDT still reserves it before any hyp-assign; a moved region silently corrupts DDR |
| WLAN FW partition name and file | **unverified** — `modem` (no A/B suffix) holds a FAT image; expected `image/wlanmdsp.mbn` | live dump of that image's directory, or `/vendor/firmware_mnt/image` on stock |
| SMMU SID for the WCN stream | **dts-cited**: `0xC0`, mask `0x1` [V `lito.dtsi:3761`] | `apps_smmu` base and the pre-existing SMR state need a live dump |
| SMP2P host ids (`smp2p_wlan_1_in`, and whether an out item exists) | **referenced but not defined** in the local DTS: `interrupts-extended = <&smp2p_wlan_1_in 0 0>, <&smp2p_wlan_1_in 1 0>` with names `qcom,smp2p-force-fatal-error`, `qcom,smp2p-early-crash-ind` [V `lito.dtsi:3786-3790`] | live FDT + SMEM table dump; no `qcom,smp2p-wlan` node is in `lito.dtsi` |
| IPCC client/signal ids for the SMP2P and GLINK doorbells | **unverified** — only the GLINK pair is known (`IPCC_CLIENT_MPSS`, `IPCC_MPROC_SIGNAL_GLINK_QMP`) [V `lito.dtsi:2633-2634`] | `dt-bindings/soc/qcom,ipcc.h` + live FDT |
| PMIC rail APIDs for L1A / L14A / L2C / L10C / L11C | **referenced by phandle only**: `vdd-cx-mx-supply = <&L1A>` … `vdd-3.3-ch0-supply = <&L10C>` [V `lito.dtsi:3778-3782`]; no regulator node or APID in `lito.dtsi` | the PM8150/PM8150L RPMh regulator nodes (not on disk); a live dump of `/sys/kernel/debug/regulator` on stock, or the cmd-db `ldoa`/`smpa` lookups Bergamota used [V `WIFI_BT_PLAN.md:319`] |
| SMEM base / TCSR / IPCC base | **dts-cited** [V `lito.dtsi:363-366`, `2607-2623`, `2232`] | — |
| Free DDR window for the driver pool | unverified | live FDT reserved-memory list; must be outside xnu RAM, below 4 GiB, not overlapping `0x8ba00000` |
| Whether stock's `icnss` sets any rail after probe | unverified | stock DT has `qcom,vdd-cx-mx-config = <0 0>`, `qcom,vdd-3.3-ch*-config = <3000000 3312000>` [V `lito.dtsi:3783-3785`] — these are the *only* voltage numbers in the tree and are the starting point, not a substitute for the APIDs |

---

## 6. Summary

- 11 of 18 patches go in as-is; 7 need address work; nothing is dropped.
- Every rewrite concentrates in four steps: PAS/SMEM/mailbox (0113, 0118), SMMU+CE (0123), MSA source
  and host_cap (0122), firmware paths (0115, 0121).
- Topaz's upper half is already WCN3990-shaped, so the expensive part of this port is lower-half
  plumbing, not protocol.
- Do not copy topaz's polled-CE design forward: avicii has 12 CE SPIs in its own DTS [V
  `lito.dtsi:3762-3771`] and should use them once the polled path works.
