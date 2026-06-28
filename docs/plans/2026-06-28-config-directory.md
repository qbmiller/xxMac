# Config Directory Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 给 xxMac 增加一个用户可配置的配置目录，让主要配置、轻量缓存、剪贴板数据库和图片缓存从该目录读取并写入；用户更换目录后自动把当前数据迁移到新目录，并删除旧目录中的 xxMac 数据。

**Architecture:** 新增一个启动期最先初始化的 `ConfigDirectoryManager`，负责解析当前配置目录、校验权限、迁移旧数据和切换目录。新增 `FileBackedPreferences` 作为文件驱动的配置键值存储，替代业务代码直接读写 `UserDefaults`；`UserDefaults` 仅保留配置目录路径这个 bootstrap 指针。剪贴板存储目录改为来自 `ConfigDirectoryManager`，切换目录时暂停剪贴板监听、关闭 SQLite、迁移文件、重开数据库。

**Tech Stack:** SwiftUI, AppKit `NSOpenPanel`, Foundation `FileManager`, SQLite3, XCTest.

---

## 设计约定

1. 默认配置目录仍是 `~/Library/Application Support/xxMac`，这样兼容当前剪贴板文件位置。
2. 用户选择目录后，配置目录直接使用用户选中的文件夹，不再额外嵌套一层 `xxMac`。
3. `UserDefaults` 只允许保留一个 bootstrap key：`ConfigDirectoryPath`。其他可配置项和缓存迁移到配置目录。
4. 配置文件布局：

```text
<ConfigDirectory>/
├── manifest.json
├── preferences.json
├── app-search-index.json
├── clipboard.db
├── clipboard.db-wal
├── clipboard.db-shm
└── clipboard_images/
```

5. `preferences.json` 保存现有 `UserDefaults` 中的可配置项，继续使用原 key，降低迁移风险。
6. `app-search-index.json` 保存当前 `AppSearchIndexCacheV1` 的内容。它是缓存，但仍随配置目录移动，便于新机器复用索引。
7. 剪贴板历史、SQLite 数据库和图片缓存跟随配置目录移动。导出配置仍然只导出设置，不导出剪贴板历史、SQLite 数据库或图片缓存。
8. 不迁移 macOS TCC 权限、辅助功能权限、自动化权限、临时脚本文件和系统日志。
9. 当前项目没有启用 App Sandbox，目录权限以 POSIX 读写权限和 macOS 隐私限制为准。实现仍要集中做权限探测，方便未来启用 sandbox 时扩展 security-scoped bookmark。

## 成功标准

1. 首次启动后，旧 `UserDefaults` 配置自动写入默认配置目录的 `preferences.json`。
2. App 后续读取配置时，以配置目录文件为源。
3. 用户在“通用 > 配置”里可以选择配置目录、在 Finder 中显示、恢复默认目录。
4. 选择新目录后，当前配置、应用索引缓存、剪贴板数据库、图片缓存迁移到新目录，旧目录中的 xxMac 数据会被删除。
5. 目标目录不可读、不可写、是文件、位于明显不合适的系统目录时，UI 显示明确错误且不切换。
6. 迁移失败时保持旧目录继续可用，不写入新的 bootstrap 路径。
7. `swift test` 通过。
8. README 和 README_en 更新配置目录说明。

---

## Task 1: 增加配置目录管理器

**Files:**
- Create: `Sources/xxMac/Managers/ConfigDirectoryManager.swift`
- Test: `Tests/xxMacTests/ConfigDirectoryManagerTests.swift`

**Step 1: 写失败测试**

覆盖：
- 默认目录为 `~/Library/Application Support/xxMac`
- 用户目录路径保存后可重新解析
- 目标是普通文件时校验失败
- 目标目录可写探测失败时校验失败

测试建议让 `ConfigDirectoryManager` 支持依赖注入，避免真实写入用户目录：

```swift
final class ConfigDirectoryManagerTests: XCTestCase {
    func testDefaultDirectoryUsesApplicationSupportXXMac() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let manager = ConfigDirectoryManager(
            defaults: defaults,
            fileManager: .default,
            applicationSupportURL: URL(fileURLWithPath: "/tmp/AppSupport", isDirectory: true)
        )

        XCTAssertEqual(
            manager.currentDirectory.path,
            "/tmp/AppSupport/xxMac"
        )
    }

    func testRejectsFileAsConfigDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("not-a-directory")
        try Data("x".utf8).write(to: file)

        let result = ConfigDirectoryManager.validateDirectory(file, fileManager: .default)

        XCTAssertFalse(result.isValid)
    }
}
```

