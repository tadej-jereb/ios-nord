# Shared brief for the three GPU-userland lanes — read me first, then your lane file

Repo: `/home/tadej/ios-nord`. You are one of three parallel research lanes, coordinated by Hermes.
The goal behind all three: iOS 16.7.16 (iPhone X userland, D22AP) runs on the OnePlus Nord, but
SpringBoard scrolls at ~24 fps because every frame is composited by the CPU (one `backboardd`
thread needs ~35 ms per frame at 1125×2436). The fix in progress is GPU compositing on the
Nord's **Adreno 620** (Qualcomm SM7250 "lito"), ported layer by layer from `raphael-ios-gpu`
(Adreno 640) — see `refs/marnov999-raphael-ios-gpu/`. The kernel side (layers 1–5: power, GMU,
command processor, shaders, KGSL/DRM uAPI) is done by the main agent in `xnu-avicii/patches/`.
**Your lanes are about layer 6–7: the userland** — how iOS's compositor reaches a GPU, and what
it takes to put Mesa (freedreno) under it.

Read in this order: `AGENTS.md`, `docs/STATUS.md` (first entry), the "GPU" section of
`avicii/CONSTANTS.md`, `refs/marnov999-raphael-ios-gpu/NOTES.md`, then your lane file.

Hardware facts you can rely on (from `avicii/CONSTANTS.md`):
* GPU: Adreno 620, chipid `0x06020000`, A650 family ("A6xx gen3"), 512 KiB GMEM,
  highest-bank-bit 14, UBWC mode 3. Firmware `a650_sqe.fw`, `a650_gmu.bin`, `a620_zap`.
* Mesa has `GPUId(620)` since 24.2.8 (`src/freedreno/common/freedreno_devices.py`).
* Display: 1080×2400 panel; iOS renders 1125×2436 (D22AP) into a framebuffer the kernel
  (`SweetFramebuffer.cpp`, an IOMobileFramebuffer stand-in) scans out.

Public references (clone read-only into `refs/` only if not already there; never commit into them):
* `https://github.com/Gsjsjzhznsz/hackios-xnu-userland` — Mesa 25.0.7 "freedreno-darwin" patches,
  `redwood-drm`, `mkeagl.py` / `eagl.c` (an EAGL replacement on Mesa).
* `https://github.com/HeliumStudio-Dev/hackios-xnu-kernel` branch `raphael-bringup`.
* `refs/marnov999-raphael-ios-gpu/` (local): kernel patches 0105–0141, `tools/build-redwood-gl.sh`.
* Mesa upstream `https://gitlab.freedesktop.org/mesa/mesa`.

Rules that hold for every lane:

* **Read-only research.** Never touch the phone, `adb`, `fastboot`, `boot_a`/`boot_b`, any
  partition, `xnu-avicii/`, `~/xnu-8796.141.3`, `tooling/71*`/`74*`, or CI (`gh workflow run`).
  The main agent is booting test kernels on the one phone; any interference breaks its run.
* You own the files named in your lane and **nothing else**. Two lanes never write the same
  file. Do not `git add/commit/checkout/stash`; the coordinator commits. Do not edit `.hermes-lanes/`.
* Apple binaries: analyse them only on this machine, for interoperability. **No decompiled or
  disassembled Apple code goes into the repo** — your report describes interfaces in your own
  words (selector numbers, struct layouts, call order, symbol names). Keep raw disassembly and
  tool output under `~/.hermes/cache/scratch/<lane>/`, not in the repo.
* The iOS root is read-only input: the OS DMG `build/ipsw-x/087-86698-044.dmg` and the SystemOS
  cryptex `087-86593-047.dmg` (holds the dyld shared cache), mounted unprivileged with
  `tooling/opt/apfs-fuse` the way `tooling/61-mkrd-root.sh` does (the file must be reached by a
  name ending in `.dmg`). Never write `build/ios16-root.img` or anything under `build/`.
* Run any Python that reads downloaded or extracted files with `python3 -I`, scripts kept outside
  the extracted directory.
* The reports are the deliverable. Be concrete: exact paths, symbol names, selector numbers,
  struct offsets, versions, sha256, the command lines you ran. Every number must come from a
  command you actually ran. If you are blocked, say so and why — a smaller honest result beats
  a padded one. Mark anything inferred rather than read as **inferred**.
