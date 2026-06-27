# 设置窗口侧边栏按钮处理记录

## 背景

设置窗口使用 `NavigationSplitView` 实现三栏结构：

1. 第一列：工具分类。
2. 第二列：功能列表。
3. 第三列：具体配置。

在折叠或收起侧边栏时，系统自动生成的侧边栏按钮会随 `NavigationSplitView` 状态移动。展开时按钮靠近列分隔区域，折叠后会跑到窗口右侧，视觉位置不稳定。

## 问题表现

排查过程中出现过两个侧边栏按钮：

1. 左侧按钮：应用自定义的固定入口，位置符合预期。
2. 右侧按钮：SwiftUI / AppKit 为 `NavigationSplitView` 自动插入的系统按钮，点击后仍走旧效果，收缩后会移动到右侧。

曾尝试直接用 `NavigationSplitView(columnVisibility:)` 切换列可见性，但这会触发 SwiftUI 重新计算列宽，点击左侧按钮后窗口被撑大。因此不能直接通过手动修改 `columnVisibility` 来模拟系统折叠行为。

## 当前处理

当前实现位于 `Sources/xxMac/Views/SettingsView.swift`。

处理原则：

1. 保留左侧固定按钮。
2. 左侧按钮不直接改 `NavigationSplitViewVisibility`。
3. 左侧按钮调用系统原生 `NSSplitViewController.toggleSidebar(_:)`，保持和系统按钮一致的折叠行为，避免窗口变大。
4. 用 `SettingsToolbarCleanup` 清理 SwiftUI / AppKit 自动插入的重复 sidebar toolbar item。
5. 给自定义按钮固定 toolbar id：`xxmac.settings.sidebarToggle`，cleanup 时保留该 id，移除其它 sidebar 相关按钮。

当前可见结果：

1. 重复的第二个按钮已删除。
2. 标题栏中仍可见一条竖线，疑似系统生成的 tracking separator 或标题栏分隔元素。
3. 该竖线暂不处理，避免继续影响系统标题栏和 `NavigationSplitView` 原生布局行为。

## 关键经验

1. SwiftUI 的 `NavigationSplitView` 会自动给 macOS toolbar 注入 sidebar 相关 item。
2. 这些 item 不一定稳定暴露为 `.toggleSidebar` 或 `.sidebarTrackingSeparator`，只按标准 identifier/action 删除可能漏掉。
3. 自定义按钮如果直接改 `columnVisibility`，行为不等同于系统 `toggleSidebar:`，可能导致窗口尺寸变化。
4. 更稳妥的方式是让固定按钮走 AppKit responder chain：

```swift
NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
```

## 后续注意

1. 不要为了移除当前残留竖线继续扩大 toolbar cleanup 范围，除非先确认它的真实 `NSToolbarItem.Identifier` 或来源。
2. 如果后续要彻底控制标题栏，优先考虑 AppKit 层自定义 `NSToolbar`，不要在 SwiftUI toolbar 和系统自动 toolbar item 之间继续叠加猜测式清理。
3. 修改设置窗口三栏结构时，需要回归检查：
   - 展开状态只显示一个侧边栏按钮。
   - 点击按钮不改变窗口大小。
   - 折叠后按钮位置稳定。
   - 第二列和第三列内容不被标题栏元素遮挡。
