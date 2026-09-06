# 打包与发布排障

本文档只记录打包、DMG 发布和 macOS 权限排障细节。项目介绍、功能列表和日常命令见 `README.md`。

## App 打包

```bash
bash bundle_app.sh
```

脚本会生成 `xxMac.app`：

- 默认使用固定签名身份 `qbmiller`，可通过 `SIGNING_IDENTITY` 覆盖。
- 从 `Sources/xxMac/Info.plist` 拷贝应用元信息。
- 从 `Resources/` 拷贝图标、本地化和日历数据。
- 构建并嵌入 `Contents/PlugIns/TodoWidgetExtension.appex`。
- 先签名 Widget Extension，再签名主应用，并校验嵌套签名。

指定开发者签名：

```bash
SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" bash bundle_app.sh
```

## Todo Widget 打包要求

Todo 桌面小组件位于独立的 `TodoWidget/` Xcode 工程中。主应用仍由 SwiftPM 构建，只有扩展由 `bundle_app.sh` 调用 `xcodebuild`。

主应用与扩展必须同时包含 App Group `group.com.xiaomi318.xxMac`，扩展还必须启用 App Sandbox。两者应使用同一签名身份；缺少 App Group、扩展产物或嵌套签名校验失败时，脚本会直接终止。

可用以下命令复核生成物：

```bash
codesign --verify --deep --strict --verbose=2 xxMac.app
codesign -d --entitlements :- xxMac.app
codesign -d --entitlements :- xxMac.app/Contents/PlugIns/TodoWidgetExtension.appex
plutil -p xxMac.app/Contents/PlugIns/TodoWidgetExtension.appex/Contents/Info.plist
```

系统只有在安装应用后才会注册其中的 Widget Extension。不要把“扩展构建成功”等同于桌面小组件已完成系统验收；仍需在 macOS 14 或更高版本的“编辑小组件”中找到 Todo，并手动添加中号组件验证。

## DMG 发布

```bash
bash publish_dmg.sh
```

`bundle_app.sh` 和 `publish_dmg.sh` 默认使用固定签名身份 `qbmiller`，不支持使用 ad-hoc 签名。发布脚本会校验生成的 `xxMac.app` 不是 ad-hoc 签名，并包含证书要求，避免 macOS 把重新打包后的 App 当成新的辅助功能授权主体。需要临时换证书时，可以通过 `SIGNING_IDENTITY` 环境变量覆盖。

脚本会：

1. 读取并打印 `Sources/xxMac/Info.plist` 中的当前版本。
2. 提示输入本次发布版本。
3. 写回 `CFBundleShortVersionString` 和 `CFBundleVersion`。
4. 写回 `XXLastUpdated`，关于页会显示这个最近更新时间。
5. 调用 `bundle_app.sh` 重新生成 `xxMac.app`。
6. 创建包含 `xxMac.app` 和 `Applications` 快捷方式的压缩 DMG。
7. 执行 `hdiutil verify` 校验镜像。
8. 选择发布 GitHub Release 时，使用 `${VISUAL:-${EDITOR:-vi}}` 编辑并预览发布说明；输入 `e` 可反复修改，输入 `y` 确认，输入 `n` 取消 GitHub 发布但继续保留本地 DMG 构建流程。

版本号也可以通过环境变量传入：

```bash
VERSION=0.0.1 bash publish_dmg.sh
```

只用现有 `xxMac.app` 重新生成 DMG：

```bash
SKIP_BUILD=1 bash publish_dmg.sh
```

覆盖输出文件名或挂载卷名：

```bash
DMG_NAME="xxMac-0.0.1.dmg" VOLUME_NAME="xxMac" bash publish_dmg.sh
```

## 版本记录

版本源文件是 `Sources/xxMac/Info.plist`：

- `CFBundleShortVersionString`：展示版本号，关于页读取这个字段。
- `CFBundleVersion`：构建版本号，发布脚本会同步写成同一个版本。
- `XXLastUpdated`：最近更新时间，发布脚本会写入当天日期，关于页读取这个字段。

## 权限排障

首次运行打包后的 App，需要在系统设置里授予辅助功能权限：

1. 打开 System Settings。
2. 进入 Privacy & Security。
3. 进入 Accessibility。
4. 添加并启用当前路径下的 `xxMac.app`。

重新打包或移动 App 后，如果快捷键、窗口控制或剪贴板回贴失效，优先检查 Accessibility 列表里授权的是否是当前路径下的 `xxMac.app`，并确认每次发布使用同一个 `SIGNING_IDENTITY`。必要时删除旧条目后重新添加。

## 常用排障命令

检查签名：

```bash
codesign -v xxMac.app
```

查看 Gatekeeper 评估：

```bash
spctl --assess --type execute --verbose xxMac.app
```

查看进程：

```bash
ps aux | grep xxMac
```

查看日志：

```bash
log stream --style compact --predicate 'process == "xxMac"'
```

清理隔离属性：

```bash
xattr -cr /Applications/xxMac.app
```
