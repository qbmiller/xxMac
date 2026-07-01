# Clipboard Large Item Performance Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 打开剪贴板历史和上下选择时，即使历史里有超大文本或大图片，也不阻塞列表滚动和选择。

**Architecture:** 保留现有 SQLite + 图片文件缓存架构，SQLite 继续存历史记录、排序、大小和可搜索数据；列表查询改成只返回轻量摘要，详情和回贴再按需读取完整内容。图片保留原图文件，超过可配置阈值时新增缩略图缓存，列表标题和预览不再同步解码大图原图。

**Tech Stack:** SwiftUI, AppKit `NSPasteboard` / `NSImage`, SQLite3, Foundation file cache, XCTest.

---

## 现状结论

当前剪贴板不是“一条一个文件”存储：

- 文本：存进配置目录下的 `clipboard.db`，表是 `clipboard_items`，`content` 字段保存完整文本。
- 图片：原图保存到配置目录下的 `clipboard_images/<uuid>.png`，SQLite 的 `content` 字段保存图片文件名。
- 排序：SQLite 用 `timestamp` 排序，`markItemUsed` 会更新 timestamp，让用过的项回到顶部。
- 查询：`ClipboardStorageManager.getAllItems(limit: 100)` 读 SQLite 最近 100 条；但当前搜索没有用 `DatabaseManager.search` 的 FTS，而是在 Swift 层取最近 100 条后遍历过滤。
- UI：列表 `SearchItem` 当前把完整文本塞进 `clipboardPreview: .text(item.content)`；右侧详情直接 `Text(text)` 渲染完整文本。图片标题和搜索会调用 `NSImage(contentsOf:)` 解码图片拿尺寸；右侧预览也在 SwiftUI `body` 里同步 `NSImage(contentsOf:)` 读原图。

卡顿的主要触发点：

- 大文本进入列表模型时被完整带到主线程，选择后右侧 `Text` 渲染完整内容。
- 图片上下选择时，`ClipboardImagePreview.body` 同步读原图。
- 生成图片标题时，`imageDisplayTitle` 反复用 `NSImage(contentsOf:)` 解码图片拿尺寸。
- 搜索路径在 Swift 层遍历并对图片调用 `imageDisplayTitle`，容易额外触发图片解码。

## 推荐方案

不要把剪贴板改成“一条一个文件”作为主存储。原因：

- SQLite 已经适合做排序、去重、上限清理和搜索索引。
- 一条一个文件会让排序、搜索、清理、迁移、并发一致性都变复杂。
- 真正的问题不是 SQLite 本身，而是列表模型加载了完整内容、UI 同步解码大图。

建议采用“SQLite 元数据 + 大内容按需加载 + 缩略图文件缓存”：

- 文本仍可先保存在 SQLite，但列表查询只返回 `snippet`，例如前 2 KB 或前 300 字符。
- 大文本详情只显示截断预览，例如最多 20 KB，并提示“仅显示前一部分，回车仍粘贴完整内容”。
- 回贴时从完整 `ClipboardItem.content` 或按 id 查询完整内容，保证粘贴不丢数据。
- 图片超过可配置阈值时生成缩略图，默认阈值 5 MB，例如最长边 512 px，放到 `clipboard_thumbnails/`。
- SQLite 增加图片元数据字段或独立表，保存 `width`、`height`、`thumbnail_filename`，标题不再读原图。
- 右侧图片预览默认加载缩略图；需要完整预览时再异步加载原图，或保持缩略图即可。
- 搜索使用 SQLite FTS 查询文本；图片搜索只查固定关键词和图片元数据，不在搜索时读文件。

## Task 1: 给数据库增加轻量列表查询

**Files:**
- Modify: `Sources/xxMac/Managers/DatabaseManager.swift`
- Modify: `Sources/xxMac/Managers/ClipboardStorageManager.swift`
- Test: `Tests/xxMacTests/ClipboardStorageDirectoryTests.swift` 或新增 `Tests/xxMacTests/ClipboardDatabaseSummaryTests.swift`

**Step 1: 新增轻量模型**

在 `Sources/xxMac/Models/ClipboardModels.swift` 添加：

```swift
struct ClipboardListItem: Identifiable, Equatable {
    let id: UUID
    let type: ClipboardContentType
    let previewContent: String
    let fullContentLength: Int
    let timestamp: Date
    let size: Int
    let imageFilename: String?
    let imageWidth: Int?
    let imageHeight: Int?
    let thumbnailFilename: String?
}
```

**Step 2: 写测试覆盖大文本列表查询不返回完整内容**

新增测试：

```swift
func testListItemsReturnTruncatedTextPreview() throws {
    let root = temporaryDirectory()
    let storage = ClipboardStorageManager(storageDirectory: root)
    let largeText = String(repeating: "abcdef", count: 10_000)

    storage.saveItem(type: .text, content: largeText, size: largeText.utf8.count)

    let items = storage.getListItems(limit: 10)
    XCTAssertEqual(items.count, 1)
    XCTAssertLessThan(items[0].previewContent.count, largeText.count)
    XCTAssertEqual(items[0].fullContentLength, largeText.count)
}
```

