# Todo Desktop Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native, interactive macOS desktop Todo widget that shows up to 10 incomplete tasks in one medium-size column and completes tasks without opening xxMac.

**Architecture:** Keep the xxMac host application as a Swift Package executable and add a separate Xcode Widget Extension under `TodoWidget/`. The host remains authoritative for `todo.db`; a small shared Swift target stores a render snapshot and durable completion journal in `group.com.xiaomi318.xxMac`, while the host reconciles journal entries into SQLite and reloads WidgetKit timelines.

**Tech Stack:** Swift 5.9+, Swift Package Manager, Xcode 26 Widget Extension, WidgetKit, SwiftUI, AppIntents, App Group files, XCTest, shell packaging tests, codesign.

**Spec:** `docs/superpowers/specs/2026-09-06-todo-widget-design.md`

## Global Constraints

- Do not modify Todo window level, pinning, Space behavior, toolbar, `TodoWindowController`, or `TodoRootView` for this feature.
- The host application remains a Swift Package and keeps `swift build` / `swift test` as its normal workflow.
- Only the extension project under `TodoWidget/` may use `xcodebuild`.
- The desktop widget requires macOS 14 or newer and supports only `.systemMedium`.
- Display at most 10 tasks in one compact column; never include completed or archived tasks.
- Priority order is Today, In Progress, Todo. Today means overdue plus due today and takes precedence over status groups.
- `todo.db` remains in the configurable xxMac directory and remains the authoritative task database.
- Shared widget files live only in App Group `group.com.xiaomi318.xxMac` and do not move with the configurable directory.
- Widget completion actions must be durable and idempotent when the host application is not running.
- Preserve all unrelated worktree changes, especially the current edits in `README.md`, `README_zh-CN.md`, `publish_dmg.sh`, packaging files, and `Sources/xxMac/Managers/TodoWindowController.swift`.
- Do not run `git commit`, create a branch, push, or publish a release.

---

### Task 1: Shared Widget Models and Locked File Store

**Files:**
- Modify: `Package.swift`
- Create: `Sources/TodoWidgetShared/TodoWidgetModels.swift`
- Create: `Sources/TodoWidgetShared/TodoWidgetFileStore.swift`
- Create: `Tests/TodoWidgetSharedTests/TodoWidgetModelsTests.swift`
- Create: `Tests/TodoWidgetSharedTests/TodoWidgetFileStoreTests.swift`

**Interfaces:**
- Produces public constants `TodoWidgetEnvironment.appGroupIdentifier`, `TodoWidgetEnvironment.widgetKind`, and `TodoWidgetEnvironment.maximumItemCount`.
- Produces `TodoWidgetCategory`, `TodoWidgetItem`, `TodoWidgetSnapshot`, `TodoWidgetActionKind`, and `TodoWidgetAction` as `Codable`, `Equatable`, `Sendable` value types.
- Produces `TodoWidgetFileStoring` and `TodoWidgetFileStore`:

```swift
public protocol TodoWidgetFileStoring: AnyObject {
    func readSnapshot() throws -> TodoWidgetSnapshot?
    func writeSnapshot(_ snapshot: TodoWidgetSnapshot) throws
    func readActions() throws -> [TodoWidgetAction]
    func appendCompletion(taskID: UUID, now: Date) throws -> TodoWidgetAction
    func removeAction(id: UUID) throws
    func removeItemFromSnapshot(taskID: UUID) throws
}

public final class TodoWidgetFileStore: TodoWidgetFileStoring {
    public init(directoryURL: URL, fileManager: FileManager = .default)
    public static func appGroup(fileManager: FileManager = .default) -> TodoWidgetFileStore?
}
```

- `TodoWidgetFileStore.appGroup()` resolves `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` and returns `nil` when the entitlement/container is unavailable.
- Every journal read-modify-write operation holds an exclusive `flock` on `todo-widget.lock`; JSON files use temporary-file replacement while the lock is held.

- [ ] **Step 1: Add the shared SwiftPM target and failing model tests**

Add `.target(name: "TodoWidgetShared")` and `.testTarget(name: "TodoWidgetSharedTests", dependencies: ["TodoWidgetShared"])`. Add `TodoWidgetShared` to the `xxMac` executable dependencies.

