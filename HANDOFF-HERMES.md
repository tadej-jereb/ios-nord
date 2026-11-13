# Handoff — to Hermes: make the payload boot observable, then make XNU speak

Written 2026-11-13 by Claude Code for Hermes. It follows `HANDOFF-XNU.md`, checks it
against the code, and corrects it where the code disagrees. Read `AGENTS.md` first. Its
rules apply here unchanged.

## How to work

### Use multiple agents

Split the work into parallel lanes and give each lane its own sub-agent. Use one
coordinator (you). The coordinator owns the device, the build, the commit and
`docs/IMAGE_PROVENANCE.md`. Sub-agents never touch the phone and never run `fastboot`.

| lane | agent | owns | output |
|---|---|---|---|
| A | shim-logging | `avicii/shim/shim.c`, `loader.c`, `console.[ch]`, `diaglog.[ch]` | ring logging on the loader path (task 1) |
| B | boot-args-diff | read-only: `refs/edi194-ios-fajita/shim/loader.c`, `refs/edi194-ios-fajita/NOTES.md`, `avicii/tools/mkpayload.py`, `avicii/tools/mkadt_avicii.py` | a line-by-line diff of the `boot_args`/ADT/cmdline differences between fajita and avicii, each tied to a hypothesis below |
| C | ring-reader | `tooling/42-log-pull.sh`, `logs/` | a decoder that prints a pulled ring as text and flags the last `LOADER`/`JUMP` line |
| D | reviewer | read-only, the whole diff | reviews A's patch before the coordinator builds it: correctness, size, no new constants without a `CONSTANTS.md` citation |

Rules for the lanes:
- Lanes A, B and C start together. D starts when A says it is done.
- Each agent returns a short report with file:line references, not a narrative.
- Two agents never edit the same file. If a lane needs a change in a file it does not
  own, it asks the coordinator.
- If two agents disagree, the coordinator settles it by measuring (a host test, a
  build, or a boot), not by picking one answer.
- Only the coordinator boots, and only after A's patch has passed D's review and the
  build.

### Code quality: clean, efficient, optimised

- **Clean:** keep the existing style: kernel C, tabs, short functions, a comment only
  where the *why* is not obvious. Write one helper rather than copy-pasting a pair of
  `con_*` + `dlog_*` calls at every site. Leave no dead code, commented-out experiments
  or stray debug prints in the commit.
- **Efficient:** the shim runs with the MMU and caches off, so every store goes to Device
  memory and every ring line is a UFS WRITE+SYNC. Do not log inside loops (no line per
  segment unless it is behind a flag). Format each line once and send it to both sinks.
  Do not grow `.bss` needlessly: `diaglog.c` already keeps 80 KB of static buffers.
- **Optimise where it is safe and measurable:**
  - `copy64`/`zero64` in `loader.c` use `volatile` 8-byte accesses on purpose, because
    the MMU is off and the memory is Device type. Measure before you change them. One
    option is `ldp/stp` pairs (16 B per access, still aligned and still allowed on
    Device-nGnRnE). Time the 16.6 MB copy with `cntpct_el0` before and after, and keep
    the change only if the boot still works and the copy is measurably faster. Record
    both numbers in the commit message.
  - Do not "optimise" away `dsb sy; ic iallu; dsb sy; isb` before the jump.
  - Everything must still pass `-Wall -Wextra` with no new warnings, plus
    `host_test.c` where it applies.

## Verified against the code (2026-11-13)

1. **No ring on the payload path. Confirmed, and wider than `HANDOFF-XNU.md` says.**
   - `diag.c:733-737`: at `DIAG_STAGE < 1`, `diag_run()` returns 0 before
     `dlog_init()` (`diag.c:774`).
   - `shim.c:389-399`: `shim_main()` then calls `loader_boot()`, and every loader line
     goes through `con_*` only. Nothing on this path calls `dlog_line()`.
     **Initialising the ring alone fixes nothing.** The loader's output has to reach
     the ring too.
2. **`con_hex2` truncates to 32 bits** (`console.h:26`: `uint32_t va, vb`). The loader
   passes 64-bit values to it: `PHYS base=0x180000000` shows as `80000000`, and
   `SEGS end=`, `BOOTARG pa=` and `top=` are truncated the same way. Any photo of the
   panel from p1/p2 misreports high-bank addresses. Fix this together with the ring
   logging, with 64-bit pairs.