**Step 2: 运行测试确认失败**

Run: `swift test --filter ConfigDirectoryManagerTests`

Expected: 编译失败，因为类型还不存在。

**Step 3: 实现最小管理器**

新增：
- `static let directoryPathKey = "ConfigDirectoryPath"`
- `currentDirectory: URL`
- `defaultDirectory: URL`
- `manifestURL`
- `preferencesURL`
- `appSearchIndexURL`
- `clipboardDatabaseURL`
- `clipboardImagesDirectoryURL`
- `validateDirectory(_:) -> ConfigDirectoryValidation`
- `setDirectory(_:) throws`
- `resetToDefault() throws`

权限校验规则：
- 如果路径不存在，尝试创建目录。
- 如果路径存在但不是目录，失败。
- 拒绝 `/`、`/System`、`/Library`、`/Applications`、App bundle 内部路径。
- 用 `.xxmac-write-test-<uuid>` 做写入、读取、删除探测。
- 用 `URL.standardizedFileURL` 保存规范路径。

**Step 4: 跑测试确认通过**

Run: `swift test --filter ConfigDirectoryManagerTests`

Expected: PASS.

**Step 5: 提交**

```bash
git add Sources/xxMac/Managers/ConfigDirectoryManager.swift Tests/xxMacTests/ConfigDirectoryManagerTests.swift
git commit -m "feat: add config directory manager"
```

---

## Task 2: 增加文件驱动配置存储

**Files:**
- Create: `Sources/xxMac/Managers/FileBackedPreferences.swift`
- Test: `Tests/xxMacTests/FileBackedPreferencesTests.swift`

**Step 1: 写失败测试**

覆盖现有配置值类型：
- `String`
- `Bool`
- `Int`
- `Double`
- `Data`
- `[String]`
- 删除 key
- 重载后能读回
- 写入使用原子替换，损坏 JSON 时不覆盖原文件

示例：

```swift
func testPersistsDataAndStringArray() throws {
    let url = tempRoot.appendingPathComponent("preferences.json")
    let store = FileBackedPreferences(fileURL: url)

    store.set(Data([1, 2, 3]), forKey: "HotKeyConfigurations")
    store.set(["/Applications"], forKey: "AppSearchPaths")
    try store.flush()

    let reloaded = FileBackedPreferences(fileURL: url)
    XCTAssertEqual(reloaded.data(forKey: "HotKeyConfigurations"), Data([1, 2, 3]))
    XCTAssertEqual(reloaded.stringArray(forKey: "AppSearchPaths"), ["/Applications"])
}
```

**Step 2: 运行测试确认失败**

Run: `swift test --filter FileBackedPreferencesTests`

Expected: 编译失败，因为类型还不存在。

**Step 3: 实现 `FileBackedPreferences`**

实现一个小型键值存储：

```swift
enum PreferenceValue: Codable, Equatable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case data(Data)
    case stringArray([String])
}
```

公开 API 尽量贴近当前 `UserDefaults` 使用：
- `string(forKey:)`
- `stringArray(forKey:)`
- `data(forKey:)`
- `boolObject(forKey:) -> Bool?`
- `intObject(forKey:) -> Int?`
- `doubleObject(forKey:) -> Double?`
- `set(_:forKey:)`
- `removeObject(forKey:)`
- `flush() throws`
- `reload() throws`

写文件使用：
- 写到同目录临时文件
- `FileManager.replaceItemAt`
- 失败时保留旧文件

**Step 4: 跑测试确认通过**

Run: `swift test --filter FileBackedPreferencesTests`

Expected: PASS.

**Step 5: 提交**

```bash
git add Sources/xxMac/Managers/FileBackedPreferences.swift Tests/xxMacTests/FileBackedPreferencesTests.swift
git commit -m "feat: add file backed preferences"
```

---

## Task 3: 迁移旧 UserDefaults 到配置目录

**Files:**
- Modify: `Sources/xxMac/Managers/ConfigDirectoryManager.swift`
- Modify: `Sources/xxMac/Managers/FileBackedPreferences.swift`
- Create: `Sources/xxMac/Managers/PreferencesStore.swift`
- Test: `Tests/xxMacTests/PreferencesStoreMigrationTests.swift`

**Step 1: 写失败测试**

