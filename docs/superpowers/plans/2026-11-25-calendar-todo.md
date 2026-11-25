# Calendar Todo Implementation Plan

> **For agentic workers:** Execute inline using superpowers:executing-plans. User has authorized implementation; no GitHub operations or automatic commits.

**Goal:** 把现有日历与本地 Todo 联动，完成已认可的 HTML 设计。
**Architecture:** 独立日期查询策略与 TodoStore 原子延期操作；独立 SwiftUI 待办组件嵌入月历；弹窗控制器管理本次固定状态。
**Tech Stack:** SwiftUI、AppKit、Combine、SwiftPM，macOS 13。
**Spec:** docs/superpowers/specs/2026-11-25-calendar-todo-design.md

## Global Constraints

保留已有未提交改动；不操作 GitHub、不提交、不安装或启动应用；不新增依赖。

## Review Focus

日界线和夏令时；任务归档和无截止日；延期不能覆盖并发编辑；文字输入不被快捷键抢占；固定弹窗关闭后重置。

### Task 1: 日期查询及原子延期

Files: Sources/xxMac/Models/CalendarTodoQuery.swift; Sources/xxMac/Managers/TodoStore.swift; Tests/xxMacTests/CalendarTodoQueryTests.swift; Tests/xxMacTests/TodoStoreTests.swift.
- [x] 先测试：按本地日过滤、排除归档和无日期、完成过滤、排序和日期小点、跨夏令时延期。
- [x] 增加 CalendarTodoQuery.tasks/daysWithOpenTasks/deferredDeadline；TodoStore.deferToTomorrow(id:calendar:) 从 worker 最新任务仅改截止日。
- [x] 运行定向测试验证筛选、持久化失败保留状态、延期保留其他字段。

### Task 2: 原生界面及弹窗

Files: Sources/xxMac/Views/CalendarFeatureView.swift; Sources/xxMac/Views/CalendarTodoListView.swift; Sources/xxMac/Views/CalendarKeyboardNavigation.swift; Resources/*/Localizable.strings.
- [x] 接入 Task 1 的日期查询；列表 182 pt、完成切换、添加、延期、打开 Todo、错误提示。
- [x] 日期小点、日期 Button、方向键导航与固定功能；输入框/其他窗口不处理导航事件。
- [x] swift build，检查 macOS 13 API 与生命周期。

### Task 3: 文档与验证

Files: README.md; README_zh-CN.md; Resources/*/Localizable.strings.
- [x] 同步功能与配置目录说明，说明没有新增数据文件；固定状态和显示已完成状态仅当前会话。
- [x] swift test；git diff --check；审阅全部改动，记录不能自动验证的原生交互。

## 执行记录

- 日期查询与延期测试先因缺少实现失败；实现后 27 项定向测试通过。
- 原生布局回归：空列表与 40 项任务列表高度相同，日历面板 fitting height 小于 760 pt；29 项定向测试通过。
- 独立只读审查发现快速添加写入失败会丢失草稿；补充失败重试测试，先因缺少保存回调失败，随后增加成功回调、失败保留输入与提交期间禁用，完整 336 项测试通过。
- `swift build` 编译成功；最终 `swift test` 重编译应用和测试目标，336 项测试全部通过，无编译警告。
- 三语 strings 的 plutil 校验与 git diff --check 通过。
- 未提交、未打包安装或启动应用。实际菜单栏的固定/取消固定、文字输入焦点与小屏幕弹出位置需人工实机验收；SwiftUI 布局已通过自动检查。
- 无新增持久化配置；待办继续使用 todo.db。用户原有 xxmac.json 和 lockjob.json 未改动。
