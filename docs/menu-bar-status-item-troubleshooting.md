# 菜单栏状态项不可见排查记录

## 适用症状

xxMac 的"通用 > 配置 > 状态栏诊断"显示状态项已经创建，但菜单栏中看不到图标。典型诊断值如下：

```text
shouldShow: true
hasStatusItem: true
isVisible: true
hasButton: true
buttonHasWindow: true
imageVisiblePixelRatio: > 0
```

这说明 AppKit 已创建并渲染了 `NSStatusItem`，不能据此断定图标实际在用户可见位置。

### 新增：时钟区重叠检测

v1.1.3 起，诊断面板新增 `clockZone` 字段，自动检测状态项是否落在系统时钟区域：

- `leftOfClock`：正常 —— 状态项在时钟左侧的可见区域
- `overlappingClock`：异常 —— 状态项与系统时钟区域重叠，可能被遮挡
- `rightOfClock`：罕见 —— 状态项位于时钟右侧（通常是多显示器场景）
- `noButton` / `noScreen` / `unknown`：无法判断

如果看到 `overlappingClock`，说明遇到了本文档描述的问题。

### 不要混淆 macOS 屏幕控制指示器

使用 Codex Computer Use、远程控制或屏幕录制工具调试时，macOS 可能在菜单栏显示“控制工具 App 图标 + 鼠标箭头”的胶囊指示器。点击后会出现“停止运行”或“停止控制”之类的系统操作。这个胶囊属于 Control Center 的隐私提示，不是 xxMac 的状态栏图标，也不能作为 xxMac 已恢复的验证信号。

### 状态项注册方式（v1.2.0+）

xxMac 参考 Thaw 的状态项注册顺序：创建前初始化稳定 `autosaveName` 对应的可见性偏好，使用长度 `0` 创建 `NSStatusItem`，立即绑定 `autosaveName`，最后再配置图标并展开到实际宽度。这样 AppKit 从状态项首次注册起就能使用稳定身份和保存位置。

`reaffirmMenuBarItemIfNeeded` 只重新确认现有状态项可见并刷新图标，不会因为 `malpositioned` 或 `overlappingClock` 自动清除偏好、销毁并重建状态项。启动阶段自动重建曾造成 Control Center 场景重连期间辅助场景断开，因此已停用。

如果重新启动 xxMac 后仍无法正常显示，可尝试注销并重新登录 macOS 用户。

## 已记录事故

2026-07-10，在一台 M3 Pro、双显示器的 macOS 会话中，xxMac 的状态项被 WindowServer 放在系统时钟覆盖区。辅助功能查询显示 xxMac 项约位于 `x=2034`，系统时钟约覆盖 `x=2016...2062`。同一进程中额外创建的不带菜单、图像和控制器的纯文本状态项也会落在相同区域。

因此，本次事故已排除日历图像、`CalendarMenuBarController`、状态栏菜单、窗口大小或设置开关；现有证据强烈指向该 macOS 登录会话对 `com.xiaomi318.xxMac` 的 `NSStatusItem` 布局异常。

## 菜单栏间距私有偏好（NSStatusItemSpacing）

### 没有"默认数值"，默认状态是键不存在

`NSStatusItemSpacing` 和 `NSStatusItemSelectionPadding` 是 AppKit 未公开的私有键，控制菜单栏项目的间距与可点击区域宽度。macOS 出厂状态是**这两个键完全不存在**，间距由 AppKit 内部硬编码决定。

网上常见的"默认 16"是社区反推的观测值，不是 Apple 文档定义。写 `-int 16` 只是把一个猜测值固化进偏好，仍然属于自定义状态。**恢复默认的唯一正确做法是删除键**，让系统回落到内部默认：

```bash
defaults -currentHost delete -globalDomain NSStatusItemSpacing
defaults -currentHost delete -globalDomain NSStatusItemSelectionPadding
```

这两个键只存在于 ByHost 域（`~/Library/Preferences/ByHost/.GlobalPreferences.<UUID>.plist`），非 ByHost 的 `NSGlobalDomain` 里本来就没有，不需要额外清理。

修改后需要**注销重新登录**（或重启）才生效，间距值在登录时读取。不要为此执行 `killall ControlCenter`，见下文。

### 变更记录

- 2026-06-05：曾写入 `NSStatusItemSpacing -int 6`。
- 时间不明：两键变为 `14`（`Spacing` 与 `SelectionPadding` 均为 14），现有记录无法确认由谁设置。
- 2026-08-05 07:43：删除两键恢复系统默认。原 plist 备份在 `~/Desktop/GlobalPreferences-ByHost-backup-20260805-074350.plist`。已用 diff 确认该次操作只删了这两个键，plist 其余内容未损坏。
- 2026-08-05 08:31：已把两键写回 `14`（见下方"ControlCenter 给第三方状态项分配 0x0"事故）。删键后的首个会话（08:05 重启）出现第三方状态项 0x0 故障，故先回滚到删除前的值以隔离变量。写回命令：

  ```bash
  defaults -currentHost write -globalDomain NSStatusItemSpacing -int 14
  defaults -currentHost write -globalDomain NSStatusItemSelectionPadding -int 14
  ```

  **需要注销重新登录才生效。** 尚未验证是否修复。

