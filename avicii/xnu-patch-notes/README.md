# xnu-patch-notes — deltas against the base tree

Patches here are **review skeletons for the base tree** (`refs/dipa-studio-ios-sweet`).
They number on from the base's `0081` and are applied upstream by CI, so they must stay a
minimal diff against existing files — not new standalone drivers (see `AGENTS.md`).

| note | subject | doc |
|---|---|---|
| `0090-avicii-goodix-gt9886-touch.patch` | Goodix GT9886: SE7 at 0x984000, vote 0x52008, TLMM 0x0f500000, rails ldoa13+smpa4, both-axis flip, `sweettouchprobe` | `docs/GOODIX_GT9886.md` |

## Applying

The patch applies to `bsd/dev/sweet_touch.c` and `bsd/dev/sweet_rpmh.c` **after** base
patches 0060, 0062 and 0063, in the base tree worktree:

    git -C <base-worktree> apply --check \\
        /home/tadej/ios-nord/avicii/xnu-patch-notes/0090-avicii-goodix-gt9886-touch.patch
    git -C <base-worktree> am --keep-cr \\
        /home/tadej/ios-nord/avicii/xnu-patch-notes/0090-avicii-goodix-gt9886-touch.patch

Verified state: applies with `patch -p1` and with zero fuzz to a tree built from 0060 +
0062 + 0063; not compiled, not booted.

## Review checklist before it goes upstream

- [ ] every number traces to `docs/GOODIX_GT9886.md` §3 and its citation
- [ ] no `pm8150_*` **DT label** leaks into `sweet_rpmh_vreg_enable` (the cmd-db keys on
      `qcom,resource-name`, i.e. `ldoa13` / `smpa4`)
- [ ] `TOUCH_RCG` / vote-word pair is confirmed on the first boot's `gcc vote=...` line
      before the hunk is treated as final (`docs/GOODIX_GT9886.md` §7)
- [ ] `sweettouch=0` stays in the normal cmdline until the ident probe returns `err=0`
