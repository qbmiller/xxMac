# Clipboard Image Overlay Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Display the selected clipboard image in an app-managed screen-level preview instead of opening the system Quick Look panel.

**Architecture:** `LauncherViewModel` owns the active original-image filename. A dedicated controller creates a fresh borderless `NSPanel` with a magnifiable `NSScrollView` and `NSImageView` for each open. The existing launcher-level keyboard handler closes this preview before applying normal Escape behavior.

**Tech Stack:** Swift, SwiftUI, AppKit, XCTest

---

### Task 1: Model the in-panel preview state

**Files:**
- Modify: `Sources/xxMac/ViewModels/LauncherViewModel.swift`
- Test: `Tests/xxMacTests/LauncherViewModelTests.swift`

**Step 1: Write the failing test**

Add a test that an image result can enter preview state, while text cannot.

**Step 2: Run the test to verify it fails**

Run: `swift test --filter LauncherViewModelTests`

Expected: FAIL because no in-panel preview state exists.

**Step 3: Write minimal implementation**

Add an optional original-image filename and methods that open or close it only for a selected image result.

**Step 4: Run the test to verify it passes**

Run: `swift test --filter LauncherViewModelTests`

Expected: PASS.

**Step 5: Commit**

Skip. Repository policy requires manual Git commits.

### Task 2: Render and dismiss the screen-level image preview

**Files:**
- Add: `Sources/xxMac/Managers/ClipboardImagePreviewPanelController.swift`
- Modify: `Sources/xxMac/Views/LauncherView.swift`

**Step 1: Render the failing behavior manually**

Open Clipboard History with an image selected. The existing child overlay is clipped to the launcher bounds.

**Step 2: Implement the overlay**

Remove the child overlay and use the original cached image path in an app-managed borderless `NSPanel`. Build the content from `NSImageView` and a magnifiable `NSScrollView`. At 1x, mouse dragging moves the panel; when magnified, dragging or scrolling pans the image. Rebuild the panel content on each open.

**Step 3: Verify build**

Run: `swift build`

Expected: PASS.

**Step 4: Commit**

Skip. Repository policy requires manual Git commits.

### Task 3: Route Space and Escape to the overlay

**Files:**
- Modify: `Sources/xxMac/xxMac.swift`
- Delete: `Sources/xxMac/Managers/ClipboardQuickLookPreviewController.swift`

**Step 1: Route the custom preview panel**

Replace Space with the view-model state update and custom preview controller.

**Step 2: Add Escape ordering**

When the overlay is open, Escape closes it. Otherwise, Escape retains its existing launcher-close behavior.

**Step 3: Run complete verification**

Run: `swift test`

Expected: PASS.

**Step 4: Build the app bundle**

Run: `bash bundle_app.sh`

Expected: `xxMac.app` is created successfully.

**Step 5: Commit**

Skip. Repository policy requires manual Git commits.
