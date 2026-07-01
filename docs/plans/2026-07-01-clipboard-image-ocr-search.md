# Clipboard Image OCR Search Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 给剪贴板图片增加本地 OCR，把识别出的文字保存为图片 metadata，并让剪贴板搜索可以搜到图片里的文字。

**Architecture:** 使用 Apple Vision 的 `VNRecognizeTextRequest` 做本机 OCR，不引入联网服务，不上传图片。图片入库后先保存原图和基础 metadata，再在后台队列执行 OCR，完成后把 `ocrText`、状态和更新时间写回 SQLite，同时更新 FTS 索引；列表查询继续保持轻量，不把 OCR 长文本塞进 UI 预览。

**Tech Stack:** SwiftUI, AppKit, Vision, SQLite3 FTS5, XCTest.

---

## 方案判断

有本地 OCR 方案，推荐使用 Apple Vision：

- `Vision.framework` 是系统框架，macOS 本地执行，不需要网络。
- `VNRecognizeTextRequest` 支持中英文等多语言识别，适合截图、文档图片、UI 图片。
- 可以在后台队列跑，避免复制图片或打开剪贴板历史时卡 UI。
- OCR 结果适合存 SQLite metadata，并写入现有 `clipboard_fts`，这样搜索逻辑仍然集中在数据库里。

不建议第一版接第三方 OCR 或云 OCR：

- 云 OCR 有隐私和网络依赖，不适合剪贴板默认能力。
- Tesseract 需要额外依赖、模型和打包处理，复杂度高。
- Vision 已经满足“本地、轻量、系统内置”的需求。

## 设计取舍

- 默认建议 `imageOCREnabled = false`，由用户在“剪贴板通用 > 图片”里打开。OCR 会读取用户剪贴板图片内容，默认关闭更符合隐私预期。
- OCR 只处理图片历史，不处理文本历史。
- OCR 结果不作为右侧预览正文展示，避免 UI 噪音；只在图片详情里显示一个小的“已识别文本”折叠区或摘要可选。
- 搜索命中 OCR 文本时，列表仍展示图片标题、大小、时间；可在 subtitle 或详情里提示 “OCR match”。
- 大图 OCR 需要限制，建议默认只 OCR `<= 20 MB` 图片，用户可配置；超过限制的图片仍保存历史，但 OCR 状态记为 skipped。
- OCR 失败不能影响图片保存和回贴。

## 数据模型

在 `clipboard_items` 增加可空列：

```sql
image_ocr_text TEXT;
image_ocr_status TEXT; -- pending / ready / failed / skipped
image_ocr_updated_at REAL;
```

扩展 Swift 模型：

```swift
enum ClipboardOCRStatus: String, Codable {
    case pending
    case ready
    case failed
    case skipped
}

struct ClipboardItem {
    ...
    var imageOCRText: String?
    var imageOCRStatus: ClipboardOCRStatus?
    var imageOCRUpdatedAt: Date?
}

struct ClipboardListItem {
    ...
    let imageOCRStatus: ClipboardOCRStatus?
    let hasImageOCRText: Bool
}
```

FTS 设计：

- 当前 `clipboard_fts(id, content)` 可以继续复用。
- 文本项：`content = 原始文本`。
- 图片项 OCR 完成后：`content = "image images img photo photos picture pictures 图片 照片 " + 文件名 + OCR 文本`。
- 删除触发器必须删除所有 type 的 FTS 行，不能只删 text。

## Task 1: 扩展 SQLite schema 和模型

**Files:**
- Modify: `Sources/xxMac/Models/ClipboardModels.swift`
- Modify: `Sources/xxMac/Managers/DatabaseManager.swift`
- Test: `Tests/xxMacTests/ClipboardDatabaseSummaryTests.swift`

**Step 1: 写失败测试**

在 `ClipboardDatabaseSummaryTests` 添加：

```swift
func testImageOCRMetadataPersistsAndIsSearchable() throws {
    let root = makeTemporaryDirectory()
    let storage = ClipboardStorageManager(storageDirectory: root)

    storage.saveImageItem(
        content: "screen.png",
        size: 1024,
        width: 800,
        height: 600,
        thumbnailFilename: nil
    )

    let item = try XCTUnwrap(storage.getListItems(limit: 1).first)
    storage.updateImageOCR(
        id: item.id,
        text: "invoice number ABC123",
        status: .ready
    )

    let results = storage.searchListItems(query: "ABC123")
    XCTAssertEqual(results.first?.id, item.id)
}
```