**Step 3: 实现数据库查询**

在 `DatabaseManager` 添加 `getListItems(limit:previewLimit:)`：

```sql
SELECT
  id,
  type,
  CASE
    WHEN type = 'text' THEN substr(content, 1, ?)
    ELSE content
  END AS preview_content,
  length(content) AS full_content_length,
  timestamp,
  size
FROM clipboard_items
ORDER BY timestamp DESC
LIMIT ?;
```

先不做 schema 迁移；图片元数据在后续任务加。

**Step 4: 暴露 Storage API**

在 `ClipboardStorageManager` 添加：

```swift
func getListItems(limit: Int = 100) -> [ClipboardListItem]
func getItem(id: UUID) -> ClipboardItem?
```

`getItem(id:)` 后续用于粘贴完整内容和详情按需加载。

**Step 5: 运行测试**

Run:

```bash
swift test --filter ClipboardDatabaseSummaryTests
```

Expected: PASS。

## Task 2: 列表模型不再携带完整文本

**Files:**
- Modify: `Sources/xxMac/Models/SearchItem.swift`
- Modify: `Sources/xxMac/Managers/ClipboardManager.swift`
- Test: `Tests/xxMacTests/ClipboardModelsTests.swift`

**Step 1: 调整预览类型**

把 `ClipboardPreviewData.text(String)` 改成携带 id 和预览内容：

```swift
case text(id: UUID, preview: String, fullLength: Int)
case image(filename: String, thumbnailFilename: String?, byteSize: Int)
```

如果不想大改调用点，也可以新增 case，保留旧 case 只给兼容测试用；实现时优先选改调用点，避免两套路径长期共存。

**Step 2: ClipboardManager 改用轻量列表**

`refreshHistory()` 和空 query 搜索改用 `storage.getListItems()`，生成 `SearchItem` 时：

- title 用 `previewContent.prefix(100)`。
- `clipboardPreview` 使用轻量 preview，不塞完整文本。
- action 闭包里通过 id 调 `storage.getItem(id:)` 再 paste。

**Step 3: 文本详情显示截断内容**

`ClipboardDetailPane` 中对 `.text(id, preview, fullLength)`：

- `Text(preview)` 只显示 preview。
- 如果 `fullLength > preview.count`，显示本地化提示：“内容较大，仅显示前一部分，回车将粘贴完整内容”。

**Step 4: 运行测试**

Run:

```bash
swift test --filter ClipboardModelsTests
```

Expected: PASS。

## Task 3: 搜索改用 SQLite FTS，避免 Swift 层遍历大内容

**Files:**
- Modify: `Sources/xxMac/Managers/DatabaseManager.swift`
- Modify: `Sources/xxMac/Managers/ClipboardStorageManager.swift`
- Modify: `Sources/xxMac/Managers/ClipboardManager.swift`
- Test: `Tests/xxMacTests/ClipboardDatabaseSummaryTests.swift`

**Step 1: 新增轻量搜索 API**

在 `DatabaseManager` 添加 `searchListItems(query:limit:previewLimit:)`，基于已有 `clipboard_fts`：

```sql
SELECT i.id, i.type, substr(i.content, 1, ?), length(i.content), i.timestamp, i.size
FROM clipboard_items i
JOIN clipboard_fts f ON i.id = f.id
WHERE f.content MATCH ?
ORDER BY rank
LIMIT ?;
```

**Step 2: 图片搜索不读原图**

空 query 继续返回最近项；非空 query：

- 文本走 FTS。
- query 是 `image` / `images` / `图片` / `照片` 时，额外取最近图片项。
- 不调用 `imageDisplayTitle(for:)` 来参与过滤。

**Step 3: 修正 `ClipboardManager.searchClipboard`**

把当前 `storage.getAllItems()` + Swift filter 改成 `storage.searchListItems(query:)`。

**Step 4: 运行测试**

Run:

```bash
swift test --filter ClipboardDatabaseSummaryTests
```

Expected: PASS。

## Task 4: 图片超过阈值时生成缩略图和尺寸元数据

**Files:**
- Modify: `Sources/xxMac/Managers/DatabaseManager.swift`
- Modify: `Sources/xxMac/Managers/ClipboardStorageManager.swift`
- Modify: `Sources/xxMac/Managers/ClipboardManager.swift`
- Modify: `Tests/xxMacTests/ClipboardStorageDirectoryTests.swift`

**Step 1: 扩展存储目录**

在 `ClipboardStorageManager` 添加：

```swift
private var thumbnailsDir: URL
var thumbnailsDirectory: URL { thumbnailsDir }
func getThumbnailPath(filename: String) -> URL
```

目录名建议：`clipboard_thumbnails`。

