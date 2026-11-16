# Task: fix fstool 0.5.4's chown-on-hard-link bug, at the root cause, and prove it on the host

Repo: /home/tadej/ios-nord (branch master). Read `AGENTS.md` first, then `docs/RAMDISK_ROOT.md`
§4 (the set table) and the paragraph at the end of §4 that starts "`chown` on a hard-linked file".

## The bug, as it is currently documented and worked around

`docs/RAMDISK_ROOT.md:198-201` records: `chown` on a hard-linked file through `fstool` writes a
second catalog record and corrupts the volume (`fsck`: "Incorrect number of file hard links"),
and is a silent no-op anyway. The workaround in the build is to leave the 43 dyld-shared-cache
files at uid 1000, gid 1000, mode 0755 instead of `root:wheel`, because dyld only needs them
readable. That workaround is why every RAMDisk image we build carries the wrong owners, and why
`tooling/61-mkrd-root.sh` has to run `fstool create` under `fakeroot`.

## What exists on this host

- `tooling/opt/fstool/bin/fstool` — the working binary, sha256
  `45edb6ce82019a7848f670b84b8626e0806c4f1427bd462479dd9c39795b4558`, 14 188 592 B. `tooling/opt`
  is **gitignored**, so nothing you do there shows in `git status`.
- `tooling/opt/fstool/fstool.tar.gz` — 5 218 440 B, and it contains **only** `fstool`, `README.md`,
  `LICENSE`. **There is no source in it.**
- `tooling/opt/fstool/fstool-0.5.4-unpriv.patch` — 13 528 B, the patch this build was made from.
  It edits `Cargo.toml` (e.g. dropping `fuser`'s `libfuse` default feature) and other files; treat
  it as the authoritative record of which upstream revision and which local changes are in use.
- **No Rust toolchain is installed** (`cargo`/`rustc` absent). Install it unprivileged
  (`rustup`, into `~/.cargo` / `~/.rustup`) — no sudo, no system packages. Pin the version the
  patch implies if it says so; otherwise use current stable and say which you used.
- `tooling/opt/apfs-fuse`, `tooling/opt/llvm`, `tooling/opt/platform-tools` are other prebuilt
  tools; do not modify them.

## What the task is

1. **Obtain the matching source.** `fstool` 0.5.4 on crates.io / its upstream repo. Confirm the
   revision matches `fstool-0.5.4-unpriv.patch` (it must apply cleanly; if it does not, stop and
   report the mismatch rather than forcing it).
2. **Reproduce first.** Build a minimal HFS+ volume, create a file with 2+ hard links, `chown` one
   link, and show both defects: (a) the owner does not change, or changes on only one name, and
   (b) `fsck.hfsplus -n` reports "Incorrect number of file hard links". Keep the reproduction as a
   small shell script in your scratch dir and paste its output in the report. Reproduction must be
   on a file you create, in a scratch dir under `/home/tadej/.hermes/cache/scratch/` — never on
   `build/*.img`.
3. **Fix the root cause** in the source. `chown` on a hard-linked inode must update the single
   catalog record (or all link records consistently — whatever HFS+ actually requires) and keep
   the link count correct. Do not paper over it by chowning before linking; this has to work for a
   chown after the links exist, because that is what the cache staging does.
4. **Prove it.** After the fix: the owner really changes on every name of the link group, the link
   count survives, `fsck.hfsplus -n` is clean, and the existing patched feature set still works —
   so re-run whatever `fstool check` / `fstool info` / create path the current binary supports.
5. **Install.** Build in release mode, put the new binary at
   `tooling/opt/fstool/bin/fstool.new`, leave the old one untouched, write the new binary's sha256
   to `tooling/opt/fstool/bin/fstool.new.sha256`, and put the source-level diff (your fix only, not
   the unpriv patch) in `tooling/opt/fstool/fstool-0.5.4-hardlink-chown.patch`. The lead agent
   swaps the binary in, not you.

## Hard limits

- Do not run QEMU, do not touch the phone, no `fastboot`, no `adb`, no `dd`, no `fakeroot` needed.
- Never write to `build/ios16-root.img`, `build/rd-root.img`, `build/rd-root.progs.img`,
  `build/rd-root.stage`, `build/rd-root.progs.stage`. Read them if useful; use copies under
  `/home/tadej/.hermes/cache/scratch/` for experiments.
- Do not `git commit`, `git add`, `git checkout`, `git stash`, or switch branches. Do not touch
  `.hermes-lanes/` or any file outside `tooling/opt/fstool/` in the repo.
- Do not claim a fix you did not see pass. Paste real command output; if a step fails and you
  cannot fix it, say exactly where.

## Report

The upstream revision and toolchain version you used; the reproduction output before the fix; the
diff of the fix with a one-paragraph explanation of the root cause; the after-fix reproduction
output and `fsck.hfsplus -n` verdict; the new binary's size and sha256; and anything still
imperfect (other hard-link operations, xattr paths, …) stated plainly.
