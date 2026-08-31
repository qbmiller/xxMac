# Finder Paste Operations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 复用可配置的 `Command + Shift + V`，在保留 Finder 文件路径粘贴的同时，将 Finder 前台的剪贴板图片或纯文本保存为当前目录中的递增命名文件。

**Architecture:** `FinderPasteOperationManager` 是快捷键的唯一入口，先读取强类型剪贴板载荷，再用纯路由策略决定粘贴路径、保存图片、保存文本或忽略。计数、格式识别、命名冲突处理均放在无 UI 的纯逻辑类型中；Finder 目录解析、剪贴板和文件系统通过小接口隔离，以便 SwiftPM 单元测试不依赖真实 Finder。

**Tech Stack:** Swift 5.9、SwiftUI、AppKit、ApplicationServices、Foundation、XCTest、Swift Package Manager

**Spec:** `docs/superpowers/specs/2026-08-24-finder-paste-operations-design.md`

## Global Constraints

- 项目是 SwiftPM 可执行包，只运行 `swift test`、`swift build`；禁止使用 `xcodebuild`。
- 不增加第三方依赖。
- 共用快捷键默认值保持 `Command + Shift + V`，继续使用 `WindowAction.pasteFinderPath` 和现有快捷键冲突检测。
- 文件 URL 优先于图片和文本；复制的图片文件或文本文件不得转换。
- 图片和文本转换仅在 Finder 前台执行；文件路径粘贴仍可在其他前台应用执行。
- 图片与文本开关默认关闭，计数每日独立重置，用户可分别手动重置。
- 不扫描目录恢复计数，不覆盖已有文件；只有成功写入后才递增。
- 设置写入配置目录的 `preferences.json`；生成文件不写入配置目录。
- 不修改或删除用户已有的 `qin.md`、`image.png` 及其他无关工作区变更。
- 按仓库 `AGENTS.md` 要求禁止自动 Git commit；本计划所有任务均以测试检查点结束，不含提交步骤。

---

## File Structure

- Create `Sources/xxMac/Managers/FinderPasteOperationModels.swift`: 设置模型、每日计数、载荷和路由策略。
- Create `Sources/xxMac/Managers/ClipboardTextFormatDetector.swift`: 纯文本格式识别。
- Create `Sources/xxMac/Managers/FinderPasteFileNaming.swift`: 基础文件名、时间戳冲突名和最终兜底序号。
- Create `Sources/xxMac/Managers/FinderPasteOperationManager.swift`: 剪贴板读取、Finder 目录解析、PNG/文本写入、状态持久化和反馈。
- Modify `Sources/xxMac/Managers/FilePathPasteManager.swift`: 允许把已解析的 URL 数组交给现有路径输入流程。
- Modify `Sources/xxMac/Managers/HotkeyManager.swift`: 将 `.pasteFinderPath` 触发目标改为统一粘贴操作管理器，只从通用设置列表移除展示。
- Modify `Sources/xxMac/AppDefaultSettings.swift`: 增加图片/文本开关默认值。
- Modify `Sources/xxMac/Models/SettingsModels.swift`: 增加“粘贴操作”第二栏功能。
- Create `Sources/xxMac/Views/ClipboardPasteOperationsSettingsView.swift`: 共用快捷键、两个开关、两个下一个编号和重置按钮。
- Modify `Sources/xxMac/Views/SettingsView.swift`: 路由新设置视图，并让“通用 > 快捷键管理”只显示启动器快捷键。
- Modify `Resources/en.lproj/Localizable.strings`, `Resources/zh-Hans.lproj/Localizable.strings`, `Resources/zh-Hant.lproj/Localizable.strings`: 新界面、成功/失败反馈和配置说明文案。
- Modify `README.md`: 功能、默认快捷键、配置目录和格式识别说明。
- Create `Tests/xxMacTests/FinderPasteOperationModelsTests.swift`: 设置默认值、每日计数和路由策略。
- Create `Tests/xxMacTests/ClipboardTextFormatDetectorTests.swift`: 七类格式正例和误判反例。
- Create `Tests/xxMacTests/FinderPasteFileNamingTests.swift`: 编号格式与重名兜底。
- Create `Tests/xxMacTests/FinderPasteOperationManagerTests.swift`: 端到端协调、持久化和成功/失败计数。
- Modify `Tests/xxMacTests/AppDefaultSettingsTests.swift`: 两个开关默认关闭。