Test exact Codable round trips and constants:

```swift
func testSnapshotRoundTripsAllWidgetFields() throws {
    let item = TodoWidgetItem(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        title: "Ship widget",
        category: .today,
        dueAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
    let snapshot = TodoWidgetSnapshot(
        generatedAt: Date(timeIntervalSince1970: 1_799_000_000),
        nextRefreshAt: Date(timeIntervalSince1970: 1_800_086_400),
        totalIncompleteCount: 12,
        items: [item]
    )

    let decoded = try JSONDecoder().decode(
        TodoWidgetSnapshot.self,
        from: JSONEncoder().encode(snapshot)
    )
    XCTAssertEqual(decoded, snapshot)
    XCTAssertEqual(TodoWidgetEnvironment.maximumItemCount, 10)
}
```

- [ ] **Step 2: Run the model tests and verify RED**

Run: `swift test --filter TodoWidgetModelsTests`

Expected: compilation fails because the shared widget types do not exist.

- [ ] **Step 3: Implement the shared model types**

Use stable raw values:

```swift
public enum TodoWidgetCategory: String, Codable, Sendable {
    case today
    case inProgress
    case todo
}

public enum TodoWidgetActionKind: String, Codable, Sendable {
    case complete
}
```

Keep the snapshot render-only: item ID, title, category, and optional deadline. Keep action records limited to operation ID, task ID, kind, and creation date.

- [ ] **Step 4: Run the model tests and verify GREEN**

Run: `swift test --filter TodoWidgetModelsTests`

Expected: all model tests pass.

- [ ] **Step 5: Write failing locked-store tests**

Use one temporary directory per test. Cover missing files, snapshot round trip, damaged JSON fallback error, append preserving existing actions, unique action IDs, removal by operation ID, optimistic snapshot removal, and two concurrent append calls retaining both actions.

```swift
func testConcurrentAppendsDoNotLoseActions() async throws {
    let store = TodoWidgetFileStore(directoryURL: temporaryDirectory)
    let ids = (0..<2).map { _ in UUID() }

    try await withThrowingTaskGroup(of: Void.self) { group in
        for id in ids {
            group.addTask { _ = try store.appendCompletion(taskID: id, now: Date()) }
        }
        try await group.waitForAll()
    }

    XCTAssertEqual(Set(try store.readActions().map(\.taskID)), Set(ids))
}
```

- [ ] **Step 6: Run the file-store tests and verify RED**

Run: `swift test --filter TodoWidgetFileStoreTests`

Expected: compilation fails because `TodoWidgetFileStore` is missing.

- [ ] **Step 7: Implement atomic JSON storage and cross-process locking**

Create the directory before use. Open `todo-widget.lock` with `O_CREAT | O_RDWR`, acquire `LOCK_EX`, execute the complete read-modify-write closure, then release and close in `defer`. Encode dates using `.millisecondsSince1970` in both processes.

- [ ] **Step 8: Run the shared target tests and inspect the scoped diff**

Run: `swift test --filter 'TodoWidgetModelsTests|TodoWidgetFileStoreTests'`

Expected: both suites pass.

Review: `git diff -- Package.swift Sources/TodoWidgetShared Tests/TodoWidgetSharedTests`

---

### Task 2: Host Snapshot Projection Policy

**Files:**
- Create: `Sources/xxMac/Managers/TodoWidgetSnapshotBuilder.swift`
- Create: `Tests/xxMacTests/TodoWidgetSnapshotBuilderTests.swift`

**Interfaces:**
- Consumes `TodoTask` and the value types from `TodoWidgetShared`.
- Produces:

```swift
enum TodoWidgetSnapshotBuilder {
    static func makeSnapshot(
        tasks: [TodoTask],
        now: Date,
        calendar: Calendar = .current,
        limit: Int = TodoWidgetEnvironment.maximumItemCount
    ) -> TodoWidgetSnapshot
}
```

- [ ] **Step 1: Write failing projection tests**

Cover these independent behaviors:

1. Completed and archived tasks are excluded from `items` and `totalIncompleteCount`.
2. Overdue and due-today tasks appear before all status-only tasks.
3. A due-today in-progress task appears once as `.today`.
4. Today sorts by deadline ascending, then update time descending.
5. In-progress precedes todo; each status group sorts by `statusRank`, then update time descending.
6. Output contains at most 10 items while `totalIncompleteCount` retains the full count.
7. `nextRefreshAt` is the next local midnight.

