# App Search Pinyin Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make indexed applications searchable by Chinese names, full pinyin, and pinyin initials, while persisting those generated search keys in the application index cache.

**Architecture:** Keep `AppSearchManager` as the owner of app indexing and search. Extract only the pinyin/search-key generation into a small pure Swift helper so it can be tested without AppKit UI. Store generated keys in the existing `AppSearchIndexCacheV1` payload so a newly installed xxMac build can reuse the indexed pinyin keys without rescanning immediately.

**Tech Stack:** Swift 5.9, Swift Package Manager, Foundation `StringTransform.toLatin`, existing SwiftUI/AppKit app.

---

### Task 1: Add Test Target

**Files:**
- Modify: `Package.swift`
- Create: `Tests/xxMacTests/AppSearchKeyBuilderTests.swift`

**Step 1: Add a test target in `Package.swift`**

Add this target after the executable target:

```swift
.testTarget(
    name: "xxMacTests",
    dependencies: ["xxMac"]
)
```

If SwiftPM refuses importing an executable target from tests, change direction in Task 2: keep helper tests as direct file tests under the same target is not possible, so use `swift build` plus manual verification. Prefer trying the test target first.

**Step 2: Create an initial failing test file**

Create `Tests/xxMacTests/AppSearchKeyBuilderTests.swift`:

```swift
import XCTest
@testable import xxMac

final class AppSearchKeyBuilderTests: XCTestCase {
    func testChineseNameAddsPinyinAndInitialKeys() {
        let keys = AppSearchKeyBuilder.keys(for: ["微信"])

        XCTAssertTrue(keys.normalized.contains("微信"))
        XCTAssertTrue(keys.normalized.contains("wei xin"))
        XCTAssertTrue(keys.compact.contains("weixin"))
        XCTAssertTrue(keys.compact.contains("wx"))
    }

    func testEnglishNameKeepsNormalSearchKeys() {
        let keys = AppSearchKeyBuilder.keys(for: ["Visual Studio Code"])

        XCTAssertTrue(keys.normalized.contains("visual studio code"))
        XCTAssertTrue(keys.compact.contains("visualstudiocode"))
        XCTAssertFalse(keys.compact.contains("vsc"))
    }

    func testMixedChineseAndEnglishNameIsSearchable() {
        let keys = AppSearchKeyBuilder.keys(for: ["腾讯会议"])

        XCTAssertTrue(keys.normalized.contains("腾讯会议"))
        XCTAssertTrue(keys.normalized.contains("teng xun hui yi"))
        XCTAssertTrue(keys.compact.contains("tengxunhuiyi"))
        XCTAssertTrue(keys.compact.contains("txhy"))
    }
}
```

**Step 3: Run tests and confirm failure**

Run:

```bash
swift test
```

Expected: fail because `AppSearchKeyBuilder` does not exist yet, or because executable target import needs adjustment.

---

### Task 2: Implement Search Key Builder

**Files:**
- Create: `Sources/xxMac/Managers/AppSearchKeyBuilder.swift`
- Modify: `Sources/xxMac/Managers/AppSearchManager.swift`

**Step 1: Add helper implementation**

Create `Sources/xxMac/Managers/AppSearchKeyBuilder.swift`:

