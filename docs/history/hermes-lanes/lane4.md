# Lane 4 — HARNESS (test infrastructure, start immediately)

Make each run judge itself, and make parallel runs safe.

* New `tooling/62-msgbuf-summary.sh RUN_DIR [BASELINE_DIR]`. It prints the last timestamp, the
  `Early boot complete` time, the count of `exec xpcproxy`, every other `exec <name>` with its
  time, `SWEET` lines after early boot, any panic string, and with a baseline a diff of exec
  names. Exit 0 if no panic. Baseline for this rung: `logs/qemu/20261114-094151`.
* Make two QEMU runs at once safe: always pass `--out logs/qemu/<stamp>-<lane>` (`60` mints the
  dir name from the second, so two runs started in the same second collide). Check `60` for any
  other shared path (payload, ADT, temp files under `avicii/shim/out/`) and give each run its
  own if one exists.
* Document the no-sudo memory scope in `docs/QEMU_AVICII.md` (see "How to run").
* **Owns:** `tooling/62-msgbuf-summary.sh` (new), `tooling/60-qemu-boot.sh`,
  `docs/QEMU_AVICII.md`.
* **Report:** the script, its output on `20261114-092833` and `20261114-094151`, and the
  parallel-run fix.

Note: lane 2 boots through `tooling/60-qemu-boot.sh` while you edit it. Keep the script's
existing CLI (`--ramdisk`, `--out`, `--cmdline`, `--secs`, `QEMU_MEM`) working at every step and
leave the file syntactically valid after each edit (`bash -n`), so a concurrent boot does not
break on a half-written file.
