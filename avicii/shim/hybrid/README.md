# hybrid/ — H/F series, entry-convention localisation

Reasoning, hypotheses, pass criterion and the expected/observed table: `docs/HYBRID.md`.

    bash mk.sh all        # everything, in ladder order, self-asserting
    bash mk.sh h1         # one target
    python3 table.py      # expected/observed table from out/
    python3 table.py set h1 "parked, 94 s"

Files: `mk.sh` (compose, pack, footer, check, verify, sha256), `check.py` (asserts one image
is exactly its recipe — stock header bytes, exact kernel section, stock ramdisk/dtb, zero
gaps, footer extent), `cards.py` (per-image what/why/next, shared by builder and table),
`table.py`, `sections/` (stock kernel/ramdisk/dtb/cmdline, extracted and asserted), `out/`.

Every image: v2, page 4096, stock cmdline/ramdisk/dtb/addresses, stock `os_version
0x1c000185`, unsigned AVB hash footer, 100663296 B, `--verify` PASS (the v2 WARN is expected).
Nothing here is flashed; slot is `boot_b` and `backup/64f70df8/boot_b.img` is restored between
runs.

Two arithmetic facts the series is built on, both measured: stock's `code0` is
`b +0x2480000` (`imm26` counts words), and stock's `os_version` is 14.0.0 / 2024-05.
