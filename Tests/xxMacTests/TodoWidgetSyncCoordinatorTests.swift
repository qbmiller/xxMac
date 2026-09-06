import Foundation
import TodoWidgetShared
import XCTest
@testable import xxMac

@MainActor
final class TodoWidgetSyncCoordinatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testSynchronizeConsumesActionsBeforePublishingSnapshot() async throws {
        let first = makeTask(title: "First")
        let second = makeTask(title: "Second")
        let taskStore = WidgetTaskStoreFake(tasks: [first, second])
        let fileStore = WidgetFileStoreFake(actions: [
            TodoWidgetAction(id: UUID(), taskID: first.id, kind: .complete, createdAt: now),
            TodoWidgetAction(id: UUID(), taskID: second.id, kind: .complete, createdAt: now.addingTimeInterval(1))
        ])
        let reloader = WidgetTimelineReloaderFake()
        let refreshed = expectation(description: "Timeline refreshed")
        reloader.onReload = { refreshed.fulfill() }
        let coordinator = TodoWidgetSyncCoordinator(
            taskStore: taskStore,
            fileStore: fileStore,
            timelineReloader: reloader,
            changeNotifier: WidgetChangeNotifierFake(),
            now: { self.now }
        )

        coordinator.synchronize()
        await fulfillment(of: [refreshed], timeout: 2)

        XCTAssertEqual(taskStore.completedIDs, [first.id, second.id])
        XCTAssertTrue(fileStore.actions.isEmpty)
        XCTAssertEqual(fileStore.snapshot?.items, [])
        XCTAssertEqual(fileStore.snapshot?.totalIncompleteCount, 0)
        XCTAssertEqual(reloader.reloadCount, 1)
    }

    func testFailedCompletionKeepsCurrentAndLaterActionsForRetry() async throws {
        let failing = makeTask(title: "Failing")
        let later = makeTask(title: "Later")
        let firstAction = TodoWidgetAction(id: UUID(), taskID: failing.id, kind: .complete, createdAt: now)
        let laterAction = TodoWidgetAction(
            id: UUID(),
            taskID: later.id,
            kind: .complete,
            createdAt: now.addingTimeInterval(1)
        )
        let taskStore = WidgetTaskStoreFake(tasks: [failing, later])
        taskStore.failureIDs = [failing.id]
        let fileStore = WidgetFileStoreFake(actions: [firstAction, laterAction])
        let reloader = WidgetTimelineReloaderFake()
        let refreshed = expectation(description: "Timeline refreshed after failure")
        reloader.onReload = { refreshed.fulfill() }
        let coordinator = TodoWidgetSyncCoordinator(
            taskStore: taskStore,
            fileStore: fileStore,
            timelineReloader: reloader,
            changeNotifier: WidgetChangeNotifierFake(),
            now: { self.now }
        )

        coordinator.synchronize()
        await fulfillment(of: [refreshed], timeout: 2)

        XCTAssertEqual(taskStore.completedIDs, [failing.id])
        XCTAssertEqual(fileStore.actions, [firstAction, laterAction])
        XCTAssertEqual(Set(fileStore.snapshot?.items.map(\.id) ?? []), Set([failing.id, later.id]))
    }

    func testUnreadableActionJournalStillPublishesCurrentSnapshot() async throws {
        let task = makeTask(title: "Current")
        let taskStore = WidgetTaskStoreFake(tasks: [task])
        let fileStore = WidgetFileStoreFake()
        fileStore.readActionsError = WidgetSyncTestError.readActionsFailed
        let reloader = WidgetTimelineReloaderFake()
        let refreshed = expectation(description: "Timeline refreshed after journal read failure")
        reloader.onReload = { refreshed.fulfill() }
        let coordinator = TodoWidgetSyncCoordinator(
            taskStore: taskStore,
            fileStore: fileStore,
            timelineReloader: reloader,
            changeNotifier: WidgetChangeNotifierFake(),
            now: { self.now }
        )

        coordinator.synchronize()
        await fulfillment(of: [refreshed], timeout: 2)

        XCTAssertEqual(fileStore.snapshot?.items.map(\.id), [task.id])
        XCTAssertEqual(fileStore.snapshot?.totalIncompleteCount, 1)
        XCTAssertEqual(reloader.reloadCount, 1)
    }

    func testStartRespondsToWidgetChangeNotification() async throws {
        let task = makeTask(title: "Notified")
        let action = TodoWidgetAction(id: UUID(), taskID: task.id, kind: .complete, createdAt: now)
        let taskStore = WidgetTaskStoreFake(tasks: [task])
        let fileStore = WidgetFileStoreFake()
        let reloader = WidgetTimelineReloaderFake()
        let notifier = WidgetChangeNotifierFake()
        let initialRefresh = expectation(description: "Initial refresh")
        let actionRefresh = expectation(description: "Action refresh")
        var refreshIndex = 0
        reloader.onReload = {
            refreshIndex += 1
            if refreshIndex == 1 {
                initialRefresh.fulfill()
            } else if refreshIndex == 2 {
                actionRefresh.fulfill()
            }
        }
        let coordinator = TodoWidgetSyncCoordinator(
            taskStore: taskStore,
            fileStore: fileStore,
            timelineReloader: reloader,
            changeNotifier: notifier,
            now: { self.now }
        )

        coordinator.start()
        await fulfillment(of: [initialRefresh], timeout: 2)
        fileStore.actions = [action]
        notifier.sendActionsChanged()
        await fulfillment(of: [actionRefresh], timeout: 2)

        XCTAssertEqual(taskStore.completedIDs, [task.id])
        XCTAssertTrue(fileStore.actions.isEmpty)
    }

    private func makeTask(title: String) -> TodoTask {
        TodoTask.makeNew(title: title, now: now)
    }
}

