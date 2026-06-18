# 打包、权限和快捷键排障

## 打包应用

运行打包脚本：
```bash
bash bundle_app.sh
```

这会生成 `xxMac.app`，其中包括：

- 代码签名：默认 ad-hoc 签名，使用 `-` 作为签名标识。
- Info.plist：从 `Sources/xxMac/Info.plist` 拷贝。
- 资源：拷贝 `Resources/` 下的图标和本地化文件。

如果要指定签名身份：

```bash
SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" bash bundle_app.sh
```

## 打包 DMG

生成可分发的 DMG：

```bash
bash publish_dmg.sh
```

脚本会先调用 `bundle_app.sh` 重新生成 `xxMac.app`，再创建包含 `xxMac.app` 和 `Applications` 快捷方式的压缩镜像，并执行校验。生成文件默认是 `xxMac.dmg`。

如果已经有现成的 `xxMac.app`，只想重新生成 DMG：

```bash
SKIP_BUILD=1 bash publish_dmg.sh
```

可通过环境变量覆盖输出名：

```bash
DMG_NAME="xxMac-0.0.1.dmg" VOLUME_NAME="xxMac" bash publish_dmg.sh
```

## 没有开发者账号时打不开 App

如果使用默认 ad-hoc 签名，且把 `xxMac.app` 拷贝到了 `/Applications`，macOS 可能会因为隔离属性阻止打开。先清理隔离属性，再重新打开：

```bash
xattr -cr /Applications/xxMac.app
open /Applications/xxMac.app
```

如果 App 不在 `/Applications`，把命令里的路径替换成实际的 `xxMac.app` 路径。

## 快捷键不工作的解决方案

打包后，快捷键可能不会立即工作。优先按下面顺序检查。

### 1. 授予辅助功能权限

首次运行打包的 App 时，系统通常会弹出权限提示。如果没有看到，手动操作：

1. 打开 System Settings。
2. 进入 Privacy & Security。
3. 进入 Accessibility。
4. 添加并启用当前路径下的 `xxMac.app`。

### 2. 重启应用

关闭并重新打开 `xxMac.app`，快捷键应该开始工作。

### 3. 验证默认快捷键

默认快捷键：

- `Control + Option + Space`：打开启动器。
- `Control + Option + Command + ←/→/↑/↓`：窗口左右上下半屏。
- `Control + Option + Command + 1/2/3/4`：窗口四角。
- `Control + Option + Command + M`：最大化。
- `Control + Option + Command + C`：居中。
- `Control + Option + Command + N/P`：移动到下一块/上一块屏幕。

## 如果快捷键仍然不工作

### 原因 1：权限授给了旧路径

macOS 的辅助功能权限和 App 路径、签名状态有关。如果重新打包后换了路径，或同名 App 有多个副本，系统可能仍信任旧条目。

处理方式：

1. 在 Accessibility 列表里删除旧的 `xxMac`。
2. 重新添加当前打包出来的 `xxMac.app`。
3. 尽量固定 App 路径，不要频繁换目录运行。

### 原因 2：代码签名失败

```bash
codesign -v xxMac.app
```

如果出错，重新运行打包脚本。脚本默认使用 ad-hoc 签名；生产分发时应使用正式开发者签名。

### 原因 3：进程没有运行或运行的不是当前包

```bash
ps aux | grep xxMac
```

## 开发环境 vs 打包环境

| 场景 | 命令 | 权限设置 | 快捷键 |
|-----|------|--------|------|
| 开发 | `swift run xxMac` | 请求时授予 | 通常立即工作 |
| 打包 | `bash bundle_app.sh` | 常需手动授予 | 重启后工作 |
| 分发 | 开发者签名 + 公证 | 系统提示更稳定 | 更适合长期使用 |

## Info.plist 关键字段

已添加的权限请求：

- `NSAccessibilityUsageDescription` - 窗口管理权限
- `NSAppleEventsUsageDescription` - AppleScript/事件权限
- `CFBundleVersion` 和 `CFBundleShortVersionString` - 版本信息
- `LSUIElement=true` - 隐藏在 Dock 中（菜单栏应用）

## 日志和排障命令

查看 App 日志：

```bash
log stream --style compact --predicate 'process == "xxMac"'
```

检查签名：

```bash
codesign -v xxMac.app
```

检查进程：

```bash
ps aux | grep xxMac
```

清理隔离属性：

```bash
xattr -cr /Applications/xxMac.app
```

## 下次打包时

修改代码后重新打包：

```bash
rm -rf xxMac.app
bash bundle_app.sh
```

然后重新启动应用。如果系统仍指向旧授权，删除旧辅助功能条目并重新添加当前 `xxMac.app`。