3. **The loader path clears the panel to RED** (`shim.c:396`, `con_clear(RED)`), not
   magenta. Use this panel key instead of the one in `HANDOFF-XNU.md` hypothesis 4:
   - red with no text = the shim reached the loader and died before its first line
   - red with text = read the last line
   - anything else = XNU drew it
4. **Hypothesis 5 is half wrong.** The working fajita port *does* use `debug=0xc`
   (`refs/edi194-ios-fajita/NOTES.md:41,244`). Its proven phone cmdline is:

       debug=0xc serial=3 cpus=1 keepsyms=1 -enable_kprintf_spam -noprogress

   `NOTES.md:312` says why `-enable_kprintf_spam` is required: DEVELOPMENT kernels
   disable kprintf output even when `DB_KPRT` is set (`pexpert/arm/pe_kprintf.c`). The
   avicii payload has neither `-enable_kprintf_spam` nor `cpus=1`. Use the fajita
   cmdline (plus avicii's own `sweet*` flags) as the baseline for p3.
5. **Hypothesis 3 gains weight.** Fajita's working boot loaded the kernel in the *low*
   bank (`NOTES.md:244`: entry PA `0xb146b488`, boot_args PA `0xb2000000`). Avicii puts
   it at `0x180000000`. That makes the low-bank A/B a strong second boot.

## Task 1: ring on the payload path (lane A)

Required behaviour:
- In `shim_main()`, under `#if DIAG_LOG`, call `dlog_init()` once before
  `loader_boot()` when `DIAG_STAGE < 1`. Write its return code to the panel. A failure
  must not block the jump: no ring is still better than no boot.
- Add one output helper that sends each loader line to both the panel and the ring. Use
  it for every `INITRD`, `PHYS`, `VIRT`, `ENTRY`, `SEGS`, `BOOTARG`, `JUMP` and `XNU`
  line, and log `loader_boot()`'s return string as `LOADER <why>`.
- Log `/chosen` `linux,initrd-start/-end` *before* the magic check (hypothesis 2). On
  failure, log which property is missing.
- Write the last ring line (`JUMP <entry_pa>`) **before** the cache maintenance and
  the branch. `dlog_line` already syncs per line, so the line is on flash before the
  jump.
- Make `con_hex2` 64-bit, or add a 64-bit variant and switch the loader to it.
- Leave the UFS host quiescent before the jump: no command in flight. XNU will not
  touch UFS this early, but do not leave a doorbell set.

Done when: `DIAG_STAGE=0 DIAG_LOG=1` builds clean, D has approved the patch, and a
host-side read of the image shows the new strings.

## Task 2: boots, in order (coordinator only)

Each boot is one `fastboot boot`, then a ring pull, then one line in `logs/`.

| image | change from p2 | discriminates |
|---|---|---|
| p3 | task 1 + fajita baseline cmdline, high bank | does the loader reach `JUMP`? what does XNU print? |
| p4 | p3 with `phys_base` in the low bank, taken from the live FDT `0x80000000` extent and checked against `CONSTANTS.md` | hypothesis 3 |
| p5 | only if B finds a real `boot_args`/ADT difference | hypothesis 6 |

Stop after any boot that leaves XNU output (a banner or a panic) on the panel or in the
ring. Capture it in `logs/` and name the cause before you change anything else.

Device state: the phone was **off USB after p2**. Recover it by holding power for about
30 s, then follow the ring-pull steps in `HANDOFF-XNU.md`. Build and boot commands are
the reproduction block in `HANDOFF-XNU.md` with `OUT=.../p3`.

## Definition of done

Unchanged from `HANDOFF-XNU.md`:
- The ring shows the loader's lines through `JUMP`, and XNU then prints something of
  its own.
- Every booted image has a sha256 line in `docs/IMAGE_PROVENANCE.md`.
- `docs/STATUS.md` is updated.
- Everything goes in one commit, with the copy-timing numbers in its message if the
  copy was optimised.

## Rules that do not bend

`fastboot boot` only. Nothing is flashed. Do not touch `persist`, `modemst1/2`, `fsg`,
`xbl`, `abl`, `tz` or the GPT. Every constant comes from `CONSTANTS.md` or the live FDT.
Procedures are numbered transcripts with one command per line. Sub-agents never touch
the device.
