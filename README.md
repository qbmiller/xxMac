# xxMac

简体中文 | [English](README_en.md)

xxMac 是一个基于 `SwiftUI + AppKit` 的 macOS 原生菜单栏效率工具。它把启动器、应用快捷启动、窗口管理、中国日历、快捷键冲突定位和剪贴板历史整合到一个轻量入口里，日常使用形态是：

1. 菜单栏入口（默认显示，可在“通用 > 配置”里关闭或重新开启）。
2. 全局热键唤起的浮动启动器面板。
3. 三栏结构的设置窗口。

## 产品截图

<table>
  <tr>
    <td width="25%" align="center"><img src="docs/images/image.png" alt="xxMac 截图 1" width="100%"><br>1</td>
    <td width="25%" align="center"><img src="docs/images/image2.png" alt="xxMac 截图 2" width="100%"><br>2</td>
    <td width="25%" align="center"><img src="docs/images/image3.png" alt="xxMac 截图 3" width="100%"><br>3</td>
    <td width="25%" align="center"><img src="docs/images/image4.png" alt="xxMac 截图 4" width="100%"><br>4</td>
  </tr>
</table>

## 功能概览

| 能力 | 说明 | 类似/替代 |
| --- | --- | --- |
| 启动器 | 通过全局热键打开半透明浮层，搜索应用、执行窗口命令、选择剪贴板历史，支持自定义底色、透明度、内容大小和窗口宽高。 | Alfred / Spotlight |
| 应用快捷启动 | 为指定 App 绑定独立热键，支持启动、激活、隐藏切换。 | Thor |
| 窗口管理 | 快捷操作窗口左右半屏、上下半屏、四角、居中、最大化、缩放、跨屏移动等。需要在“系统设置 > 隐私与安全性 > 辅助功能”中授权；重新打包或移动 App 后，需要删除旧 App 授权并重新添加当前 App。 | ShiftIt |
| 中国日历 | 菜单栏显示日期，支持中国农历、节假日、节气、周数和菜单栏样式配置。 | CalendarX |
| 快捷键捕捉 | 记录快捷键被哪个 App 接收，用于定位快捷键冲突。 | Shortcut Detective |
| 剪贴板历史 [默认关闭]| 记录文本和图片剪贴板，使用 SQLite 持久化，支持检索、预览和回贴；图片项会显示宽高和大小，并可通过 `image` / `images` 搜索。可通过自定义全局热键或菜单栏“剪贴板历史”打开，密码输入框等安全输入场景下会使用高层级浮层显示。 | 剪贴板管理器 |
| Snippets | 类似 Alfred Snippets，支持分类、条目、关键词搜索；全局热键唤起搜索面板，左侧选择条目、右侧预览内容，回车后直接向前台应用输入片段内容，并同步复制到系统剪贴板。 | Alfred Snippets |
| 快捷指令 | 在启动器里用关键词触发网页搜索或命令脚本，命令脚本支持无参、`{query}` 单参数和 `argv` 多参数模式；也可勾选为始终显示在启动器候选中，适合 Google、Baidu 等搜索入口。 | Alfred Web Search / Workflows |
| LockJob | 一键遮住所有屏幕并阻止系统睡眠，Claude、Codex、构建、下载和 SSH 会话继续运行；显示时间和自定义状态文字，支持 Touch ID 或本机密码解锁。 | caffeinate + 锁屏遮罩 |
| 多语言 | 已有简体中文、繁体中文、英文资源结构。 | - |

## 默认快捷键

| 快捷键 | 动作 |
| --- | --- |
| `Control + Option + Space` | 打开或关闭启动器 |
| `Control + Option + Command + ←/→/↑/↓` | 当前窗口左右/上下半屏 |
| `Control + Option + Command + 1/2/3/4` | 当前窗口移动到四角 |
| `Control + Option + Command + C` | 当前窗口居中 |
| `Control + Option + Command + M` | 当前窗口最大化 |
| `Control + Option + Command + F` | 切换全屏 |
| `Control + Option + Command + =/-` | 放大或缩小窗口 |
| `Control + Option + Command + N/P` | 移动到下一块/上一块屏幕 |
| `Control + Option + Command + L` | LockJob：遮住屏幕并保持运行 |
| `Control + Option + Command + X` | 打开 Snippets 搜索 |

这些快捷键都可以在设置窗口里调整。

启动器搜索到应用后，直接按 `Return` 打开应用；按住 `Command` 时选中行会显示 `Reveal in Finder`，此时按 `Return` 会在 Finder 中定位该应用文件。

## 快速开始

前置要求：

1. macOS 13 或更新版本。
2. Xcode Command Line Tools 或 Xcode。
3. Swift 5.9 兼容工具链。

开发运行：

```bash
swift build
swift run xxMac
```

打包为 `.app`：

```bash
bash bundle_app.sh
open xxMac.app
```

发布为 `.dmg`：

```bash
bash publish_dmg.sh
```