**Step 2: 数据库 schema 迁移**

给 `clipboard_items` 增加可空列：

```sql
ALTER TABLE clipboard_items ADD COLUMN image_width INTEGER;
ALTER TABLE clipboard_items ADD COLUMN image_height INTEGER;
ALTER TABLE clipboard_items ADD COLUMN thumbnail_filename TEXT;
```

SQLite 没有 `ADD COLUMN IF NOT EXISTS` 的老版本兼容问题，建议实现一个 `ensureColumnExists(table:column:definition:)`，通过 `PRAGMA table_info(clipboard_items)` 检查后再 `ALTER TABLE`。

**Step 3: 保存图片时生成缩略图**

在 `ClipboardManager.processPasteboardContent()` 保存原图后：

- 从 `NSBitmapImageRep` 读取像素宽高。
- 当图片大小超过 `thumbnailGenerationThresholdMB` 时，生成最长边 512 px 的 PNG 缩略图。
- 写入 `clipboard_thumbnails/<uuid>.png`。
- 调 `storage.saveImageItem(content:size:width:height:thumbnailFilename:)`。

**Step 4: 清理时删除缩略图**

`deleteItem(_:)` 删除图片原图时同步删除 `thumbnailFilename` 对应文件。

**Step 5: 测试目录和清理**

扩展 `ClipboardStorageDirectoryTests`：

```swift
XCTAssertEqual(storage.thumbnailsDirectory.path, root.appendingPathComponent("clipboard_thumbnails").path)
XCTAssertTrue(FileManager.default.fileExists(atPath: storage.thumbnailsDirectory.path))
```

Run:

```bash
swift test --filter ClipboardStorageDirectoryTests
```

Expected: PASS。

## Task 5: 图片标题和预览不再同步解码原图

**Files:**
- Modify: `Sources/xxMac/Managers/ClipboardManager.swift`
- Modify: `Sources/xxMac/Views/LauncherView.swift`
- Modify: `Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Resources/en.lproj/Localizable.strings`

**Step 1: 标题使用元数据**

移除列表路径中的 `imageDimensions(for:)` 调用。图片标题从 `ClipboardListItem.imageWidth/imageHeight/size` 生成：

```swift
"Image: \(width)x\(height) (\(formatSize(size)))"
```

没有尺寸时退回：

```swift
"Image: \(formatSize(size))"
```

**Step 2: 图片预览优先显示缩略图**

`ClipboardImagePreview` 改成接收 `thumbnailFilename` 和 `filename`：

- 默认加载缩略图。
- 如果没有缩略图，再显示“图片较大，按回车可粘贴”或异步加载原图。
- 不在 `body` 顶层同步 `NSImage(contentsOf:)` 读原图。

**Step 3: 可选异步加载原图**

如果需要右侧完整预览，使用 `@State private var image: NSImage?` + `.task(id:)` 后台加载，并限制只在当前选中项仍一致时赋值。

**Step 4: 手动验证**

准备三类内容：

- 1 MB 以下普通文本。
- 10 MB 以上大文本。
- 50 MB 以上图片。

验证：

- 打开剪贴板历史窗口小于 200 ms 内有响应。
- 按上下键连续选择 30 次不明显卡顿。
- 大文本详情只显示截断内容。
- 图片项显示尺寸和大小。
- 回车仍能粘贴完整文本或图片。

## Task 6: 文档和导出配置检查

**Files:**
- Modify: `README.md`
- Modify: `README_en.md`
- Inspect: `Sources/xxMac/Views/CommonSettingsView.swift`
- Inspect: `Sources/xxMac/Managers/PreferencesStore.swift`

**Step 1: 更新 README**

说明剪贴板历史：

- SQLite 存储历史索引和文本内容。
- 图片原图在 `clipboard_images/`。
- 图片缩略图在 `clipboard_thumbnails/`。
- 图片缩略图默认只在原图超过 5 MB 时生成，阈值支持在剪贴板设置里调整。
- 大文本和大图预览会截断或使用缩略图，回贴仍使用完整内容。

**Step 2: 检查导出配置**

确认“通用 > 导出配置/导入配置”仍只导出 `ClipboardSettings`，不导出：

- `clipboard.db`
- `clipboard.db-wal`
- `clipboard_images/`
- `clipboard_thumbnails/`

**Step 3: 全量验证**

Run:

```bash
swift test
```

Expected: PASS。

Run:

```bash
swift build
```

Expected: PASS。

## 验收标准

- 打开剪贴板历史不需要把完整大文本塞进 SwiftUI 列表模型。
- 上下选择图片项不会同步解码原图。
- 搜索文本不在 Swift 层遍历完整大文本。
- 大文本详情有截断预览，但粘贴完整内容。
- 图片列表标题不依赖实时读取图片文件。
- 图片原图、缩略图、SQLite 清理逻辑一致。
- README 中明确当前存储方案和大内容预览策略。
