import Combine
import Foundation
import UserNotifications
import XCTest
@testable import xxMac

@MainActor
final class TodoStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testCreatePersistsBeforePublishingTask() async throws {
        let events = LockedEvents()
        let persistence = TodoPersistenceFake()
        persistence.onInsert = { events.append("persist") }
        let notifications = TodoNotificationSpy()
        let store = TodoStore(persistence: persistence, notifications: notifications, now: { self.now })
        var cancellables: Set<AnyCancellable> = []
        store.$tasks.dropFirst().sink { _ in events.append("publish") }.store(in: &cancellables)

        store.create(
            title: "  New task  ",
            notes: "Notes",
            quadrant: .importantUrgent,
            status: .todo,
            dueAt: self.now.addingTimeInterval(3_600)
        )
        try await waitUntil { store.tasks.count == 1 }

        XCTAssertEqual(events.values, ["persist", "publish"])
        XCTAssertEqual(store.tasks[0].title, "New task")
        XCTAssertEqual(store.tasks[0].quadrant, .importantUrgent)
        XCTAssertEqual(persistence.tasks, store.tasks)
        XCTAssertEqual(notifications.reconciliations.count, 1)
        _ = cancellables
    }

    func testFailedWriteLeavesPublishedSnapshotUnchanged() async throws {
        let original = makeTask(title: "Original")
        let persistence = TodoPersistenceFake(tasks: [original])
        persistence.updateError = TestError.writeFailed
        let store = TodoStore(persistence: persistence, notifications: TodoNotificationSpy(), now: { self.now })

        store.setStatus(id: original.id, status: .completed)
        try await waitUntil { store.errorMessage != nil }

        XCTAssertEqual(store.tasks, [original])
        XCTAssertEqual(persistence.tasks, [original])
    }

    func testLegacyCompletedTaskWithoutHistoryUsesFixedFallback() async throws {
        var completed = makeTask(title: "Completed", status: .completed)
        completed.completedAt = now.addingTimeInterval(-60)
        let persistence = TodoPersistenceFake(tasks: [completed])
        let store = TodoStore(persistence: persistence, notifications: TodoNotificationSpy(), now: { self.now })

        store.rollbackStatus(id: completed.id)
        try await waitUntil { store.tasks.first?.status == .inProgress }
        XCTAssertNil(store.tasks.first?.completedAt)

        store.rollbackStatus(id: completed.id)
        try await waitUntil { store.tasks.first?.status == .todo }
        XCTAssertNil(store.tasks.first?.status.previous)
    }

    func testCancellingCompletionRestoresStatusBeforeCompletion() async throws {
        let task = makeTask(title: "Restore original status")
        let persistence = TodoPersistenceFake(tasks: [task])
        let store = TodoStore(persistence: persistence, notifications: TodoNotificationSpy(), now: { self.now })

        store.setStatus(id: task.id, status: .completed)
        try await waitUntil { store.tasks.first?.status == .completed }
        XCTAssertEqual(persistence.tasks.first?.statusBeforeCompletion, .todo)

        let reloadedStore = TodoStore(
            persistence: persistence,
            notifications: TodoNotificationSpy(),
            now: { self.now }
        )
        reloadedStore.rollbackStatus(id: task.id)
        try await waitUntil { reloadedStore.tasks.first?.status == .todo }

        XCTAssertNil(reloadedStore.tasks.first?.completedAt)
        XCTAssertNil(reloadedStore.tasks.first?.statusBeforeCompletion)
    }

    func testCancellingCompletionRestoresInProgressStatus() async throws {
        let task = makeTask(title: "Continue original work", status: .inProgress)
        let persistence = TodoPersistenceFake(tasks: [task])
        let store = TodoStore(persistence: persistence, notifications: TodoNotificationSpy(), now: { self.now })

        store.setStatus(id: task.id, status: .completed)
        try await waitUntil { store.tasks.first?.status == .completed }

        store.rollbackStatus(id: task.id)
        try await waitUntil { store.tasks.first?.status == .inProgress }
    }

    func testQuadrantAndStatusMovesChangeIndependentRanks() async throws {
        let target = makeTask(title: "Target", quadrantRank: 1_024, statusRank: 3_000)
        let quadrantNeighbor = makeTask(
            title: "Quadrant neighbor",
            quadrant: .importantUrgent,
            quadrantRank: 4_000,
            statusRank: 4_000
        )
        let statusNeighbor = makeTask(
            title: "Status neighbor",
            status: .inProgress,
            quadrantRank: 5_000,
            statusRank: 6_000
        )
        let persistence = TodoPersistenceFake(tasks: [target, quadrantNeighbor, statusNeighbor])
        let store = TodoStore(persistence: persistence, notifications: TodoNotificationSpy(), now: { self.now })

        store.moveToQuadrant(id: target.id, quadrant: .importantUrgent, beforeID: quadrantNeighbor.id)
        try await waitUntil { store.tasks.first(where: { $0.id == target.id })?.quadrant == .importantUrgent }
        let quadrantMoved = try XCTUnwrap(store.tasks.first(where: { $0.id == target.id }))
        XCTAssertEqual(quadrantMoved.statusRank, 3_000)
        XCTAssertLessThan(quadrantMoved.quadrantRank, quadrantNeighbor.quadrantRank)

        store.moveToStatus(id: target.id, status: .inProgress, beforeID: statusNeighbor.id)
        try await waitUntil { store.tasks.first(where: { $0.id == target.id })?.status == .inProgress }
        let statusMoved = try XCTUnwrap(store.tasks.first(where: { $0.id == target.id }))
        XCTAssertEqual(statusMoved.quadrantRank, quadrantMoved.quadrantRank)
        XCTAssertLessThan(statusMoved.statusRank, statusNeighbor.statusRank)
    }

    func testMoveToQuadrantSupportsStartMiddleAndEndPlacement() async throws {
        let first = makeTask(title: "First", quadrant: .importantUrgent, quadrantRank: 1_024)
        let second = makeTask(title: "Second", quadrant: .importantUrgent, quadrantRank: 2_048)
        let third = makeTask(title: "Third", quadrant: .importantUrgent, quadrantRank: 3_072)
        let target = makeTask(title: "Target", quadrant: .notImportantNotUrgent, quadrantRank: 1_024)
        let persistence = TodoPersistenceFake(tasks: [first, second, third, target])
        let store = TodoStore(persistence: persistence, notifications: TodoNotificationSpy(), now: { self.now })

        store.moveToQuadrant(id: target.id, quadrant: .importantUrgent, beforeID: first.id)
        try await waitUntil { self.quadrantOrder(in: store).first == target.id }
        XCTAssertEqual(quadrantOrder(in: store), [target.id, first.id, second.id, third.id])

        store.moveToQuadrant(id: target.id, quadrant: .importantUrgent, beforeID: third.id)
        try await waitUntil { self.quadrantOrder(in: store) == [first.id, second.id, target.id, third.id] }

        store.moveToQuadrant(id: target.id, quadrant: .importantUrgent, beforeID: nil)
        try await waitUntil { self.quadrantOrder(in: store).last == target.id }
        XCTAssertEqual(quadrantOrder(in: store), [first.id, second.id, third.id, target.id])
    }

    func testMoveToStatusSupportsStartMiddleAndEndPlacement() async throws {
        let first = makeTask(title: "First", status: .inProgress, statusRank: 1_024)
        let second = makeTask(title: "Second", status: .inProgress, statusRank: 2_048)
        let third = makeTask(title: "Third", status: .inProgress, statusRank: 3_072)
        let target = makeTask(title: "Target", status: .todo, statusRank: 1_024)
        let persistence = TodoPersistenceFake(tasks: [first, second, third, target])
        let store = TodoStore(persistence: persistence, notifications: TodoNotificationSpy(), now: { self.now })

        store.moveToStatus(id: target.id, status: .inProgress, beforeID: first.id)
        try await waitUntil { self.statusOrder(in: store).first == target.id }
        XCTAssertEqual(statusOrder(in: store), [target.id, first.id, second.id, third.id])

        store.moveToStatus(id: target.id, status: .inProgress, beforeID: third.id)
        try await waitUntil { self.statusOrder(in: store) == [first.id, second.id, target.id, third.id] }

        store.moveToStatus(id: target.id, status: .inProgress, beforeID: nil)
        try await waitUntil { self.statusOrder(in: store).last == target.id }
        XCTAssertEqual(statusOrder(in: store), [first.id, second.id, third.id, target.id])
    }

    func testMoveUsesHiddenSiblingsWhenCalculatingInsertionRank() async throws {
        let first = makeTask(title: "Visible first", quadrant: .importantUrgent, quadrantRank: 1_024)
        let hidden = makeTask(title: "Hidden by search", quadrant: .importantUrgent, quadrantRank: 2_048)
        let visibleTarget = makeTask(title: "Visible target", quadrant: .importantUrgent, quadrantRank: 3_072)
        let moving = makeTask(title: "Moving", quadrant: .notImportantNotUrgent, quadrantRank: 1_024)
        let persistence = TodoPersistenceFake(tasks: [first, hidden, visibleTarget, moving])
        let store = TodoStore(persistence: persistence, notifications: TodoNotificationSpy(), now: { self.now })

        store.moveToQuadrant(id: moving.id, quadrant: .importantUrgent, beforeID: visibleTarget.id)
        try await waitUntil { self.quadrantOrder(in: store).contains(moving.id) }

        XCTAssertEqual(quadrantOrder(in: store), [first.id, hidden.id, moving.id, visibleTarget.id])
    }

    func testMoveNormalizesOnlyTargetLaneWhenRanksHaveNoGap() async throws {
        let first = makeTask(title: "First", quadrant: .importantUrgent, quadrantRank: 1_024, statusRank: 9_000)
        let second = makeTask(
            title: "Second",
            quadrant: .importantUrgent,
            quadrantRank: Double(1_024).nextUp,
            statusRank: 8_000
        )
        let unrelated = makeTask(title: "Unrelated", quadrant: .notImportantUrgent, quadrantRank: 77, statusRank: 7_000)
        let moving = makeTask(title: "Moving", quadrant: .notImportantNotUrgent, quadrantRank: 1_024, statusRank: 6_000)
        let persistence = TodoPersistenceFake(tasks: [first, second, unrelated, moving])
        let store = TodoStore(persistence: persistence, notifications: TodoNotificationSpy(), now: { self.now })

        store.moveToQuadrant(id: moving.id, quadrant: .importantUrgent, beforeID: second.id)
        try await waitUntil { self.quadrantOrder(in: store) == [first.id, moving.id, second.id] }

        let ordered = store.tasks
            .filter { $0.quadrant == .importantUrgent }
            .sorted { $0.quadrantRank < $1.quadrantRank }
        XCTAssertEqual(ordered.map(\.id), [first.id, moving.id, second.id])
        XCTAssertEqual(Set(ordered.map(\.quadrantRank)).count, 3)
        XCTAssertEqual(store.tasks.first(where: { $0.id == unrelated.id })?.quadrantRank, 77)
        XCTAssertEqual(store.tasks.first(where: { $0.id == first.id })?.statusRank, 9_000)
        XCTAssertEqual(persistence.tasks, store.tasks)
    }

    func testDirectoryMigrationReopensNewDatabasePath() throws {
        let persistence = TodoPersistenceFake(tasks: [makeTask(title: "Stored")])
        let store = TodoStore(persistence: persistence, notifications: TodoNotificationSpy(), now: { self.now })
        let oldURL = URL(fileURLWithPath: "/tmp/old-todo.db")
        let newURL = URL(fileURLWithPath: "/tmp/new-todo.db")

        store.prepareForDirectoryMigration(currentDatabaseURL: oldURL)
        try store.reloadStorageDirectory(newURL)

        XCTAssertEqual(persistence.checkpointCount, 1)
        XCTAssertEqual(persistence.reopenedURLs, [newURL])
        XCTAssertEqual(store.tasks.map(\.title), ["Stored"])
    }

    func testFailedDirectoryMigrationReopensPreviousDatabasePath() throws {
        let persistence = TodoPersistenceFake(tasks: [makeTask(title: "Stored")])
        let store = TodoStore(persistence: persistence, notifications: TodoNotificationSpy(), now: { self.now })
        let oldURL = URL(fileURLWithPath: "/tmp/old-todo.db")

        store.prepareForDirectoryMigration(currentDatabaseURL: oldURL)
        try store.resumeAfterDirectoryMigration()

        XCTAssertEqual(persistence.checkpointCount, 1)
        XCTAssertEqual(persistence.reopenedURLs, [oldURL])
    }

    func testArchiveRestoreAndDeletePublishPersistedLifecycle() async throws {
        let task = makeTask(title: "Lifecycle")
        let persistence = TodoPersistenceFake(tasks: [task])
        let store = TodoStore(persistence: persistence, notifications: TodoNotificationSpy(), now: { self.now })

        store.archive(id: task.id)
        try await waitUntil { store.tasks.first?.archivedAt != nil }

        store.restore(id: task.id)
        try await waitUntil { store.tasks.first?.archivedAt == nil }

        store.delete(id: task.id)
        try await waitUntil { store.tasks.isEmpty }
        XCTAssertTrue(persistence.tasks.isEmpty)
    }

    func testWidgetCompletionUsesNormalCompletionTransition() async throws {
        let task = makeTask(title: "Active", status: .inProgress)
        let persistence = TodoPersistenceFake(tasks: [task])
        let notifications = TodoNotificationSpy()
        let store = TodoStore(persistence: persistence, notifications: notifications, now: { self.now })

        let result = await completionResult(store: store, id: task.id)

        try result.get()
        XCTAssertEqual(store.tasks[0].status, .completed)
        XCTAssertEqual(store.tasks[0].completedAt, now)
        XCTAssertEqual(store.tasks[0].statusBeforeCompletion, .inProgress)
        XCTAssertEqual(persistence.tasks, store.tasks)
        XCTAssertEqual(notifications.reconciliations.count, 1)
    }

    func testWidgetCompletionTreatsMissingCompletedAndArchivedTasksAsSuccess() async throws {
        var completed = makeTask(title: "Completed", status: .completed)
        completed.completedAt = now.addingTimeInterval(-60)
        var archived = makeTask(title: "Archived")
        archived.archivedAt = now.addingTimeInterval(-60)
        let persistence = TodoPersistenceFake(tasks: [completed, archived])
        let notifications = TodoNotificationSpy()
        let store = TodoStore(persistence: persistence, notifications: notifications, now: { self.now })

        try await completionResult(store: store, id: UUID()).get()
        try await completionResult(store: store, id: completed.id).get()
        try await completionResult(store: store, id: archived.id).get()

        XCTAssertEqual(store.tasks, [completed, archived])
        XCTAssertEqual(persistence.tasks, [completed, archived])
        XCTAssertTrue(notifications.reconciliations.isEmpty)
    }

    func testWidgetCompletionReturnsPersistenceFailureWithoutPublishing() async throws {
        let task = makeTask(title: "Failure")
        let persistence = TodoPersistenceFake(tasks: [task])
        persistence.updateError = TestError.writeFailed
        let store = TodoStore(persistence: persistence, notifications: TodoNotificationSpy(), now: { self.now })

        let result = await completionResult(store: store, id: task.id)

        XCTAssertThrowsError(try result.get())
        XCTAssertEqual(store.tasks, [task])
        XCTAssertEqual(persistence.tasks, [task])
    }

    func testSuccessfulMutationPostsTasksDidChangeAfterPublishing() async throws {
        let persistence = TodoPersistenceFake()
        let store = TodoStore(persistence: persistence, notifications: TodoNotificationSpy(), now: { self.now })
        let expectation = expectation(description: "Todo tasks changed")
        var publishedTitles: [String] = []
        let observer = NotificationCenter.default.addObserver(
            forName: .todoStoreTasksDidChange,
            object: store,
            queue: .main
        ) { _ in
            Task { @MainActor in
                publishedTitles = store.tasks.map(\.title)
                expectation.fulfill()
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        store.create(
            title: "Published",
            notes: "",
            quadrant: .notImportantNotUrgent,
            status: .todo,
            dueAt: nil
        )
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertEqual(publishedTitles, ["Published"])
    }

    private func completionResult(store: TodoStore, id: UUID) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            store.completeFromWidget(id: id) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func makeTask(
        title: String,
        status: TodoStatus = .todo,
        quadrant: TodoQuadrant = .notImportantNotUrgent,
        quadrantRank: Double = 1_024,
        statusRank: Double = 1_024
    ) -> TodoTask {
        var task = TodoTask.makeNew(
            title: title,
            now: now,
            quadrantRank: quadrantRank,
            statusRank: statusRank
        )
        task.status = status
        task.quadrant = quadrant
        return task
    }

    private func quadrantOrder(in store: TodoStore) -> [UUID] {
        store.tasks
            .filter { $0.archivedAt == nil && $0.quadrant == .importantUrgent }
            .sorted { $0.quadrantRank < $1.quadrantRank }
            .map(\.id)
    }

    private func statusOrder(in store: TodoStore) -> [UUID] {
        store.tasks
            .filter { $0.archivedAt == nil && $0.status == .inProgress }
            .sorted { $0.statusRank < $1.statusRank }
            .map(\.id)
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let start = DispatchTime.now().uptimeNanoseconds
        while !condition() {
            if DispatchTime.now().uptimeNanoseconds - start > timeoutNanoseconds {
                XCTFail("Timed out waiting for TodoStore state")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

private enum TestError: Error {
    case writeFailed
}

private final class LockedEvents {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

private final class TodoPersistenceFake: TodoPersisting {
    private let lock = NSLock()
    private var storage: [TodoTask]
    var onInsert: (() -> Void)?
    var updateError: Error?
    private(set) var checkpointCount = 0
    private(set) var reopenedURLs: [URL] = []

    init(tasks: [TodoTask] = []) {
        storage = tasks
    }

    var tasks: [TodoTask] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func fetchTasks(includeArchived: Bool) throws -> [TodoTask] {
        lock.lock()
        defer { lock.unlock() }
        return includeArchived ? storage : storage.filter { $0.archivedAt == nil }
    }

    func insert(_ task: TodoTask) throws {
        onInsert?()
        lock.lock()
        storage.append(task)
        lock.unlock()
    }

    func update(_ task: TodoTask) throws {
        if let updateError { throw updateError }
        lock.lock()
        defer { lock.unlock() }
        guard let index = storage.firstIndex(where: { $0.id == task.id }) else { return }
        storage[index] = task
    }

    func update(_ task: TodoTask, normalizingRanks tasks: [TodoTask]) throws {
        if let updateError { throw updateError }
        lock.lock()
        defer { lock.unlock() }
        for normalized in tasks {
            guard let index = storage.firstIndex(where: { $0.id == normalized.id }) else { continue }
            storage[index].quadrantRank = normalized.quadrantRank
            storage[index].statusRank = normalized.statusRank
        }
        guard let index = storage.firstIndex(where: { $0.id == task.id }) else { return }
        storage[index] = task
    }

    func updateRanks(_ tasks: [TodoTask]) throws {
        lock.lock()
        defer { lock.unlock() }
        for task in tasks {
            guard let index = storage.firstIndex(where: { $0.id == task.id }) else { continue }
            storage[index].quadrantRank = task.quadrantRank
            storage[index].statusRank = task.statusRank
        }
    }

    func delete(id: UUID) throws {
        lock.lock()
        storage.removeAll { $0.id == id }
        lock.unlock()
    }

    func checkpointAndClose() {
        lock.lock()
        checkpointCount += 1
        lock.unlock()
    }

    func reopen(at url: URL) throws {
        lock.lock()
        reopenedURLs.append(url)
        lock.unlock()
    }
}

private final class TodoNotificationSpy: TodoNotificationScheduling {
    private(set) var reconciliations: [(old: TodoTask?, new: TodoTask?)] = []

    func reconcile(old: TodoTask?, new: TodoTask?) {
        reconciliations.append((old, new))
    }

    func authorizationStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
        completion(.authorized)
    }

    func openSystemSettings() {}
}
