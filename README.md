# xxMac

简体中文 | [English](README_en.md)

xxMac 是一个基于 `SwiftUI + AppKit` 的 macOS 原生菜单栏效率工具。它把启动器、应用快捷启动、窗口管理、中国日历、快捷键冲突定位和剪贴板历史整合到一个轻量入口里，日常使用形态是：

1. 菜单栏常驻入口。
2. 全局热键唤起的浮动启动器面板。
3. 三栏结构的设置窗口。

## 功能概览

| 能力 | 说明 | 类似/替代 |
| --- | --- | --- |
| 启动器 | 通过全局热键打开半透明浮层，搜索应用、执行窗口命令、选择剪贴板历史，支持自定义底色、透明度、内容大小和窗口宽高。 | Alfred / Spotlight |
| 应用快捷启动 | 为指定 App 绑定独立热键，支持启动、激活、隐藏切换。 | Thor |
| 窗口管理 | 快捷操作窗口左右半屏、上下半屏、四角、居中、最大化、缩放、跨屏移动等。 | ShiftIt |
| 中国日历 | 菜单栏显示日期，支持中国农历、节假日、节气、周数和菜单栏样式配置。 | CalendarX |
| 快捷键捕捉 | 记录快捷键被哪个 App 接收，用于定位快捷键冲突。 | Shortcut Detective |
| 剪贴板历史 [默认关闭]| 记录文本和图片剪贴板，使用 SQLite 持久化，支持检索、预览和回贴。 | 剪贴板管理器 |
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

这些快捷键都可以在设置窗口里调整。

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

发布脚本会先打印 `Sources/xxMac/Info.plist` 中记录的当前版本号，并提示输入本次发布版本。版本会写回 `CFBundleShortVersionString` 和 `CFBundleVersion`，生成的 DMG 默认命名为 `xxMac-版本号.dmg`。

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

如果窗口控制、全局热键或剪贴板回贴在重新打包后失效，优先检查系统“辅助功能”列表里授权的是否是当前路径下的 `xxMac.app`。macOS 的辅助功能授权会受 App 路径和签名状态影响，重新打包或移动 App 后可能需要删除旧授权并重新添加。

## 配置与数据

- 应用搜索默认扫描 `/Applications`、`/System/Applications`、`/System/Library/CoreServices`，也支持在设置里添加自定义搜索路径。
- 热键配置、应用快捷启动配置、启动器窗口宽高与外观、语言偏好等轻量配置保存在 `UserDefaults`。
- 剪贴板数据库与图片缓存位于 `~/Library/Application Support/xxMac`。
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
- `PACKAGING_GUIDE.md`：打包、签名、权限、日志和快捷键排障。
