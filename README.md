# xxMac

xxMac 是一个基于 `SwiftUI + AppKit` 的 macOS 原生效率工具，当前围绕三类桌面高频能力提供统一入口：

1. 启动器：通过全局热键打开浮层，搜索并启动应用、执行窗口命令、选择剪贴板历史。
2. 窗口管理：提供类似 ShiftIt 的左右半屏、上下半屏、四角、居中、最大化、跨屏移动等操作。
3. 剪贴板历史：记录文本和图片剪贴板，使用 SQLite 持久化，并支持从启动器中检索和回贴。

项目运行形态是菜单栏应用 + 浮动启动器面板 + 三栏设置窗口。设置窗口第一列是工具分类，第二列是功能项，第三列是具体配置。

## 快速开始

可选打包：

```bash
bash bundle_app.sh
```

首次运行后，需要在“系统设置 > 隐私与安全性”里授予：

1. 辅助功能权限：窗口管理、全局热键、模拟粘贴依赖它。
2. 自动化权限：应用激活、重开窗口和剪贴板回贴链路可能用到。

## 当前功能

- 全局启动器热键：默认 `Control + Option + Space`。
- 窗口管理热键：默认 `Control + Option + Command + 方向键/数字键/M/C/N/P`。
- 应用搜索：扫描 `/Applications`、`/System/Applications`、`/System/Library/CoreServices`，并支持自定义搜索路径。
- 应用快捷启动：为指定 App 绑定独立热键，支持启动、激活、隐藏切换。
- 剪贴板历史：支持文本和图片记录、基础检索、选中后一键回贴。
- Shortcut Detective：记录快捷键被哪个 App 接收，用于定位快捷键冲突。
- 多语言：已有简体中文、繁体中文、英文资源结构。
- 日历

## 目录结构

```text
xxMac/
├── Package.swift
├── README.md
├── PACKAGING_GUIDE.md
├── bundle_app.sh
├── Resources/
├── Sources/xxMac/
│   ├── xxMac.swift
│   ├── Managers/
│   ├── Models/
│   ├── ViewModels/
│   └── Views/
└── docs/
    └── ARCHITECTURE.md
```

## 文档

- `docs/ARCHITECTURE.md`：项目架构、模块职责、运行流程、后续任务地图。
- `PACKAGING_GUIDE.md`：打包、签名、权限、日志和快捷键排障。

## 常用命令

```bash
swift build
swift run xxMac
bash bundle_app.sh
log stream --style compact --predicate 'process == "xxMac"'
```

如果窗口控制、全局热键或剪贴板回贴在重新打包后失效，优先检查系统“辅助功能”列表里授权的是否是当前路径下的 `xxMac.app`。
