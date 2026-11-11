# avicii: USB gadget behind apps_smmu — port note

Status: **adaptation note, nothing built or booted on avicii.** Derived from anonbeat1's
Spacewar (SM7325) work: `bsd/dev/sweet_smmu.c` (added by
`refs/anonbeat1/patches/0091.patch:17-244`), the `sweet_usb.c` changes in the same patch, and the
NOTES.md entries that go with them. Line numbers of the form `refs/anonbeat1/patches/0091.patch:N`
are **patch** lines; the new file's own line is `N-18` (patch line 19 == `sweet_smmu.c:1`).

Everything below assumes the reader has patch 0091 checked out. Nothing here is a full driver.

---

## 1. The avicii facts this note is built on

| fact | citation |
|---|---|
| USB controller `usb0: ssusb@a600000`, `reg = <0x0a600000 0x100000>` | `refs/lito-dts/lito-usb.dtsi:6-8` |
| **`iommus = <&apps_smmu 0xE0 0x0>`** — SID 0xE0, mask 0 | `refs/lito-dts/lito-usb.dtsi:11` |
| `qcom,iommu-dma = "atomic"` (no lazy mapping, no `.attach` deferral) | `refs/lito-dts/lito-usb.dtsi:12` |
| apps_smmu `apps-smmu@15000000`, `reg = <0x15000000 0x100000>` | `refs/lito-dts/msm-arm-smmu-lito.dtsi:71-75` |
| apps_smmu covers SIDs 0x0..0x3ff (`qcom,stream-id-range = <0x0 0x400>`) | `refs/lito-dts/msm-arm-smmu-lito.dtsi:204` |
| HS PHY is `snps-femto` at `hsphy@88e3000`, not QUSB2 | `refs/lito-dts/lito-usb.dtsi:100` |
| WCN/icnss **`iommus = <&apps_smmu 0xC0 0x1>`** — SID 0xC0 with **mask 1** | `avicii/lito.dtsi:3761` |
| IPA endpoint SIDs 0x520/0x521/0x522 (ap/wlan/uc CBs) | `avicii/lito.dtsi:3733,3743,3751` |
| qupv3_0 / qupv3_1 wrapper SIDs 0x4e3 / 0x23 | `refs/lito-dts/lito-qupv3.dtsi:19,308` |
| `usb30_prim_gdsc` at GCC+0x10f004, wired as `USB3_GDSC-supply` | `refs/lito-dts/lito-gdsc.dtsi:10-14`, `refs/lito-dts/lito-usb.dtsi:26` |
| QSCRATCH = core base + 0xf8800 = **0x0a6f8800** | `refs/anonbeat1/patches/0074.patch:8-13` |

**SID 0xE0 is the same value Spacewar uses** (live DT there: `iommus <0x1a 0xe0>`,
`docs/anonbeat1-NOTES.md:374`), so the anonbeat1 code paths apply unchanged. Two avicii-specific
deltas matter: the controller is `dr_mode = "drd"` with the femto PHY, and the WCN stream 0xC0
carries a **mask of 1**, which the current `sweet_smmu_map_sid()` cannot represent (§5.2).

---

## 2. Why a bypass is not an option

Three measured facts from Spacewar, all under the Qualcomm hypervisor:

1. `sCR0 = 0x00220406` — SMMU enabled, `USFCFG` (bit 10) **set**, i.e. an unmatched stream is a
   *global* fault, not a pass-through (`docs/anonbeat1-NOTES.md:196`).
2. Writing an S2CR with `type = bypass` reads back as **fault**: SMR read back `0x80000056`
   (accepted) but S2CR read back `0x00020000` (forced to FAULT) (`docs/anonbeat1-NOTES.md:200-202`).
   The hypervisor virtualizes the SMMU: it owns stage 2 and will only accept a *translating* S2CR.
3. An unmatched stream during a live transfer does not return an error — it **resets the SoC**
   (`docs/anonbeat1-NOTES.md:310-313`).