给旧 `UserDefaults` 写入已知 key：
- `AppLanguage`
- `AppSearchPaths`
- `HotKeyConfigurations`
- `ClearedHotKeyActions`
- `LauncherAppearanceBackgroundHex`
- `LauncherAppearanceOpacity`
- `LauncherAppearanceSizeScale`
- `LauncherAppearanceWidth`
- `LauncherAppearanceHeight`
- `AppLauncherShortcuts`
- `QuickShortcutItems`
- `ClipboardSettings`
- `ShortcutDetectiveEnabled`
- `SnippetSettings`
- `SnippetCollections`
- `SnippetEntries`
- `CalendarShowLunar`
- `CalendarShowWeekNumbers`
- `CalendarFirstWeekday`
- `CalendarMenuBarIconStyle`
- `LockAIStatusText`
- `AppSearchIndexCacheV1`

断言初始化后：
- `preferences.json` 包含设置 key。
- `app-search-index.json` 包含应用索引缓存。
- 再次初始化不会用旧 `UserDefaults` 覆盖已有文件。

**Step 2: 运行测试确认失败**

Run: `swift test --filter PreferencesStoreMigrationTests`

Expected: FAIL.

**Step 3: 实现迁移**

新增 `PreferencesStore.shared`，包装 `FileBackedPreferences`。

初始化流程：
1. `ConfigDirectoryManager` 解析配置目录。
2. 创建目录和 `manifest.json`。
3. 如果 `preferences.json` 不存在，从旧 `UserDefaults` 复制已知配置 key。
4. 如果 `app-search-index.json` 不存在，从旧 `UserDefaults` 的 `AppSearchIndexCacheV1` 复制。
5. 后续读写只走 `PreferencesStore` 和 `app-search-index.json`。

保留旧 `UserDefaults` 不删除，作为一次性兼容备份；不要继续写入除 `ConfigDirectoryPath` 外的 key。

**Step 4: 跑测试确认通过**

Run: `swift test --filter PreferencesStoreMigrationTests`

Expected: PASS.

**Step 5: 提交**

```bash
git add Sources/xxMac/Managers/ConfigDirectoryManager.swift Sources/xxMac/Managers/FileBackedPreferences.swift Sources/xxMac/Managers/PreferencesStore.swift Tests/xxMacTests/PreferencesStoreMigrationTests.swift
git commit -m "feat: migrate preferences into config directory"
```

---

## Task 4: 将现有配置读写切到 PreferencesStore

**Files:**
- Modify: `Sources/xxMac/Managers/LocalizationManager.swift`
- Modify: `Sources/xxMac/Managers/AppSearchManager.swift`
- Modify: `Sources/xxMac/Managers/AppLauncherManager.swift`
- Modify: `Sources/xxMac/Managers/HotkeyManager.swift`
- Modify: `Sources/xxMac/Managers/LauncherAppearanceManager.swift`
- Modify: `Sources/xxMac/Managers/QuickShortcutManager.swift`
- Modify: `Sources/xxMac/Managers/ClipboardManager.swift`
- Modify: `Sources/xxMac/Managers/SnippetManager.swift`
- Modify: `Sources/xxMac/Managers/ShortcutDetectiveManager.swift`
- Modify: `Sources/xxMac/Managers/LockAIManager.swift`
- Modify: `Sources/xxMac/Views/CalendarFeatureView.swift`
- Modify: `Sources/xxMac/Views/CommonSettingsView.swift`

**Step 1: 写失败测试**

优先给纯逻辑 manager 加测试：
- `AppSearchManager` 能从配置目录读 `AppSearchPaths`。
- `QuickShortcutManager` 能从配置目录读写 `QuickShortcutItems`。
- `ClipboardManager` 能从配置目录读写 `ClipboardSettings`。

如果单例难以测试，先给新 store 做覆盖，再对 manager 做最少初始化测试，避免大重构。

**Step 2: 替换直接 UserDefaults 调用**

替换模式：

```swift
// Before
UserDefaults.standard.set(value, forKey: "QuickShortcutItems")
UserDefaults.standard.data(forKey: "QuickShortcutItems")

// After
PreferencesStore.shared.set(value, forKey: "QuickShortcutItems")
PreferencesStore.shared.data(forKey: "QuickShortcutItems")
```

`CommonSettingsView.collectConfigurations()` 也改成从 `PreferencesStore.shared` 读取。导入配置时写回 `PreferencesStore.shared`，并调用相关 manager 刷新。

