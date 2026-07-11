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

### 不自动恢复

`clockZone` 只用于诊断，不会自动销毁、清除偏好或重建状态项。

2026-07-11 的启动日志证明，在 ControlCenter 状态项场景仍处于重连期间执行自动重建，会导致 `No scene exists for identity`、`Unhandled disconnected auxiliary scene` 和 `No matching scene to invalidate`。因此禁止基于该启发式坐标自动操作 `NSStatusItem` 生命周期。

## 已记录事故

2026-07-10，在一台 M3 Pro、双显示器的 macOS 会话中，xxMac 的状态项被 WindowServer 放在系统时钟覆盖区。辅助功能查询显示 xxMac 项约位于 `x=2034`，系统时钟约覆盖 `x=2016...2062`。同一进程中额外创建的不带菜单、图像和控制器的纯文本状态项也会落在相同区域。

因此，本次事故已排除日历图像、`CalendarMenuBarController`、状态栏菜单、窗口大小或设置开关；现有证据强烈指向该 macOS 登录会话对 `com.xiaomi318.xxMac` 的 `NSStatusItem` 布局异常。

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
4. 修改 `autosaveName`、写入 `NSStatusItem Preferred Position` 私有偏好，或用状态栏管理 App 强行排序。
5. 重写 `CalendarMenuBarController`，或仅为排查加入第二个 `NSStatusItem`。
6. 在仓库目录和 `/Applications` 同时保留多个同 bundle ID 的 xxMac App。双副本应避免，但删除副本不能修复本次会话问题。
7. 修改 App 显示名、`CFBundleIdentifier` 或反向域名。2026-07-11 已在重启后的会话中验证 `cc.xiaomi318.xxMac`：新身份仍会与时钟重叠；写入正常 App 的排序值后又落到另一块屏幕边界。改身份还会触发辅助功能和自动化权限重新授权，因此不能作为修复方案。

这些尝试会产生无效代码、临时状态项或本机偏好。若曾做过，必须在结束前恢复源码、删除临时状态项和删除自行写入的 `NSStatusItem Preferred Position` 键。

## 待验证的会话重置

在本事故中，注销 macOS 用户后重新登录，或重启 Mac，是尚未执行的最后会话级重置步骤。重新登录后只启动一个 xxMac App，再检查状态栏。

如果重新登录后仍能稳定复现，应保留以下信息后再考虑代码修改：状态栏诊断全文、`ps` 中的 App 路径、上述辅助功能查询输出、macOS 版本、显示器排列和是否存在其他可见状态项。

## 开发约定

本机开发验证使用仓库目录中 `bash bundle_app.sh` 生成的 `xxMac.app`。避免同时运行或同时保留同 bundle ID 的 `/Applications/xxMac.app` 副本，以免 LaunchServices、辅助功能授权和状态项偏好难以判断。