---

### Task 1: 设置模型、每日独立计数与路由策略

**Files:**
- Create: `Sources/xxMac/Managers/FinderPasteOperationModels.swift`
- Create: `Tests/xxMacTests/FinderPasteOperationModelsTests.swift`
- Modify: `Sources/xxMac/AppDefaultSettings.swift`
- Modify: `Tests/xxMacTests/AppDefaultSettingsTests.swift`

**Interfaces:**
- Produces: `FinderPasteOperationSettings`, `DailyPasteCounter`, `FinderPastePayload`, `FinderPasteRoute`, `FinderPasteRoutingPolicy.route(payload:isFinderFrontmost:settings:)`。
- Consumes: `AppDefaultSettings.Clipboard.imagePasteToFileEnabled` 和 `textPasteToFileEnabled`，均为 `false`。

- [ ] **Step 1: 写默认开关和每日计数失败测试**

在 `AppDefaultSettingsTests` 增加：

```swift
XCTAssertFalse(AppDefaultSettings.Clipboard.imagePasteToFileEnabled)
XCTAssertFalse(AppDefaultSettings.Clipboard.textPasteToFileEnabled)
```

在新测试文件中使用固定 `Calendar(identifier: .gregorian)` 和 GMT 时区，覆盖：

```swift
func testCounterStartsAtOneAndAdvancesOnlyAfterSuccess() {
    var counter = DailyPasteCounter()
    let date = makeDate("2026-08-25T10:00:00Z")
    XCTAssertEqual(counter.nextNumber(on: date, calendar: calendar), 1)
    counter.recordSuccess(on: date, calendar: calendar)
    XCTAssertEqual(counter.nextNumber(on: date, calendar: calendar), 2)
}

func testCounterResetsWhenDayChanges() {
    var counter = DailyPasteCounter(dateKey: "20260825", nextValue: 18)
    XCTAssertEqual(counter.nextNumber(on: makeDate("2026-08-26T00:01:00Z"), calendar: calendar), 1)
}

func testManualResetOnlyChangesSelectedCounter() {
    var settings = FinderPasteOperationSettings(
        imageCounter: .init(dateKey: "20260825", nextValue: 9),
        textCounter: .init(dateKey: "20260825", nextValue: 4)
    )
    settings.imageCounter.reset(on: date, calendar: calendar)
    XCTAssertEqual(settings.imageCounter.nextValue, 1)
    XCTAssertEqual(settings.textCounter.nextValue, 4)
}
```

- [ ] **Step 2: 运行测试并确认 RED**

Run: `swift test --filter 'AppDefaultSettingsTests|FinderPasteOperationModelsTests'`

Expected: 编译失败，提示新增默认值和类型不存在。

- [ ] **Step 3: 实现最小设置、计数和路由类型**

实现以下公开到测试模块的内部接口：

```swift
struct DailyPasteCounter: Codable, Equatable {
    var dateKey: String = ""
    var nextValue: Int = 1

    func nextNumber(on date: Date, calendar: Calendar) -> Int
    mutating func recordSuccess(on date: Date, calendar: Calendar)
    mutating func reset(on date: Date, calendar: Calendar)
}

struct FinderPasteOperationSettings: Codable, Equatable {
    var imageEnabled: Bool
    var textEnabled: Bool
    var imageCounter: DailyPasteCounter
    var textCounter: DailyPasteCounter

    init(
        imageEnabled: Bool = AppDefaultSettings.Clipboard.imagePasteToFileEnabled,
        textEnabled: Bool = AppDefaultSettings.Clipboard.textPasteToFileEnabled,
        imageCounter: DailyPasteCounter = .init(),
        textCounter: DailyPasteCounter = .init()
    )
}

enum FinderPastePayload: Equatable {
    case fileURLs([URL])
    case image(Data)
    case text(String)
    case unsupported
}

enum FinderPasteRoute: Equatable {
    case pastePaths([URL])
    case saveImage(Data)
    case saveText(String)
    case none
}
```

`DailyPasteCounter` 使用 `yyyyMMdd` 和传入日历生成 `dateKey`；`nextNumber` 不修改状态，日期不同时直接返回 `1`。`recordSuccess` 先把日期和编号规范化为当天状态，再将编号加一。这样仅打开设置页查看编号不会产生持久化写入。

