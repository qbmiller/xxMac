# 菜单栏图标不可见：请看 docs/

本文件早期版本记录的"刘海遮挡"结论和修复步骤**已被 2026-08-05 的对照实验推翻**，为避免误导已清空。

权威记录见 [`docs/menu-bar-status-item-troubleshooting.md`](docs/menu-bar-status-item-troubleshooting.md)。

## 已推翻的内容（不要再照做）

以下是本文件旧版本的建议，均已验证无效或前提错误：

1. **`defaults delete com.xiaomi318.xxMac "NSStatusItem Preferred Position xxMac.statusItem"`**
   —— 该键在 `com.xiaomi318.xxMac` 域中**从来不存在**，全系统搜索也没有 xxMac 对应的 `Preferred Position`。执行这条命令没有任何效果。

2. **"刘海遮挡，状态项在 x=1476 超出可见区"**
   —— 这只是某一次会话的观测值。2026-08-05 故障中状态项在 `(-1, -7)`（主屏左下角，AppKit 坐标），与刘海无关。

3. **"重启 Mac 或注销重新登录"**
   —— 2026-08-05 已执行完整重启，**没有修复**。不再是有效建议。

4. **"当前代码已禁用 autosaveName 防止保存错误位置"**
   —— 与实际代码不符。`configureMenuBarStatusItemIdentity` 会设置 `autosaveName`，但 `ensureMenuBarItem()` 从未调用它，所以 `autosaveName` 实际上处于未设置状态。

5. **"这是 macOS 的已知限制，不是 xxMac 的 bug"**
   —— 结论方向对（确实不是 xxMac 代码问题），但当时没有证据。2026-08-05 才用独立对照 App 证明了这一点。

## 一句话现状

同一会话中，一个与 xxMac 完全无关的独立 App（`Experiments/MenuBarClickProbe`，不同 bundle ID、纯 AppKit）出现完全相同的故障，ControlCenter 给两个第三方状态项都分配了 `0x0` 尺寸。这是会话/系统层面的问题，改 App 身份、签名或代码都不解决。