`AppSearchManager` 特殊处理：
- `AppSearchPaths` 走 `PreferencesStore`。
- `AppSearchIndexCacheV1` 不再写入 preferences，改写 `ConfigDirectoryManager.shared.appSearchIndexURL`。

**Step 3: 启动顺序调整**

修改 `Sources/xxMac/xxMac.swift`：
- 在 `AppDelegate.applicationDidFinishLaunching` 最前面初始化 `ConfigDirectoryManager.shared` 和 `PreferencesStore.shared`。
- 再初始化 HotKey、AppLauncher、Clipboard、Snippet、LockAI 等 manager。

**Step 4: 跑测试**

Run: `swift test`

Expected: PASS.

**Step 5: 提交**

```bash
git add Sources/xxMac/Managers Sources/xxMac/Views/CommonSettingsView.swift Sources/xxMac/Views/CalendarFeatureView.swift Sources/xxMac/xxMac.swift Tests/xxMacTests
git commit -m "refactor: read app settings from config directory"
```

---

## Task 5: 让剪贴板数据库和图片缓存跟随配置目录

**Files:**
- Modify: `Sources/xxMac/Managers/ClipboardStorageManager.swift`
- Modify: `Sources/xxMac/Managers/DatabaseManager.swift`
- Modify: `Sources/xxMac/Managers/ClipboardManager.swift`
- Test: `Tests/xxMacTests/ClipboardStorageDirectoryTests.swift`

**Step 1: 写失败测试**

覆盖：
- 默认 DB 路径来自 `ConfigDirectoryManager.clipboardDatabaseURL`。
- 图片目录来自 `ConfigDirectoryManager.clipboardImagesDirectoryURL`。
- 切换目录后新图片写入新目录。
- 旧 `~/Library/Application Support/xxMac/clipboard.db` 在默认目录下不需要移动。

**Step 2: 运行测试确认失败**

Run: `swift test --filter ClipboardStorageDirectoryTests`

Expected: FAIL.

**Step 3: 改造 DatabaseManager**

新增：
- `func checkpointAndClose()`
- `func reopen(path:)`

关闭前执行：

```sql
PRAGMA wal_checkpoint(FULL);
```

然后 `sqlite3_close`。

**Step 4: 改造 ClipboardStorageManager**

把 `storageDir`、`imagesDir`、`dbManager` 从 `let` 改为可重载状态。

新增：
- `func reloadStorageDirectory()`
- `func prepareForDirectoryMigration()`
- `func resumeAfterDirectoryMigration()`

`reloadStorageDirectory()` 读取 `ConfigDirectoryManager.shared` 的当前路径，创建图片目录，打开对应 `clipboard.db`。

**Step 5: 改造 ClipboardManager**

新增：
- `pauseMonitoringForStorageMigration()`
- `resumeMonitoringAfterStorageMigration()`

迁移时暂停定时器或 pasteboard 轮询，避免复制 SQLite 时继续写入。

**Step 6: 跑测试**

Run: `swift test --filter ClipboardStorageDirectoryTests`

Expected: PASS.

**Step 7: 提交**

```bash
git add Sources/xxMac/Managers/ClipboardStorageManager.swift Sources/xxMac/Managers/DatabaseManager.swift Sources/xxMac/Managers/ClipboardManager.swift Tests/xxMacTests/ClipboardStorageDirectoryTests.swift
git commit -m "feat: store clipboard data in config directory"
```

---

## Task 6: 实现目录切换和自动迁移

**Files:**
- Modify: `Sources/xxMac/Managers/ConfigDirectoryManager.swift`
- Modify: `Sources/xxMac/Managers/PreferencesStore.swift`
- Modify: `Sources/xxMac/Managers/AppSearchManager.swift`
- Modify: `Sources/xxMac/Managers/ClipboardStorageManager.swift`
- Test: `Tests/xxMacTests/ConfigDirectoryMigrationTests.swift`

**Step 1: 写失败测试**

创建旧目录：

```text
old/
├── manifest.json
├── preferences.json
├── app-search-index.json
├── clipboard.db
└── clipboard_images/a.png
```

切换到新目录后断言：
- 所有文件复制到新目录。
- `ConfigDirectoryPath` 指向新目录。
- `PreferencesStore` 从新 `preferences.json` 读取。
- 旧目录仍保留，作为回滚备份。

再覆盖失败场景：
- 新目录不可写时，不修改 `ConfigDirectoryPath`。
- 复制中途失败时，不修改 `ConfigDirectoryPath`。