```swift
func testTodayTakesPriorityWithoutDuplicatingInProgressTask() {
    let dueToday = makeTask(status: .inProgress, dueAt: noonToday)
    let ordinaryInProgress = makeTask(status: .inProgress, dueAt: nil)
    let snapshot = TodoWidgetSnapshotBuilder.makeSnapshot(
        tasks: [ordinaryInProgress, dueToday],
        now: morningToday,
        calendar: calendar
    )

    XCTAssertEqual(snapshot.items.map(\.id), [dueToday.id, ordinaryInProgress.id])
    XCTAssertEqual(snapshot.items.map(\.category), [.today, .inProgress])
}
```

- [ ] **Step 2: Run the projection tests and verify RED**

Run: `swift test --filter TodoWidgetSnapshotBuilderTests`

Expected: compilation fails because `TodoWidgetSnapshotBuilder` is missing.

- [ ] **Step 3: Implement the pure snapshot builder**

Calculate `startOfTomorrow` once. Build three arrays from the same incomplete, unarchived source:

```swift
let today = source.filter { task in
    guard let dueAt = task.dueAt else { return false }
    return dueAt < startOfTomorrow
}
let todayIDs = Set(today.map(\.id))
let inProgress = source.filter { $0.status == .inProgress && !todayIDs.contains($0.id) }
let todo = source.filter { $0.status == .todo && !todayIDs.contains($0.id) }
```

Map category before concatenating, take `max(0, limit)` items, and retain the full incomplete count.

- [ ] **Step 4: Run projection tests and inspect the scoped diff**

Run: `swift test --filter TodoWidgetSnapshotBuilderTests`

Expected: all projection tests pass.

Review: `git diff -- Sources/xxMac/Managers/TodoWidgetSnapshotBuilder.swift Tests/xxMacTests/TodoWidgetSnapshotBuilderTests.swift`

---

### Task 3: TodoStore Completion Entry Point and Change Publication

**Files:**
- Modify: `Sources/xxMac/Managers/TodoStore.swift`
- Modify: `Tests/xxMacTests/TodoStoreTests.swift`

**Interfaces:**
- Adds `Notification.Name.todoStoreTasksDidChange`.
- Adds a tested host entry point:

```swift
func completeFromWidget(
    id: UUID,
    completion: @escaping (Result<Void, Error>) -> Void
)
```

- `completeFromWidget` treats missing, archived, or already completed tasks as idempotent success.
- For an active incomplete task, it uses the existing completed transition so `completedAt`, `statusBeforeCompletion`, `updatedAt`, status rank, persistence, and notification cancellation match an in-app completion.
- Successful task publication, reload, reopen, and migration recovery post `.todoStoreTasksDidChange` after `tasks` has been assigned.

- [ ] **Step 1: Write failing TodoStore widget tests**

Add tests for active completion, in-progress history preservation, missing-task success, already-completed success, archived-task success, persistence failure returning `.failure`, notification reconciliation, and one change notification after a successful mutation.

```swift
func testWidgetCompletionUsesNormalCompletionTransition() async throws {
    let task = makeTask(title: "Active", status: .inProgress)
    let persistence = TodoPersistenceFake(tasks: [task])
    let notifications = TodoNotificationSpy()
    let store = TodoStore(persistence: persistence, notifications: notifications, now: { self.now })

    let result = await withCheckedContinuation { continuation in
        store.completeFromWidget(id: task.id) { continuation.resume(returning: $0) }
    }

    try result.get()
    XCTAssertEqual(store.tasks[0].status, .completed)
    XCTAssertEqual(store.tasks[0].statusBeforeCompletion, .inProgress)
    XCTAssertEqual(notifications.reconciliations.count, 1)
}
```

- [ ] **Step 2: Run focused tests and verify RED**

Run: `swift test --filter TodoStoreTests`

Expected: compilation fails because `completeFromWidget` and the notification name are missing.

- [ ] **Step 3: Refactor status mutation behind one private helper**

Extract the existing completed transition into a worker mutation used by both `setStatus` and `completeFromWidget`. Extend private `submit` with an optional result callback, but preserve every existing public method signature and behavior.