Expected before implementation: compile failure because OCR APIs do not exist.

**Step 2: 添加 OCR status enum 和字段**

在 `ClipboardModels.swift` 新增 `ClipboardOCRStatus`，并给 `ClipboardItem` / `ClipboardListItem` 增加 OCR 字段。

**Step 3: 增加数据库列迁移**

在 `DatabaseManager.ensureClipboardMetadataColumnsUnlocked()` 添加：

```swift
ensureColumnExists(table: "clipboard_items", column: "image_ocr_text", definition: "TEXT")
ensureColumnExists(table: "clipboard_items", column: "image_ocr_status", definition: "TEXT")
ensureColumnExists(table: "clipboard_items", column: "image_ocr_updated_at", definition: "REAL")
```

**Step 4: 更新 SELECT / mapper**

所有读取 `clipboard_items` 的 SELECT 都补上：

```sql
image_ocr_text, image_ocr_status, image_ocr_updated_at
```

`makeClipboardItem` 和 `makeClipboardListItem` 解析这些列。列表项不要带完整 OCR 文本，只带 `hasImageOCRText` 和 status。

**Step 5: 增加 OCR update API**

在 `DatabaseManager` 添加：

```swift
func updateImageOCR(id: String, text: String?, status: ClipboardOCRStatus) {
    let sql = """
    UPDATE clipboard_items
    SET image_ocr_text = ?, image_ocr_status = ?, image_ocr_updated_at = ?
    WHERE id = ? AND type = 'image';
    """
    ...
    updateFTSForImage(id: id, ocrText: text)
}
```

FTS upsert 使用：

```sql
DELETE FROM clipboard_fts WHERE id = ?;
INSERT INTO clipboard_fts(id, content) VALUES (?, ?);
```

图片 FTS 内容由固定 aliases、文件名、OCR 文本拼接。

**Step 6: Storage 暴露 API**

在 `ClipboardStorageManager` 添加：

```swift
func updateImageOCR(id: UUID, text: String?, status: ClipboardOCRStatus)
```

**Step 7: 跑测试**

Run:

```bash
swift test --filter ClipboardDatabaseSummaryTests
```

Expected: PASS。

## Task 2: 调整 FTS 触发器支持图片 OCR

**Files:**
- Modify: `Sources/xxMac/Managers/DatabaseManager.swift`
- Test: `Tests/xxMacTests/ClipboardDatabaseSummaryTests.swift`

**Step 1: 写删除测试**

添加测试：保存图片、写 OCR、确认能搜到；删除图片；确认搜不到。

```swift
func testDeletingImageRemovesOCRSearchIndex() throws {
    let root = makeTemporaryDirectory()
    let storage = ClipboardStorageManager(storageDirectory: root)
    storage.saveImageItem(content: "ocr.png", size: 1024, width: nil, height: nil, thumbnailFilename: nil)
    let item = try XCTUnwrap(storage.getItem(id: try XCTUnwrap(storage.getListItems().first).id))

    storage.updateImageOCR(id: item.id, text: "temporary searchable text", status: .ready)
    XCTAssertFalse(storage.searchListItems(query: "temporary").isEmpty)

    storage.deleteItem(item)
    XCTAssertTrue(storage.searchListItems(query: "temporary").isEmpty)
}
```

**Step 2: 修正 delete trigger**

当前删除触发器只在 `old.type = 'text'` 时删除 FTS。改成：

```sql
CREATE TRIGGER IF NOT EXISTS after_delete_clipboard_items AFTER DELETE ON clipboard_items
BEGIN
    DELETE FROM clipboard_fts WHERE id = old.id;
END;
```

注意：老数据库已有同名 trigger，`CREATE TRIGGER IF NOT EXISTS` 不会替换。实现中要先：

```sql
DROP TRIGGER IF EXISTS after_delete_clipboard_items;
```

然后创建新 trigger。

**Step 3: 避免 update trigger 覆盖图片 OCR FTS**

文本更新 trigger 保持 `WHEN new.type = 'text'`。图片 OCR FTS 只由 `updateImageOCR` 显式维护。

**Step 4: 跑测试**

Run:

```bash
swift test --filter ClipboardDatabaseSummaryTests
```

