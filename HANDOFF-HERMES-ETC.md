# Handoff — launchd cannot resolve `mobile` (QEMU)

For Hermes. Written 2026-11-14 by Claude Code. Every number is measured on this host today; run
directories are named so nothing has to be re-derived from prose.

Read first, in this order: `AGENTS.md`, `docs/STATUS.md` (2026-11-14 entry),
`docs/LAUNCHD_BOOTSTRAP.md` §5 row 6, `HANDOFF-CLAUDE-DYLDCACHE.md` (closed, the rung before
this one), then this file.

QEMU only. No phone write happens until QEMU passes this rung.

## Closed: the dyld shared cache wall

`HANDOFF-CLAUDE-DYLDCACHE.md` is done. dyld *did* ask for the cache; the kernel refused it:

    shared_region: … map('dyld_shared_cache_arm64'): not in trust cache
    shared_region: … map('dyld_shared_cache_arm64'): owned by uid=1000 instead of 0

Without trust caches XNU falls through to `root_check` (`bsd/vm/vm_unix.c`, ~line 2490) and
requires `va_uid == 0`. `tooling/61-mkrd-root.sh` created the image unprivileged, and fstool
cannot chown a hard link, so the cache stayed `1000:1000`. Fix (committed): `fstool create` runs
under `fakeroot`, every record is born `0:0`, and the probe asserts the cache is `0:0`.
`fsck_hfs` clean, 119 files, `build/rd-root.img` sha256
`5e48f808e018b07bb2d113463606abdc19284523b9291e49f1df5a24269cfa6c`.

`build/ios16-root.img` (phone) is not affected: cache `0:80`, nlink 2, checked through a
read-only loop device, sha256 still `8654ec2b…70a0`. None of the four earlier attempts in the
dyldcache handoff (`--shared-cache`, `ignition_force_dylib_root`, `ignition_level=0`, cryptex
symlinks) were needed; they could not have worked.

## The kernel log: read `msgbuf.txt`, not `screen.txt`

The blank console was not the payload size. The harness's high-framebuffer layout (fb at
`MEM − 32 MiB`, needed for the 2.9 GiB root) makes the kernel boot *graphical*: after the run
`console_flags.json` reads `gc_graphics_boot=1`, `disableConsoleOutput=1`, and only the Apple
progress bar is drawn. With `--mem 2592M` (fb at `0xa0000000`, the old layout) text renders again
(`logs/qemu/20261114-065908`). Why the layout flips this is not known; it does not block anything.

`tooling/60-qemu-boot.sh` now reads the kernel message buffer out of guest RAM after every run
(`msgbufp` → ring, via `gVirtBase`/`gPhysBase`, symbols from `nm`) into
`<run>/msgbuf.txt` (~14 KB, the whole boot) plus `<run>/console_flags.json`. That is the
channel. `--uart0` + `serial=3` gets only the panic onto `serial.txt`.

## The wall now

Run `logs/qemu/20261114-070727`, `msgbuf.txt`:

    [30.408821] load_init_program: attempting to load /sbin/launchd
    [30.450706] SWEET: signed iOS binary, taken past the OSX platform check
    [30.647819] shared_region: … map(…'dyld_shared_cache_arm64'): not in trust cache   (x43, all pass root_check)
    [30.907759] SWEET Sandbox: launchd op 4
    [30.985232] SWEET NET: launchd lo0 add address 127.0.0.1
    [31.007302] pid 1 exited -- exit reason namespace 7 subcode 0x1, description unable to resolve 'mobile': 114 - The specified username does not exist

Panic ~36.0 s. libSystem is loaded and launchd is running its own code; namespace 7 is launchd's.

## Hypotheses, ranked

1. **No `/etc` on the RAMDisk root.** `build/rd-root.stage/` top level is only
   `dev private sbin System usr`. The phone image has `etc -> private/etc`,
   `var -> private/var`, `tmp -> private/var/tmp` (read-only check today). Libinfo's file module
   reads `/etc/master.passwd` / `/etc/passwd`; `mobile:…:501:501:…:/var/mobile` is in
   `private/etc/passwd`, but not reachable at `/etc`. Add the three links to `tooling/61`
   (it already makes symlinks at line ~257, `ln -sfn / "$stage/$l"` for the cryptex roots),
   rebuild, boot. Check `34-check-bootstrap.sh` still says absent 0, mismatch 0.
2. **The lookup goes through a daemon, not the file.** `usr/libexec/usermanagerd` and
   `xpcroleaccountd` are in the set. If 1 is applied and the error persists unchanged, find
   which Libinfo module launchd's `getpwnam("mobile")` uses on iOS 16 before adding anything.
3. **`/var/mobile` itself.** If the name resolves but the home is missing, the next message
   will say so; `private/var/mobile` is not in the RAMDisk set.

Success: the `unable to resolve 'mobile'` exit is gone and the exit/panic moves on.
A run that still says it is the same wall.

## How to run

sudo cannot prompt in a tool shell (no tty). Pipe it; the scope escapes the session cgroup:

    printf '%s\n' "$SUDO_PW" | sudo -S -p '' systemd-run --scope -p MemoryMax=12G -q -- /bin/sh -c 'cd /home/tadej/ios-nord && DISPLAY= QEMU_MEM=6G ./tooling/60-qemu-boot.sh --uart0 --ramdisk build/rd-root.img --cmdline "rd=md0 serial=3 sweetsmp=0 cpus=1 sweettouch=0 sweetkeys=0 sweetfb_console=1 sweetecon=1 keepsyms=1 launchd_log_serial=1 launchd_disable_all_timeouts=1 -v debug=0x144 cpu-factor=10" --secs 90'
    sudo chown -R tadej:tadej logs/qemu/<run>
    grep -n 'load_init_program\|shared_region\|exited' logs/qemu/<run>/msgbuf.txt

Run artifacts are created root-owned; chown them. Rebuild the root after touching `61`
(~4 min, unprivileged, now needs `fakeroot`): `./tooling/61-mkrd-root.sh`.
Fast loop for harness work: `--ramdisk build/rd-root.skeleton.img` at the default 4G, ~75 s.

Note: there is a ~30 s gap in every boot between ~0.19 s and ~30.25 s (before
`mcache: 1 CPU(s)`); it predates all of this and is not the wall.

## Do not

* Do not touch the phone, `boot_a`/`boot_b`, `persist`, `modemst1/2`, `fsg`, `xbl`, `abl`, `tz`,
  the GPT, or `build/ios16-root.img` (validated; read-only loop mounts only).
* Do not chown the cache through the fstool mount or move it off
  `/System/Library/Caches/com.apple.dyld/`; the fakeroot create is the fix.
* Do not drop `lp-sip0=0x6f`/`lp-sip1=1`, AMFI, or `0104`.
* Do not run QEMU without the memory scope.
* Do not commit `build/*.img`, `logs/*`.
