# Lane 5 — GATE (read-only analysis, no phone)

`docs/IMAGE_PROVENANCE.md` "Gate: write the 16 GiB root over userdata" requires that **the same
root has booted in QEMU**. `build/ios16-root.img` is 16 GiB; QEMU guest DRAM here is ~3.7 GiB, so
it cannot be an `md0` ramdisk. Work out what can satisfy the gate, and present the options.
**Do not choose one yourself.**

* Options to weigh, with evidence: a QEMU block device the kernel can root on (does the `sweet`
  config carry any virtio/AHCI/NVMe storage driver?); a RAMDisk built from the *same files* as
  `ios16-root.img` minus the bulk (a provable subset); or rewording the gate.
* Diff the RAMDisk set against `ios16-root.img` for the paths launchd touches up to now: the
  launchd table (byte-equal after the tweak?), the 492 plists, `/private/etc`, the root links,
  owners (`0:80` cache on the phone vs `0:0` here). Open the image **read-only** only
  (`fstool` read path or `apfs-fuse`-style read-only mount, never `rw`), and sha256 it before
  and after: it must stay `8654ec2b…70a0`.
* **Owns:** nothing in the tree. The report is the output.
* **Report:** the options, each with what it proves and what it costs; the diff.
