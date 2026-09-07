# macOS Control Center 第三方菜单栏状态项恢复记录

## 文档范围

本文记录 2026-09-07 在 `miller` 用户中修复第三方菜单栏状态项不可见问题的完整过程。

本次故障不是 xxMac 自身没有创建 `NSStatusItem`，而是当前 macOS 用户的 Control Center 持久化数据发生污染，导致多个第三方状态项被系统登记为 `0 x 0`。同一台 Mac 的新用户 `millertest` 可以正常显示 xxMac，因此无需重装 macOS。

本文方法具有用户和机器相关性。不要未经诊断直接在其他 Mac 上执行覆盖操作。

## 故障表现

- `/Applications/xxMac.app` 正常运行。
- xxMac 设置中的“显示在右上角状态栏”已经开启。
- 关机重启、注销重新登录后仍不显示。
- 同一台 Mac 的新用户登录后可以正常显示 xxMac。
- 原用户中不止 xxMac，其他第三方菜单栏项目也存在异常。

## 已验证结论

### 应用进程正常

原用户中只有一个 xxMac 主进程：

```bash
pgrep -afil 'xxMac|MacTools'
```

实际运行路径为：

```text
/Applications/xxMac.app/Contents/MacOS/xxMac
```

因此排除了仓库 App 与 `/Applications` App 双实例同时运行的问题。

### xxMac 状态项已创建但位于异常位置

通过辅助功能读取 xxMac 状态项：

```bash
osascript -e 'tell application "System Events" to tell process "xxMac" to get {position, size, description, subrole} of every menu bar item of menu bar 2'
```

故障期间先后出现过以下坐标：

```text
7, 965, 30, 24, xxMac, AXMenuExtra
1475, -1, 30, 24, xxMac, AXMenuExtra
```

这说明 xxMac 已经创建了尺寸为 `30 x 24` 的 `AXMenuExtra`，但 WindowServer / Control Center 将它放到了不可见或被系统区域覆盖的位置。

### Control Center 将第三方状态项登记为 0 x 0

读取 Control Center 菜单栏项目：

```bash
osascript -e 'tell application "System Events" to tell process "ControlCenter" to get {position, size, description, subrole} of every menu bar item of menu bar 1'
```

系统电池、蓝牙、时钟、声音、Wi-Fi 和控制中心项目尺寸正常。多个第三方“状态菜单”被登记为：

```text
position: 0, 982
size: 0, 0
description: 状态菜单
subrole: AXMenuExtra
```

这证明故障发生在当前用户的 Control Center 第三方状态项管理层，不是 xxMac 图标图片、菜单或 SwiftUI/AppKit 生命周期单独导致。

### 新用户对照正常

同一台 Mac 新建 `millertest` 用户并运行同一个 `/Applications/xxMac.app` 后，菜单栏图标正常显示。

因此可以排除：

- xxMac 应用包损坏。
- 当前 macOS 安装完全损坏。
- 显示器硬件无法显示第三方状态项。
- 仅靠重装 macOS 才能恢复。

问题范围被缩小到 `miller` 用户的持久化配置。

## 关键配置位置

第三方状态项跟踪数据位于：

```text
~/Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist
```

其中关键键为：

```text
trackedApplications
```

`trackedApplications` 本身是一个 Data 值，内容还是一层二进制 plist，必须先 Base64 解码后才能检查。

普通 shell 或未获得“完全磁盘访问权限”的终端可能收到：

```text
Operation not permitted
```

不要把这个错误误判为文件不存在。

## 新用户参考配置采集

登录正常的新用户 `millertest`，给终端开启“系统设置 > 隐私与安全性 > 完全磁盘访问权限”，然后将参考配置复制到共享目录：

```bash
REF="/Users/Shared/millertest-controlcenter-reference-20260907"

mkdir -p "$REF/Preferences/ByHost"
mkdir -p "$REF/Group Containers"

cp "$HOME/Library/Preferences/com.apple.controlcenter.plist" \
  "$REF/Preferences/"

cp "$HOME/Library/Preferences/com.apple.systemuiserver.plist" \
  "$REF/Preferences/"

cp "$HOME"/Library/Preferences/ByHost/.GlobalPreferences.*.plist \
  "$REF/Preferences/ByHost/"

cp "$HOME"/Library/Preferences/ByHost/com.apple.controlcenter*.plist \
  "$REF/Preferences/ByHost/"

ditto \
  "$HOME/Library/Group Containers/group.com.apple.controlcenter" \
  "$REF/Group Containers/group.com.apple.controlcenter"
```

如果切回原用户后无法读取共享目录中的 group container 副本，可以只修改该副本的所有者：

```bash
sudo chown -R miller:staff \
  "/Users/Shared/millertest-controlcenter-reference-20260907/Group Containers/group.com.apple.controlcenter"
```

