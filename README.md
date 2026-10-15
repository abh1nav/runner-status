# Runner Status

A macOS menu bar app that shows the self-hosted GitHub Actions runners in an org: online, offline, busy or idle. For each busy runner it also shows the repo, workflow, job, branch and how long the job has been running.

The menu bar shows only an Octocat icon. Clicking it checks the runners right then and shows the results; nothing runs in the background. Click a busy runner to open its job on GitHub.

## How to install

Requires macOS 14 or later on Apple Silicon.

### From a release

1. Download `RunnerStatus-<version>.zip` from the [Releases](https://github.com/abh1nav/actions-runner-status/releases) page and unzip it.
2. Move `Runner Status.app` to `/Applications`.
3. The app is ad-hoc signed and not notarized, so macOS blocks it on first open. Clear the quarantine flag:

   ```bash
   xattr -dr com.apple.quarantine "/Applications/Runner Status.app"
   ```

4. Open the app. The Octocat icon appears in the menu bar.

### From source

Install the Xcode Command Line Tools (`xcode-select --install`), then:

```bash
git clone https://github.com/abh1nav/actions-runner-status.git
cd actions-runner-status
make install
```

`make install` builds the app, copies it to `/Applications`, and launches it.

The build picks a macOS SDK that can compile the app. With only Command Line Tools, the macOS 27+ SDKs can't, because SwiftUI's `@State` macro plugin ships only with Xcode. In that case the build falls back to the newest older SDK you have installed. If none works, install Xcode. To force a specific SDK, run `make install SDK=/path/to/MacOSX26.5.sdk`.

### First run

1. Click the Octocat icon. Settings opens because no org is set yet.
2. Enter your GitHub organization and click Save.
3. Optionally, paste a token (see [Auth](#auth)) and turn on **Launch at login**.

## Build

```bash
make build    # dist/Runner Status.app + dist/RunnerStatus-<version>.zip
make install  # build, copy to /Applications, relaunch
make clean    # remove dist/
```

The marketing version (`CFBundleShortVersionString`) comes from `VERSION`; bump it by hand when releasing. The build number (`CFBundleVersion`) is the UTC build time (`YYYYMMDDHHMM`), so it always increases. Override it with `make build BUILD=42`.

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