### 与本文事故的关系

间距键会影响菜单栏整体排布密度、拥挤程度和溢出，但**不会指定任何 App 的绝对坐标**。2026-07-10 事故中的 `x=2034` 不是被任何文件写死的值，而是 WindowServer / Control Center 在运行时分配给 `AXMenuExtra` 窗口的 frame。该次故障的直接原因是旧 xxMac 进程持有了过期的显示器坐标；在未修改任何偏好、仅完整重启 xxMac 后，坐标即从屏幕外的 `2034` 回到屏幕内的 `1909`。

### 不要删除整个 Control Center 偏好域

2026-07-03 曾执行过 `defaults delete com.apple.controlcenter`，删掉整个域后由系统重新生成。这是影响最大的一步，可能扰乱第三方状态项与场景身份的历史映射，**不要重复**。同期还删除了匿名的 `NSStatusItem Visible Item-0` … `Item-10` 键（部分因中断可能未执行完），这类操作同样有风险。

若要恢复系统默认菜单栏行为，只针对上面两个全局间距键做最小清理即可，不要碰 `com.apple.controlcenter` 域。

事故发生时，`com.xiaomi318.xxMac` 域中不存在 xxMac 对应的 `NSStatusItem Preferred Position` / `NSStatusItem Visible` 键。当前版本恢复使用稳定身份 `xxMac.statusItem`，不主动写入 `Preferred Position`，只维护对应的 `Visible` 和 `VisibleCC` 键。曾尝试使用本机会话中 Thaw 可见控制项的排序值 `395`，结果 xxMac 状态项从时钟区移动到屏幕左上边界外，证明其他 App 的排序值不能移植。这些值是排序偏好，不是屏幕像素坐标。

## 首先做什么

1. 在"通用 > 配置"查看状态栏诊断；只有上面的创建/渲染值都正常时，才按本文继续。**特别注意 `clockZone` 字段**。
2. 确认只有一个 xxMac 进程和一个正在运行的 App 路径：

   ```bash
   pgrep -x xxMac
   ps -p "$(pgrep -x xxMac)" -o pid,lstart,comm,args
   ```

3. 使用辅助功能查询确认状态项是否与系统项重叠：

   ```bash
   osascript -e 'tell application "System Events" to tell process "xxMac" to get {position, size, description, subrole} of every menu bar item of menu bar 2'
   ```

坐标只用于确认重叠，不应作为跨显示器的绝对位置计算依据。

## 本事故中不要重复尝试

在上述事故中，以下操作均已验证无效；不要再为该症状修改项目代码或反复执行：

1. 在设置中反复切换"显示在右上角状态栏"，或点击刷新/重建。
2. 重启 `ControlCenter` 或 `SystemUIServer`。
3. 反复设置 `NSStatusItem.isVisible = true`、调整 `NSStatusItem` 固定/可变宽度，或更改日历图像。
4. 反复修改 `autosaveName`、写入 `NSStatusItem Preferred Position` 私有偏好，或用状态栏管理 App 强行排序。当前状态项身份为 `xxMac.statusItem`，不主动写入初始位置。
5. 重写 `CalendarMenuBarController`，或仅为排查加入第二个 `NSStatusItem`。
6. 在仓库目录和 `/Applications` 同时保留多个同 bundle ID 的 xxMac App。双副本应避免，但删除副本不能修复本次会话问题。
7. 修改 App 显示名、`CFBundleIdentifier` 或反向域名。2026-07-11 已在重启后的会话中验证 `cc.xiaomi318.xxMac`：新身份仍会与时钟重叠；写入正常 App 的排序值后又落到另一块屏幕边界。改身份还会触发辅助功能和自动化权限重新授权，因此不能作为修复方案。

   2026-08-05 用对照实验二次确认：`Experiments/MenuBarClickProbe`（独立 bundle ID `dev.codex.MenuBarClickProbe`、纯 AppKit、无 SwiftUI、代码与 xxMac 无关）在同一会话中出现**完全相同**的故障。App 身份、签名、SwiftUI 生命周期、`autosaveName` 全部被排除。

这些尝试会产生无效代码、临时状态项或本机偏好。若曾做过，必须在结束前恢复源码、删除临时状态项和删除自行写入的 `NSStatusItem Preferred Position` 键。

## 会话重置已执行且无效