不要修改新用户真实 Home 目录中的容器所有者。

## 原用户配置采集

在原用户中，将受保护的偏好文件复制到共享目录：

```bash
cp \
  "$HOME/Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist" \
  "/Users/Shared/group.com.apple.controlcenter.plist"

chmod a+r "/Users/Shared/group.com.apple.controlcenter.plist"
```

本次原用户文件大小为 `4493` 字节，新用户正常文件大小为 `248` 字节。

文件大小只能作为线索，不能单独证明配置损坏。

## 解码 trackedApplications

原用户配置解码：

```bash
plutil -extract trackedApplications raw -o - \
  /Users/Shared/group.com.apple.controlcenter.plist \
  | base64 -D \
  > /private/tmp/miller-trackedApplications.plist

plutil -lint /private/tmp/miller-trackedApplications.plist
plutil -p /private/tmp/miller-trackedApplications.plist
```

新用户配置解码：

```bash
REFERENCE="/Users/Shared/millertest-controlcenter-reference-20260907/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist"

plutil -extract trackedApplications raw -o - "$REFERENCE" \
  | base64 -D \
  > /private/tmp/millertest-trackedApplications.plist

plutil -lint /private/tmp/millertest-trackedApplications.plist
plutil -p /private/tmp/millertest-trackedApplications.plist
```

## 根因证据

新用户正常配置只有两个数组项，表示一个正确的 xxMac 跟踪对象：

```text
bundle = com.xiaomi318.xxMac
isAllowed = true
location = com.xiaomi318.xxMac
menuItemLocations = [com.xiaomi318.xxMac]
```

原用户配置包含 86 个数组项，并出现跨应用错误关联：

- `com.openai.codex` 的 `menuItemLocations` 同时包含 Codex、xxMac 和 `dev.codex.MenuBarClickProbe`。
- xxMac 的记录同时包含正式身份 `com.xiaomi318.xxMac` 和临时身份 `com.xiaomi318.xxMac2`。
- `com.googlecode.iterm2` 的 `menuItemLocations` 错误指向 `com.xiaomi318.xxMac`。
- 持久化数据中残留调试探针 `dev.codex.MenuBarClickProbe`。
- 持久化数据中出现 Xcode 的 `swift-frontend` 临时文件 URL。
- 部分应用的 `location` 与 `menuItemLocations` 指向不同 bundle。

这些记录表明 Control Center 的第三方状态项跟踪关系已经发生交叉污染。结合所有第三方项目被分配为 `0 x 0`、新用户配置正常且替换后恢复，最终确认 `trackedApplications` 污染是本次故障的直接原因。

## 已验证无效的尝试

曾尝试只清除普通偏好中的：

```text
ControlCenterDisplayableChronoControlsProviderConfiguration
```

该键在原用户中包含 12 个重复的“深色模式、截屏、台前调度”控制项，而新用户只有 4 个。

删除后完整注销并重新登录，第三方状态项仍为 `0 x 0`，问题没有解决。该键随后从已验证备份中恢复。

因此不要继续删除普通 `com.apple.controlcenter.plist` 中的其他键，也不要删除整个 `com.apple.controlcenter` 域。

## 生成清理版配置

清理原则：

- 以原用户的外层 group plist 为基础。
- 保留 `showSiri`、`showSpotlight`、`showTimeMachine` 和 `showWeather`。
- 只将 `trackedApplications` 替换为新用户已验证正常的数据。
- 不复制 group container 元数据。

生成命令：

```bash
ORIGINAL="/Users/Shared/group.com.apple.controlcenter.plist"
REFERENCE="/Users/Shared/millertest-controlcenter-reference-20260907/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist"
CLEANED="/Users/Shared/group.com.apple.controlcenter.cleaned.plist"

cp "$ORIGINAL" "$CLEANED"

b64=$(plutil -extract trackedApplications raw -o - "$REFERENCE")
plutil -replace trackedApplications -data "$b64" "$CLEANED"
```

`plutil -replace ... -data` 接收的是 Base64 字符串，不能传入十六进制字符串。

## 校验清理版

先校验外层 plist：

```bash
plutil -lint /Users/Shared/group.com.apple.controlcenter.cleaned.plist
plutil -p /Users/Shared/group.com.apple.controlcenter.cleaned.plist
```

本次清理版外层结果：

```text
showSiri = true
showSpotlight = true
showTimeMachine = false
showWeather = false
trackedApplications length = 158
```

再校验嵌套 plist：

```bash
plutil -extract trackedApplications raw -o - \
  /Users/Shared/group.com.apple.controlcenter.cleaned.plist \
  | base64 -D \
  > /private/tmp/cleaned-trackedApplications.plist

plutil -lint /private/tmp/cleaned-trackedApplications.plist
plutil -p /private/tmp/cleaned-trackedApplications.plist
```

