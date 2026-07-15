# Automatic Update Check Design and Implementation Plan

**Goal:** Add configurable automatic update checks and show a red update indicator in the launcher when a newer release exists.

**Architecture:** A shared `UpdateManager` owns the persisted schedule, GitHub release request, version comparison, successful-check timestamp, retry timing, and available-version state. The About view and launcher observe this manager; only the manager performs network requests.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, Combine, URLSession, XCTest.

## Confirmed Behavior

- The About page keeps the manual Check for Updates button and adds a segmented picker with Off, Daily, Weekly, and Monthly choices.
- Weekly is the first-run default.
- Automatic checks never show alerts or system notifications.
- When a newer release exists, the launcher search row shows a fixed-size red update icon.
- Hovering the icon identifies the available version. Clicking it opens the GitHub Releases page.
- Failed automatic checks remain silent and retry after one hour. Manual checks continue to show inline success or failure text on the About page.
- The selected interval, last successful check time, and available release version are stored in `preferences.json`.

## Implementation Tasks

### 1. Update Policy and Manager

**Files:**
- Create: `Sources/xxMac/Managers/UpdateManager.swift`
- Create: `Tests/xxMacTests/UpdateManagerTests.swift`
- Modify: `Sources/xxMac/AppDefaultSettings.swift`
- Modify: `Sources/xxMac/Managers/PreferencesStore.swift`

1. Add failing tests for interval due dates, version comparison, successful state persistence, failed-check timestamp behavior, and stale-version cleanup.
2. Add `UpdateCheckFrequency`, preference storage and GitHub release provider protocols, and `UpdateManager`.
3. Use a one-shot timer for the next due check and a one-hour in-memory retry after network failures.
4. Run `swift test --disable-sandbox --filter UpdateManagerTests`.

### 2. About Page and Launcher Indicator

**Files:**
- Modify: `Sources/xxMac/Views/SettingsView.swift`
- Modify: `Sources/xxMac/Views/LauncherView.swift`
- Modify: `Sources/xxMac/xxMac.swift`
- Modify: `Resources/en.lproj/Localizable.strings`
- Modify: `Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Resources/zh-Hant.lproj/Localizable.strings`

1. Move manual update checks from local About-view state to `UpdateManager`.
2. Add the four-option segmented picker beside the manual button.
3. Add a red `arrow.down.circle.fill` button to the launcher's search row only when an update is available.
4. Start scheduling during app launch and re-check due state when the app becomes active.
5. Run launcher and update-manager tests.

### 3. Documentation and Verification

**Files:**
- Modify: `README.md`
- Modify: `README_zh-CN.md`

1. Document the automatic schedule, launcher indicator, and `preferences.json` fields.
2. Run the focused tests, full test suite, `git diff --check`, and `bash bundle_app.sh`.
3. Do not commit automatically; repository policy requires a human commit.

## Success Criteria

- Off performs no automatic request.
- Daily, weekly, and monthly checks run only when due, including after app reactivation.
- A newer version produces no popup and makes the launcher update icon visible.
- Clicking the icon opens the releases page.
- Existing manual update checking remains available and reports its result inline.
- Update settings migrate with the configured xxMac configuration directory.