2026-08-05 已完成重启（开机 08:05:33，WindowServer / loginwindow / ControlCenter 均为 08:06 全新启动）。**重启没有修复该症状。** 因此"注销重新登录 / 重启 Mac"这一条不再是待验证步骤，也不应再作为建议给出。

## 2026-08-05 事故：ControlCenter 给第三方状态项分配 0x0

### 症状与旧事故不同

这次不是时钟重叠，也不是被刘海遮挡。状态项窗口被停在主屏左下角、菜单栏之外：

- xxMac：AX `(-1, 965)` size `41x24`，换算 AppKit 约 `(-1, -7)`
- MenuBarClickProbe：AppKit `{{0, -17}, {34, 22}}`，AX `(-1, 976)`

主屏为内置刘海屏 `{{0, 0}, {1512, 982}}`。两个窗口都跨在 AppKit `y=0` 边界上，即主屏底部之外，不在任何菜单栏内。

### 决定性证据：ControlCenter 侧尺寸为 0x0

```bash
osascript -e 'tell application "System Events" to tell process "ControlCenter"
  repeat with anItem in menu bar items of menu bar 1
    log (description of anItem) & " | pos=" & ((position of anItem) as text) & " | size=" & ((size of anItem) as text)
  end repeat
end tell'
```

输出中 6 个系统项（电池 / 蓝牙 / 时钟 / 声音 / Wi‑Fi / 控制中心）尺寸全部正常（`y=5`，高 22），而两个第三方项：

```text
状态菜单 | pos=0,982 | size=0x0
状态菜单 | pos=0,982 | size=0x0
```

数量与当时运行的第三方状态栏 App 数量一致（xxMac + MenuBarClickProbe）。**ControlCenter 知道这两个项存在，但分配了 0 宽度**，因此不可见；窗口随之被停在原点附近。

菜单栏当时并不拥挤：系统项占 `x=1155...1505`，左侧仍有约 370 点空间，排除"空间不足溢出"。

### 已排除的因素

- App 身份 / 签名 / bundle ID：对照实验用完全不同的 bundle ID 复现
- SwiftUI 生命周期、`LSUIElement`、`autosaveName`：探针是纯 AppKit，且从不设置 `autosaveName`
- 持久化位置偏好：`com.xiaomi318.xxMac` 及全 Preferences 目录均无 `NSStatusItem Preferred Position`
- 会话级缓存：重启后仍复现
- 菜单栏自动隐藏（`_HIHideMenuBar` 未设置）、跨屏菜单栏（`spans-displays` 未设置）
- 代码路径：`ensureMenuBarItem()` 创建后 `isVisible = true`、按钮有 title，诊断显示 `hasButton` / `buttonHasWindow` 均正常

### 当前最强线索：间距键缺失

时间线高度吻合：

| 时间 | 事件 |
| --- | --- |
| 07:43 | 删除 `NSStatusItemSpacing` / `NSStatusItemSelectionPadding`（两键此前为 14） |
| 08:05 | 重启，本次登录是**删键后的第一个会话** |
| 08:11 | xxMac 启动，状态项 0x0 |
| — | 同会话中探针同样 0x0；而删键前的会话里探针位置完全正常 |

这两个键在登录时读取。删键前正常、删键后第一个会话即全面失效，是目前唯一与故障同步的变更。已在 08:31 恢复为 14/14：

```bash
defaults -currentHost write -globalDomain NSStatusItemSpacing -int 14
defaults -currentHost write -globalDomain NSStatusItemSelectionPadding -int 14
```

**需要注销重新登录后验证。** 备份 plist 与当前 plist 的顶层键 diff 已确认：07:43 那次操作只删除了这两个键，没有波及其他键，plist 未损坏。

注意这与本文前面"恢复默认的唯一正确做法是删除键"存在张力：理论上出厂状态无此二键且第三方状态项正常工作。若恢复 14/14 后重新登录仍为 0x0，则间距键假设被推翻，应转向 macOS 26.5.2 (25F84) 自身对第三方 `AXMenuExtra` 布局的回归，并考虑向 Apple 反馈。

### 复现验证方法

用对照实验判断是 xxMac 代码问题还是会话/系统问题，不要直接改 xxMac：

```bash
cd Experiments/MenuBarClickProbe && ./script/build_and_run.sh --verify
cat dist/diagnostics.json   # 看 buttonFrame 是否在 screenFrame 顶部
```

探针也异常 → 会话/系统级，改 xxMac 代码无用。探针正常而 xxMac 异常 → 才值得查 xxMac 代码。

## 开发约定

本机开发验证使用仓库目录中 `bash bundle_app.sh` 生成的 `xxMac.app`。避免同时运行或同时保留同 bundle ID 的 `/Applications/xxMac.app` 副本，以免 LaunchServices、辅助功能授权和状态项偏好难以判断。


https://developer.apple.com/forums/thread/827337