**Step 2: 运行测试确认失败**

Run: `swift test --filter ConfigDirectoryMigrationTests`

Expected: FAIL.

**Step 3: 实现迁移流程**

在 `ConfigDirectoryManager.changeDirectory(to:)` 中：
1. 校验目标目录权限。
2. 如果目标目录已有 `manifest.json` 或 xxMac 文件，返回 `.requiresConfirmation`，UI 负责二次确认。
3. `PreferencesStore.shared.flush()`
4. `AppSearchManager.shared.flushIndexCacheIfNeeded()`
5. `ClipboardManager.shared.pauseMonitoringForStorageMigration()`
6. `ClipboardStorageManager.shared.prepareForDirectoryMigration()`
7. 复制文件到目标目录：
   - `manifest.json`
   - `preferences.json`
   - `app-search-index.json`
   - `clipboard.db`
   - `clipboard.db-wal`
   - `clipboard.db-shm`
   - `clipboard_images/`
8. 写入 `UserDefaults.standard.set(target.path, forKey: "ConfigDirectoryPath")`
9. 更新 `currentDirectory`
10. `PreferencesStore.shared.reload(from:)`
11. `ClipboardStorageManager.shared.reloadStorageDirectory()`
12. `ClipboardManager.shared.resumeMonitoringAfterStorageMigration()`
13. 发通知 `ConfigDirectoryDidChange`

复制策略：
- 不删除旧目录。
- 目标已有文件时，确认后用当前配置覆盖目标 xxMac 文件。
- 复制 SQLite 前已做 WAL checkpoint，通常不会依赖 `-wal`；仍复制存在的 `-wal` 和 `-shm` 以防边界情况。

**Step 4: 跑测试**

Run: `swift test --filter ConfigDirectoryMigrationTests`

Expected: PASS.

**Step 5: 提交**

```bash
git add Sources/xxMac/Managers Tests/xxMacTests/ConfigDirectoryMigrationTests.swift
git commit -m "feat: migrate data when config directory changes"
```

---

## Task 7: 增加通用设置 UI

**Files:**
- Modify: `Sources/xxMac/Views/CommonSettingsView.swift`
- Modify: `Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Resources/zh-Hant.lproj/Localizable.strings`
- Modify: `Resources/en.lproj/Localizable.strings`

**Step 1: 添加 UI 文案**

新增 key：
- `common.config_directory`
- `common.config_directory_desc`
- `common.current_config_directory`
- `common.set_config_directory`
- `common.reveal_config_directory`
- `common.reset_config_directory`
- `common.config_directory_permission_error`
- `common.config_directory_migration_failed`
- `common.config_directory_contains_existing_data_title`
- `common.config_directory_contains_existing_data_message`
- `common.config_directory_replace`
- `common.cancel`

**Step 2: 在 CommonSettingsView 增加区域**

位置：放在 “App Index Section” 和 “Export Section” 之间。

UI 行为：
- 显示当前目录路径，长路径用 `.lineLimit(2)`。
- “设置配置目录...” 打开 `NSOpenPanel`：
  - `canChooseDirectories = true`
  - `canChooseFiles = false`
  - `canCreateDirectories = true`
  - `allowsMultipleSelection = false`
- “在 Finder 中显示” 调用 `NSWorkspace.shared.activateFileViewerSelecting([url])`。
- “恢复默认目录” 调用 `ConfigDirectoryManager.shared.resetToDefault()`，同样走迁移流程。
- 失败时在本区域显示错误。

**Step 3: 目标已有数据时弹确认框**

如果 `changeDirectory(to:)` 返回需要确认：
- 标题：目标目录已有 xxMac 数据
- 内容：继续会用当前这台 Mac 的配置覆盖目标目录中的 xxMac 配置文件。
- 按钮：覆盖并同步、取消

**Step 4: 手工验证 UI**

Run: `swift run xxMac`

手工检查：
- 设置窗口可打开。
- 当前配置目录显示正确。
- Reveal in Finder 可用。
- 选择 `/tmp/xxMac-test-config` 后配置文件自动出现。
- 选择不可写目录时显示错误且路径不变。

**Step 5: 提交**

```bash
git add Sources/xxMac/Views/CommonSettingsView.swift Resources/zh-Hans.lproj/Localizable.strings Resources/zh-Hant.lproj/Localizable.strings Resources/en.lproj/Localizable.strings
git commit -m "feat: add config directory settings UI"
```

---

## Task 8: 更新导入导出和文档

