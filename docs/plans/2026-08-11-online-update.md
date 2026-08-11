# Online Update Plan

**Status:** Deferred. This document records a possible future implementation; no code changes have been made.

**Goal:** Allow users to check for a new version, download and install it from the About page, then relaunch xxMac to use the new version.

## Current Behavior

- `UpdateManager` sends a `HEAD` request to `https://github.com/qbmiller/xxMac/releases/latest` and extracts the latest version from the redirect URL.
- The About page can report whether a newer version exists.
- The launcher update indicator opens the GitHub Releases page.
- The app does not currently read release assets, download an update, replace the installed app, or relaunch itself.

## Decision

Use Sparkle for a real online-update workflow. GitHub Releases will host the signed and notarized update archive, while Sparkle will verify, download, install, roll back on failure, and relaunch the app.

Do not implement direct replacement of the running `xxMac.app` with custom file operations. A custom updater would need to handle permissions, signatures, an app running from unexpected locations, interrupted replacement, rollback, and relaunching safely.

A lightweight alternative is to download and open a DMG. That option must say "Download complete; install the update and restart xxMac" because downloading a DMG alone does not install the update. It is not the target workflow described by this plan.

## Intended User Experience

1. Keep the initial button label as **Check for Updates**.
2. When a newer version is found, change the primary action to **Update Online**.
3. Show download and verification progress after the user confirms the update.
4. When installation is ready, show **Restart and Update** and **Later** actions.
5. After relaunch, display the new version in About.
6. Automatic checks remain silent and never download or install an update without an explicit user action.
7. The launcher update indicator starts the same update flow instead of opening the Releases page.

## Implementation Plan

### 1. Integrate Sparkle

- Add Sparkle as a SwiftPM dependency in `Package.swift`.
- Add the feed URL and Sparkle public update key to `Sources/xxMac/Info.plist`.
- Keep the private signing key outside the repository, on the release machine or in CI secrets.
- Wrap Sparkle behind the existing `UpdateManager` so the About page and launcher continue to share one source of state.

### 2. Update State and UI

- Model idle, checking, update-available, downloading, ready-to-relaunch, cancelled, and failed states.
- Update `Sources/xxMac/Views/SettingsView.swift` with progress and restart actions.
- Update `Sources/xxMac/Views/LauncherView.swift` so its update indicator enters the same flow.
- Add English, Simplified Chinese, and Traditional Chinese localization strings.
- Preserve the existing Off, Daily, Weekly, and Monthly preferences. Use one scheduler only; do not allow Sparkle and `UpdateManager` to schedule duplicate checks.

### 3. Release Feed and Package

- Build with a stable Developer ID Application identity and hardened runtime.
- Notarize the app and staple the notarization ticket before creating the update archive.
- Publish a versioned archive such as `xxMac-1.1.6.zip` as a GitHub Release asset.
- Generate an `appcast.xml` entry containing the version, download URL, file length, and Sparkle EdDSA signature.
- Host `appcast.xml` at a stable HTTPS URL; its enclosure URL may point directly to the GitHub Release asset.
- Extend `release_notarize.sh` or add a narrowly scoped release helper to generate and validate the Sparkle metadata.

The existing local `qbmiller` signing identity is useful for local builds but is not sufficient for a publicly trusted automatic-update channel. Public online updates require a consistent Developer ID identity and notarized artifacts.

### 4. Tests and Documentation

- Add tests for state transitions, frequency mapping, cancellation, failed downloads, stale versions, and relaunch readiness.
- Verify rejection of an update with an invalid Sparkle signature.
- Perform a real upgrade test from an older signed build to a newer signed build installed in `/Applications`.
- Confirm that Accessibility authorization and global hotkeys still work after the upgrade.
- Update `README.md` and `README_zh-CN.md` when the feature is implemented.
- Run `swift test`, `swift build`, `git diff --check`, and a packaged-app upgrade test.

## Acceptance Criteria

- Clicking **Update Online** downloads only a newer signed release.
- A modified, unsigned, incorrectly signed, or incomplete update is rejected.
- Cancelling or losing the network leaves the current installation usable.
- **Restart and Update** installs the downloaded version and relaunches xxMac.
- Automatic checks do not display intrusive dialogs and do not install without consent.
- GitHub API availability is not required for installation when the Sparkle appcast and release asset are reachable.
- The release procedure is documented and reproducible without committing private signing material.

## Files Expected to Change Later

- `Package.swift`
- `Sources/xxMac/Info.plist`
- `Sources/xxMac/Managers/UpdateManager.swift`
- `Sources/xxMac/Views/SettingsView.swift`
- `Sources/xxMac/Views/LauncherView.swift`
- `Resources/en.lproj/Localizable.strings`
- `Resources/zh-Hans.lproj/Localizable.strings`
- `Resources/zh-Hant.lproj/Localizable.strings`
- `Tests/xxMacTests/UpdateManagerTests.swift`
- `release_notarize.sh` or a dedicated Sparkle release helper
- `README.md`
- `README_zh-CN.md`
