# xnu-patch-notes — deltas against the base tree

Patches here are **review skeletons for the base tree** (`xnu-avicii/patches` series, sourced
from `refs/dipa-studio-ios-sweet`). They number on from the series' last entry and are
applied upstream by CI, so they must stay a minimal diff against existing files — not new
standalone drivers (see `AGENTS.md`).

| note | subject | doc |
|---|---|---|
| `0095-avicii-goodix-gt9886-touch.patch` | Goodix GT9886: per-quadrant GPIO windows, S4/L13 rail votes (`smpa4`, `ldo13`/`ldoa13`), both-axis flip, `sweettouchprobe` | `docs/GOODIX_GT9886.md` |

## Applying

The patch applies to `bsd/dev/sweet_touch.c` and `bsd/dev/sweet_rpmh.c` **after** series
patches 0060, 0062 and 0063, in the xnu worktree:

    git -C <xnu-worktree> apply --check \\
        /home/tadej/ios-nord/avicii/xnu-patch-notes/0095-avicii-goodix-gt9886-touch.patch
    git -C <xnu-worktree> apply \\
        /home/tadej/ios-nord/avicii/xnu-patch-notes/0095-avicii-goodix-gt9886-touch.patch

Verified state: applies with `patch -p1` and zero fuzz to a tree built from 0060 + 0062 +
0063 of `xnu-avicii/patches`; not compiled, not booted. If a later series edit touches the
same regions, `git apply --3way` and re-read §5 of the doc before resolving.

## Review checklist before it goes upstream

- [ ] every number traces to `docs/GOODIX_GT9886.md` §3 and its citation
- [ ] no `pm8150_*` **DT label** leaks into `sweet_rpmh_vreg_enable` (the cmd-db keys on
      `qcom,resource-name`: `ldoa13` / `smpa4`; the series' `ldo13` is retried against
      `ldoa13`, not merged into one string)
- [ ] GPIO 8/9 stay on the WEST window and GPIO 90 on SOUTH — a flat TLMM base silently
      addresses the wrong quadrant
- [ ] `sweettouch=0` stays in the normal cmdline until the ident probe returns `err=0`
