# Runner Status

A macOS menu bar app that shows the self-hosted GitHub Actions runners in an org: online, offline, busy or idle. For each busy runner it also shows the repo, workflow, job, branch and how long the job has been running.

The menu bar shows only an Octocat icon. Clicking it checks the runners right then and shows the results; nothing runs in the background. Click a busy runner to open its job on GitHub.

## Build

Needs macOS 14+ and the Xcode Command Line Tools.

```bash
make build    # dist/Runner Status.app + dist/RunnerStatus-<version>.zip
make install  # build, copy to /Applications, relaunch
make clean    # remove dist/
```

The marketing version (`CFBundleShortVersionString`) comes from `VERSION`; bump it by hand when releasing. The build number (`CFBundleVersion`) is the UTC build time (`YYYYMMDDHHMM`), so it always increases. Override it with `make build BUILD=42`.

The app is ad-hoc signed, not notarized. On another Mac, clear the quarantine flag after unzipping: `xattr -dr com.apple.quarantine "Runner Status.app"`.

## Auth

Uses `gh auth token` by default. You can also paste a token in Settings; it is stored in the Keychain. The token needs org admin, or a fine-grained token with *Self-hosted runners: read* on the org and *Actions: read* on its repos.

## How jobs are matched

GitHub has no API that says which job a runner is running. On each refresh the app checks in-progress workflow runs repo by repo:

- It checks first the repo where each runner's last job was found, then the other repos, most recently pushed first.
- It stops once every busy runner has a match.

If a job can't be found (for example, the repo is outside the token's access), a full scan of every repo runs at most once every 5 minutes. In between, only the top 50 repos are checked.

Only org-level runners are listed. Repo-level runners are not included.

## License

MIT. See `LICENSE`. The menu bar icon comes from [Primer Octicons](https://github.com/primer/octicons) (MIT). See `THIRD_PARTY_NOTICES`. The GitHub logo is a trademark of GitHub, Inc. This project is not affiliated with or endorsed by GitHub.
