# Browser Search Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add configurable Chrome/Edge bookmark and history search to the launcher while preventing duplicate xxMac keyboard shortcuts and launcher keywords.

**Architecture:** A browser-agnostic manager depends on a `BrowserDataProvider`; the first provider reads Chromium `Local State`, `Bookmarks`, and a temporary copy of `History`. A central shortcut registry validates keyboard combinations and launcher keywords without changing existing persisted model shapes.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit Launch Services, SQLite3, XCTest

---

Repository policy overrides generic workflow guidance: do not commit automatically. Verify each task with focused tests and inspect the final diff.

### Task 1: Browser settings and launcher keyword validation

**Files:**
- Create: `Sources/xxMac/Models/BrowserSearchModels.swift`
- Create: `Sources/xxMac/Managers/ShortcutRegistry.swift`
- Modify: `Sources/xxMac/AppDefaultSettings.swift`
- Modify: `Sources/xxMac/Managers/QuickShortcutManager.swift`
- Test: `Tests/xxMacTests/ShortcutRegistryTests.swift`
- Test: `Tests/xxMacTests/AppDefaultSettingsTests.swift`

**Steps:**

1. Add failing tests for `bm`/`bh` defaults, case-insensitive keyword normalization, browser keyword duplication, quick-shortcut duplication, and keyboard configuration duplication.
2. Run `swift test --filter 'ShortcutRegistryTests|AppDefaultSettingsTests'` and verify the new symbols/tests fail.
3. Add `BrowserKind`, browser preference keys and defaults, stable `ShortcutActionID`, and distinct keyboard/launcher-keyword validation methods.
4. Make quick-shortcut updates reject enabled keyword conflicts without changing the Codable representation of existing items.
5. Re-run the focused tests and verify they pass.

### Task 2: Centralize existing xxMac keyboard conflict checks

**Files:**
- Modify: `Sources/xxMac/Managers/HotkeyManager.swift`
- Modify: `Sources/xxMac/Managers/AppLauncherManager.swift`
- Modify: `Sources/xxMac/Managers/ClipboardManager.swift`
- Modify: `Sources/xxMac/Managers/SnippetManager.swift`
- Modify: corresponding shortcut setting views under `Sources/xxMac/Views/`
- Test: `Tests/xxMacTests/ShortcutRegistryTests.swift`

**Steps:**

1. Extend failing tests with enabled window, app, clipboard and Snippets shortcut combinations and expected conflicting action names.
2. Run the focused registry tests and verify failure.
3. Feed each manager's enabled configuration into the central registry and validate before updating or enabling a configuration.
4. Surface the registry conflict as inline validation in existing shortcut recorder views; preserve existing stored values on load.
5. Run registry and existing preference migration tests.

### Task 3: Implement the extensible Chromium browser provider

**Files:**
- Create: `Sources/xxMac/Managers/BrowserDataProvider.swift`
- Create: `Sources/xxMac/Managers/ChromiumBrowserDataProvider.swift`
- Test: `Tests/xxMacTests/ChromiumBrowserDataProviderTests.swift`

**Steps:**

1. Add fixtures generated inside tests for `Local State`, nested `Bookmarks`, and a Chromium-compatible `History` SQLite database.
2. Add failing tests for `profile.last_used`, `Default` fallback, recursive bookmark parsing, HTTP/HTTPS filtering, title/URL matching, history ordering/deduplication, and temporary-file cleanup.
3. Run `swift test --filter ChromiumBrowserDataProviderTests` and verify failure.
4. Define the provider protocol and immutable browser records/status types.
5. Implement Chrome/Edge path injection, JSON parsing, SQLite read-only query against a uniquely named temporary copy, and cleanup with `defer`.
6. Re-run provider tests and verify they pass.

### Task 4: Connect browser search to the launcher

**Files:**
- Create: `Sources/xxMac/Managers/BrowserSearchManager.swift`
- Modify: `Sources/xxMac/Models/SearchItem.swift`
- Modify: `Sources/xxMac/ViewModels/LauncherViewModel.swift`
- Test: `Tests/xxMacTests/BrowserSearchManagerTests.swift`

**Steps:**

1. Add failing tests for default/custom keyword activation, exact-keyword empty query, disabled search, browser switching, and stale async request suppression.
2. Run `swift test --filter BrowserSearchManagerTests` and verify failure.
3. Implement preference loading, first-run default-browser detection, installed-browser fallback, provider selection, and explicit browser opening.
4. Route matching `bm`/`bh` queries before calculator/app fallback search and map records to stable `SearchItem` values.
5. Use request IDs so an older background result cannot replace a newer query.
6. Run manager tests and launcher-related tests.

### Task 5: Add browser search settings and localization

**Files:**
- Modify: `Sources/xxMac/Models/SettingsModels.swift`
- Modify: `Sources/xxMac/Views/SettingsView.swift`
- Create: `Sources/xxMac/Views/BrowserSearchSettingsView.swift`
- Modify: `Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Resources/zh-Hant.lproj/Localizable.strings`
- Modify: `Resources/en.lproj/Localizable.strings`

**Steps:**

1. Add “Browser Search” as the second Search sidebar function after General.
2. Build a native compact settings form with enable toggle, Chrome/Edge picker, bookmark keyword, history keyword, install/data status, and inline conflict messages.
3. Apply edits only after validation succeeds; notify active launcher searches when settings change.
4. Add Simplified Chinese, Traditional Chinese and English strings.
5. Build with `swift build` and fix type/layout integration errors.

### Task 6: Documentation and final verification

**Files:**
- Modify: `README.md`
- Modify: `README_zh-CN.md`
- Modify: configuration-directory text in all three localization files if needed

**Steps:**

1. Document Chrome/Edge support, current Profile selection, default/custom `bm`/`bh`, local-only reads, and explicit browser opening.
2. Update “General > Configuration Directory” documentation to state browser data and temporary history copies are not stored or migrated there.
3. Run `swift test` and require zero failures.
4. Run `swift build` and require success.
5. Inspect `git diff --check`, `git status --short`, and scoped diffs; preserve all unrelated pre-existing changes.

