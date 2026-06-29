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

最近一轮 DEBUG 日志已经确认：

1. `com.apple.SwiftUI.navigationSplitView.toggleSidebar` 是 SwiftUI 自动生成的 sidebar toggle。
2. `com.apple.SwiftUI.splitViewSeparator-0` 是它旁边的分隔线。
3. `NSToolbar` 里没有第二个独立的业务按钮，之前看到的“第二个图标”本质上就是 SwiftUI 自动注入项。

曾尝试直接用 `NavigationSplitView(columnVisibility:)` 切换列可见性，但这会触发 SwiftUI 重新计算列宽，点击左侧按钮后窗口被撑大。因此不能直接通过手动修改 `columnVisibility` 来模拟系统折叠行为。

## 当前处理

当前实现位于 `Sources/xxMac/Views/SettingsView.swift`。

处理原则：

1. 仅保留一个可见入口。
2. 设置窗口不再使用 `NavigationSplitView` 的自动三栏和自动 toolbar 项。
3. 顶层改为显式 `HStack` 四段布局：固定按钮栏、工具栏、二级功能栏、详情栏。
4. 固定按钮栏永远可见，按钮只切换工具栏显示状态，不依赖系统 toolbar 或 `NavigationSplitViewVisibility`。
5. 二级功能栏和详情栏始终保留，避免收起工具栏后丢失上下文。

当前可见结果：

1. 展开 / 收起只影响第一列工具分类。
2. 固定按钮位于窗口内容左侧窄栏顶部，不随展开 / 收起侧边栏移动，也不会消失。
3. 不再需要清理 SwiftUI 自动插入的 sidebar toolbar item。
4. 二级栏使用普通 sidebar 列表风格，避免卡片套卡片。

## 关键经验

1. SwiftUI 的 `NavigationSplitView` 会自动给 macOS toolbar 注入 sidebar 相关 item。
2. 这些 item 的 `itemIdentifier.rawValue` 更稳定，调试时应以真实 id 为准。
3. 自定义按钮如果直接改 `columnVisibility`，行为不等同于系统 `toggleSidebar:`，可能导致窗口尺寸变化。
4. 通过 `NSViewRepresentable` 往 `NSToolbar` 异步插入自定义按钮也不够稳定；`NavigationSplitView` 收起 / 展开可能重建 toolbar 项，导致按钮暂时消失，直到其它状态变化触发 SwiftUI 更新。
5. 如果需要按钮位置完全稳定，应把按钮纳入自有布局，而不是混在 SwiftUI / AppKit 自动 toolbar 系统里。

## 后续注意

1. 不要为了移除当前残留竖线继续扩大 toolbar cleanup 范围，除非先确认它的真实 `NSToolbarItem.Identifier` 或来源。
2. 如果后续要彻底控制标题栏，优先考虑 AppKit 层自定义 `NSToolbar`，不要在 SwiftUI toolbar 和系统自动 toolbar item 之间继续叠加猜测式清理。
3. 修改设置窗口三栏结构时，需要回归检查：
   - 展开状态只显示一个侧边栏按钮。
   - 点击按钮不改变窗口大小。
   - 折叠后按钮位置稳定。
   - 第二列和第三列内容不被标题栏元素遮挡。