路由规则的最小实现：文件 URL 始终 `.pastePaths`；图片/文本仅在 Finder 前台且对应开关开启时保存；其他返回 `.none`。

- [ ] **Step 4: 增加路由优先级失败测试**

```swift
func testFilesAlwaysRouteToPathPaste() {
    let urls = [URL(fileURLWithPath: "/tmp/a.png")]
    XCTAssertEqual(
        FinderPasteRoutingPolicy.route(
            payload: .fileURLs(urls),
            isFinderFrontmost: false,
            settings: .init(imageEnabled: true, textEnabled: true)
        ),
        .pastePaths(urls)
    )
}

func testImageAndTextRequireFinderAndTheirOwnSwitch() {
    XCTAssertEqual(route(.image(Data([1])), finder: false, image: true, text: true), .none)
    XCTAssertEqual(route(.image(Data([1])), finder: true, image: false, text: true), .none)
    XCTAssertEqual(route(.text("{}"), finder: true, image: true, text: false), .none)
}
```

- [ ] **Step 5: 运行定向测试并确认 GREEN**

Run: `swift test --filter 'AppDefaultSettingsTests|FinderPasteOperationModelsTests'`

Expected: PASS。

---

### Task 2: 保守的文本格式识别

**Files:**
- Create: `Sources/xxMac/Managers/ClipboardTextFormatDetector.swift`
- Create: `Tests/xxMacTests/ClipboardTextFormatDetectorTests.swift`

**Interfaces:**
- Produces: `ClipboardTextFormatDetector.fileExtension(for:) -> String?`。
- Consumes: 原始 `String`，不修改文本内容。

- [ ] **Step 1: 写 JSON、plist、XML 失败测试**

```swift
XCTAssertEqual(ClipboardTextFormatDetector.fileExtension(for: #"{"name":"xxMac"}"#), "json")
XCTAssertEqual(ClipboardTextFormatDetector.fileExtension(for: plistXML), "plist")
XCTAssertEqual(ClipboardTextFormatDetector.fileExtension(for: "<root><item/></root>"), "xml")
XCTAssertNil(ClipboardTextFormatDetector.fileExtension(for: "今天配置 xxMac"))
```

- [ ] **Step 2: 运行并确认 RED**

Run: `swift test --filter ClipboardTextFormatDetectorTests`

Expected: 编译失败，提示 `ClipboardTextFormatDetector` 不存在。

- [ ] **Step 3: 实现严格解析器**

实现：

```swift
enum ClipboardTextFormatDetector {
    static func fileExtension(for text: String) -> String? {
        let data = Data(text.utf8)
        if isJSON(data) { return "json" }
        if isPropertyList(data) { return "plist" }
        if isXML(data) { return "xml" }
        return nil
    }
}
```

JSON 使用 `JSONSerialization.jsonObject`；plist 使用 `PropertyListSerialization.propertyList`，且必须确认文本含 plist 声明或 `<plist` 根元素，避免普通 XML 被抢先识别；XML 使用 `XMLParser` 并要求完整解析成功。

- [ ] **Step 4: 增加 YAML、TOML、INI、ENV 正例和反例测试**

```swift
XCTAssertEqual(detect("services:\n  api:\n    image: xxmac:1"), "yml")
XCTAssertEqual(detect("[server]\nhost = \"localhost\"\nport = 8080"), "toml")
XCTAssertEqual(detect("[server]\nhost=localhost\nport=8080"), "ini")
XCTAssertEqual(detect("API_URL=https://example.com\nDEBUG=true"), "env")
XCTAssertNil(detect("title: hello"))
XCTAssertNil(detect("answer=42"))
XCTAssertNil(detect("a normal sentence\nwith two lines"))
```

- [ ] **Step 5: 实现保守特征识别**

按 JSON、plist、XML、YAML、TOML、INI、ENV 顺序调用私有判定函数。YAML 必须有至少两条结构证据（缩进映射、列表项、`---` 文档头之一）；TOML 必须有表头且存在类型化/带空格键值；INI 必须有节头且至少两个键值；ENV 必须至少两条非注释 `^[A-Za-z_][A-Za-z0-9_]*=.*$` 行。普通单键值不识别。

