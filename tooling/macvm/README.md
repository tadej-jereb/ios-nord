# XNU macOS VM runner

This provisions the Intel macOS 15 VM as repository runner `xnu-vm`. Install
Xcode 16.0 (16A242d) manually first, as `/Applications/Xcode.app` or
`/Applications/Xcode_16.app`. Do not run these scripts on the Linux host.
The scripts have been syntax checked; the VM lifecycle is owned by Claude.

1. On the Linux host, start the VM, then SSH as its admin user (replace `ADMIN`).

```sh
~/macos-vm/run-vm.sh
ssh -p 2222 ADMIN@127.0.0.1
```

2. In another host terminal, obtain a fresh, short-lived registration token. Paste
it only at the hidden prompt in step 3. Never put it in a file or commit.

```sh
gh api -X POST repos/tadej-jereb/ios-nord/actions/runners/registration-token --jq .token
```

3. In the VM admin user's SSH session, download the provisioning branch and run it.
Gate: this installs Homebrew packages, accepts the installed Xcode's license,
runs first-launch setup, installs the macOS **13.5 / 22G74 target KDK**, and
registers a launchd agent for this user. It creates `~/actions-runner`, `~/ccache`
and `~/xnu-ci`. Enter sudo credentials when asked; do not run the script with sudo.
The KDK version comes from the pinned dxb build script, not the VM's OS version.

```sh
bash
git clone --branch codex/selfhosted-runner https://github.com/tadej-jereb/ios-nord.git ~/ios-nord-runner
cd ~/ios-nord-runner
read -r -s -p 'Registration token: ' runner_token
bash tooling/macvm/provision.sh "$runner_token"
unset runner_token
cd ~/actions-runner
./svc.sh status
```

Rerunning `bash ~/ios-nord-runner/tooling/macvm/provision.sh` needs no token if
`.runner` already exists. It does not replace an existing registration. GitHub
adds `self-hosted`, `macOS`, `X64`; the script adds `xnu-vm`. The latest osx-x64
runner archive is checked against GitHub's SHA256 release-asset digest. ccache
uses `~/ccache` with a 20G limit, also saved in the runner's `.env`. The Homebrew
PATH is saved in `.path` for launchd. The service is a user LaunchAgent; keep this
admin user logged in (a headless VM may need a console login after reboot).
Service commands follow [GitHub's macOS service instructions](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/configure-the-application).

4. On the host, check registration and dispatch a source-only validation. Use a
branch containing this workflow change; it is not installed on `master` by this task.

```sh
gh api repos/tadej-jereb/ios-nord/actions/runners --jq '.runners[] | {name,status,busy,labels:[.labels[].name]}'
gh workflow run xnu.yml -R tadej-jereb/ios-nord --ref codex/selfhosted-runner -f runner=xnu-vm -f mode=dry-run
gh run list -R tadej-jereb/ios-nord --branch codex/selfhosted-runner
```

Once the dry run passes, dispatch with `-f mode=build`. The default for pushes
remains `macos-15`; hosted Intel remains selectable as `macos-15-intel`.

## Persistent build state

Only run **one runner** against `~/xnu-ci`. Each job resets the dedicated dxb and
xnu clones to their pins and removes untracked/ignored sources. dxb's object
root is `~/xnu-ci/dxb/build`, outside the xnu clone. That directory and dxb's
`.cache` survive; fakeroot and staged sources are regenerated. Toolchain version,
XNU tag, dxb pin or kernel/machine configuration changes invalidate the objects.
Normal source changes use make and ccache; resetting/reapplying patches may
refresh timestamps and cause additional ccache lookups. Unchanged objects are
retained where make permits. Final `kernel.*` outputs are removed before every
run so dxb cannot skip make or publish a stale kernel after a failure.

Self-hosted runs bypass `actions/cache`; hosted runs retain it. Patch paths and
build-log paths use `GITHUB_WORKSPACE` so the external source directory works.
The provisioned KDK, Xcode selection and `xcodes` presence stub avoid CI sudo
prompts. Other `macos_version` targets require their corresponding KDK to be
installed interactively first. No VM or self-hosted execution is part of this task's validation.

## Updates and troubleshooting

Runner updates are automatic by default. To refresh Xcode, wait for an idle
runner (`busy: false`), stop the service, replace Xcode manually, and rerun
provisioning. No registration token is needed for an existing runner.
Gate: stop only this VM's idle runner, not an active build.

```sh
cd ~/actions-runner
./svc.sh stop
bash ~/ios-nord-runner/tooling/macvm/provision.sh
./svc.sh status
```

For a runner installation that cannot auto-update, stop it while idle, remove
its repository registration through GitHub Settings → Actions → Runners, and
move `~/actions-runner` aside before provisioning with a fresh token. Do not
extract a new release over a live service. Logs are in `~/actions-runner/_diag`
and `~/Library/Logs/actions.runner.*`; do not share credential files.

For workflow lint on the Linux host, install `actionlint` into
`tooling/macvm/.tools/` (ignored; no binaries are committed), then:

```sh
tooling/macvm/.tools/actionlint .github/workflows/xnu.yml
bash -n tooling/macvm/provision.sh tooling/macvm/prepare-sources.sh tooling/macvm/install-kdk.sh
```