发布脚本会先打印 `Sources/xxMac/Info.plist` 中记录的当前版本号，并提示输入本次发布版本。版本会写回 `CFBundleShortVersionString` 和 `CFBundleVersion`，最近更新时间会写回 `XXLastUpdated`，生成的 DMG 默认命名为 `xxMac-版本号.dmg`。

`bundle_app.sh` 和 `publish_dmg.sh` 默认使用固定签名身份 `qbmiller-dev`，不允许退回 ad-hoc 签名。这样可以让 macOS 辅助功能权限尽量绑定到稳定的 App 身份，减少重新打包后需要删除旧授权并重新添加的情况。需要临时换证书时，可以通过 `SIGNING_IDENTITY` 环境变量覆盖。

如果没有开发者账号，App 拷贝到 `/Applications` 后可能会被 macOS 标记为隔离来源，导致打不开。可以先清理隔离属性再启动：

```bash
xattr -cr /Applications/xxMac.app
open /Applications/xxMac.app
```

如果要使用开发者证书签名：

```bash
SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" bash bundle_app.sh
```

## 系统权限

首次运行后，需要在“系统设置 > 隐私与安全性”里授予权限：

1. 辅助功能权限：窗口管理、全局热键、模拟粘贴依赖它。
2. 自动化权限：应用激活、重开窗口和剪贴板回贴链路可能用到。

如果窗口控制、全局热键或剪贴板回贴在重新打包后失效，优先检查系统“辅助功能”列表里授权的是否是当前路径下的 `xxMac.app`，并确认发布包使用同一个 `SIGNING_IDENTITY` 签名。macOS 的辅助功能授权会受 App 路径和签名状态影响，重新打包或移动 App 后可能需要删除旧授权并重新添加。

## 配置与数据

- 默认配置目录是 `~/Library/Application Support/xxMac`，可在“通用 > 配置”里修改。修改后会把当前配置、应用索引缓存、剪贴板 SQLite 数据库和图片缓存迁移到新目录，并删除旧目录中的 xxMac 数据。
- 菜单栏入口默认显示；如果图标异常消失，或希望隐藏菜单栏入口，可在“通用 > 配置”里切换“显示在菜单栏里”，重新勾选会立即重建菜单栏图标。
- 配置目录可以是本地目录，也可以是 iCloud Drive、Dropbox 等同步服务下保持本地可用的目录；不建议选择系统目录、App 包内目录或临时移动磁盘路径。
- 热键配置、应用快捷启动配置、启动器窗口宽高、整体大小、文字大小与外观、语言偏好、快捷指令、Snippets 和日历偏好保存在配置目录的 `preferences.json`。
- 配置目录下会自动创建 `quick/`，用于放置复杂快捷指令脚本。命令脚本执行时会注入 `XXMAC_HOME`（配置目录）和 `XXMAC_QUICK_HOME`（`quick/` 目录），例如 `python "$XXMAC_QUICK_HOME/xxx/a.py" {query}`。
- 应用搜索默认扫描 `/Applications`、`/System/Applications`、`/System/Library/CoreServices`，也支持在设置里添加自定义搜索路径；应用索引缓存保存在配置目录的 `app-search-index.json`，也可在“通用 > 配置”里手动点击“索引应用”重建。中文应用名会同时写入原文、全拼和拼音首字母索引；英文应用名也会写入单词首字母索引。
- 剪贴板数据库与图片缓存位于配置目录的 `clipboard.db` 和 `clipboard_images/`。
- “导出配置”只导出可配置设置，不导出剪贴板历史记录、SQLite 数据库、图片缓存或应用索引缓存；完整迁移请使用配置目录切换。
- 剪贴板历史最多保留条数和图片缓存总量可在“剪贴板通用”中配置，默认分别为 1000 条和 500 MB。
- 设置窗口第一列是工具分类，第二列是功能项，第三列是具体配置。

## 目录结构

```text
xxMac/
├── Package.swift
├── README.md
├── PACKAGING_GUIDE.md
├── bundle_app.sh
├── publish_dmg.sh
├── Resources/
│   ├── AppIcon.icns
│   ├── *.lproj/
│   └── calendar_*.json
├── Sources/xxMac/
│   ├── xxMac.swift
│   ├── Managers/
│   ├── Models/
│   ├── ViewModels/
│   └── Views/
└── docs/
    ├── images/
    └── ARCHITECTURE.md
```

## 常用命令

```bash
swift build
swift run xxMac
bash bundle_app.sh
bash publish_dmg.sh
VERSION=0.0.1 bash publish_dmg.sh
xattr -cr /Applications/xxMac.app
log stream --style compact --predicate 'process == "xxMac"'
codesign -v xxMac.app
```

## 文档

- `docs/ARCHITECTURE.md`：项目架构、模块职责、运行流程、数据配置和后续任务地图。
- `docs/secure-input-overlay.md`：密码输入框等安全输入场景下剪贴板历史和 Snippets 浮层唤起方案。
- `PACKAGING_GUIDE.md`：打包、签名、权限、日志和快捷键排障。