So both USB and the qupv3 wrapper it drives (0x23 on avicii) need a stage-1 context bank with a
real identity map, reached from an SMR whose S2CR says *translate*.

Consequence: **never** write a bypass S2CR — the write appears to succeed and the readback is the
only place the failure shows.

---

## 3. The SMMU sequence, verbatim

This is the whole of `smmu_bank_create()`; keep the order and the values, they are hardware
contract, not style.

### 3.1 Geometry from ID registers, not from constants

```c
	uint32_t id0 = smmu_rd(0x20), id1 = smmu_rd(0x24);
	unsigned pgshift = (id1 >> 31) ? 16 : 12;
	unsigned ncb = id1 & 0xff, ns2cb = (id1 >> 16) & 0xff;
	uint32_t gr1 = 1u << pgshift;
	uint32_t cb0 = (1u << (((id1 >> 28) & 7) + 1)) << pgshift;
	smmu_nsmr = id0 & 0xff;
```
`refs/anonbeat1/patches/0091.patch:89-94` — `IDR0[7:0]` = NUMSMRG, `IDR1[7:0]` = NUMCB,
`IDR1[23:16]` = NUMS2CB, `IDR1[31]` = page granule, `IDR1[30:28]` = CB stride exponent. The
Spacewar readback decodes against the notes exactly: `ID0 0x4C017E4B` = 75 SMRs
(`docs/anonbeat1-NOTES.md:196-197`) and `id1 0x6000003D` = 4K pages, 61 CBs, NUMS2CB 0, CB base
0x15080000 (`docs/anonbeat1-NOTES.md:217`). avicii values unknown — read them, do not assume.

### 3.2 Pick a context bank no translating SMR already owns

```c
	uint32_t used[8] = { 0 };
	for (unsigned i = 0; i < smmu_nsmr && i < 128; i++) {
		uint32_t smr = smmu_rd(0x800 + 4 * i), s2cr = smmu_rd(0xc00 + 4 * i);
		if ((smr & (1u << 31)) && ((s2cr >> 16) & 3) == 0) {
			used[(s2cr & 0xff) / 32] |= 1u << ((s2cr & 0xff) % 32);
		}
	}
	for (unsigned c = ns2cb; c < ncb && smmu_cb < 0; c++) {
		if (!(used[c / 32] & (1u << (c % 32))) &&
		    !(smmu_rd(cb0 + (c << pgshift)) & 1)) {
			smmu_cb = (int)c;
		}
	}
```
`refs/anonbeat1/patches/0091.patch:97-109`. SMR at 0x800+4N, S2CR at 0xC00+4N, CBn at
`cb0 + n*stride`. `S2CR[17:16]` = 0 is `translate`. A CB is free only if no translating SMR points
at it *and* its SCTLR.M (bit 0) is clear.

### 3.3 Identity map: one level-1 table, 1 GiB blocks, Normal-NC

```c
	uint64_t l1_pa = ptoa_64(pn);
	volatile uint64_t *l1 = (volatile uint64_t *)l1v;
	for (unsigned i = 2; i < 10; i++) {
		l1[i] = (uint64_t)i << 30 | 1u << 10 | 2u << 8 | 1u << 6 | 1;
	}
	flush_dcache64((addr64_t)l1_pa, L1_SIZE, TRUE);
```
`refs/anonbeat1/patches/0091.patch:128-133`. L1 indices 2..9 = IOVA 0x80000000..0x27fffffff,
each a 1 GiB block descriptor: `AF` (bit 10), `S2 = 2` (shareability outer, bits 9:8), `AP = RW/EL1`
(bits 7:6), valid. Normal-NC comes from the MAIR index in §3.4. Table comes from
`kmem_alloc_contig(..., L1_SIZE, ...)` and its PA from `pmap_find_phys`
(`refs/anonbeat1/patches/0091.patch:117-123`). **IOVA == PA**, so drivers keep using physical
addresses; each driver cleans/invalidates its own buffers.