- [ ] **Step 6: 运行定向测试并确认 GREEN**

Run: `swift test --filter ClipboardTextFormatDetectorTests`

Expected: PASS。

---

### Task 3: 不扫描计数的文件命名与冲突保护

**Files:**
- Create: `Sources/xxMac/Managers/FinderPasteFileNaming.swift`
- Create: `Tests/xxMacTests/FinderPasteFileNamingTests.swift`

**Interfaces:**
- Produces: `FinderPasteFileNamer.destinationURL(directory:date:number:fileExtension:fileExists:) -> URL`。
- Consumes: 已持久化编号、固定日期、可选扩展名和用于测试注入的存在性闭包。

- [ ] **Step 1: 写基础命名和超过 999 的失败测试**

```swift
XCTAssertEqual(name(number: 1, ext: "png"), "20260825-001.png")
XCTAssertEqual(name(number: 18, ext: "json"), "20260825-018.json")
XCTAssertEqual(name(number: 1000, ext: nil), "20260825-1000")
```

- [ ] **Step 2: 运行并确认 RED**

Run: `swift test --filter FinderPasteFileNamingTests`

Expected: 编译失败，提示 `FinderPasteFileNamer` 不存在。

- [ ] **Step 3: 实现基础候选名**

使用传入日历/时区格式化 `yyyyMMdd`，编号使用 `String(format: "%03d", number)`。扩展名为 `nil` 时不追加句点。不得枚举目录内容。

- [ ] **Step 4: 写秒、毫秒和最终序号冲突测试**

固定 `date.timeIntervalSince1970 == 1787623456.789`，通过 `fileExists` 返回集合模拟冲突，断言依次得到：

```text
20260825-001.png
20260825-001-1787623456.png
20260825-001-1787623456789.png
20260825-001-1787623456789-1.png
```

- [ ] **Step 5: 实现冲突候选链**

仅对基础名、秒名、毫秒名逐一调用 `fileExists`；前三个都冲突后，从 `-1` 开始寻找最小可用序号。绝不删除或覆盖已有文件。

- [ ] **Step 6: 运行定向测试并确认 GREEN**

Run: `swift test --filter FinderPasteFileNamingTests`

Expected: PASS。

---

### Task 4: 剪贴板载荷读取和现有路径粘贴复用

**Files:**
- Modify: `Sources/xxMac/Managers/FilePathPasteManager.swift`
- Create: `Sources/xxMac/Managers/FinderPasteOperationManager.swift`（先加入载荷读取器和协议）
- Create: `Tests/xxMacTests/FinderPasteOperationManagerTests.swift`

**Interfaces:**
- Produces: `FinderPasteboardReading.readPayload() -> FinderPastePayload`、`SystemFinderPasteboardReader`、`FilePathPasteManager.pasteFinderPaths(_ urls: [URL])`。
- Consumes: `NSPasteboard.general` 和现有 `FilePathPasteManager.pathText(for:)`。

- [ ] **Step 1: 写文件 URL 优先的失败测试**

使用 `NSPasteboard(name: .init("FinderPasteOperationManagerTests.<UUID>"))` 写入同时可表现为文件和图片/文本的项目，断言读取结果是 `.fileURLs`。另写独立 PNG 数据和纯文本用例，断言分别得到 `.image`、`.text`；空剪贴板得到 `.unsupported`。

- [ ] **Step 2: 运行并确认 RED**

Run: `swift test --filter FinderPasteOperationManagerTests`

Expected: 编译失败，提示载荷读取接口不存在。

- [ ] **Step 3: 实现载荷读取优先级**

定义：

```swift
protocol FinderPasteboardReading {
    func readPayload() -> FinderPastePayload
}

struct SystemFinderPasteboardReader: FinderPasteboardReading {
    let pasteboard: NSPasteboard
    func readPayload() -> FinderPastePayload
}
```

依次读取文件 URL、`public.png/public.tiff/public.jpeg/public.heic/com.compuserve.gif/com.microsoft.bmp` 原始数据、`.string`。文件 URL 读取复用现有现代 URL、pasteboard item、旧 `NSFilenamesPboardType` 兼容逻辑，并从 `FilePathPasteManager` 提取为内部静态函数，避免复制两份实现。

