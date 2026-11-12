# Kernel CI — building the avicii XNU kernel

XNU cannot be built on this Linux host: it needs Xcode, `mig`, `libfirehose_kernel`
and a macOS KDK. The local clang is for the shim and the payload only. The kernel
is built on a GitHub macOS runner by `.github/workflows/xnu.yml`, which applies
`xnu-avicii/series` in order to `xnu-8796.141.3` and uploads
`kernel.development.sweet`.

Nothing in this document touches the phone.

## 0. Once: local pre-flight

Prove the series applies **before** any CI minute is spent. A bad series is a
cheap local failure and an expensive CI one.

    XNU_TAG=xnu-8796.141.3
    git clone --depth 1 --branch "$XNU_TAG" \
        https://github.com/apple-oss-distributions/xnu ~/xnu-8796.141.3
    xnu-avicii/tools/preflight.sh --tree ~/xnu-8796.141.3 --dry

`--dry` applies everything in order, runs `git apply --check` ahead of each
patch, and then resets the tree. Drop `--dry` to keep the patched tree for
local inspection. The script also runs the hunk-count check first: `git apply`
*trusts* declared hunk counts, so a short count silently drops trailing lines
instead of failing.

Stage scripts (``xnu-avicii/patches/*.sh``) are executed by the pre-flight exactly
as the CI runs them — they fetch pinned Apple/BearSSL commits. On Linux there is
no `xcrun`; the script substitutes a stub SDK holding only
`TargetConditionals.h`, which is all they read.

Both the `--check` run and the CI use the tag from Apple's `macos-135`
`release.json`, **`xnu-8796.141.3`** — not `8796.101.5`. Patching any other
subversion fails from `0004` on (`start.s` differs).

## 1. Once: fork and log `gh` in

`gh` is installed at `/usr/bin/gh` and is **not** logged in (`gh auth status`
says so). Log in first, then fork — a fork is required because the workflow has
to be dispatched on a repository you own.

    gh auth status                    # expect: "not logged in"
    gh auth login                     # GitHub.com → HTTPS → login with a browser
    gh auth status                    # expect: "Logged in to github.com as <you>"

`gh auth login` needs the `repo` and `workflow` scopes. If you would rather use
a token: `export GH_TOKEN=<token with repo+workflow>` instead of `gh auth login`
— the CLI picks the variable up.

    gh repo fork --remote --remote-name fork   # prints owner/name of the fork
    gh repo view --json nameWithOwner          # confirm what you are pushing to
    git push fork main                         # main is the default branch here

Enable Actions on the fork once (web UI → Actions → "I understand my workflows,
go ahead and enable them"). macOS runners bill at 10x minutes; every workflow in
this repo is `workflow_dispatch`-only for that reason.

## 2. Build

Dry run first — it checks out the tag, applies the whole series and stops:

    gh workflow run xnu.yml -R <you>/ios-avicii -f mode=dry-run

    gh run watch -R <you>/ios-avicii           # or: gh run list -R <you>/ios-avicii

Then the real build:

    gh workflow run xnu.yml -R <you>/ios-avicii -f mode=build

Defaults are `macos_version=13.5`, `kernel_config=DEVELOPMENT`,
`machine_config=SWEET`, `keep_going=true`. A run takes 20–40 min; the first one
usually has compile errors — that is what `keep_going` is for, and the whole
build log comes back as the `xnu-build-log` artifact.

## 3. Download

    gh run list -R <you>/ios-avicii -w xnu.yml --limit 3      # get the run id
    gh run download <run-id> -R <you>/ios-avicii -n xnu-kernel-sweet \
        -D avicii/shim/out/kernel

That leaves `avicii/shim/out/kernel/kernel.development.sweet` plus `SHA256SUMS`.
Check before using it:

    ( cd avicii/shim/out/kernel && shasum -a 256 -c SHA256SUMS )
    file avicii/shim/out/kernel/kernel.development.sweet       # Mach-O 64-bit arm64
    otool -l avicii/shim/out/kernel/kernel.development.sweet | grep -A4 LC_SEGMENT_64 | head

`kernel.development.sweet` is a Mach-O arm64 image (ARMv8.2, 16K pages,
`SWEET` machine config); `file` says `Mach-O 64-bit arm64` and the segment
`__PAGEZERO` is present. If the artifact is missing, the run's
"Collect" step found no `kernel.*` — read the log, not the artifact name.

## 4. Hand it to the payload builder

The kernel is a **payload input**, not a boot image. From `avicii/shim`, with
the live FDT dump as the memory source:

    cd avicii/shim
    ../tools/fdt-mem.py ../../logs/dumps/run-*/10-fdt.dtb > out/fdt-mem.json
    ../tools/mkadt_avicii.py out/avicii.adt --fdt-json out/fdt-mem.json --dump
    ../tools/mkpayload.py out/kernel/kernel.development.sweet \
        out/avicii.adt out/payload.bin
    STOCK_BOOT=../../src/los21-boot.img ./build.sh out/payload.bin

`mkpayload.py` resolves the chained fixups and writes the payload; `build.sh`
packs the shim plus that payload into `out/shim-boot.img` (header v1,
`Image.gz-dtb`). The ADT must be the one built from the **live** FDT — its
`dram-base`/`dram-size` come from `logs/mem-live.json`, and the kernel reads
exactly those two properties out of `/chosen` (patch `0016`); the static memory
node is a placeholder on this device. `avicii/tools/mkadt_avicii.py` refuses to
run without them for that reason.

Getting the payload into a boot image and onto `boot_a` is `docs/SHIM_BOOT.md`.
Boot args that matter for the first kernel boot are listed in `docs/STATUS.md`
(`sweetsmp=0` to keep one CPU, `sweettouch=0`, `sweetkeys=0`, `sweetecon=1`,
`sweetfb_console=1`).

## 5. When it fails

The workflow is built to fail on the step that is wrong, in this order:

| symptom | meaning | what to do |
|---|---|---|
| `Validate patch hunk counts` fails | a patch header disagrees with its body | `python3 xnu-avicii/tools/check-hunk-counts.py xnu-avicii/patches`, fix the header (or re-run `make-series.py` and re-adapt) |
| `does not apply: <file> (entry N)` | patch N does not fit this tag | reproduce locally with the pre-flight; most likely a context line another patch changed — fix the series, do not reorder by hand |
| `release.json for macOS X -> Y` mismatch | Apple repointed the release | bump `XNU_TAG` and re-verify the series against the new tag |
| `a series patch was skipped by build.sh` | a patch reached `patches/` in dxb and was re-applied or rejected there | the workflow applies the series itself; a non-empty `dxb/patches` means a stray copy |
| `dxb/patches is not empty` | same as above | move the stray file, or drop the `cp` that produced it |
| compile errors | real porting work | read `xnu-build-log`; fix the series near the failing hunk |

Never "fix" a red run by deleting the patch that failed — `xnu-avicii/HANDOFF.md`
records why each file is there and what was adapted.