> avicii check: the USB DMA pool in DT is `0x90000000 + 0x60000000` (`refs/lito-dts/lito-usb.dtsi:13`)
> and icnss's is `0xa0000000 + 0x10000000` (`avicii/lito.dtsi:3775`) — both inside 0x80000000..0x27fffffff.

### 3.4 Context bank programming, in order

```c
	smmu_wr(cb + 0x0, 0);                                    /* SCTLR off while programming */
	smmu_wr(cb + 0x58, 0xffffffffu);                        /* FSR clear */
	smmu_wr(gr1 + 0x800 + 4 * (unsigned)smmu_cb, 1);        /* CBA2R VA64 */
	smmu_wr(gr1 + 4 * (unsigned)smmu_cb, 1u << 16 | 0xfu << 12 | 3u << 8); /* CBAR S1+S2 bypass WB NSH */
	smmu_wr(cb + 0x10, 7u << 15 | 2);                       /* TCR2: SEP upstream, PA 40-bit */
	smmu_wr(cb + 0x30, 25 | 1u << 23);                      /* TCR: T0SZ 25, 4K, NC walks, EPD1 */
	smmu_wr(cb + 0x34, asid);                               /* CONTEXTIDR */
	smmu_wr64(cb + 0x20, l1_pa | (uint64_t)asid << 48);     /* TTBR0 */
	smmu_wr64(cb + 0x28, 0);
	smmu_wr(cb + 0x38, 0x44);                               /* MAIR0 attr0 Normal NC */
	smmu_wr(cb + 0x618, 0);                                 /* TLBIALL */
	smmu_wr(cb + 0x7f0, 0);                                 /* TLBSYNC */
	for (int t = 0; t < 100000 && (smmu_rd(cb + 0x7f4) & 1); t++) {
		delay(1);
	}
	smmu_wr(cb + 0x0, 1u << 6 | 1u << 5 | 1u << 2 | 1u << 1 | 1); /* CFIE CFRE AFE TRE M */
	if (!(smmu_rd(cb + 0x0) & 1)) {
		printf("SWEET SMMU: context bank %d did not enable\n", smmu_cb);
		...
```
`refs/anonbeat1/patches/0091.patch:137-157`. Field notes:

- `CBAR` `1<<16` = type **S1** (stage 1 present, stage 2 supplied by the hypervisor behind it),
  `0xf<<12` = MEMATTR write-back, `3<<8` = inner/outer shareable.
- `TCR` `T0SZ = 25` → 39-bit VA; `bit 23` = EPD1 (walk region 1 disabled); walk attributes from
  TCR2/TCR give Normal-NC table walks, and MAIR0 attr0 `0x44` = Normal-NC for the mapped memory.
- `TTBR0` carries the ASID in bits 63:48; CONTEXTIDR is written first so the walk is tagged.
- TLBIALL at `cb+0x618`, TLBSYNC at `cb+0x7f0`, status polled at `cb+0x7f4`.
- SCTLR is enabled **last**, with `M` (bit 0) plus CFIE/CFRE/AFE/TRE (bits 6,5,2,1).
- The readback of `SCTLR.M` is the only proof the bank took; a bank the hypervisor refuses stays 0
  (that is what `did not enable` catches).

### 3.5 Mapping a stream: reuse an existing SMR, never add a duplicate

```c
	int free_smr = -1, match = -1;
	for (unsigned i = 0; i < smmu_nsmr && i < 128; i++) {
		uint32_t smr = smmu_rd(0x800 + 4 * i);
		if (!(smr & (1u << 31))) {
			if (free_smr < 0 && (int)i >= smmu_next_smr) {
				free_smr = (int)i;
			}
			continue;
		}
		uint32_t mask = (smr >> 16) & 0x7fff;
		if (((smr ^ sid) & ~mask & 0x7fff) == 0 && match < 0) {
			match = (int)i;
		}
	}
```
`refs/anonbeat1/patches/0091.patch:191-204`. `SMR[14:0]` = ID, `SMR[30:16]` = MASK,
`SMR[31]` = valid. The comparison is done *under the SMR's mask*.

Then, on a match (`refs/anonbeat1/patches/0091.patch:205-227`):

