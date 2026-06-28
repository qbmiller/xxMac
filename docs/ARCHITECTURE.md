# xxMac 架构说明

本文档是项目的主技术说明。原先独立的初始化摘要已经合并到这里，避免 README、架构说明和 AI 协作摘要三处重复维护。

## 1. 项目定位

xxMac 是一个基于 `SwiftUI + AppKit` 的 macOS 原生效率工具，当前目标是做一个聚合型桌面效率入口：

1. `Launcher`：统一搜索入口，执行应用启动、窗口操作、剪贴板选择等动作。
2. `Window Management`：通过全局快捷键控制当前活动窗口布局，能力类似 ShiftIt。
3. `Clipboard History`：记录文本和图片剪贴板，支持检索、预览和回贴。
4. `App Launcher`：给指定 App 绑定热键，快速启动、激活或隐藏。
5. `Shortcut Detective`：记录快捷键接收方，辅助排查快捷键冲突。

运行形态：

1. 菜单栏应用，不常驻 Dock。
2. 全局热键唤起浮动启动器面板。
3. 独立设置窗口，采用三栏结构：工具分类、功能列表、配置详情。

## 2. 技术栈

1. Swift 5.9
2. Swift Package Manager
3. SwiftUI
4. AppKit
5. Accessibility API
6. SQLite3
7. HotKey

## 3. 快速初始化

前置要求：

1. macOS 13+
2. Xcode Command Line Tools 或 Xcode


可选打包：

```bash
bash bundle_app.sh
```

首次运行通常需要授予：

1. 辅助功能权限：窗口移动、全局热键、模拟粘贴依赖它。
2. 自动化权限：应用激活、重开窗口和回贴链路可能用到。

## 4. 目录结构

```text
xxMac/
├── Package.swift
├── README.md
├── PACKAGING_GUIDE.md
├── bundle_app.sh
├── Resources/
├── Sources/xxMac/
│   ├── xxMac.swift        # App 入口、状态栏、浮动窗口生命周期
│   ├── Models/                        # 数据模型
│   ├── ViewModels/                    # 业务编排（Launcher）
│   ├── Views/                         # SwiftUI 配置与主界面
│   ├── Managers/                      # 系统能力、持久化、搜索、热键等核心逻辑
│   └── Info.plist
└── docs/ARCHITECTURE.md
```

## 5. 架构分层

核心分层关系：

```text
View <-> ViewModel <-> Manager <-> macOS System API
                   |
                 Model
```

职责边界：

1. `View`：展示、输入、焦点、列表交互和设置表单。
2. `ViewModel`：状态管理、搜索结果编排、选择项执行。
3. `Manager`：调用系统 API、持久化、热键注册、应用扫描和跨模块协作。
4. `Model`：热键配置、搜索项、剪贴板项、设置项等数据结构。

新增功能时优先遵循这个方向：系统能力先进 `Manager`，业务组合进 `ViewModel`，界面只做展示和输入。

## 6. 核心模块

入口与窗口生命周期：

1. `Sources/xxMac/xxMac.swift`
2. 负责 AppDelegate 生命周期、状态栏菜单、Launcher Panel、Settings Window、焦点恢复、通知注册。

启动器（搜索与执行）：

1. `ViewModels/LauncherViewModel.swift`
2. 模式：`launcher` / `clipboard`
3. 搜索结果来源：
   1. 窗口命令
   2. 应用搜索（`AppSearchManager`）
   3. 剪贴板历史（`ClipboardManager`）

热键系统：

1. `Managers/HotkeyManager.swift`
2. 使用 HotKey 注册全局快捷键
3. 负责窗口管理动作和主 Launcher 热键
4. 默认主热键：`Control + Option + Space`

窗口管理：

1. `Managers/AccessibilityManager.swift`
2. 基于 AX API 获取当前活动窗口并修改位置/大小
3. 支持半屏、四角、居中、最大化、缩放、全屏、跨屏移动等

应用搜索与启动：

1. `Managers/AppSearchManager.swift`
2. 扫描 `/Applications`、`/System/Applications`、`/System/Library/CoreServices` 和用户自定义路径
3. 对应用名、Bundle 名、显示名和路径建立普通搜索键与 compact 搜索键
4. 排序策略：前缀优先、包含次之、路径匹配最后

应用快捷启动器：

1. `Managers/AppLauncherManager.swift`
2. 为指定 App 绑定热键
3. 支持启动、激活、隐藏切换
4. 对隐藏、最小化、窗口关闭但进程仍运行的 App，会尝试 `reopen` + `activate`

剪贴板系统：

1. `Managers/ClipboardManager.swift`：监听系统剪贴板、文本/图片入库、历史发布、回贴
2. `Managers/ClipboardStorageManager.swift`：存储目录、图片文件管理、LRU 清理
3. `Managers/DatabaseManager.swift`：SQLite 表/索引/FTS5、增删改查
4. 当前 UI 搜索走内存过滤；数据库层已有 FTS5 能力，后续可统一接入

设置页：

1. `Views/SettingsView.swift` 为三栏导航入口
2. 已实现配置页：通用、语言、搜索路径、窗口热键、Shortcut Detective、剪贴板、应用快捷、关于
3. 未完成配置页会显示占位内容

本地化：

