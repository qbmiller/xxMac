# 打包与发布排障

本文档只记录打包、DMG 发布和 macOS 权限排障细节。项目介绍、功能列表和日常命令见 `README.md`。

## App 打包

```bash
bash bundle_app.sh
```

脚本会生成 `xxMac.app`：

- 默认使用 ad-hoc 签名，签名标识为 `-`。
- 从 `Sources/xxMac/Info.plist` 拷贝应用元信息。
- 从 `Resources/` 拷贝图标、本地化和日历数据。

指定开发者签名：

```bash
SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" bash bundle_app.sh
```

## DMG 发布

```bash
bash publish_dmg.sh
```

脚本会：

1. 读取并打印 `Sources/xxMac/Info.plist` 中的当前版本。
2. 提示输入本次发布版本。
3. 写回 `CFBundleShortVersionString` 和 `CFBundleVersion`。
4. 写回 `XXLastUpdated`，关于页会显示这个最近更新时间。
5. 调用 `bundle_app.sh` 重新生成 `xxMac.app`。
6. 创建包含 `xxMac.app` 和 `Applications` 快捷方式的压缩 DMG。
7. 执行 `hdiutil verify` 校验镜像。

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

## 无开发者账号

默认 ad-hoc 签名的 App 拷贝到 `/Applications` 后，macOS 可能因为隔离属性阻止打开。清理隔离属性后再启动：

```bash
xattr -cr /Applications/xxMac.app
open /Applications/xxMac.app
```

如果 App 不在 `/Applications`，把路径替换成实际的 `xxMac.app` 路径。

## 权限排障

首次运行打包后的 App，需要在系统设置里授予辅助功能权限：

1. 打开 System Settings。
2. 进入 Privacy & Security。
3. 进入 Accessibility。
4. 添加并启用当前路径下的 `xxMac.app`。

重新打包或移动 App 后，如果快捷键、窗口控制或剪贴板回贴失效，优先检查 Accessibility 列表里授权的是否是当前路径下的 `xxMac.app`。必要时删除旧条目后重新添加。

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