- already ours (`s2cr & 0xff == smmu_cb` and type 0) → return 0, nothing written;
- **masked** entry (`smr>>16 & 0x7fff != 0`) → log `is masked; leaving it alone`, return `EEXIST`;
- **exact** entry (mask 0) → repoint its S2CR, do not add another SMR:
  ```c
	smmu_wr(0xc00 + 4 * (unsigned)match, (uint32_t)smmu_cb);
	s2cr = smmu_rd(0xc00 + 4 * (unsigned)match);
	printf("SWEET SMMU: sid 0x%x smr %d s2cr now 0x%x (%s)\n", sid, match, s2cr,
	    (((s2cr >> 16) & 3) == 0 && (s2cr & 0xff) == (uint32_t)smmu_cb) ? "translate" : "REFUSED");
  ```
- otherwise take the free SMR (S2CR first, then SMR, so no window with a valid SMR and a stale S2CR):
  ```c
	smmu_wr(0xc00 + 4 * (unsigned)free_smr, (uint32_t)smmu_cb);  /* S2CR translate -> cb */
	smmu_wr(0x800 + 4 * (unsigned)free_smr, 1u << 31 | (sid & 0x7fff)); /* SMR valid, mask 0 */
  ```
  `refs/anonbeat1/patches/0091.patch:233-234`.

Every path re-reads S2CR and only returns 0 when the readback is `translate → our cb`; a refused
write is an error, not a warning.

---

## 4. Failure signature if the SMR is duplicated

Two valid SMRs matching one SID = stream-match conflict = global fault on the **first** transfer,
which the hypervisor turns into an SoC reset — no error return, no fault log, just a dead phone
(`docs/anonbeat1-NOTES.md:403-408`).

What it looked like, in order:

1. Every print up to and including `SWEET USB: endpoints ready; arming setup (first DMA)` and
   `SWEET USB: setup armed; VBUS override` (`refs/anonbeat1/patches/0091.patch:398-400`).
2. `CrashDump on the first DWC3 DMA (ud_start_setup: STARTTRANSFER of the ep0 setup TRB)`
   (`docs/anonbeat1-NOTES.md:403`).
3. Host sees nothing; `ue0` never appears.

The hypothesis was confirmed on the 0094 boot, which printed the pre-existing entry:
`SWEET SMMU: sid 0xe0 already matched by smr 6 (smr 0x800000e0 s2cr 0x5)` → `s2cr now 0x7`
(`docs/anonbeat1-NOTES.md:457-458`). ABL had **SMR 6 for 0xE0 translating to cb 5** — it uses this
controller for fastboot.

> **Expect the same on avicii from the first boot.** The first free SMR will be above ABL's, so a
> mapper without the reuse pass creates exactly the duplicate above. The touch path never hit this
> because nothing else owned SID 0x56/0x43 (`docs/anonbeat1-NOTES.md:408`).

Adjacent signature, for contrast — a stream with *no* SMR at all (USFCFG path): same reset, but the
`already matched` line is absent and it can be triggered by any single transfer
(`docs/anonbeat1-NOTES.md:308-313`).

Diagnostics to keep in any port: print SMR/S2CR **before** deciding, print the readback **after**
writing, and never treat a successful write as success.

---

## 5. What must change on avicii

### 5.1 Constants