1. `Managers/LocalizationManager.swift`
2. `Resources/*.lproj/Localizable.strings`
3. 当前已有 `zh-Hans`、`zh-Hant`、`en`

## 7. 关键运行流程

应用启动流程：

1. `AppDelegate.applicationDidFinishLaunching`
2. 初始化 Manager（热键、应用启动器、剪贴板）
3. 请求 Accessibility 权限
4. 创建状态栏菜单与 Launcher 浮层窗口
5. 注册通知与键盘事件监听

热键触发 Launcher 流程：

1. `HotkeyManager` 捕获 `toggleLauncher`
2. 发出通知 `ToggleLauncher`
3. `AppDelegate.toggleLauncher` 判断当前可见状态
4. 调用 `openLauncher` 或 `closeLauncher`

Launcher 搜索流程：

1. 输入变化 -> `LauncherViewModel.$query`（debounce）
2. `performSearch`
3. 根据模式调用 `performLauncherSearch` 或 `performClipboardSearch`
4. Launcher 模式合并 App 搜索结果与窗口命令
5. Clipboard 模式调用剪贴板搜索
6. 更新结果并维护选中项

剪贴板采集流程：

1. 定时轮询 `NSPasteboard.changeCount`
2. 发现变化后识别文本/图片
3. 写入 DB 与图片缓存目录
4. 异步刷新 `history` 给 UI

剪贴板回贴流程：

1. 剪贴板热键或 Launcher 进入剪贴板模式
2. 捕获当前前台 App
3. 用户选择剪贴板项
4. 写入系统剪贴板
5. 关闭 Launcher 面板但不清掉焦点恢复链路
6. 重新激活之前的 App
7. 发送 `Command + V`

应用快捷启动流程：

1. 用户在设置页维护 App 快捷键
2. `AppLauncherManager` 保存到配置目录的 `preferences.json`
3. 刷新 HotKey 注册
4. 触发后判断 App 是否运行
5. 未运行则启动，已运行则激活或隐藏

## 8. 数据与配置

配置目录：

1. 默认目录：`~/Library/Application Support/xxMac`
2. 可在“通用 > 配置”里修改，切换后会迁移当前配置、应用索引缓存、剪贴板数据库和图片缓存，并删除旧目录中的 xxMac 数据。
3. `UserDefaults` 只保留启动定位指针 `ConfigDirectoryPath`；首次迁移会从旧 `UserDefaults` 拷贝已知配置键。

配置目录文件：

1. `manifest.json`：配置目录元信息
2. `preferences.json`：`HotKeyConfigurations`、`AppSearchPaths`、`AppLauncherShortcuts`、`ClipboardSettings`、`ShortcutDetectiveEnabled`、快捷指令、Snippets、日历和外观偏好等可配置项
3. `app-search-index.json`：应用搜索索引缓存
4. `clipboard.db`：剪贴板 SQLite 数据库
5. `clipboard_images/`：剪贴板图片缓存

导入导出边界：

1. “导出配置”只导出 `preferences.json` 中的可配置设置。
2. 不导出剪贴板历史记录、SQLite 数据库、图片缓存或应用索引缓存。
3. 完整迁移使用配置目录切换。

打包产物：

1. `bundle_app.sh` 构建 `.build/arm64-apple-macosx/debug/xxMac`
2. 生成 `xxMac.app`
3. 拷贝 `Info.plist`、图标和本地化资源
4. 默认 ad-hoc 签名，可通过 `SIGNING_IDENTITY` 覆盖

## 9. 已知风险

1. `ClipboardSettings` 中的天数和图片大小参数需要继续核对清理策略是否完全生效。
2. `AppSearchManager.scanApplications()` 已使用 `subpathsOfDirectory` 深层扫描，但大目录扫描仍可能带来启动期压力。
3. Launcher 结果 ID 由 `type + title` 组成，存在同名冲突可能，建议使用稳定唯一标识。
4. FTS 仅索引文本项；图片目前只按记录展示，不参与内容检索。
5. 大量模块通过 `NotificationCenter` 字符串事件解耦，建议集中管理事件名。
6. 剪贴板回贴依赖焦点恢复和模拟按键，不同 App 或安全设置下仍可能有边界问题。

## 10. AI / 协作者任务地图

适合优先做的任务：

1. 剪贴板清理策略：让文本保留天数、图片保留天数、图片大小上限真正驱动存储层清理。
2. 搜索体验：继续优化 App 搜索排序、最近使用、别名和拼写容错。
3. Launcher 结果 ID：避免同名应用、同名剪贴板摘要导致冲突。
4. 事件常量化：把 `ToggleLauncher`、`CloseLauncher` 等通知名集中定义。
5. 设置页补全：把仍显示占位的搜索通用、排除项、窗口行为、吸附区、剪贴板历史、忽略项补成真实配置。
6. 回归验证：为模型、搜索排序、数据库存储和设置序列化补单元测试。

新增能力建议：

1. 系统 API 相关能力先放进 `Managers/`。
2. 与 Launcher 集成时统一输出 `SearchItem`。
3. 持久化数据保持 UserDefaults 与 SQLite/文件的边界清晰。
4. 涉及热键的功能统一经过 `HotkeyManager` 或独立 Manager 管理生命周期。
5. 涉及 UI 的改动优先保持现有三栏设置结构，不把业务逻辑堆进 View。
