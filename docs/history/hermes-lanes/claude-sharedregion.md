# Task: why does the dyld shared cache fail to map, and can it be fixed without guessing?

Repo: /home/tadej/ios-nord (branch master, uncommitted lane work present — do not commit).
XNU tree you build against: `xnu-avicii/` holds the patch series (0100-0105) applied to
`xnu-8796.141.3`; a pristine checkout of that base is at `~/xnu-8796.141.3`.

## The wall, exactly

On both QEMU and the real handset the boot now stops with
`dyld: Library not loaded: /usr/lib/libSystem.B.dylib`. QEMU's ring shows why, in
`logs/qemu/20261114-103445-kern0105/msgbuf.txt`:

    30.581017  shared_region: [1(launchd)] check_np(0x16f343bd0) vm_shared_region_start_address() failed
    30.606284  shared_region: [1(launchd)] check_np(0x16f343160) vm_shared_region_start_address() failed
    30.775657  shared_region: [1(launchd)] map(…:'dyld_shared_cache_arm64'): not in trust cache
    … same "not in trust cache" for .01 … .42

The cache is present and huge: `build/rd-root.progs.stage/System/Library/Caches/com.apple.dyld`
is 2.6 GiB of `dyld_shared_cache_arm64` + subcaches. SIP is already relaxed — `adt.raw` carries
`lp-sip0` = 0x6f (CSR_ALLOW_UNRESTRICTED_FS included) and `lp-sip1` = 1, the same values the
completed fajita/sweet port used to get past exactly this. And `docs/anonbeat1-NOTES.md:846`
records that on that port the trust-cache lines were *warnings* and libSystem loaded — so the
`check_np … vm_shared_region_start_address() failed` pair, which is new here, is the prime suspect.

## What to do

1. **Read the code, do not guess.** Find `check_np`, `vm_shared_region_start_address`, and the
   `not in trust cache` printf in `~/xnu-8796.141.3` and establish, with file:line, which condition
   returns the error that makes the map fail, and whether the trust-cache message is a warning or
   the actual failure on this configuration.
2. **Check the port's own config first.** The avicii/sweet machine config is ARMv8.2, 16K granule,
   native LSE/PAN (`AGENTS.md`, `avicii/CONSTANTS.md`). A shared region carved at first launch with
   a 16K page granule, a `shared_region` size that does not fit the 1.20 GiB kernel-managed
   ramdisk window, or a missing `vm_shared_region` ADT property are all candidate causes. Compare
   against what the fajita port had at `docs/anonbeat1-NOTES.md` (it reached libSystem) and against
   `refs/` clones if useful.
3. **Decide what the fix is and prove the smallest one.** If it is a boot-arg/ADT value or a
   one-line kernel condition, that is ideal. If it needs a patch, write it as
   `xnu-avicii/patches/0106-*.patch`, add it to `xnu-avicii/series`, and run the pre-flight
   (`xnu-avicii/tools/preflight.sh --tree ~/xnu-8796.141.3 --dry`). **Do not dispatch the CI
   kernel workflow** — the lead agent reads the patch first and dispatches.
4. Report the causal chain explicitly: `check_np` fails because X, therefore the map fails, therefore
   dyld cannot find libSystem. If evidence contradicts the `check_np` theory, say so and give the
   alternative.

## Hard limits

- No QEMU in this spawn (the lead agent runs boots). No phone, no fastboot/adb, no `dd`.
- Do not touch `build/*.img`, `build/rd-root.stage`, `build/rd-root.progs.stage`, the phone logs, or
  `.hermes-lanes/`. Do not `git commit`.
- Own only: a new `xnu-avicii/patches/0106-*` if you write one, `xnu-avicii/series`, and the
  pristine tree at `~/xnu-8796.141.3` (leave it clean when you finish).
- If the answer needs a boot to settle, say which single boot would settle it and what line to look
  for — do not claim it.

## Report

Causal chain with file:line; the candidate you ruled out and how; the smallest fix (patch text or
ADT/boot-arg change); what a boot would have to show to prove it.