| constant / site | sweet/Spacewar value | avicii value | citation |
|---|---|---|---|
| `SMMU_PA`, `SMMU_SIZE` | 0x15000000, 0x100000 | **unchanged** | `refs/lito-dts/msm-arm-smmu-lito.dtsi:73-74` |
| SID passed to `sweet_smmu_map_sid()` | 0xe0 (ADT `smmu-sid`) | **0xE0, mask 0** | `refs/lito-dts/lito-usb.dtsi:11` |
| `GCC_PA` | 0x00100000 | unchanged | `refs/anonbeat1/patches/0091.patch:261` |
| `GCC_SIZE` | 0x001f0000 | **0x001f0000 still works** (highest USB reg is GDSC 0x10f004) | `refs/lito-dts/lito-gdsc.dtsi:12` |
| `usb_gdscr_off` | 0x0f004 (sweet) / 0x10f004 (Spacewar) | **0x10f004** — same as Spacewar | `refs/lito-dts/lito-gdsc.dtsi:12` |
| `usb_master_off` | 0x0f010 | 0x0f010 (same) | `refs/lito-dts/gcc-lito.c:2302` |
| `usb_cfgnoc_off` | 0x0502c | **0x0f07c** | `refs/lito-dts/gcc-lito.c:1062` |
| sleep CBCR | 0x0f014 | **0x0f018** | `refs/lito-dts/gcc-lito.c:2338` |
| utmi CBCR | 0x0f018 | **0x0f01c** | `refs/lito-dts/gcc-lito.c:2320` |
| `usb_has_qusb2` | true (sweet) / false (Spacewar) | **false** — femto PHY, no QUSB2 block | `refs/lito-dts/lito-usb.dtsi:100` |
| `DWC3_PA`, `DWC3_SIZE` | 0x0a600000, 0xd000 | unchanged | `refs/anonbeat1/patches/0072.patch:70-71` |
| `QSCRATCH_PA` | 0x0a6f8800 | unchanged (core base + 0xf8800) | `refs/anonbeat1/patches/0074.patch:13` |
| aggre CBCR (unread on the no-QUSB2 path) | 0x8201c | 0x0f080 if ever read | `refs/lito-dts/gcc-lito.c:973` |

ADT node `/sweet-usb` (avicii has none yet; Spacewar's lives in its image and is read in
`usb_board_params()`, `refs/anonbeat1/patches/0091.patch:281-305`):

```
/sweet-usb
    gdscr-off   = <0x0010f004>
    master-off  = <0x0000f010>
    cfgnoc-off  = <0x0000f07c>
    smmu-sid    = <0x000000e0>
    no-qusb2    = <1>          /* property presence is what is tested */
```

### 5.2 Code changes not covered by constants

1. **Masked SIDs.** `sweet_smmu_map_sid()` writes `SMR` with mask 0
   (`refs/anonbeat1/patches/0091.patch:234`). icnss needs `sid 0xC0 mask 1`
   (`avicii/lito.dtsi:3761`): one SMR must cover **0xC0 and 0xC1**. Add a mask argument; SMR =
   `1<<31 | mask<<16 | id`, and the conflict scan must also refuse to add a mask-0 entry for an id
   already covered by a wider entry (the current `~mask` compare finds that case but only *after* a
   match is recorded — the write path would still duplicate it).
2. **Return of `EEXIST` must not be fatal for WCN.** For USB the driver stops cleanly
   (`refs/anonbeat1/patches/0091.patch:362-368`); a WCN path that treats `EEXIST` as failure would
   never boot Wi-Fi whenever ABL left a masked SMR.
3. **`dr_mode = "drd"`** (`refs/lito-dts/lito-usb.dtsi:94`): the port is device-only in a gadget
   role, but ABL may leave the wrapper in host role. Read `GCTL.PrtCapDir`/`GSTS` before the soft
   reset; a host-role controller will not enumerate as a device.
4. **VBUS.** avicii charges over the same port; the QSCRATCH override
   (`UTMI_OTG_VBUS_VALID | SW_SESSVLD_SEL`, `refs/anonbeat1/patches/0074.patch:15-16,32`) is
   mandatory as on Spacewar — the controller only pulls up D+ when it believes a session exists.
5. **`sweet_smmu.c` is shared** with the touch path on Spacewar. If the touch port lands on the
   same file, keep one bank and one lock; SIDs get their own SMRs, banks are never re-created
   (`smmu_cb` is cached, `refs/anonbeat1/patches/0091.patch:178-183`).

### 5.3 Not needed

`GCC_USB30_PRIM_GDSCR` read is the only GDSC access; the enable itself is the DT regulator
`usb30_prim_gdsc` (`refs/lito-dts/lito-usb.dtsi:26`). No PMIC/SPMI register is touched by this
block.

