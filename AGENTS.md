# AGENTS.md

This file provides guidance to coding agents working with code in this repository.

## What this is

A macOS 14+ SwiftUI menu bar app (`LSUIElement`, no Dock icon) that lists an org's self-hosted GitHub Actions runners and, for busy ones, the job they're running. README.md is the user-facing spec, including the job-matching behavior.

## Build

No Xcode project, no SwiftPM, no dependencies, no tests. The Makefile calls `swiftc` directly on `Sources/*.swift` (with `-parse-as-library`, since `@main` lives in `RunnerStatusApp.swift`) and assembles the `.app` bundle by hand.

```bash
make build    # dist/Runner Status.app + dist/RunnerStatus-<version>.zip (ad-hoc signed)
make install  # build, kill the running copy, replace /Applications/Runner Status.app, launch it
make clean
```

- New `.swift` files in `Sources/` are picked up automatically by the glob.
- `Info.plist` holds only static keys; `CFBundleShortVersionString` (from `VERSION`), `CFBundleVersion` (UTC timestamp, override with `BUILD=`) and `LSMinimumSystemVersion` are inserted by `plutil` at build time. Don't add them to `Info.plist` or `plutil -insert` will fail.
- Verifying a change means `make install` and clicking the menu bar icon; there is no headless way to exercise the UI.

## Architecture

- **`RunnerStatusApp.swift`**: `MenuBarExtra` with `.window` style hosting `PopoverView`. One `RunnerStore` for the app's lifetime.
- **`RunnerStore`** (`@MainActor ObservableObject`): owns all state and the refresh logic. Refresh is on-demand only (popover open / refresh button); there are no timers or background polling, and that is intentional. `refresh()` drops overlapping calls via `isRefreshing`. `reconfigure()` (called after Settings save) rebuilds the client and clears every cache.
- **Job matching** (`RunnerStore.findJobs`): GitHub has no runner→job API, so it scans `in_progress` workflow runs per repo in parallel batches of 8, ordering repos by each runner's `lastSeenRepo` first, then by most recently pushed, and stops as soon as every busy runner is matched. If some stay unmatched, an exhaustive scan is allowed at most every 5 min; otherwise only the first 50 repos are scanned. The repo list is cached for 10 min. These constants are documented in README; keep them in sync.
- **`GitHubClient`** (actor): thin REST wrapper over `URLSession` with snake_case→camelCase decoding. Token precedence: Keychain token passed at init, else `gh auth token` (looked up at fixed Homebrew/system paths because GUI apps don't get the shell `PATH`), cached and dropped on a 401. Tracks `X-RateLimit-Remaining` for display.
- **`Keychain`**: single generic-password item (service `actions-runner-status`, account `github-token`). Saving an empty token deletes it.
- **Settings**: org in `UserDefaults` key `org`; launch-at-login via `SMAppService.mainApp`.
- **`Octocat.swift`**: menu bar icon from Primer Octicons (MIT, attributed in `THIRD_PARTY_NOTICES`, which is bundled into the app's Resources).

Only org-level runners are listed (`/orgs/{org}/actions/runners`); repo-level runners are out of scope.