Expected: PASS。

## Task 3: 实现本地 Vision OCR Manager

**Files:**
- Create: `Sources/xxMac/Managers/ClipboardOCRManager.swift`
- Test: `Tests/xxMacTests/ClipboardOCRManagerTests.swift`

**Step 1: 新建 OCR manager 协议，方便测试**

```swift
protocol ClipboardOCRRecognizing {
    func recognizeText(in imageURL: URL, languages: [String]) async throws -> String
}
```

**Step 2: 实现 Vision recognizer**

```swift
import Foundation
import Vision
import AppKit

final class VisionClipboardOCRRecognizer: ClipboardOCRRecognizing {
    func recognizeText(in imageURL: URL, languages: [String]) async throws -> String {
        guard let image = NSImage(contentsOf: imageURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if !languages.isEmpty {
                request.recognitionLanguages = languages
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
```

**Step 3: 增加 orchestrator**

```swift
final class ClipboardOCRManager {
    static let shared = ClipboardOCRManager()
    private let recognizer: ClipboardOCRRecognizing

    init(recognizer: ClipboardOCRRecognizing = VisionClipboardOCRRecognizer()) {
        self.recognizer = recognizer
    }

    func enqueueImageOCR(itemID: UUID, imageURL: URL, languages: [String]) {
        Task.detached(priority: .utility) {
            do {
                let text = try await self.recognizer.recognizeText(in: imageURL, languages: languages)
                ClipboardStorageManager.shared.updateImageOCR(
                    id: itemID,
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    status: text.isEmpty ? .skipped : .ready
                )
            } catch {
                ClipboardStorageManager.shared.updateImageOCR(id: itemID, text: nil, status: .failed)
            }
        }
    }
}
```

**Step 4: 写 unit test 用 fake recognizer**

不要在单元测试里依赖真实 Vision 识别准确率。用 fake recognizer 返回固定字符串，测试 orchestrator 会写入 storage。为了避免 singleton 难测，给 `ClipboardOCRManager` 注入 `storage` 或 closure。

**Step 5: 跑测试**

Run:

```bash
swift test --filter ClipboardOCRManagerTests
```

Expected: PASS。

## Task 4: 图片入库后后台 OCR

**Files:**
- Modify: `Sources/xxMac/Managers/ClipboardManager.swift`
- Modify: `Sources/xxMac/Managers/ClipboardStorageManager.swift`
- Test: `Tests/xxMacTests/ClipboardDatabaseSummaryTests.swift`

**Step 1: 让保存图片返回 item id**

当前 `saveImageItem(...)` 不返回 id。改成：

```swift
@discardableResult
func saveImageItem(...) -> UUID
```

内部生成 `UUID` 后返回。`saveItem` 可保持不变。

**Step 2: 增加 OCR 初始状态**

保存图片时根据设置写入：

- `pending`：启用 OCR 且图片大小未超过 OCR 限制。
- `skipped`：未启用 OCR 或超过 OCR 限制。

`saveImageItem` 增加参数：

```swift
ocrStatus: ClipboardOCRStatus? = nil
```

**Step 3: ClipboardManager 调度 OCR**

在 `processPasteboardContent()` 保存图片后：

```swift
let itemID = storage.saveImageItem(...)
if shouldOCRImage(byteSize: pngData.count) {
    ClipboardOCRManager.shared.enqueueImageOCR(
        itemID: itemID,
        imageURL: fileURL,
        languages: settings.imageOCRLanguages
    )
}
```

**Step 4: OCR 完成后刷新历史**

`ClipboardOCRManager` 更新数据库后发通知：

```swift
NotificationCenter.default.post(name: .clipboardOCRDidUpdate, object: nil)
```

`ClipboardManager` 监听该通知并 `refreshHistory()`。

**Step 5: 跑测试**

Run:

```bash
swift test --filter ClipboardDatabaseSummaryTests
```

Expected: PASS。

## Task 5: 设置项和本地化

**Files:**
- Modify: `Sources/xxMac/Managers/ClipboardManager.swift`
- Modify: `Sources/xxMac/Views/ClipboardSettingsView.swift`
- Modify: `Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Resources/zh-Hant.lproj/Localizable.strings`
- Modify: `Resources/en.lproj/Localizable.strings`

**Step 1: 扩展 ClipboardSettings**