---

## 6. First test — smallest probe that proves the block answers

Read the SMR table and report what already matches SID 0xE0. **No writes.** Correct output tells
you whether the reuse path will fire; wrong output tells you the port will reset on the first TRB.
It needs no DWC3, no clocks, no rails, no DMA — only the SMMU map.

```c
/* bsd/dev/sweet_smmu.c — diagnostic only, run before any gadget work. */
static void
smmu_report_sid(uint32_t sid)
{
	vm_offset_t b = ml_io_map(0x15000000u, 0x100000u);
	if (b == 0) {
		printf("SWEET SMMU: map failed\n");
		return;
	}
	printf("SWEET SMMU: probe sid 0x%x (no writes)\n", sid);
	/* SMMU_IDR0 0x20: [7:0] NUMSMRG; SMMU_IDR1 0x24: [7:0] NUMCB, [23:16] NUMS2CB,
	 * [31] granule; SMMU_sCR0 0x0: [10] USFCFG. */
	uint32_t id0 = smmu_rd(0x20);
	unsigned nsmr = id0 & 0xff;
	printf("SWEET SMMU: idr0 0x%08x (nsmr %u) idr1 0x%08x scr0 0x%08x usfcfg %u\n",
	    id0, nsmr, smmu_rd(0x24), smmu_rd(0), (smmu_rd(0) >> 10) & 1);
	unsigned hits = 0;
	for (unsigned i = 0; i < nsmr && i < 128; i++) {
		uint32_t smr = smmu_rd(0x800 + 4 * i);
		if (!(smr & (1u << 31))) {
			continue;
		}
		uint32_t mask = (smr >> 16) & 0x7fff;
		if (((smr ^ sid) & ~mask & 0x7fff) != 0) {
			continue;
		}
		uint32_t s2cr = smmu_rd(0xc00 + 4 * i);
		printf("SWEET SMMU: MATCH smr %u smr 0x%08x mask 0x%x s2cr 0x%08x type %u cbndx %u\n",
		    i, smr, mask, s2cr, (s2cr >> 16) & 3, s2cr & 0xff);
		hits++;
	}
	printf("SWEET SMMU: sid 0x%x matches %u smr(s): %s\n", sid, hits,
	    hits == 1 ? "REUSE it, do not add" : hits ? "CONFLICT" : "NO entry, add one");
}
```

Run it from the existing probe at the point where `sweet_smmu_map_sid()` would be called
(`refs/anonbeat1/patches/0091.patch:362`), with the rest of the gadget start skipped.

**Correct answer — free run.** Console, over the framebuffer:

```
SWEET SMMU: probe sid 0xe0 (no writes)
SWEET SMMU: idr0 0x0000004b (nsmr 75) idr1 0x6000003d scr0 0x00220406 usfcfg 1
SWEET SMMU: MATCH smr 6 smr 0x800000e0 mask 0x0 s2cr 0x00000005 type 0 cbndx 5
SWEET SMMU: sid 0xe0 matches 1 smr(s): REUSE it, do not add
```

`usfcfg 1` + exactly one mask-0 match with `type 0` = the port can go on. The follow-up run must
show `already matched by smr 6` and `s2cr now 0x7`.

**Incorrect answers.**

- `matches 0 smr(s): NO entry, add one` but the code adds a second entry anyway when one already
  exists under a mask → duplicate → SoC reset on the first TRB (§4).
- `matches 2 smr(s): CONFLICT` on a *fresh* boot means either ABL left two entries, or a previous
  run of this kernel already added one and the SMR was never cleared. Both fault the same way.
- `USFCFG 0` — someone wrote sCR0; expect silent passes instead of faults and treat a later
  unexplained reset as an SMMU bug.
- `s2cr ... type 2/3` on the matching SMR = a bypass entry. It will read back as
  `0x00020000`/`type 2` if written that way; it must be repointed to translate.
- `idr0`/`idr1` all zeros or `0xffffffff` = the map is wrong (wrong base, or apps_smmu is not
  clocked/powered).