- [ ] **Step 4: 将现有路径动作改为接收已解析 URL**

保留无参 `pasteFinderPaths()` 兼容入口，新增：

```swift
func pasteFinderPaths(_ urls: [URL]) {
    guard !urls.isEmpty else { return }
    let pathText = Self.pathText(for: urls)
    ClipboardManager.shared.recordText(pathText)
    typeTextAfterModifierRelease(pathText)
}
```

无参版本读取 URL 后调用新重载。

- [ ] **Step 5: 运行载荷和现有路径测试**

Run: `swift test --filter 'FinderPasteOperationManagerTests|ClipboardModelsTests'`

Expected: PASS；现有路径格式行为无回归。

---

### Task 5: Finder 目录解析、文件写入、持久化与统一分流

**Files:**
- Modify: `Sources/xxMac/Managers/FinderPasteOperationManager.swift`
- Modify: `Sources/xxMac/Managers/HotkeyManager.swift`
- Modify: `Tests/xxMacTests/FinderPasteOperationManagerTests.swift`

**Interfaces:**
- Produces: `FinderDirectoryResolving.currentDirectory() -> URL?`、`FinderPasteFileWriting.write(data:to:) throws`、`FinderPasteOperationManager.perform()`、`resetImageCounter()`、`resetTextCounter()`。
- Consumes: Tasks 1-4 的设置、路由、识别、命名、载荷读取和路径粘贴接口。

- [ ] **Step 1: 写协调器成功/失败计数测试**

注入假的 pasteboard reader、Finder resolver、writer、clock 和 preferences adapter，验证：

```swift
func testSuccessfulImageWriteAdvancesOnlyImageCounter()
func testSuccessfulTextWriteUsesDetectedExtensionAndAdvancesOnlyTextCounter()
func testWriteFailureDoesNotAdvanceCounter()
func testMissingFinderDirectoryDoesNotWriteOrAdvance()
func testFilePayloadCallsPathPasteOutsideFinder()
func testDisabledConversionDoesNothing()
func testPersistedSettingsReloadWithIndependentCounters()
func testMissingPersistedSettingsUseDisabledDefaults()
```

成功图片用例应断言写入 URL 为 `.../20260825-001.png`；成功 JSON 用例应断言原始 UTF-8 数据未变化且 URL 为 `.../20260825-001.json`。

- [ ] **Step 2: 运行并确认 RED**

Run: `swift test --filter FinderPasteOperationManagerTests`

Expected: 编译失败，提示协调器和依赖协议尚未完整实现。

- [ ] **Step 3: 实现可注入协调器和持久化适配器**

先定义所有依赖边界，后续测试 fake 必须逐一实现这些精确签名：

```swift
protocol FinderDirectoryResolving {
    func currentDirectory() -> URL?
}

protocol FinderPasteFileWriting {
    func write(_ data: Data, to url: URL) throws
}

protocol FinderPasteSettingsStoring {
    func load() -> FinderPasteOperationSettings?
    func save(_ settings: FinderPasteOperationSettings)
}

protocol FinderPasteFeedbackPresenting {
    func showSuccess(fileURL: URL)
    func showFailure(message: String)
}
```

核心构造器：

```swift
final class FinderPasteOperationManager: ObservableObject {
    static let shared = FinderPasteOperationManager()

    @Published private(set) var settings: FinderPasteOperationSettings

    init(
        pasteboardReader: FinderPasteboardReading,
        directoryResolver: FinderDirectoryResolving,
        fileWriter: FinderPasteFileWriting,
        settingsStore: FinderPasteSettingsStoring,
        frontmostBundleIdentifier: @escaping () -> String?,
        now: @escaping () -> Date,
        calendar: Calendar,
        pathPaster: @escaping ([URL]) -> Void,
        feedback: FinderPasteFeedbackPresenting
    )

    func perform()
    func setImageEnabled(_ enabled: Bool)
    func setTextEnabled(_ enabled: Bool)
    func resetImageCounter()
    func resetTextCounter()

    var imageNextNumber: Int { get }
    var textNextNumber: Int { get }
}
```