- [ ] **Step 4: Publish task-change notifications only after successful state assignment**

Use one private method:

```swift
private func publish(_ newTasks: [TodoTask]) {
    tasks = newTasks
    NotificationCenter.default.post(name: .todoStoreTasksDidChange, object: self)
}
```

Call it from successful mutation, reload, `reloadStorageDirectory`, and `resumeAfterDirectoryMigration`. Do not post after failed persistence.

- [ ] **Step 5: Run TodoStore tests and inspect the scoped diff**

Run: `swift test --filter TodoStoreTests`

Expected: all TodoStore tests pass.

Review: `git diff -- Sources/xxMac/Managers/TodoStore.swift Tests/xxMacTests/TodoStoreTests.swift`

---

### Task 4: Host Widget Synchronization and Lifecycle Integration

**Files:**
- Create: `Sources/xxMac/Managers/TodoWidgetSyncCoordinator.swift`
- Create: `Sources/xxMac/Models/TodoDeepLink.swift`
- Modify: `Sources/xxMac/xxMac.swift`
- Modify: `Sources/xxMac/Info.plist`
- Create: `Tests/xxMacTests/TodoWidgetSyncCoordinatorTests.swift`
- Create: `Tests/xxMacTests/TodoDeepLinkTests.swift`

**Interfaces:**
- Produces `TodoWidgetTaskCompleting`, adopted by `TodoStore`:

```swift
@MainActor
protocol TodoWidgetTaskCompleting: AnyObject {
    var tasks: [TodoTask] { get }
    func completeFromWidget(id: UUID, completion: @escaping (Result<Void, Error>) -> Void)
}
```

- Produces injectable `TodoWidgetTimelineReloading` and `TodoWidgetChangeNotifying` wrappers around `WidgetCenter` and the Darwin notification center.
- Produces `@MainActor final class TodoWidgetSyncCoordinator` with `start()` and `synchronize()`.
- Produces `TodoDeepLink.route(for:) -> TodoDeepLinkRoute?`, recognizing only `xxmac://todo`.

- [ ] **Step 1: Write failing coordinator tests**

Use in-memory fakes for task completion, shared files, timeline reload, and change notification. Cover initial publish, sequential action consumption, failed actions retained, successful actions removed, no concurrent duplicate synchronization, TodoStore change republishing, and snapshot publication after all actions are consumed.

```swift
func testSynchronizeConsumesActionsBeforePublishingSnapshot() async throws {
    fileStore.actions = [TodoWidgetAction(id: actionID, taskID: taskID, kind: .complete, createdAt: now)]
    taskStore.tasks = [makeTask(id: taskID, status: .todo)]

    coordinator.synchronize()
    await coordinator.waitForIdleForTesting()

    XCTAssertEqual(taskStore.completedIDs, [taskID])
    XCTAssertTrue(fileStore.actions.isEmpty)
    XCTAssertFalse(try XCTUnwrap(fileStore.snapshot).items.contains { $0.id == taskID })
    XCTAssertEqual(timelineReloader.kinds, [TodoWidgetEnvironment.widgetKind])
}
```

- [ ] **Step 2: Run coordinator tests and verify RED**

Run: `swift test --filter TodoWidgetSyncCoordinatorTests`

Expected: compilation fails because the coordinator and protocols are missing.

- [ ] **Step 3: Implement serialized reconciliation and snapshot publication**

`synchronize()` must coalesce overlapping calls using `isSynchronizing` and `needsAnotherPass`. Read actions oldest-first, complete them one at a time, remove only successful operations, then build and write a snapshot from the current `taskStore.tasks`. Leave a failed action and all later actions in the journal for retry.

- [ ] **Step 4: Implement host notifications and WidgetKit reload wrapper**

Observe `.todoStoreTasksDidChange` locally and a stable Darwin notification name such as `com.xiaomi318.xxMac.todoWidgetActionsChanged`. Darwin callbacks dispatch to `MainActor` before calling `synchronize()`.

- [ ] **Step 5: Write failing deep-link tests**

Assert `xxmac://todo` returns `.todo`, while wrong hosts, schemes, and arbitrary paths return `nil`.

- [ ] **Step 6: Run deep-link tests and verify RED**