**Then, and only then,** the second probe: `sweet_smmu_map_sid(0xe0)` and re-read S2CR. Panel
answer for that one: prints continue into `DWC3 GSNPSID 0x5533330a` and `ue0 created`, host sees an
enumeration and a `ue0` interface; the failure answer is the console freezing right after
`endpoints ready; arming setup (first DMA)` and the phone dropping to the bootloader logo.

---

## 7. GPIO / rail / clock inventory

Nothing in this block is optional-but-skippable — the list is short because the USB path is almost
entirely inside GCC and the DWC3 core.

| item | owner | who must supply it | notes |
|---|---|---|---|
| D+/D− HS PHY pins | femto PHY, internal | — (no pad mux) | `refs/lito-dts/lito-usb.dtsi:100` |
| VBUS session valid | QSCRATCH 0x0a6f8800 (`HS_PHY_CTRL` bit 20, `SW_SESSVLD_SEL` bit 28) | **ADT/MMIO write by the driver** | `refs/anonbeat1/patches/0074.patch:14-16` |
| `usb30_prim_gdsc` | GCC 0x10f004 | **ADT regulator** (`USB3_GDSC-supply`); must already be on before DWC3 regs | `refs/lito-dts/lito-gdsc.dtsi:10-14`, `refs/lito-dts/lito-usb.dtsi:26` |
| `GCC_USB30_PRIM_MASTER_CLK` | GCC branch 0xf010 | ADT/MMIO (read-only poll in this port) | `refs/lito-dts/gcc-lito.c:2302` |
| `GCC_USB30_PRIM_MOCK_UTMI_CLK` | GCC 0xf01c | ditto | `refs/lito-dts/gcc-lito.c:2320` |
| `GCC_USB30_PRIM_SLEEP_CLK` | GCC 0xf018 | ditto | `refs/lito-dts/gcc-lito.c:2338` |
| `GCC_CFG_NOC_USB3_PRIM_AXI_CLK` | GCC 0xf07c | ditto — gates DWC3 register access | `refs/lito-dts/gcc-lito.c:1062` |
| `GCC_AGGRE_USB3_PRIM_AXI_CLK` | GCC 0xf080 | ditto | `refs/lito-dts/gcc-lito.c:973` |
| `GCC_USB3_PRIM_CLKREF_CLK` / `GCC_USB3_PRIM_PHY_AUX_CLK` (0x8c010 / 0xf054) | GCC | only for the SS/DP path | `refs/anonbeat1/patches/0072.patch:67`, `refs/lito-dts/gcc-lito.c:2364` |
| `vdda_usb_ss_dp_core` 0.88 V | **PM8150L GPIO 12** → PM8150L ELDO13 | **SPMI** (PM8150L USID, not PM8150) | `avicii/mtp.dtsi:37-46` |
| PM8150 rails for USB | none | — | USB VBUS/charger goes through PM7250B (`avicii/a2.dtsi:437`) |

**PM8150 (main) owns nothing in the USB path** — its charger/PMIC partner here is PM7250B, and the
one PHY rail is on **PM8150L**. Do not look for USB rails on PM8150.

---

## 8. Open items / unverified

- SMMU geometry on avicii (NUMSMRG, NUMCB, NUMS2CB, CB base, granule) is **unread**. Spacewar's
  numbers (`docs/anonbeat1-NOTES.md:217`) are only an expectation.
- Whether ABL leaves an SMR for 0xE0 on avicii is **unverified**; the Spacewar evidence
  (`docs/anonbeat1-NOTES.md:457`) makes it likely. §6 settles it in one boot.
- Masked-SID support (§5.2 item 1) is required by the avicii DT but not implemented in patch 0091.
- The IPA SID set (0x520/0x521/0x522, `avicii/lito.dtsi:3733,3743,3751`) belongs to ipa_smmu
  consumers, not to this block; listed only so nobody re-uses those SMRs.
- `dr_mode = "drd"` role after ABL is unverified.