```swift
import Foundation

struct AppSearchKeyBuilder {
    struct Keys {
        let normalized: [String]
        let compact: [String]
    }

    static func keys(for names: [String]) -> Keys {
        var normalized = Set<String>()
        var compact = Set<String>()

        for name in names {
            insert(name, into: &normalized, &compact)

            guard containsCJK(name), let pinyin = pinyin(for: name) else {
                continue
            }

            insert(pinyin, into: &normalized, &compact)

            let initials = pinyin
                .split(separator: " ")
                .compactMap { $0.first }
                .map(String.init)
                .joined()
            insert(initials, into: &normalized, &compact)
        }

        return Keys(
            normalized: normalized.sorted(),
            compact: compact.sorted()
        )
    }

    static func normalize(_ value: String) -> String {
        let folded = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))

        let cleanedScalars = folded.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar) &&
            !CharacterSet.nonBaseCharacters.contains(scalar)
        }
        return String(String.UnicodeScalarView(cleanedScalars)).lowercased()
    }

    static func normalizeCompact(_ value: String) -> String {
        let lowered = normalize(value)
        let filteredScalars = lowered.unicodeScalars.filter { scalar in
            if CharacterSet.whitespacesAndNewlines.contains(scalar) { return false }
            if CharacterSet.punctuationCharacters.contains(scalar) { return false }
            if CharacterSet.symbols.contains(scalar) { return false }
            return true
        }
        return String(String.UnicodeScalarView(filteredScalars))
    }

    private static func insert(_ value: String, into normalized: inout Set<String>, _ compact: inout Set<String>) {
        let normalizedValue = normalize(value)
        if !normalizedValue.isEmpty {
            normalized.insert(normalizedValue)
        }

        let compactValue = normalizeCompact(value)
        if !compactValue.isEmpty {
            compact.insert(compactValue)
        }
    }

    private static func containsCJK(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
        }
    }

    private static func pinyin(for value: String) -> String? {
        let mutable = NSMutableString(string: value)
        guard CFStringTransform(mutable, nil, kCFStringTransformToLatin, false),
              CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false) else {
            return nil
        }
        return String(mutable)
    }
}
```

**Step 2: Move normalization call sites**

In `AppSearchManager.swift`:

- Replace `Self.normalize(...)` with `AppSearchKeyBuilder.normalize(...)`.
- Replace `Self.normalizeCompact(...)` with `AppSearchKeyBuilder.normalizeCompact(...)`.
- Remove the private static `normalize` and `normalizeCompact` methods from `AppSearchManager`.

**Step 3: Build**

Run:

```bash
swift build
```

Expected: build succeeds.

**Step 4: Run tests**

Run:

```bash
swift test
```

Expected: tests pass if test target import works.

---

### Task 3: Persist Pinyin Keys in App Index Cache

**Files:**
- Modify: `Sources/xxMac/Managers/AppSearchManager.swift`

**Step 1: Extend `CachedEntry`**

Change:

```swift
private struct CachedEntry: Codable {
    let id: String
    let title: String
    let subtitle: String
    let path: String
    let nameKeys: [String]
}
```

to:

```swift
private struct CachedEntry: Codable {
    let id: String
    let title: String
    let subtitle: String
    let path: String
    let nameKeys: [String]
    let nameCompactKeys: [String]?
}
```

Keep `nameCompactKeys` optional so older caches decode successfully.

**Step 2: Generate keys from all app names during indexing**

In `makeEntry(fromPath:fileManager:)`, after collecting `nameKeys`, call:

```swift
let searchKeys = AppSearchKeyBuilder.keys(for: Array(nameKeys))
```

Use:

```swift
nameSearchKeys: searchKeys.normalized,
nameCompactSearchKeys: searchKeys.compact,
pathSearchKey: AppSearchKeyBuilder.normalize(path),
pathCompactSearchKey: AppSearchKeyBuilder.normalizeCompact(path)
```

**Step 3: Restore full keys from cache**

In `makeEntry(fromCached:)`, use cached keys directly when present:

```swift
let normalizedKeys = Set(entry.nameKeys + [entry.title])
let generatedKeys = AppSearchKeyBuilder.keys(for: Array(normalizedKeys))
let compactKeys = entry.nameCompactKeys ?? generatedKeys.compact
```

Then assign:

```swift
nameSearchKeys: Array(normalizedKeys).map(AppSearchKeyBuilder.normalize),
nameCompactSearchKeys: compactKeys,
pathSearchKey: AppSearchKeyBuilder.normalize(entry.path),
pathCompactSearchKey: AppSearchKeyBuilder.normalizeCompact(entry.path)
```