Run: `swift test --filter TodoDeepLinkTests`

Expected: compilation fails because `TodoDeepLink` is missing.

- [ ] **Step 7: Implement the URL route and application integration**

Register the `xxmac` URL scheme in `Info.plist`. Add one retained coordinator property to `AppDelegate`; after `TodoStore.shared` initialization, construct and start it. Call `synchronize()` from `applicationDidBecomeActive`. Implement `application(_:open:)` so `.todo` calls `TodoWindowController.shared.show()` without changing that controller.

- [ ] **Step 8: Run focused host tests and inspect the scoped diff**

Run: `swift test --filter 'TodoWidgetSyncCoordinatorTests|TodoDeepLinkTests|TodoStoreTests'`

Expected: all focused suites pass.

Review: `git diff -- Sources/xxMac/Managers/TodoWidgetSyncCoordinator.swift Sources/xxMac/Models/TodoDeepLink.swift Sources/xxMac/xxMac.swift Sources/xxMac/Info.plist Tests/xxMacTests`

---

### Task 5: Standalone Todo Widget Extension

**Files:**
- Create: `TodoWidget/TodoWidget.xcodeproj/project.pbxproj`
- Create: `TodoWidget/TodoWidgetExtension/Info.plist`
- Create: `TodoWidget/TodoWidgetExtension/TodoWidgetExtension.entitlements`
- Create: `TodoWidget/TodoWidgetExtension/TodoWidgetBundle.swift`
- Create: `TodoWidget/TodoWidgetExtension/TodoWidgetProvider.swift`
- Create: `TodoWidget/TodoWidgetExtension/TodoWidgetView.swift`
- Create: `TodoWidget/TodoWidgetExtension/CompleteTodoIntent.swift`
- Create: `TodoWidget/TodoWidgetExtension/Assets.xcassets/Contents.json`
- Create: `TodoWidget/TodoWidgetExtension/Assets.xcassets/AccentColor.colorset/Contents.json`
- Create: `TodoWidget/TodoWidgetExtension/Assets.xcassets/WidgetBackground.colorset/Contents.json`
- Create: `TodoWidget/TodoWidgetExtension/en.lproj/Localizable.strings`
- Create: `TodoWidget/TodoWidgetExtension/zh-Hans.lproj/Localizable.strings`
- Create: `TodoWidget/TodoWidgetExtension/zh-Hant.lproj/Localizable.strings`

**Interfaces:**
- The Xcode project has exactly one `com.apple.product-type.app-extension` target named `TodoWidgetExtension` and references the shared source files under `../Sources/TodoWidgetShared/`.
- Deployment target is macOS 14.0; product bundle identifier is `com.xiaomi318.xxMac.TodoWidget`; extension point is `com.apple.widgetkit-extension`.
- `TodoWidgetProvider` uses `TimelineProvider` and reads `TodoWidgetFileStore.appGroup()`.
- `CompleteTodoIntent` accepts `taskID: String`, appends a completion action, removes the item from the snapshot, posts the Darwin notification, and calls `WidgetCenter.shared.reloadTimelines(ofKind:)`.

- [ ] **Step 1: Create the minimal extension project and configuration files**

Set these build settings explicitly in the extension target:

```text
APPLICATION_EXTENSION_API_ONLY = YES
CODE_SIGNING_ALLOWED = NO
GENERATE_INFOPLIST_FILE = NO
INFOPLIST_FILE = TodoWidgetExtension/Info.plist
MACOSX_DEPLOYMENT_TARGET = 14.0
PRODUCT_BUNDLE_IDENTIFIER = com.xiaomi318.xxMac.TodoWidget
PRODUCT_NAME = TodoWidgetExtension
SKIP_INSTALL = YES
SWIFT_VERSION = 5.0
```

The bundle is built unsigned by Xcode because `bundle_app.sh` performs deterministic nested signing later.

- [ ] **Step 2: Implement provider placeholder, snapshot, and timeline loading**

Use a render entry containing the shared snapshot. For a valid snapshot, schedule the next timeline at `max(snapshot.nextRefreshAt, now + 60 seconds)`. For missing or invalid shared data, show an empty entry and retry no more frequently than 15 minutes.

- [ ] **Step 3: Implement the interactive completion intent**

