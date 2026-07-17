# Quick Shortcut Command Debounce Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task.

**Goal:** 命令脚本快捷指令只在输入稳定 400ms 后启动，防抖窗口内被替代或取消的输入不执行也不写入历史。

**Architecture:** 在 `LauncherViewModel` 所在模块增加基于 `DispatchWorkItem` 的小型防抖器，沿用项目现有调度模式。ViewModel 仍即时识别输入和更新加载状态，但把历史写入及外部脚本启动放进防抖任务；现有运行标识继续隔离过期输出。

**Tech Stack:** Swift 5.9、SwiftUI/Combine、Grand Central Dispatch、XCTest

---

### Task 1: 用测试定义防抖与取消语义

**Files:**
- Modify: `Tests/xxMacTests/LauncherViewModelTests.swift`

**Step 1: Write the failing tests**

增加两个测试：

```swift
func testDebouncerOnlyRunsLatestScheduledAction() {
    let debouncer = LauncherCommandDebouncer(delay: 0.02)
    let latestRan = expectation(description: "latest action ran")
    var executions: [String] = []

    debouncer.schedule { executions.append("first") }
    debouncer.schedule {
        executions.append("latest")
        latestRan.fulfill()
    }

    wait(for: [latestRan], timeout: 0.5)
    XCTAssertEqual(executions, ["latest"])
}

func testDebouncerCancelPreventsPendingAction() {
    let debouncer = LauncherCommandDebouncer(delay: 0.02)
    let actionRan = expectation(description: "cancelled action did not run")
    actionRan.isInverted = true

    debouncer.schedule { actionRan.fulfill() }
    debouncer.cancel()

    wait(for: [actionRan], timeout: 0.1)
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter LauncherViewModelTests`

Expected: FAIL because `LauncherCommandDebouncer` does not exist.

### Task 2: 实现最小防抖器

**Files:**
- Modify: `Sources/xxMac/ViewModels/LauncherViewModel.swift`
- Test: `Tests/xxMacTests/LauncherViewModelTests.swift`

**Step 1: Write the minimal implementation**

在 ViewModel 文件中增加内部类型：

```swift
final class LauncherCommandDebouncer {
    private let delay: TimeInterval
    private var pendingWorkItem: DispatchWorkItem?

    init(delay: TimeInterval = 0.4) {
        self.delay = delay
    }

    func schedule(_ action: @escaping () -> Void) {
        cancel()
        let workItem = DispatchWorkItem(block: action)
        pendingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func cancel() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
    }

    deinit {
        cancel()
    }
}
```

**Step 2: Run focused tests**

Run: `swift test --filter LauncherViewModelTests`

Expected: PASS, including latest-only and cancel behavior.

### Task 3: 将命令脚本执行接入防抖

**Files:**
- Modify: `Sources/xxMac/ViewModels/LauncherViewModel.swift`

**Step 1: Add ViewModel state**

- 增加默认延时为 400ms 的 `LauncherCommandDebouncer`。
- 重置搜索状态时取消待执行任务。

**Step 2: Cancel obsolete pending commands**

- 空查询直接返回前取消待执行命令。
- 快捷指令状态变为 `.none`、`.waitingForInput` 或网页搜索时取消待执行命令，并使旧运行标识失效。

**Step 3: Schedule command execution**

- 每次命令脚本输入生成新的运行标识和完整源输入。
- 保持当前“正在运行”结果展示。
- 延时任务到期时再次校验 launcher 模式、运行标识和输入内容。
- 仅在校验通过后写入历史并调用 `runCommandScript`。
- 脚本完成后沿用现有校验，拒绝过期输出。

**Step 4: Run focused tests and build**

Run: `swift test --filter LauncherViewModelTests`

Expected: PASS.

Run: `swift build`

Expected: Build complete with exit code 0.

### Task 4: 同步用户文档并完成验证

**Files:**
- Modify: `README_zh-CN.md`
- Modify: `README.md`

**Step 1: Document the behavior**

在快捷指令命令脚本说明中补充：输入短暂停顿后执行，只执行防抖窗口内最后一次输入。配置目录和存储类型未变化，不修改“通用 > 配置目录”说明。

**Step 2: Run full verification**

Run: `swift test`

Expected: all tests pass with zero failures.

Run: `swift build`

Expected: Build complete with exit code 0.

Run: `git diff --check`

Expected: no output and exit code 0.

**Step 3: Review scope**

确认 diff 不包含会话历史合并、方向键历史回填或其他无关重构。遵守仓库规则，不执行 git commit。

