# 安全输入框下的剪贴板与 Snippets 唤起方案

## 背景

在密码输入框等安全输入场景下，剪贴板历史和 Snippets 的全局热键可以触发，但 Launcher 面板不一定显示。日志中已经确认：

1. 密码输入框中，`CarbonHotKey` 已收到 `fired name=clipboard source=carbon` 和 `fired name=snippets source=carbon`。
2. 普通输入框中，同一热键路径可以显示面板。
3. 因此根因不在热键注册，而在安全输入状态下的 App 激活、焦点和浮层窗口显示链路。

## 方案边界

安全输入框会特殊处理编辑菜单、焦点和文本输入链路。xxMac 不尝试绕过目标 App 的安全策略，只做两件事：

1. 可靠显示自己的剪贴板历史和 Snippets 浮层。
2. 用户选择内容后，恢复原 App 焦点，再按既有流程粘贴或输入。

## 实现要点

### 热键接收

`CarbonHotKeyRegistration` 使用 Carbon `RegisterEventHotKey` 注册全局热键，并保留 CGEvent tap fallback。

Carbon 路径触发后会等待相关修饰键释放，再回到主线程执行 handler，避免安全输入框或输入法仍持有组合键状态时打断面板显示。

关键日志：

```text
[CarbonHotKey] fired name=clipboard source=carbon
[CarbonHotKey] dispatching name=clipboard after modifier release
```

### 焦点释放与恢复

`AccessibilityManager.suspendFocusedTextInputForOverlay()` 在显示浮层前捕获：

1. 当前前台 App。
2. 当前 focused AX element。

如果 focused element 是文本、编辑、secure 或 password 类型，会暂时设置 `AXFocused=false`。关闭浮层或执行回贴前，通过 `restoreSuspendedTextInputFocus()` 激活原 App 并恢复 `AXFocused=true`。

关键日志：

```text
[Accessibility] suspended focused text input app=com.example.app#12345
[Accessibility] restored focused text input app=com.example.app#12345
```

### 浮层显示

Launcher 面板使用 `NSPanel`，并按浮层窗口处理：

1. `styleMask` 包含 `.nonactivatingPanel`。
2. 常规层级为 `.floating`，打开时临时升到 `.statusBar`。
3. `hidesOnDeactivate=false`，避免激活链路变化时面板立即隐藏。
4. `collectionBehavior` 包含 `.canJoinAllSpaces`、`.fullScreenAuxiliary`、`.transient` 和 `.ignoresCycle`。
5. 显示顺序为 `orderFrontRegardless()`、`NSApp.activate(ignoringOtherApps: true)`、`makeKeyAndOrderFront(nil)`，之后再次 `orderFrontRegardless()`。
6. 打开后进行短时间状态复查，如果面板未 visible 或未 key，会再次前置。

关键日志：

```text
[LauncherPanel] openLauncher.begin
[LauncherPanel] bringLauncherToFront.before
[LauncherPanel] bringLauncherToFront.after
[LauncherPanel] launcherPresentation.verify
```

### 剪贴板历史流程

剪贴板热键触发后：

1. `ClipboardManager` 捕获当前前台 App。
2. 调用 `suspendFocusedTextInputForOverlay()`。
3. 发出 `ShowClipboardHistory` 通知。
4. `AppDelegate` 打开 Launcher 面板。
5. 用户选择历史项后，将内容写入系统剪贴板。
6. 关闭面板、恢复原 App 焦点、发送 `Command + V`。

### Snippets 流程

Snippets 热键触发后：

1. `SnippetManager` 捕获当前前台 App。
2. 调用 `suspendFocusedTextInputForOverlay()`。
3. 发出 `ShowSnippets` 通知。
4. `AppDelegate` 打开 Launcher 面板。
5. 用户选择片段后，先把片段内容写入系统剪贴板。
6. 关闭面板、恢复原 App 焦点、逐字发送 Unicode keyboard event 输入片段内容。

Snippets 会同步改写系统剪贴板。这是有意行为，便于安全输入框或目标 App 不接受模拟文本输入时，用户仍可直接使用系统粘贴板内容。

## 排障顺序

如果后续再次出现安全输入框下无法打开面板，按下面顺序看日志：

1. `CarbonHotKey` 是否有 `fired` 和 `dispatching`。
2. `ClipboardFlow` 或 `SnippetFlow` 是否发出打开通知。
3. `Accessibility` 是否捕获并释放了 focused text input。
4. `LauncherPanel` 是否进入 `openLauncher`、`bringLauncherToFront` 和 `launcherPresentation.verify`。

如果第 1 步存在，通常不要再优先改热键注册，应继续查窗口显示、层级、App 激活和焦点恢复链路。
