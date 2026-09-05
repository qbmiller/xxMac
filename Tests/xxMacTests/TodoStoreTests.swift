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

    func testRollbackUsesFixedPreviousStatus() async throws {
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

    func checkpointAndClose() {}
    func reopen(at url: URL) throws {}
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
