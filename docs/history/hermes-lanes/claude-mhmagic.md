# Task: what is dyld reading 0xFF 0xFF 0xFF 0xFF at, and why does no staged file contain it?

Repo: /home/tadej/ios-nord. Run to work from (do not re-run it): `logs/qemu/20261114-115454-lane9`.

## The wall, exactly

With the tier-2 root (`build/rd-root.tier2.img`, 3 270 508 544 B, sha256
`ce8eb192f1232a3e1a2bdf6fa3f51a3889928a2e4554a54cc9ec58fb705b4886`) on the 0105 kernel,
`SWEET EXEC` failures are **zero** (0 of 227 execs) and launchd spawns real services:
`containermanagerd`, `passd`, `tccd`, `SpringBoard`, `biomed`, `nfcd`, `UserEventAgent`,
`fairplayd.H2`. They then die in a loop and launchd throttles each at ~10 s. 53 of 80 crash reasons
are this, from one dyld pc inside the shared cache (`0x1a9b70ee4`):

    CRASH SpringBoard reason ns 6 code 0x9: file does not start with MH_MAGIC[_64]: 0xFF000000 0xFF000000
    CRASH nfcd        reason ns 6 code 0x9: file does not start with MH_MAGIC[_64]: 0xFF000000 0xFF000000

`0xFF000000` is what dyld *read*; those 4 bytes appear in **no** file the lane staged (it checked).
`tccd` additionally dies with `sig 5` brk in its own text, and `passd` SIGABRTs right after its AKS
calls succeed — those may be separate bugs; say so if they are.

## What to establish, in this order

1. **Which file.** From the crash `bt`/`far` values and dyld's own error convention, work out how to
   identify the path/slice dyld was loading (dyld4 prints the path only at higher log verbosity —
   check whether `launchd_log_serial=1` + `debug=0x8` reach it, or whether a dyld env/`DYLD_PRINT_*`
   arg is settable from `launchd.plist`). If the path cannot be recovered from this log, say which
   one boot with which flag would name it.
2. **Whether 0xFF is plausible from our side.** Two independent checks, no QEMU needed:
   a. Walk every staged Mach-O in `build/rd-root.tier2.stage` with Python, read the first 8 bytes and
      the `MH_MAGIC_64` position from the HFS extents, and list any file whose first bytes are not a
      Mach-O magic — i.e. a file dyld *would* reject if it opened it.
   b. Read the image as raw bytes at the extents of the staged dylibs and see whether anything in
      the volume reads `FF FF FF FF`: free-space patterns, the allocator's uninitialised blocks, the
      tail beyond the last allocated block, or a hard-link iNode whose data fork points at the wrong
      extent. `fstool check` says clean, so a structural answer is unlikely — but 0xFF is also what
      a guard page or an unmapped read looks like, so consider that the bytes may be dyld's own
      mmap of a region XNU filled with 0xFF.
3. **Check the kernel side.** `SWEET HFS` / mockfs reads: does the port's md/HFS stack return 0xFF
   for a read past a file's extent, or zero-fill? Search `xnu-avicii/patches/` (notably 0028 UFS,
   the HFS/mockfs patches) and `~/xnu-8796.141.3` for `0xff` fill patterns and for the mockfs
   read path. State whether this is a kernel read bug or a dyld/cache-content bug, with file:line.
4. **Deliver a testable conclusion.** Either the smallest fix (patch `0106-*` + `series`, preflight
   `--dry`, **do not dispatch CI** — the lead agent reads it first), or the single boot/flag that
   would name the file, and what line to look for.

## Hard limits

No QEMU, no phone, no `fastboot`/`adb`/`dd`. Do not modify `build/*.img`, `build/*.stage`,
`tooling/60`, `61`, `62`, `70`, the phone logs, or `.hermes-lanes/`. You may own a new
`xnu-avicii/patches/0106-*` plus `xnu-avicii/series`, and `~/xnu-8796.141.3` (leave it clean).
No `git commit`. Real output only; if the answer is "cannot tell without one boot", say exactly that.