```swift
var imageOCREnabled: Bool = false
var maxOCRImageSizeMB: Int = 20
var imageOCRLanguages: [String] = ["zh-Hans", "en-US"]
```

`init(from:)` 里给旧配置默认值。

**Step 2: 设置页增加控件**

在图片 section 里添加：

- Toggle：`启用本地 OCR`
- Stepper：`OCR 最大图片大小`，范围 `1...100` MB，默认 20 MB
- Picker 或简化 Toggle：第一版不做复杂语言管理，默认中英文；后续再加语言选择。

**Step 3: 本地化 key**

新增：

```text
clipboard.ocr_enable
clipboard.ocr_enable_desc
clipboard.ocr_max_image_size
clipboard.ocr_status_pending
clipboard.ocr_status_ready
clipboard.ocr_status_failed
clipboard.ocr_status_skipped
clipboard.ocr_match
```

**Step 4: 导出配置检查**

确认 `CommonSettingsView.AppConfiguration.clipboardSettings` 仍导出设置，所以 OCR 设置会随配置导出；OCR 文本属于剪贴板历史 metadata，不单独导出。

## Task 6: 搜索和 UI 命中展示

**Files:**
- Modify: `Sources/xxMac/Managers/ClipboardManager.swift`
- Modify: `Sources/xxMac/Views/LauncherView.swift`

**Step 1: 搜索使用 OCR FTS**

`ClipboardStorageManager.searchListItems(query:)` 已走 `DatabaseManager.searchListItems`。确保 OCR 完成后图片 FTS 写入后，搜索图片文字可以返回图片项。

**Step 2: 图片 subtitle 显示 OCR 状态**

如果图片列表项有 OCR 状态：

- `.pending`：显示 “OCR 处理中”
- `.ready` 且当前搜索非空：显示 “OCR match • size • date”
- `.failed`：默认不在列表打扰用户，可在详情显示
- `.skipped`：不显示

为避免把 query 传进 `updatePublishedHistory()` 大改，可第一版只在详情里显示 OCR 状态，不做命中提示。

**Step 3: 图片详情展示 OCR 摘要**

在 `ClipboardDetailPane` 图片预览下面显示：

- `OCR 处理中`
- `已识别文本` 前 500 字
- `OCR 失败`

注意不要显示超长 OCR 全文，避免重新引入 UI 卡顿。

## Task 7: 文档更新

**Files:**
- Modify: `README.md`
- Modify: `README_en.md`
- Modify: `docs/plans/2026-07-01-clipboard-image-ocr-search.md`

**Step 1: README 中文**

更新剪贴板历史说明：

- 图片可启用本地 OCR。
- OCR 使用系统 Vision，本机处理，不上传图片。
- OCR 结果存入 `clipboard.db` 作为图片 metadata，用于搜索。
- 导出配置不导出 OCR 历史 metadata；完整迁移用配置目录切换。

**Step 2: README 英文**

同步英文描述。

## Task 8: 全量验证

**Files:**
- No code changes

**Step 1: 定向测试**

Run:

```bash
swift test --filter ClipboardDatabaseSummaryTests
swift test --filter ClipboardOCRManagerTests
```

Expected: PASS。

**Step 2: 全量测试**

Run:

```bash
swift test
```

Expected: PASS。

**Step 3: 构建**

Run:

```bash
swift build
```

Expected: PASS。

**Step 4: 手动验证**

1. 打开“剪贴板通用 > 图片 > 启用本地 OCR”。
2. 复制一张包含中文和英文的截图。
3. 等待 1-3 秒。
4. 打开剪贴板历史，搜索截图中的文字。
5. 预期返回该图片项。
6. 回车粘贴图片，预期仍粘贴原图。
7. 复制一张超过 OCR 大小限制的图片，预期保存历史但 OCR 状态为 skipped。

## 风险和注意事项

- Vision OCR 首次运行可能有系统级开销，必须后台执行。
- `VNRecognizeTextRequest.recognitionLanguages` 的语言标识在不同 macOS 版本支持可能有差异；如果设置语言导致失败，应 fallback 到空语言数组让系统自动判断。
- OCR 文本可能很长，不能放进列表 preview。
- OCR 结果属于剪贴板历史 metadata，不应随“导出配置”导出。
- 图片删除、历史清空、LRU 清理必须同步删除 FTS OCR 索引。
