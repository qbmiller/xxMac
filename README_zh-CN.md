# xxMac

简体中文 | [English](README.md)

xxMac 是一个安装包约 2 MB 的轻量级 macOS 原生状态栏效率工具，基于 `SwiftUI + AppKit` 构建，支持窗口管理、全局快捷键、启动器、中国日历、快捷键冲突定位、剪贴板历史与常用工作流。它把日常高频操作整合到一个轻量入口里，日常使用形态是：

1. 右上角状态栏入口（默认显示，可在“通用 > 配置”里关闭或重新开启）。
2. 全局热键唤起的浮动启动器面板。
3. 双击打开 App 时显示三栏结构的设置窗口，窗口支持拉伸并可拖拽调整栏目宽度。

## 功能概览

| 能力 | 说明 | 类似/替代 |
| --- | --- | --- |
| 启动器 | 通过全局热键打开半透明浮层，搜索应用、执行窗口命令、选择剪贴板历史；支持最近操作历史、键盘翻页选择、自定义底色、透明度、内容大小和窗口宽高。面板可拖动背景调整位置，并记住上次拖动后的位置。 | Alfred / Spotlight |
| 启动器计算器 | 在启动器搜索栏直接输入 `4+8`、`(2+3)*4`、`-3.5/2` 等四则运算表达式，实时显示计算结果，回车复制结果。 | Alfred Calculator / Spotlight |
| 应用快捷启动 | 为指定 App 绑定独立热键，支持启动、激活、隐藏切换。 | Thor |
| 窗口管理 | 快捷操作窗口左右半屏、上下半屏、四角、居中、最大化、缩放、跨屏移动等。需要在“系统设置 > 隐私与安全性 > 辅助功能”中授权；重新打包或移动 App 后，需要删除旧 App 授权并重新添加当前 App。 | ShiftIt |
| Finder 粘贴操作 | 在 Finder 里复制文件或文件夹后，可在 Finder 以外的前台应用中按 `Command + Shift + V` 粘贴完整路径，适合终端、编辑器、聊天窗口等场景。在 Finder 内使用同一快捷键可将剪贴板原始图片或文本保存为文件；若剪贴板是文件则忽略，避免把长路径逐字输入 Finder。 | Copy Path / Path Finder |
| 中国日历 | 提供右上角状态栏入口，支持中国农历、节假日、节气、周数和状态栏图标样式配置。 | CalendarX |
| 快捷键捕捉 | 记录快捷键被哪个 App 接收，用于定位快捷键冲突。 | Shortcut Detective |
| 待办 | 通过独立且可调节大小的窗口管理本地任务。包含独立 2 x 2 四象限、“全部 / 今日 / 待办 / 进行中 / 已完成”视图、卡片与列表布局，以及可展开的三栏状态看板。任务支持标题、备注、四象限、精确到分钟的截止时间、搜索、编辑、归档/永久删除、状态撤回，并可在象限或状态栏内及跨栏拖动排序。已完成任务仍保留在原象限，并以划线样式显示。 | Microsoft To Do / 滴答清单 / Trello |
| 剪贴板历史 [默认关闭]| 记录文本和图片剪贴板，使用 SQLite 持久化，支持检索、预览、回贴、收藏和收藏置顶；面板默认打开“历史”，可用 Tab / Shift+Tab 在“历史 / 历史-图片 / 收藏 / Snippets”之间切换。选择“历史-图片”会在搜索栏显示 `img`，并且只展示图片。上下选择图片后按 Command+Space 可在应用自管的屏幕级预览中放大查看原图，普通空格仍可继续输入搜索词；预览支持触控板捏合缩放和平移，1 倍时拖动图片可把预览移到屏幕任意位置，放大后拖动或双指滚动可查看图片局部。再按 Command+Space 或 Esc 只关闭图片预览，剪贴板面板保持打开。Command+Return 可收藏“历史 / 历史-图片”选中项；Command+Delete 可从当前“历史 / 历史-图片 / 收藏”列表移除选中项，若已收藏项是从历史移除，则仍保留在“收藏”里；收藏页右侧红色星星负责取消收藏，pin 按钮负责在收藏列表内置顶/取消置顶。收藏后的记录不会被自动清理或手动清空历史删除，从收藏中移除时会保留原历史记录。大文本预览只显示前一部分但回贴保留完整内容；图片项会显示宽高和大小，超过阈值时生成缩略图用于预览；可选启用本地 OCR，把图片文字作为 metadata 写入数据库用于搜索。可通过自定义全局热键或菜单栏“剪贴板历史”打开，密码输入框等安全输入场景下会使用高层级浮层显示。 | 剪贴板管理器 |
| Snippets | 类似 Alfred Snippets，支持分类、条目、关键词搜索；全局热键唤起搜索面板，左侧选择条目、右侧预览内容，回车后直接向前台应用输入片段内容，并同步复制到系统剪贴板。 | Alfred Snippets |
| 快捷指令搜索 | 在启动器里用关键词触发网页搜索，例如输入自定义关键词后跟搜索词即可打开 Google、Baidu 或任意 URL 模板；也可勾选为始终显示在启动器候选中。 | Alfred Web Search |
| 快捷指令脚本 | 在启动器里用关键词执行本地命令脚本，支持无参、`{query}` 单参数和 `argv` 多参数模式；输入稳定约 400 毫秒后执行，连续输入时只执行最后一次待处理内容。复杂脚本可放在配置目录的 `quick/` 下复用。 | Alfred Workflows |
| 浏览器搜索 | 在启动器中用 `bm` 搜索当前 Chrome/Edge Profile 的书签，用 `bh` 搜索历史记录；浏览器和两个关键词均可在“搜索 > 浏览器搜索”配置。 | Alfred Browser Bookmarks |
| 更新检查 | 可在“关于”中手动检查，也可选择关闭、每天、每周或每月自动检查，默认每周。“关于”页显示的 GitHub Releases 地址可点击并由默认浏览器打开。自动检查不会弹窗；发现新版本后，启动器右侧显示红色更新按钮，点击打开 GitHub Releases。 | Sparkle |
| LockJob | 一键遮住所有屏幕并阻止系统睡眠，Claude、Codex、构建、下载和 SSH 会话继续运行；显示时间和自定义状态文字，支持 Touch ID 或本机密码解锁。 | 锁屏遮罩 |
| 多语言 | 已有简体中文、繁体中文、英文资源结构。 | - |

