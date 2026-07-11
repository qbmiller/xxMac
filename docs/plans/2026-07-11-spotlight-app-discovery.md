# Spotlight App Discovery Implementation Plan

**Goal:** Use the macOS Spotlight index to discover applications while retaining xxMac's cached search keys, ranking, and directory-scan fallback.

**Architecture:** Add a small Spotlight path provider based on `NSMetadataQuery`. `AppSearchManager` asks it for application bundle paths inside configured roots, builds the existing `AppEntry` values, and falls back to the current filesystem traversal when Spotlight fails or returns no usable applications. Existing directory monitors, JSON cache, pinyin keys, and launcher matching remain unchanged.

**Tech Stack:** Swift 5.9, AppKit/Foundation `NSMetadataQuery`, XCTest, Swift Package Manager.

---

### Task 1: Isolate application path discovery

**Files:**
- Create: `Sources/xxMac/Managers/SpotlightApplicationFinder.swift`
- Test: `Tests/xxMacTests/SpotlightApplicationFinderTests.swift`

1. Add tests for filtering Spotlight paths to configured roots and excluding nested application bundles.
2. Implement a Spotlight query for `com.apple.application-bundle` metadata and expose an asynchronous path result.
3. Verify the focused tests pass.

### Task 2: Integrate Spotlight with the existing index

**Files:**
- Modify: `Sources/xxMac/Managers/AppSearchManager.swift`

1. Make full rebuilds request Spotlight paths first.
2. Reuse the existing `makeEntry`, sorting, cache writing, and generation cancellation logic.
3. Fall back to filesystem traversal when Spotlight fails or returns no paths.
4. Keep directory monitoring and incremental append behavior unchanged.

### Task 3: Document and verify

**Files:**
- Modify: `README.md`
- Modify: `README_zh-CN.md`

1. Document Spotlight-first discovery and directory-scan fallback under General > Configuration.
2. Run focused tests, the full test suite, and a debug build.
3. Review the diff and leave all changes uncommitted for manual submission.
