# 菜单栏状态项时钟区重叠问题的代码修复方案

> 状态：已废弃（2026-07-11）。启动日志证明自动销毁并重建状态项会在 ControlCenter 场景重连期间造成辅助场景断开；保留只读 `clockZone` 诊断，不执行本文第 2 节自动恢复方案。

## 问题回顾

根据 troubleshooting doc，在某些 macOS 会话（特别是双显示器 M3 Pro）中，WindowServer 将 xxMac 的 `NSStatusItem` 布局到系统时钟区域（屏幕最右侧 ~50px），导致图标被覆盖不可见。

**核心问题**：这是 macOS 会话级 bug，重启会话可修复。但代码层面可以增加检测和自动恢复能力。

## 修改计划

### 1. 在诊断数据中增加屏幕位置检测（MenubarStatusSnapshot）

**文件**: `Sources/xxMac/xxMac.swift`

- 在 `MenuBarStatusSnapshot` 中添加 `positionRelativeToClockZone` 字段
- 在 `updateMenuBarDiagnostics` 中计算 status item 按钮的 frame 是否落在屏幕右侧 60px 内（时钟区域）
- 如果 frame.origin.x + frame.width > screen.width - 60，则标记为 `overlappingClock`

这样用户直接在"状态栏诊断"界面就能看到是否被时钟遮挡，无需手动运行 AppleScript。

### 2. 自动检测 + 延迟重建恢复

**文件**: `Sources/xxMac/xxMac.swift`

- 在 `reaffirmMenuBarItemIfNeeded(trigger: "launch")` 中增加时钟区重叠检测
- 如果检测到重叠，执行激进恢复：
  1. 销毁当前 statusItem
  2. 短暂延迟（0.5s）让 WindowServer 重新布局
  3. 清除相关 NSStatusItem 偏好
  4. 重新创建
- 记录恢复尝试次数，避免死循环

### 3. 更新故障排除文档

**文件**: `docs/menu-bar-status-item-troubleshooting.md`

- 更新为反映新增的诊断能力和自动恢复检测

## 不做什么

按照文档的建议，以下操作不再尝试：
- 不修改 autosaveName 策略
- 不反复切换 isVisible
- 不改动 CalendarMenuBarController 结构
- 不做会留下垃圾偏好或临时状态项的改动

## 风险

- 延迟重建可能在极少数情况下导致短暂的状态项闪烁
- 位置检测依赖 button.frame，如果 frame 返回异常值可能需要额外保护