生产设置存储 `PreferencesFinderPasteSettingsStore` 用单个 `Data` 键 `FinderPasteOperationSettings` 编解码到 `PreferencesStore`。缺少或解码失败时使用两个默认关闭开关和两个初始计数。`imageNextNumber` 和 `textNextNumber` 使用注入的时钟调用 counter 的非修改 `nextNumber`；只有成功保存、开关变化或用户重置时才调用 store。

协调器在主线程读取载荷和路由；图片编码、文本 UTF-8 转换及写入放到串行后台队列。成功后回主线程记录对应 counter、保存设置并发布 UI；失败只反馈错误。生产反馈实现 `UserNotificationFinderPasteFeedbackPresenter`，使用 macOS 用户通知显示本地化的成功文件名或失败原因，不弹阻塞式对话框。

- [x] **Step 4: 实现 Finder 当前目录解析**

`FinderAppleEventDirectoryResolver` 先确认前台 bundle identifier 是 `com.apple.finder`，再由 `FinderAppleScriptTargetDirectoryQuery` 通过 Finder Apple Events 读取 `target of front Finder window`。Finder 没有窗口时由同一脚本返回桌面目录；Apple Events 被拒绝、脚本失败或返回的路径不是现有目录时返回 `nil`。

测试将 Apple Events 边界留在小适配器内，协调器测试只注入固定路径、固定 URL 或 `nil`。

- [ ] **Step 5: 实现 PNG 和原子文件写入**

图片通过 `NSImage(data:)` 解码、`CGImage`/`NSBitmapImageRep` 转 PNG。文本直接使用 `Data(text.utf8)`。写入器先验证目标父目录可写，再调用 `data.write(to:options: .withoutOverwriting)`；命名器已保证冲突规避，`.withoutOverwriting` 负责关闭竞态覆盖窗口。

- [ ] **Step 6: 接入现有快捷键**

将 `HotKeyManager.performAction(.pasteFinderPath)` 改为：

```swift
DispatchQueue.main.async {
    FinderPasteOperationManager.shared.perform()
}
```

不新增 `WindowAction`，不改默认快捷键，不改变 `ShortcutRegistryStore` 注册身份。

- [ ] **Step 7: 运行协调器与快捷键回归测试**

Run: `swift test --filter 'FinderPasteOperationManagerTests|ShortcutRegistryTests|AppDefaultSettingsTests'`

Expected: PASS。

---

### Task 6: “剪贴板 > 粘贴操作”设置页与快捷键迁移

**Files:**
- Modify: `Sources/xxMac/Models/SettingsModels.swift`
- Create: `Sources/xxMac/Views/ClipboardPasteOperationsSettingsView.swift`
- Modify: `Sources/xxMac/Views/SettingsView.swift`
- Modify: `Sources/xxMac/Managers/HotkeyManager.swift`
- Modify: `Resources/en.lproj/Localizable.strings`
- Modify: `Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Resources/zh-Hant.lproj/Localizable.strings`

**Interfaces:**
- Produces: `FunctionType.clipboardPasteOperations`、`ClipboardPasteOperationsSettingsView`。
- Consumes: `HotKeyRecorderView(action: .pasteFinderPath)` 和 `FinderPasteOperationManager.shared` 的 published settings/mutators。

- [ ] **Step 1: 增加第二栏功能类型并路由新视图**

在 `FunctionType` 添加：

```swift
case clipboardPasteOperations = "function.clipboard.paste_operations"
```

图标返回 `doc.on.doc`，并在 clipboard functions 中放在第一项：

```swift
ToolFunction(type: .clipboardPasteOperations),
ToolFunction(type: .clipboardGeneral),
ToolFunction(type: .clipboardHistory),
ToolFunction(type: .clipboardIgnored)
```

`ConfigurationView` 对该 case 返回 `ClipboardPasteOperationsSettingsView()`。

- [ ] **Step 2: 从通用快捷键页面移除路径粘贴行**

将 `WindowAction.commonShortcutCases` 改为只包含 `.toggleLauncher`。不要从 `WindowAction.allCases`、默认配置或注册表移除 `.pasteFinderPath`。

- [ ] **Step 3: 实现粘贴操作设置视图**

页面使用三个同级设置区，不嵌套卡片：

```swift
struct ClipboardPasteOperationsSettingsView: View {
    @ObservedObject private var manager = FinderPasteOperationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            pathPasteSection
            imagePasteSection
            textPasteSection
            Spacer()
        }
    }
}
```

