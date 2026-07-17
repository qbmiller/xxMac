# Clipboard Image Filter Toggle Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task.

**Goal:** Add a clipboard-only image Toggle at the right edge of the Launcher search bar that writes `img` and stays synchronized with manual `image`/`img` queries.

**Architecture:** Keep the query as the single source of truth. `LauncherViewModel` exposes a derived image-filter state plus one mutation method; `LauncherView` binds a button-style Toggle to that interface. Existing clipboard search and database image filtering remain unchanged.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, XCTest

---

### Task 1: ViewModel image-filter state

**Files:**
- Modify: `Sources/xxMac/ViewModels/LauncherViewModel.swift`
- Test: `Tests/xxMacTests/LauncherViewModelTests.swift`

**Step 1: Write failing state tests**

Add tests proving:

```swift
func testClipboardImageFilterRecognizesOnlyImageAndImg() {
    let viewModel = LauncherViewModel()
    viewModel.mode = .clipboard

    for query in ["image", "img", " IMAGE ", " Img "] {
        viewModel.query = query
        XCTAssertTrue(viewModel.isClipboardImageFilterActive)
    }

    for query in ["", "images", "photo", "图片", "other"] {
        viewModel.query = query
        XCTAssertFalse(viewModel.isClipboardImageFilterActive)
    }
}
```

Also verify the state is false outside clipboard mode.

**Step 2: Run the tests and confirm failure**

Run:

```bash
swift test --filter LauncherViewModelTests
```

Expected: compilation fails because `isClipboardImageFilterActive` does not exist.

**Step 3: Implement the derived state**

Add a query normalization helper and:

```swift
var isClipboardImageFilterActive: Bool {
    guard mode == .clipboard else { return false }
    return Self.clipboardImageFilterQueries.contains(normalizedQuery)
}
```

The accepted query set is exactly `image` and `img`.

**Step 4: Add toggle mutation tests and implementation**

Test and implement:

```swift
func setClipboardImageFilterEnabled(_ isEnabled: Bool) {
    guard mode == .clipboard else { return }
    query = isEnabled ? "img" : ""
}
```

Verify enabling always writes `img`, disabling clears the query, and calls outside clipboard mode do nothing.

**Step 5: Run ViewModel tests**

Run `swift test --filter LauncherViewModelTests`.

Expected: all `LauncherViewModelTests` pass.

### Task 2: Launcher search-bar Toggle

**Files:**
- Modify: `Sources/xxMac/Views/LauncherView.swift`

**Step 1: Add a binding to the ViewModel interface**

Create a private `Binding<Bool>` whose getter reads `isClipboardImageFilterActive` and whose setter calls `setClipboardImageFilterEnabled(_:)`.

**Step 2: Add the clipboard-only control**

At the end of the top search-bar `HStack`, render the Toggle only when `viewModel.mode == .clipboard`. Use an SF Symbol image label, button Toggle style, fixed dimensions, selected/unselected styling, tooltip, and accessibility label. Keep it after the update indicator so it remains the rightmost control.

**Step 3: Build the app**

Run `swift build`.

Expected: build succeeds without warnings introduced by the change.

### Task 3: Localization and documentation

**Files:**
- Modify: `Resources/en.lproj/Localizable.strings`
- Modify: `Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Resources/zh-Hant.lproj/Localizable.strings`
- Modify: `README.md`

**Step 1: Add the localized control label**

Add `clipboard.filter_images` in all three resources:

- English: `Show Images`
- Simplified Chinese: `显示图片`
- Traditional Chinese: `顯示圖片`

**Step 2: Update README**

Extend the Clipboard History feature description to mention the image filter Toggle and its `img` query behavior.

**Step 3: Validate localization formatting**

Run `git diff --check` and inspect all three localization entries.

Expected: no whitespace errors and all locales contain the key.

### Task 4: Full verification

**Files:**
- Test: `Tests/xxMacTests/LauncherViewModelTests.swift`

**Step 1: Run focused tests**

Run:

```bash
swift test --filter 'LauncherViewModelTests|ClipboardModelsTests'
```

Expected: all focused tests pass.

**Step 2: Run the full suite**

Run `swift test`.

Expected: all tests pass with zero failures.

**Step 3: Review the final diff**

Confirm the change contains only the ViewModel interface, clipboard-only Toggle, localization, README, tests, design document, and this plan. Do not commit automatically.
