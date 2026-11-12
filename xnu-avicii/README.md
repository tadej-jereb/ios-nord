# xnu-avicii

The kernel half of the port: an ordered patch series against `xnu-8796.141.3`
plus the tooling that proves it applies.

* `HANDOFF.md` — what every file is: carried verbatim, adapted (and how), or
  dropped (and why). Read it before touching anything here.
* `series` — the only order. `apply` = patch, `copy` = stage script.
* `patches/` — the series, byte-exact except for the documented adaptations.
* `tools/make-series.py` — re-derives `patches/` + `series` from `refs/`.
* `tools/preflight.sh` — applies the series to a scratch `xnu-8796.141.3`
  checkout locally. Run it before every push.
* `tools/check-hunk-counts.py` — hunk-count gate; CI and pre-flight step 1.

Build host is a GitHub macOS runner: `.github/workflows/xnu.yml`. User steps,
including the `gh auth login` that is still missing on this machine:
`docs/KERNEL_CI.md`.

    python3 tools/check-hunk-counts.py patches
    tools/preflight.sh --tree ~/xnu-8796.141.3 --dry
    python3 tools/make-series.py --check        # fail if patches/ drifted

After `make-series.py` rewrites anything, refresh the checksums:

    ( cd . && sha256sum series patches/* > SHA256SUMS )

The dram path is never compiled in: `0016` reads `dram-base`/`dram-size` from the
ADT `/chosen`, which `avicii/tools/mkadt_avicii.py` fills from the live FDT dump.