This preserves old caches and gives new caches full pinyin compact keys.

**Step 4: Save all generated keys**

In `saveCachedIndex(_:)`, store both key arrays:

```swift
CachedEntry(
    id: $0.id,
    title: $0.title,
    subtitle: $0.subtitle,
    path: $0.path,
    nameKeys: $0.nameSearchKeys,
    nameCompactKeys: $0.nameCompactSearchKeys
)
```

**Step 5: Build**

Run:

```bash
swift build
```

Expected: build succeeds.

---

### Task 4: Improve Search Ranking for Pinyin Initials

**Files:**
- Modify: `Sources/xxMac/Managers/AppSearchManager.swift`

**Step 1: Confirm current matching behavior**

Current search checks:

- compact key prefix: rank `0`
- compact key contains: rank `1`
- normalized key prefix: rank `0`
- normalized key contains: rank `1`

This is enough for:

- `wx` -> `微信` from initials compact key `wx`
- `weixin` -> `微信` from full pinyin compact key `weixin`
- `wei xin` -> `微信` from full pinyin normalized key `wei xin`
- `微信` -> `微信` from original Chinese normalized key

**Step 2: Do not add more ranking complexity**

No code change needed unless manual testing shows poor ordering. Keep this task as a review checkpoint.

**Step 3: Manual verification**

After rebuilding the app index from “通用 > 配置 > 索引应用”, verify in launcher:

- Search `微信` finds WeChat/微信 if installed.
- Search `weixin` finds 微信.
- Search `wx` finds 微信.
- Search `txhy` finds 腾讯会议 if installed.
- Search pure English app names such as `code` still finds Visual Studio Code.

---

### Task 5: Update Docs

**Files:**
- Modify: `README.md`
- Modify: `README_en.md`

**Step 1: Update Chinese README**

In `README.md` under “配置与数据”, extend the app search bullet:

```markdown
- 应用搜索默认扫描 `/Applications`、`/System/Applications`、`/System/Library/CoreServices`，也支持在设置里添加自定义搜索路径；应用索引会缓存到 `UserDefaults`，新版本启动后可复用旧索引，也可在“通用 > 配置”里手动点击“索引应用”重建。中文应用名会同时写入拼音和拼音首字母索引，支持中文、全拼和首字母搜索。
```

**Step 2: Update English README**

In `README_en.md` under “Configuration and Data”, extend the app search bullet:

```markdown
- App search scans `/Applications`, `/System/Applications`, and `/System/Library/CoreServices` by default. Custom search paths can also be added in settings; the app index is cached in `UserDefaults`, reused after installing a new xxMac build, and can be rebuilt from General > Configuration with “Index Applications”. Chinese app names are indexed with their original text, full pinyin, and pinyin initials.
```

**Step 3: Build**

Run:

```bash
swift build
```

Expected: build succeeds.

---

### Task 6: Final Verification

**Files:**
- No code changes.

**Step 1: Run automated checks**

Run:

```bash
swift build
swift test
```

Expected:

- `swift build` succeeds.
- `swift test` succeeds if the test target is supported. If SwiftPM cannot test the executable target, record that limitation and rely on build plus manual launcher verification.

**Step 2: Manual app verification**

Run:

```bash
swift run xxMac
```

Then:

1. Open Settings.
2. Go to “通用 > 配置”.
3. Click “索引应用”.
4. Wait until the indexed count returns.
5. Open launcher.
6. Search installed Chinese apps using Chinese, full pinyin, and initials.
7. Search an English app name to confirm existing behavior still works.

**Step 3: Check git diff**

Run:

```bash
git diff -- Package.swift Sources/xxMac/Managers/AppSearchKeyBuilder.swift Sources/xxMac/Managers/AppSearchManager.swift Tests/xxMacTests/AppSearchKeyBuilderTests.swift README.md README_en.md
```

Expected: diff only contains pinyin search-key generation, cache persistence, docs, and tests.

