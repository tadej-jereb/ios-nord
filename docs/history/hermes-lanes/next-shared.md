# Shared brief for round 3 (four lanes) — read me first, then your lane file

Repo: `/home/tadej/ios-nord`. You are one of four parallel research lanes, coordinated by Hermes.
State on 2026-11-15: iOS 16.7.16 (iPhone X userland, D22AP) runs on the OnePlus Nord (SM7250
"lito", Adreno 620). The GPU kernel side is **done and verified** on the phone: power, GMU, command
processor, shaders, and the userland interface — `/dev/dri/renderD128` (MSM DRM, self-test OK)
and `/dev/kgsl-3d0` (KGSL, self-test OK), patches `xnu-avicii/patches/0119`–`0126`,
log `logs/phone/gpu-0126-sweetgpu11.txt`. What is left is **userland**: Mesa freedreno built for
iOS and slotted under QuartzCore's OpenGL ES renderer. Lanes 1–3 unblock that; lane 4 is a CPU
hog seen on the phone.

Read first: `AGENTS.md`, `docs/STATUS.md` (first entry), `docs/gpu-research/README.md` and the
lane report it cites for your topic (A = QuartzCore, B = HackiOS inventory, C = Mesa build),
`docs/perf-research/README.md` (lane 4 only), then your lane file.

Inputs you may use:
* The kernel uAPI we actually built: `xnu-avicii/patches/0126-avicii-gpu-kgsl-drm-uapi.patch`
  (ioctl numbers, structs, private `MSM_INFO_IOS_*` ops). Read only. This is the contract; where
  HackiOS or raphael differ, say so and follow 0126.
* Clones from round 1 under `refs/` (HackiOS userland/kernel, raphael) — read only.
* Lane C's scratch: `~/.hermes/cache/scratch/lane-c-mesa/` (Mesa 25.0.7 source, the meson cross
  file, the toolchain proof). Reuse it; do not delete it.
* iOS images: OS DMG `build/ipsw-x/087-86698-044.dmg`, SystemOS cryptex `087-86593-047.dmg`
  (dyld shared cache), mounted read-only with `tooling/opt/apfs-fuse` the way
  `tooling/61-mkrd-root.sh` does (the path must end in `.dmg`). Toolchain: `tooling/opt/llvm`.
* Phone evidence already captured: `logs/phone/` (read only). Lane 4 also has
  `logs/phone/h1-disable-before.txt` / `h1-disable-after.txt`.

Rules for every lane:
* **No phone, no kernel, no CI.** Never touch `adb`, `fastboot`, SSH to 192.168.7.2, partitions,
  `xnu-avicii/`, `~/xnu-8796.141.3`, `tooling/71*`/`74*`, `build/`, or `gh workflow run`. The main
  agent is the only one that talks to the phone. If something can only be answered on the phone,
  write the exact read-only command(s) for the main agent to run in your report.
* You own only the files your lane names. Scratch work in `~/.hermes/cache/scratch/<lane>/`.
  No `git add/commit/checkout/stash/branch`. Do not edit `.hermes-lanes/`.
* **No Apple SDK or Xcode download, and no Apple code in the repo.** `.tbd` stubs generated from
  our own dyld cache and Apple's *open-source* releases (opensource.apple.com / apple-oss-distributions
  on GitHub: Libc, xnu, libpthread, Libsystem, …) are fine to use; record their versions and
  licences. Disassembly of Apple binaries stays in scratch; reports describe interfaces in your own
  words (symbols, selectors, struct layouts, call order).
* Run Python that reads downloaded/extracted files with `python3 -I`.
* Every number comes from a command you ran or a cited file:line. Mark inferences **inferred**.
  A smaller honest result beats a padded one. Report shape: summary (≤15 lines) → evidence →
  plan (ordered, with how to verify each step) → open questions.