**Files:**
- Modify: `Sources/xxMac/Views/CommonSettingsView.swift`
- Modify: `README.md`
- Modify: `README_en.md`
- Modify: `docs/ARCHITECTURE.md`

**Step 1: 导入导出保持边界**

确认 `CommonSettingsView.AppConfiguration`：
- 导出配置仍只导出 `PreferencesStore` 中的设置。
- 不导出 `clipboard.db`、`clipboard.db-wal`、`clipboard.db-shm`、`clipboard_images/`。
- 不导出 `app-search-index.json`，因为这是缓存。
- 不导出 `ConfigDirectoryPath`，避免把一台 Mac 的本地路径导入到另一台 Mac。

**Step 2: README 中文更新**

在“配置与数据”中写清：
- 默认配置目录是 `~/Library/Application Support/xxMac`。
- 可在“通用 > 配置”中修改配置目录。
- 修改后会自动同步当前配置、应用索引缓存、剪贴板 SQLite 数据库和图片缓存到新目录。
- 适合选择本地目录或同步盘目录，但同步服务必须保证文件本地可用。
- 不建议选择系统目录、App 包内目录、移动磁盘临时路径。
- 导出配置不包含剪贴板历史和图片缓存。

**Step 3: README 英文同步**

同步 `README_en.md`。

**Step 4: 架构文档更新**

更新 `docs/ARCHITECTURE.md`：
- 增加 `ConfigDirectoryManager`
- 增加 `FileBackedPreferences`
- 更新持久化数据边界
- 更新启动顺序

**Step 5: 提交**

```bash
git add Sources/xxMac/Views/CommonSettingsView.swift README.md README_en.md docs/ARCHITECTURE.md
git commit -m "docs: document configurable config directory"
```

---

## Task 9: 端到端验证和回归检查

**Files:**
- No source changes expected

**Step 1: 跑完整测试**

Run: `swift test`

Expected: PASS.

**Step 2: 跑构建**

Run: `swift build`

Expected: PASS.

**Step 3: 手工迁移验证**

Run: `swift run xxMac`

验证步骤：
1. 启动 App。
2. 打开设置。
3. 修改启动器颜色或语言。
4. 确认默认目录 `~/Library/Application Support/xxMac/preferences.json` 更新。
5. 打开剪贴板历史，复制一段文本和一张图片。
6. 确认默认目录出现 `clipboard.db` 和 `clipboard_images/`。
7. 在“通用 > 配置”选择 `/tmp/xxMac-config-test`。
8. 确认 `/tmp/xxMac-config-test/preferences.json`、`clipboard.db`、`clipboard_images/` 存在。
9. 退出并重新启动。
10. 确认设置仍从 `/tmp/xxMac-config-test` 读取。
11. 恢复默认目录，确认数据同步回默认目录。

**Step 4: 权限验证**

手工检查：
- 选择一个普通文件，失败。
- 选择 `/System`，失败。
- 选择只读目录，失败。
- 选择 iCloud Drive 或 Dropbox 本地可用目录，成功。

**Step 5: 检查 diff**

Run: `git diff --stat`

Expected: 只包含配置目录、配置存储、剪贴板目录、设置 UI、文档和测试相关改动。

---

## 风险和处理

1. **SQLite 复制时损坏**
   - 处理：迁移前暂停剪贴板监听，执行 WAL checkpoint，关闭数据库后复制。

2. **同步盘冲突**
   - 处理：不做双向合并。选择新目录时以当前机器配置覆盖目标目录，并弹窗确认。

3. **用户选择不可长期可用目录**
   - 处理：UI 文案提示目录必须本地可用；启动时如果目录不可访问，显示错误并回退默认目录前先保留旧路径，不静默覆盖。

4. **旧 UserDefaults 与新文件存储不一致**
   - 处理：迁移后以 `preferences.json` 为准。旧 UserDefaults 只作为首次迁移来源。

5. **单例 manager 难测**
   - 处理：新建核心类型支持依赖注入；单例只做薄包装。

6. **用户以为导出配置会导出剪贴板历史**
   - 处理：README 和 UI 文案说明，导出配置只导出设置；完整迁移使用配置目录切换。

---

## 推荐实施顺序

先完成 Task 1 到 Task 3，确保目录和文件配置存储稳定；再做 Task 4 替换读取源；随后做剪贴板迁移和 UI。不要先做 UI，否则容易出现按钮存在但底层迁移不完整的问题。