路径区展示说明和 `HotKeyRecorderView(action: .pasteFinderPath)`；图片/文本区分别使用 `Toggle`、等宽字体显示 `String(format: "%03d", manager.imageNextNumber)` / `textNextNumber`，并用带 `arrow.counterclockwise` 图标的重置按钮调用对应 reset。按钮和长文案在窄宽度下可换行，不设置随视口变化的字体。

- [ ] **Step 4: 增加三语言文案**

至少加入以下 key，并为英文、简体中文、繁体中文提供真实翻译：

```text
function.clipboard.paste_operations
clipboard_paste.desc
clipboard_paste.path_title
clipboard_paste.path_desc
clipboard_paste.image_title
clipboard_paste.image_desc
clipboard_paste.image_enabled
clipboard_paste.text_title
clipboard_paste.text_desc
clipboard_paste.text_enabled
clipboard_paste.next_number
clipboard_paste.reset_counter
clipboard_paste.saved
clipboard_paste.failed
```

- [ ] **Step 5: 构建检查设置页**

Run: `swift build`

Expected: BUILD SUCCEEDED，无 switch exhaustiveness、SwiftUI binding 或本地化资源构建错误。

---

### Task 7: 配置迁移说明、README 与完整验证

**Files:**
- Modify: `README.md`
- Modify: `Resources/en.lproj/Localizable.strings`
- Modify: `Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Resources/zh-Hant.lproj/Localizable.strings`
- Modify: `Tests/xxMacTests/PreferencesStoreMigrationTests.swift`（仅当新设置采用独立原始 key；若使用单个 Data 键则无需加入旧 UserDefaults 迁移清单）

**Interfaces:**
- Consumes: 完成后的设置键、功能名称和实际行为。
- Produces: 用户可见文档与配置目录边界说明。

- [ ] **Step 1: 更新 README 功能和快捷键表**

将现有 “Finder Path Paste” 描述扩为共用 Finder 粘贴操作：文件 URL 粘贴路径；Finder 前台时可按开关把原始图片/文本保存为文件。默认快捷键表仍只列一条 `Command + Shift + V`。

补充：

- 图片固定 PNG，文本支持 `.json/.plist/.xml/.yml/.toml/.ini/.env`，不可靠时无后缀。
- 图片和文本每日独立编号、手动重置、不扫描目录、同名追加时间戳且不覆盖。
- 两个转换开关默认关闭。

- [ ] **Step 2: 更新配置目录说明**

README 和“通用 > 配置目录”文案注明：`FinderPasteOperationSettings` 保存在 `preferences.json`；生成文件位于 Finder 目标目录，不在配置目录中，也不随导出配置导出。

- [ ] **Step 3: 运行格式与差异检查**

Run: `git diff --check`

Expected: 无空白错误。

Run: `rg -n "pasteFinderPath|paste_operations|FinderPasteOperationSettings" Sources Tests README.md Resources`

Expected: 旧快捷键仍注册；通用快捷键页面不再迭代该 action；新设置、文案、测试和 README 引用完整。

- [ ] **Step 4: 运行完整测试**

Run: `swift test`

Expected: 所有测试 PASS，无崩溃或未处理错误。

- [ ] **Step 5: 运行完整构建**

Run: `swift build`

Expected: BUILD SUCCEEDED。

- [ ] **Step 6: 生成应用包供手动验证**

Run: `bash bundle_app.sh`

Expected: 成功生成 `xxMac.app`，资源中包含三套更新后的本地化字符串。

- [ ] **Step 7: 手动验证清单**

在获得辅助功能权限的应用包中验证：

1. 打开“剪贴板 > 粘贴操作”，确认共用快捷键、图片开关、文本开关、独立编号和重置按钮。
2. Finder 当前文件夹中触发截图转 PNG，确认名称和编号递增。
3. 分别粘贴 JSON、YAML 和普通文本，确认扩展名及原内容字节一致。
4. 复制 Finder 图片文件，在终端触发快捷键，确认粘贴路径而不是创建图片。
5. 关闭图片或文本开关，确认相应载荷不创建文件。
6. 预建同名文件后触发，确认原文件不变，新文件追加时间戳。
7. 重置图片编号，确认文本编号不变；重置文本编号，确认图片编号不变。