Validate the UUID string before mutation. If App Group access or file writing fails, throw from `perform()` so the current row remains. On success, request a WidgetKit timeline reload and return `.result()` without setting `openAppWhenRun`.

- [ ] **Step 4: Implement the medium single-column view**

Use `.supportedFamilies([.systemMedium])`, `.containerBackground(.fill.tertiary, for: .widget)`, and `.widgetURL(URL(string: "xxmac://todo"))`. Render a compact header followed by `snapshot.items.prefix(10)` in a single `VStack`; each row uses a `Button(intent:)`, short category marker, and one-line truncated title. Use fixed vertical spacing and size constraints so 10 rows never overlap.

- [ ] **Step 5: Add localized widget strings**

Define translations for widget title, Today, In Progress, Todo, Overdue, empty state, completion accessibility label, and the `shown/total` count format in English, Simplified Chinese, and Traditional Chinese.

- [ ] **Step 6: Build the extension and inspect its product metadata**

Run:

```bash
xcodebuild \
  -project TodoWidget/TodoWidget.xcodeproj \
  -scheme TodoWidgetExtension \
  -configuration Release \
  -derivedDataPath .build/TodoWidgetDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Expected: exit 0 and `.build/TodoWidgetDerivedData/Build/Products/Release/TodoWidgetExtension.appex` exists.

Inspect:

```bash
plutil -p .build/TodoWidgetDerivedData/Build/Products/Release/TodoWidgetExtension.appex/Contents/Info.plist
```

Expected: correct extension point, bundle ID, version, executable, and minimum system version.

Review: `git diff -- TodoWidget`

---

### Task 6: App Group Entitlements and Bundle Packaging

**Files:**
- Modify: `xxMac.entitlements`
- Modify: `bundle_app.sh`
- Modify: `AGENTS.md`
- Create: `Tests/Shell/bundle_app_widget_test.sh`

**Interfaces:**
- Main entitlement retains `com.apple.security.app-sandbox = false` and adds `com.apple.security.application-groups = [group.com.xiaomi318.xxMac]`.
- Extension entitlement has sandbox enabled and the same App Group.
- `bundle_app.sh` builds/embeds the extension, signs the `.appex` first with its entitlement file, signs the host last with `xxMac.entitlements`, and validates both.
- `AGENTS.md` keeps SwiftPM commands for the host and documents the narrow extension-only `xcodebuild` exception.

- [ ] **Step 1: Write the failing shell packaging test**

Create fake `swift`, `xcodebuild`, and `codesign` commands under a temporary `PATH`. Run a copied `bundle_app.sh` with `INSTALL_TO_APPLICATIONS=0` and assert:

1. Extension build is invoked once with the TodoWidget project.
2. The `.appex` is copied to `xxMac.app/Contents/PlugIns/`.
3. Extension signing occurs before host signing.
4. Each signing call uses its expected entitlement file.
5. A missing `.appex` or missing App Group entitlement exits nonzero.

- [ ] **Step 2: Run the shell test and verify RED**

Run: `bash Tests/Shell/bundle_app_widget_test.sh`

Expected: failure because the current packaging script does not build or embed a widget.

- [ ] **Step 3: Add App Group entitlements and extension-aware packaging**

Use `ditto` or `cp -R` to embed the extension. Do not use `codesign --deep` as the primary signing mechanism; explicitly sign nested code first, then sign the host. Preserve the existing fixed-identity requirement and installation confirmation.

- [ ] **Step 4: Add deterministic post-sign verification**

Verify:

```bash
codesign --verify --strict --verbose=2 "$APP_BUNDLE/Contents/PlugIns/TodoWidgetExtension.appex"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
codesign -d --entitlements :- "$APP_BUNDLE"
codesign -d --entitlements :- "$APP_BUNDLE/Contents/PlugIns/TodoWidgetExtension.appex"
```

Parse the displayed entitlements and fail unless both include `group.com.xiaomi318.xxMac` and the extension has sandbox enabled.

- [ ] **Step 5: Update the repository build instruction narrowly**

Change `AGENTS.md` to state that the host still has no Xcode project and must not be built with `xcodebuild`; only `TodoWidget/TodoWidget.xcodeproj` is permitted for the Widget Extension and is normally invoked by `bundle_app.sh`.

- [ ] **Step 6: Run shell tests and inspect the scoped diff**

Run:

```bash
bash Tests/Shell/bundle_app_widget_test.sh
bash Tests/Shell/publish_dmg_release_notes_test.sh
```

Expected: both shell suites pass.

Review: `git diff -- xxMac.entitlements bundle_app.sh AGENTS.md Tests/Shell`

---

### Task 7: Documentation, Configuration Notice, and End-to-End Verification

**Files:**
- Modify: `README.md`
- Modify: `README_zh-CN.md`
- Modify: `Resources/en.lproj/Localizable.strings`
- Modify: `Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Resources/zh-Hant.lproj/Localizable.strings`

**Interfaces:**
- README feature tables describe the macOS 14+ medium interactive desktop widget, 10-row ordering, and direct completion.
- General > Configuration Folder text states that `todo.db` moves with the selected directory while regenerable widget snapshot/journal files remain in the system App Group container.

- [ ] **Step 1: Update configuration-folder localization without replacing unrelated wording**

Append one sentence to `common.config_directory_desc` in all three locales explaining the App Group exception. Preserve every existing clipboard, quick-script, paste-operation, browser-data, and local-only statement already in those strings.

- [ ] **Step 2: Update both README files in place**

Extend the existing Todo feature row and storage notes. Do not overwrite the current uncommitted release-script documentation changes. Include the exact user workflow: right-click desktop, choose Edit Widgets, find xxMac Todo, and add the medium widget.

- [ ] **Step 3: Run all automated tests**

Run: `swift test`

Expected: all Swift test suites pass with zero failures.

Run:

```bash
bash Tests/Shell/bundle_app_widget_test.sh
bash Tests/Shell/publish_dmg_release_notes_test.sh
```

Expected: both shell tests pass.

- [ ] **Step 4: Build the host and extension independently**

Run: `swift build`

Expected: exit 0.

Run the extension-only `xcodebuild` command from Task 5.

Expected: exit 0 and the `.appex` product exists.

- [ ] **Step 5: Build the application bundle without installing it**

Run: `printf 'n\n' | bash bundle_app.sh`

Expected: `xxMac.app` is generated, contains `Contents/PlugIns/TodoWidgetExtension.appex`, passes nested signature verification, and `/Applications/xxMac.app` is not replaced.

If the installed signing identity or provisioning does not authorize the App Group, stop here and report the exact signing/provisioning failure. Do not strip entitlements or claim runtime widget support.

- [ ] **Step 6: Inspect the complete worktree diff before runtime installation**

Run:

```bash
git status --short
git diff --check
git diff --stat
git diff -- Package.swift Sources/TodoWidgetShared Sources/xxMac/Managers/TodoWidgetSnapshotBuilder.swift Sources/xxMac/Managers/TodoWidgetSyncCoordinator.swift Sources/xxMac/Models/TodoDeepLink.swift Sources/xxMac/Managers/TodoStore.swift Sources/xxMac/xxMac.swift Sources/xxMac/Info.plist TodoWidget xxMac.entitlements bundle_app.sh AGENTS.md Tests README.md README_zh-CN.md Resources
```

Confirm there are no Todo window changes attributable to this feature and no unrelated edits were reverted.

- [ ] **Step 7: Perform confirmation-gated installed-app acceptance**

Only after explicit user approval to replace `/Applications/xxMac.app`, run `bash bundle_app.sh`, answer `y`, and verify the application relaunches. Then confirm with `pluginkit` or system widget discovery that `com.xiaomi318.xxMac.TodoWidget` is registered.

The user manually adds the medium xxMac Todo widget from macOS Edit Widgets. Validate:

1. One column renders without overlap and shows no more than 10 rows.
2. Ordering is Today, In Progress, Todo with no duplicates.
3. Completed and archived tasks are absent.
4. Clicking a title opens the Todo window.
5. Completing a task while xxMac runs updates SQLite and the widget.
6. Completing a task while xxMac is stopped removes it immediately; after relaunch it remains completed and does not reappear.
7. Crossing local midnight refreshes Today ordering without reinstalling the widget.

Document any step that requires user interaction separately from automated verification. Do not describe a successful build as successful desktop-widget acceptance.