private enum WidgetSyncTestError: Error {
    case completionFailed
    case readActionsFailed
}

@MainActor
private final class WidgetTaskStoreFake: TodoWidgetTaskCompleting {
    var tasks: [TodoTask]
    var failureIDs: Set<UUID> = []
    private(set) var completedIDs: [UUID] = []

    init(tasks: [TodoTask]) {
        self.tasks = tasks
    }

    func completeFromWidget(id: UUID, completion: @escaping (Result<Void, Error>) -> Void) {
        completedIDs.append(id)
        if failureIDs.contains(id) {
            completion(.failure(WidgetSyncTestError.completionFailed))
            return
        }
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            tasks[index] = tasks[index].transitioned(to: .completed)
        }
        completion(.success(()))
    }
}

private final class WidgetFileStoreFake: TodoWidgetFileStoring {
    var snapshot: TodoWidgetSnapshot?
    var actions: [TodoWidgetAction]
    var readActionsError: Error?

    init(snapshot: TodoWidgetSnapshot? = nil, actions: [TodoWidgetAction] = []) {
        self.snapshot = snapshot
        self.actions = actions
    }

    func readSnapshot() throws -> TodoWidgetSnapshot? { snapshot }
    func writeSnapshot(_ snapshot: TodoWidgetSnapshot) throws { self.snapshot = snapshot }
    func readActions() throws -> [TodoWidgetAction] {
        if let readActionsError {
            throw readActionsError
        }
        return actions
    }

    func readPageIndex() throws -> Int { 0 }
    func readFontSize() throws -> Int { TodoWidgetLayout.defaultFontSize }
    func setFontSize(_ fontSize: Int) throws -> Int { TodoWidgetLayout.clampedFontSize(fontSize) }
    func movePage(by delta: Int) throws -> Int { 0 }

    func appendCompletion(taskID: UUID, now: Date) throws -> TodoWidgetAction {
        let action = TodoWidgetAction(id: UUID(), taskID: taskID, kind: .complete, createdAt: now)
        actions.append(action)
        return action
    }

    func removeAction(id: UUID) throws {
        actions.removeAll { $0.id == id }
    }

    func removeItemFromSnapshot(taskID: UUID) throws {
        snapshot = snapshot?.removingItem(id: taskID)
    }
}

private final class WidgetTimelineReloaderFake: TodoWidgetTimelineReloading {
    private(set) var reloadCount = 0
    var onReload: (() -> Void)?

    func reloadTodoWidget() {
        reloadCount += 1
        onReload?()
    }
}

private final class WidgetChangeNotifierFake: TodoWidgetChangeNotifying {
    private var handler: (() -> Void)?

    func start(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func sendActionsChanged() {
        handler?()
    }
}
