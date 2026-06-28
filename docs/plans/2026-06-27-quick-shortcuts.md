# 快捷指令功能 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在设置里新增一个“快捷指令”工具，支持 Alfred 风格的 web search 和命令脚本，并能从启动器直接触发。

**Architecture:** 复用现有 `ToolOption / FunctionType / SettingsView / LauncherViewModel` 结构，新增一个独立的快捷指令管理器来保存配置、匹配关键词和执行动作。Web search 走 URL 模板展开并打开浏览器，命令脚本走受控的进程执行，并把查询词作为安全输入传给脚本。配置导入导出继续走现有 JSON 入口，新增字段必须纳入备份。

**Tech Stack:** SwiftUI, AppKit, `Process`, `UserDefaults`, 现有 `HotKey` 与 `Settings` 架构

---

### Task 1: 定义快捷指令数据模型

**Files:**
- Modify: `Sources/xxMac/Models/SettingsModels.swift`
- Create: `Sources/xxMac/Models/QuickShortcutModels.swift`

**Step 1: 设计最小模型**

定义两个动作类型：
- `webSearch`：keyword + title + URL 模板
- `commandScript`：keyword + title + shell脚本/js/cmd等命令

补充通用字段：
- `id`
- `keyword`
- `displayText`
- `isEnabled`
- `iconName`

**Step 2: 定义可持久化结构**

新增 `Codable` 模型与默认示例数据，确保后续能直接写入 `UserDefaults`。

**Step 3: 验证编译边界**

先不接 UI，只保证新模型能被编码/解码。

---

### Task 2: 新增快捷指令管理器

**Files:**
- Create: `Sources/xxMac/Managers/QuickShortcutManager.swift`

**Step 1: 写管理器骨架**

实现：
- 加载 / 保存配置
- `@Published var items`
- 默认示例项
- 按 keyword 查找和过滤

**Step 2: 补执行入口**

实现两个执行分支：
- web search：把 `{query}` 展开后用 `NSWorkspace.shared.open`
- command script：用 `Process` 启动 shell，查询词通过参数或环境变量传递

**Step 3: 保持行为可控**

命令脚本只执行用户配置的显式脚本，不做自动推断，不做额外“智能修复”。

---

### Task 3: 接入启动器搜索与执行

**Files:**
- Modify: `Sources/xxMac/ViewModels/LauncherViewModel.swift`
- Modify: `Sources/xxMac/Models/SearchItem.swift`

**Step 1: 增加新的搜索分支**

让启动器在普通搜索之外，识别快捷指令 keyword：
- `rt apple` 匹配 `rt`
- `gpt refactor this` 匹配脚本类指令

**Step 2: 统一结果模型**

把快捷指令结果也包装成 `SearchItem`，保持和现有 app / window / snippet 的结果列表一致。

**Step 3: 执行动作**

回车后：
- web search：直接打开目标 URL
- command script：运行脚本

**Step 4: 处理空查询**

没有 query 时不展示快捷指令结果，避免污染现有 launcher 行为。

---

### Task 4: 增加设置页的工具、列表和编辑器

**Files:**
- Modify: `Sources/xxMac/Models/SettingsModels.swift`
- Modify: `Sources/xxMac/Views/SettingsView.swift`
- Create: `Sources/xxMac/Views/QuickShortcutSettingsView.swift`

**Step 1: 增加左侧工具项**

在工具栏里新增“快捷指令”，并提供对应功能项入口。

**Step 2: 搭建列表 + 编辑器**

页面结构参考现有 `AppLauncherSettingsView` 和 `SnippetsSettingsView`：
- 左侧列表显示 keyword / title / enabled
- 右侧编辑器支持修改 URL 模板或脚本内容
- 提供新增、删除、启用/禁用

**Step 3: 提供测试入口**

为 web search 与脚本都补一个“测试/执行”按钮，便于快速验证配置是否可用。

**Step 4: 保持 macOS 风格**

尽量复用现有按钮、表单和侧边栏样式，不引入新的 UI 范式。

---

### Task 5: 更新导入/导出配置

**Files:**
- Modify: `Sources/xxMac/Views/CommonSettingsView.swift`

**Step 1: 扩展配置结构**

在 `AppConfiguration` 里加入快捷指令相关字段，导出时把完整配置写入 JSON。

**Step 2: 恢复配置**

导入时把快捷指令列表恢复到 `QuickShortcutManager`。

**Step 3: 保持剪贴板规则不变**

继续只导出剪贴板设置，不导出历史记录、SQLite 数据库或图片缓存。

---

### Task 6: 补全本地化与 README

**Files:**
- Modify: `Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Resources/zh-Hant.lproj/Localizable.strings`
- Modify: `Resources/en.lproj/Localizable.strings`
- Modify: `README.md`
- Modify: `README_en.md`

**Step 1: 补字符串**

增加快捷指令相关标题、说明、按钮文案、空状态文案和测试文案。

**Step 2: 更新功能概览**

README 里补一行“快捷指令”，说明它支持 web search 和命令脚本。

**Step 3: 更新配置说明**

说明快捷指令配置会随导出/导入走 JSON，和其它轻量设置保持一致。

---

### Task 7: 运行编译验证

**Files:**
- No new files

**Step 1: 编译**

Run: `swift build`

Expected: 通过编译，快捷指令相关类型和视图都能链接成功。

**Step 2: 运行检查**

Run: `swift run xxMac`

Expected: 设置窗口能看到新工具，启动器能展示并触发新快捷指令。

**Step 3: 手动回归**

验证：
- 导出/导入包含新配置
- 启动器查询不会破坏现有 app / window / snippets 行为
- 命令脚本不影响剪贴板历史和现有热键