<p align="center">
  <img src="docs/images/003.png" width="49%" alt="">
  <img src="docs/images/004.png" width="49%" alt="">
</p>

<p align="center">
  <img src="docs/images/005.png" width="49%" alt="">
  <img src="docs/images/006.png" width="49%" alt="">
</p>

<p align="center">
  <img src="docs/images/007.png" width="49%" alt="">
  <img src="docs/images/008.png" width="49%" alt="">
</p>

<p align="center">
  <img src="docs/images/009.png" width="49%" alt="">
  <img src="docs/images/010.png" width="49%" alt="">
</p>

<p align="center">
  <img src="docs/images/image.png" width="45%" alt="">
</p>

## 友情链接
- [亚洲规模最大的大模型 API 网关之一，全球规模仅次于 OpenRouter](https://www.orcarouter.ai/ref/ref_d47b119eebf4f9e2efd8)也长期提供免费模型使用

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
| `Command + Shift + V` | 将 Finder 中复制的文件/文件夹粘贴为完整路径 |
| `Command + Option + T` | 打开或关闭独立待办窗口 |

这些快捷键都可以在设置窗口里调整。xxMac 会统一检查窗口管理、通用、应用启动、剪贴板和 Snippets 的快捷键，拒绝保存应用内部的重复组合；启动器文本关键词在独立的命名空间中检查冲突。

启动器搜索到应用后，可用 `↑/↓` 或 `Page Up/Page Down` 选择结果，直接按 `Return` 打开应用；输入 `4+8`、`(2+3)*4` 等四则运算表达式时会显示计算结果，按 `Return` 复制结果；按住 `Command` 时选中行会显示 `Reveal in Finder`，此时按 `Return` 会在 Finder 中定位该应用文件。启动器会记录最近执行的应用、窗口命令、快捷指令和计算器结果，默认最多 100 条，可在“搜索 > 通用”调整或清空；空查询时默认显示配置为“始终显示在启动器候选中”的快捷指令，直接按方向键会切换到最近操作历史，并在顶部输入框显示当前选中的完整输入。剪贴板历史和 Snippets 不会写入该记录。

浏览器搜索首次根据 macOS 默认浏览器选择 Chrome 或 Microsoft Edge，之后可在设置中手动覆盖。xxMac 读取浏览器 `Local State` 中最近使用的 Profile；首版不合并或提供 Profile 选择。默认输入 `bm 关键词` 搜索书签、`bh 关键词` 搜索历史，只输入 `bm` 或 `bh` 可查看候选；两个关键词都可以自定义，并且不能彼此重复或与已启用的快捷指令重复。回车始终使用设置中选择的浏览器打开结果。

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
```

打包完成后脚本会询问是否覆盖 `/Applications/xxMac.app`，默认不覆盖。输入 `y` 或 `yes` 后，脚本会自动关闭当前运行的 xxMac，复制新应用覆盖旧应用，并重新打开；也可以使用 `INSTALL_TO_APPLICATIONS=1 bash bundle_app.sh` 跳过确认并自动覆盖。

发布为 `.dmg`：

```bash
bash publish_dmg.sh
```

发布脚本会先打印 `Sources/xxMac/Info.plist` 中记录的当前版本号，并提示输入本次发布版本。版本会写回 `CFBundleShortVersionString` 和 `CFBundleVersion`，最近更新时间会写回 `XXLastUpdated`，生成的 DMG 默认命名为 `xxMac-版本号.dmg`。

输入版本号后，可以选择是否直接发布 GitHub Release。启用后，脚本会先检查 `gh auth status`、提示输入发布标题，然后使用 `${VISUAL:-${EDITOR:-vi}}` 打开临时 Markdown 文件。编辑器退出后会预览发布说明：输入 `e` 可再次编辑，输入 `y` 确认使用，输入 `n` 则取消 GitHub 发布但继续构建本地 DMG。使用 VS Code 时可设置 `EDITOR='code --wait'`。完成 DMG 构建与校验后，脚本会显示最终摘要，再调用 `gh release create`。登录失效时先执行 `gh auth login -h github.com`。脚本不会自动执行 `git commit` 或 `git push`；如果数字版本标签尚不存在，GitHub 会从默认分支的最新提交创建该标签。

`bundle_app.sh` 和 `publish_dmg.sh` 默认使用固定签名身份 `qbmiller`，不允许退回 ad-hoc 签名。这样可以让 macOS 辅助功能权限尽量绑定到稳定的 App 身份，减少重新打包后需要删除旧授权并重新添加的情况。需要临时换证书时，可以通过 `SIGNING_IDENTITY` 环境变量覆盖。

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

可在 xxMac 的“通用 > 权限设置”中查看辅助功能授权状态，并点击“获取辅助功能权限”打开 macOS 对应授权入口。

如果窗口控制、全局热键或剪贴板回贴在重新打包后失效，优先检查系统“辅助功能”列表里授权的是否是当前路径下的 `xxMac.app`，并确认发布包使用同一个 `SIGNING_IDENTITY` 签名。macOS 的辅助功能授权会受 App 路径和签名状态影响，重新打包或移动 App 后可能需要删除旧授权并重新添加。

## 配置与数据

- 默认配置目录是 `~/Library/Application Support/xxMac`，可在“通用 > 配置”里修改。修改后会把当前配置、应用索引缓存、剪贴板 SQLite 数据库、待办 SQLite 数据库和图片缓存迁移到新目录，并删除旧目录中的 xxMac 数据。
- 右上角状态栏入口默认显示；如果图标异常消失，或希望隐藏状态栏入口，可在“通用 > 配置”里切换“显示在右上角状态栏”。该区域提供状态栏诊断信息和“刷新/重建”按钮，用于确认 `NSStatusItem` 是否已创建、可见并挂载到系统状态栏。
- 配置目录可以是本地目录，也可以是 iCloud Drive、Dropbox 等同步服务下保持本地可用的目录；不建议选择系统目录、App 包内目录或临时移动磁盘路径。
- 热键配置、应用快捷启动配置、启动器窗口宽高、整体大小、文字大小与外观、启动器最近操作历史、语言偏好（包括“打开启动器时使用英文输入法”，默认关闭）、快捷指令、浏览器搜索、Snippets、日历偏好和更新检查状态保存在配置目录的 `preferences.json`。启用该语言选项后，启动器打开时会切换到 macOS ABC 英文输入法。更新检查会保存 `UpdateCheckFrequency`、`UpdateLastSuccessfulCheck` 和 `UpdateAvailableVersion`，首次使用默认每周检查。启动器最近操作历史只记录应用、窗口命令、快捷指令和计算器结果的元数据，不记录剪贴板历史或 Snippets 内容；默认最多保留 100 条，可在“搜索 > 通用”配置。日历偏好包含状态栏显示方式，默认使用日历图标，也可切换为 App 图标。首次启动默认值集中在 `Sources/xxMac/AppDefaultSettings.swift`，该文件可用注释说明默认开关。
- 配置目录下会自动创建 `quick/`，用于放置复杂快捷指令脚本。命令脚本执行时会注入 `XXMAC_HOME`（配置目录）和 `XXMAC_QUICK_HOME`（`quick/` 目录），例如 `python "$XXMAC_QUICK_HOME/xxx/a.py" {query}`。网页搜索快捷指令会把站点图标缓存到 `quick_icons/`，用于设置列表和启动器候选展示；删除快捷指令或修改为其他站点时会清理对应图标缓存。
- 应用搜索默认覆盖 `/Applications`、`/System/Applications`、`/System/Library/CoreServices`，也支持在设置里添加自定义搜索路径；重建索引时优先复用 macOS Spotlight 发现应用，Spotlight 不可用或没有返回可用结果时自动回退到目录扫描。应用索引缓存保存在配置目录的 `app-search-index.json`，加载前会校验 App bundle 是否仍存在，并过滤已删除应用和 `.app.installing` 临时安装路径。把新 App 拖入这些搜索目录后会自动追加到现有索引，移除 App 后也会剪掉旧索引，不会重建整个索引；也可在“通用 > 配置”里手动点击“索引应用”重建。中文应用名会同时写入原文、全拼和拼音首字母索引；英文应用名也会写入单词首字母索引。
- 浏览器书签和历史数据库保持在 Chrome/Edge 自己的目录中，xxMac 仅在本机只读访问。历史搜索会在系统临时目录创建唯一副本并在查询结束后立即删除；这些数据不会写入、导出或随迁移进入 xxMac 配置目录。
- 剪贴板数据库、图片原图缓存与图片缩略图缓存位于配置目录的 `clipboard.db`、`clipboard_images/` 和 `clipboard_thumbnails/`；剪贴板收藏状态、收藏置顶状态和历史可见状态也保存在 `clipboard.db`，仍在历史中可见的项目从收藏中移除时只取消收藏并清掉收藏置顶，不删除原历史记录。
- 待办任务保存在配置目录的本地 `todo.db` 中；修改配置目录时会连同 SQLite 辅助文件一起迁移。首版不支持 iCloud 或 CloudKit 同步。
- 剪贴板历史会记录系统剪贴板中出现的所有非空文本；如果浏览器或密码管理器允许把密码复制到系统剪贴板，也会被记录。若网页或应用没有真正写入系统剪贴板，则 xxMac 无法采集。
- “导出配置”只导出可配置设置，不导出待办任务、`todo.db`、剪贴板历史记录、`clipboard.db`、图片缓存、缩略图缓存、快捷指令站点图标缓存或应用索引缓存；完整迁移请使用配置目录切换。
- “通用 > 配置”底部提供退出应用按钮，退出前会二次确认。
- 剪贴板历史最多保留条数、图片缓存总量和右侧文本预览字体大小可在“剪贴板通用”中配置，默认分别为 1000 条、500 MB 和 16 pt。
- 图片超过“生成缩略图”阈值时才会创建缩略图，默认阈值为 5 MB，可在“剪贴板通用”中调整。
- 图片 OCR 默认关闭；启用后使用 macOS Vision 在本机识别图片文字，不上传图片。OCR 文本存入 `clipboard.db` 作为图片 metadata，用于剪贴板搜索；“导出配置”不导出 OCR 历史 metadata。
- 设置窗口第一列是带彩色图标的工具分类，左上角显示当前方案；第二列是功能项，第三列是具体配置。现阶段所有用户均显示 Free，后续接入付费会员后可根据状态切换为 VIP。

## 目录结构

```text
xxMac/
├── Package.swift
├── README.md
├── README_zh-CN.md
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
