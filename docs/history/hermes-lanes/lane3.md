# Lane 3 — EXECLOG (make failed spawns visible)

Today a job whose Program is missing fails silently. Make the kernel say so.

* Find where an exec failure can be logged with the path and errno for every process, not only
  launchd: `exec_activate_image`/`__mac_execve`/`posix_spawn` return paths in the xnu tree. Check
  first whether an existing boot-arg already prints it (`debug=` bits, `launchd_log_serial`,
  `-v` paths). If one does, use it and skip the patch.
* Otherwise write `xnu-avicii/patches/0105-sweet-exec-fail-log.patch`: one `printf` (`SWEET
  EXEC: <path> failed errno N`) behind a boot-arg (`sweetexeclog=1`), default off. Add it to
  `xnu-avicii/series`. Dry-apply with the pre-flight in `docs/KERNEL_CI.md` and stop there:
  **do not dispatch the macOS workflow** until you, the coordinator, have read the patch. Then
  dispatch once.
* **Owns:** `xnu-avicii/patches/0105-*`, `xnu-avicii/series`, the kernel artifact it produces.
* **Report:** the patch or the existing flag, the CI run id, the kernel sha256.

## This spawn: phase 1 only

This first spawn writes the patch (or identifies the existing boot-arg), adds it to `series`,
runs the pre-flight dry-apply, and **stops**. Then the coordinator reads the patch and decides
whether you may dispatch. In this spawn, unless the coordinator's goal text explicitly tells you
the patch was approved, do not dispatch the workflow and report the patch text verbatim plus the
dry-apply result.

The existing patch series ends at `0104-sweet-ios-exec-platform.patch`; read `docs/KERNEL_CI.md`
and `xnu-avicii/HANDOFF.md` before writing anything.
