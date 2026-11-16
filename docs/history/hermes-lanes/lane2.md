# Lane 2 — RDPROGS (build, depends on lane 1's list, start the plumbing now)

Put the tier-1 daemons on the RAMDisk root.

* Add `--programs FILE` to `tooling/61-mkrd-root.sh`: it stages every path in FILE from the OS
  DMG (Program files plus the bundle files lane 1 names), at mode 0755 for Mach-O and 0644
  otherwise, and fails on a path the DMG does not have. Sizing already follows `add_bytes`.
* Start with a seed list of `logd notifyd configd` until lane 1 delivers `tier1.txt`, then
  rebuild with the real one.
* Build to **its own** paths so lanes 4 and 5 can keep reading the baseline:
  `--out build/rd-root.progs.img --staging build/rd-root.progs.stage`.
* The image must stay QEMU-bootable at `QEMU_MEM=6G` (2.9 GiB today). If tier 1 pushes it past
  ~3.3 GiB, cut tier 1 rather than raising RAM, and say what you cut.
* Gates before handing the image over: `34` absent 0 / mismatch 0, `fsck_hfs` clean, the probe
  block passes, sha256 recorded in the report.
* **Owns:** `tooling/61-mkrd-root.sh`, `build/rd-root.progs.*`.
* **Report:** the diff, the sha256, size, and one boot (see "How to run") with lane 4's summary.