清理版与新用户参考数据的 SHA-256 必须一致：

```bash
shasum -a 256 \
  /private/tmp/millertest-trackedApplications.plist \
  /private/tmp/cleaned-trackedApplications.plist
```

本次两者校验值均为：

```text
7332e04d5ac0cb58112a6d8fb15b475947f652e3582018d305c6d40a6178c132
```

## 安装清理版

不能在 `miller` 仍然登录、Control Center 和 `cfprefsd` 正在运行时直接覆盖实时配置。

先将 `millertest` 设置为管理员，然后完整注销 `miller`，登录 `millertest`。不要使用快速用户切换。

在 `millertest` 的终端执行：

```bash
TARGET="/Users/miller/Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist"
CLEANED="/Users/Shared/group.com.apple.controlcenter.cleaned.plist"
BACKUP="/Users/Shared/group.com.apple.controlcenter.before-overwrite-20260907.plist"

if pgrep -u 501 ControlCenter >/dev/null; then
  echo "miller 用户仍在登录，停止操作"
  exit 1
fi

sudo cp "$TARGET" "$BACKUP"
sudo cp "$CLEANED" "$TARGET"
sudo chown miller:staff "$TARGET"
sudo chmod 600 "$TARGET"
sudo plutil -lint "$TARGET"
```

最后一条命令必须输出：

```text
OK
```

然后注销 `millertest`，重新登录 `miller`，启动一个 `/Applications/xxMac.app` 实例。

## 为什么不能覆盖整个 group container

不能把下面整个目录从新用户复制给原用户：

```text
~/Library/Group Containers/group.com.apple.controlcenter
```

容器根目录中的 `.com.apple.containermanagerd.metadata.plist` 包含用户相关信息。本次新用户副本中包括：

```text
posixUID = 502
posixGID = 20
personaUniqueString = FEEDEEEE-DDDD-CCCC-BBBB-0000000001F6
MCMMetadataUUID = C216B680-3EF1-4756-A2B1-577592F53235
```

如果把整个容器覆盖给 UID `501` 的 `miller`，可能造成容器身份、权限和用户 persona 不一致。

只允许替换下面这个内部偏好文件，并在替换后恢复目标用户所有权：

```text
Library/Preferences/group.com.apple.controlcenter.plist
```

## 恢复结果

替换清理版、注销新用户并重新登录原用户后，xxMac 图标重新出现在菜单栏。

辅助功能连续两次读取到稳定结果：

```text
1520, -1437, 30, 24, xxMac, AXMenuExtra
```

与修复前的屏幕外位置相比，xxMac 状态项已经回到外接显示器的菜单栏顶部区域。用户同时完成了视觉确认。

其他第三方菜单栏应用在后续启动时会重新向 Control Center 登记，不需要把原来的污染数组恢复回去。

## 回滚方法

如果替换后出现新的异常，完整注销 `miller`，登录管理员用户 `millertest`，执行：

```bash
TARGET="/Users/miller/Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist"
BACKUP="/Users/Shared/group.com.apple.controlcenter.before-overwrite-20260907.plist"

sudo cp "$BACKUP" "$TARGET"
sudo chown miller:staff "$TARGET"
sudo chmod 600 "$TARGET"
sudo plutil -lint "$TARGET"
```

然后注销 `millertest`，重新登录 `miller`。

## 不要执行的操作

- 不要重装 macOS 作为第一步。新用户正常已经证明系统安装和应用包可工作。
- 不要删除整个 `com.apple.controlcenter` 偏好域。
- 不要删除整个 `group.com.apple.controlcenter` 容器。
- 不要复制新用户的 `.com.apple.containermanagerd.metadata.plist`。
- 不要复制其他 Mac 的 Control Center plist。
- 不要写入其他 App 的 `NSStatusItem Preferred Position` 数值。
- 不要反复重启 `ControlCenter` 或 `SystemUIServer` 代替注销验证。
- 不要在原用户仍登录时直接覆盖受保护偏好文件。
- 不要同时运行多个相同 bundle ID 的 xxMac。

## 后续清理

至少完成一次重启并确认 xxMac 和常用第三方菜单栏应用仍然正常后，再考虑删除临时用户和共享目录备份。

建议暂时保留：

```text
/Users/Shared/group.com.apple.controlcenter.before-overwrite-20260907.plist
/Users/Shared/group.com.apple.controlcenter.plist
/Users/Shared/group.com.apple.controlcenter.cleaned.plist
/Users/Shared/millertest-controlcenter-reference-20260907
```

这些文件可能包含当前用户安装过的应用 bundle ID。确认不再需要回滚后，应由用户手动清理。
