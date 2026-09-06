import Foundation
import TodoWidgetShared
import WidgetKit

@MainActor
protocol TodoWidgetTaskCompleting: AnyObject {
    var tasks: [TodoTask] { get }
    func completeFromWidget(id: UUID, completion: @escaping (Result<Void, Error>) -> Void)
}

extension TodoStore: TodoWidgetTaskCompleting {}

@MainActor
protocol TodoWidgetTimelineReloading: AnyObject {
    func reloadTodoWidget()
}

@MainActor
final class SystemTodoWidgetTimelineReloader: TodoWidgetTimelineReloading {
    func reloadTodoWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: TodoWidgetEnvironment.widgetKind)
    }
}

@MainActor
protocol TodoWidgetChangeNotifying: AnyObject {
    func start(handler: @escaping () -> Void)
}

@MainActor
final class DarwinTodoWidgetChangeNotifier: TodoWidgetChangeNotifying {
    private var handler: (() -> Void)?
    private var isObserving = false

    func start(handler: @escaping () -> Void) {
        self.handler = handler
        guard !isObserving else { return }
        isObserving = true
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let notifier = Unmanaged<DarwinTodoWidgetChangeNotifier>
                    .fromOpaque(observer)
                    .takeUnretainedValue()
                Task { @MainActor in
                    notifier.handler?()
                }
            },
            TodoWidgetEnvironment.actionsChangedNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        guard isObserving else { return }
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(TodoWidgetEnvironment.actionsChangedNotification as CFString),
            nil
        )
    }
}

@MainActor
final class TodoWidgetSyncCoordinator {
    private let taskStore: TodoWidgetTaskCompleting
    private let fileStore: TodoWidgetFileStoring
    private let timelineReloader: TodoWidgetTimelineReloading
    private let changeNotifier: TodoWidgetChangeNotifying
    private let now: () -> Date
    private let calendar: Calendar
    private var taskChangeObserver: NSObjectProtocol?
    private var isStarted = false
    private var isSynchronizing = false
    private var needsAnotherPass = false

    init(
        taskStore: TodoWidgetTaskCompleting,
        fileStore: TodoWidgetFileStoring,
        timelineReloader: TodoWidgetTimelineReloading? = nil,
        changeNotifier: TodoWidgetChangeNotifying? = nil,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.taskStore = taskStore
        self.fileStore = fileStore
        self.timelineReloader = timelineReloader ?? SystemTodoWidgetTimelineReloader()
        self.changeNotifier = changeNotifier ?? DarwinTodoWidgetChangeNotifier()
        self.now = now
        self.calendar = calendar
    }

    deinit {
        if let taskChangeObserver {
            NotificationCenter.default.removeObserver(taskChangeObserver)
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        changeNotifier.start { [weak self] in
            self?.synchronize()
        }
        taskChangeObserver = NotificationCenter.default.addObserver(
            forName: .todoStoreTasksDidChange,
            object: taskStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.synchronize()
            }
        }
        synchronize()
    }

    func synchronize() {
        if isSynchronizing {
            needsAnotherPass = true
            return
        }
        isSynchronizing = true

        do {
            let actions = try fileStore.readActions().sorted {
                if $0.createdAt != $1.createdAt {
                    return $0.createdAt < $1.createdAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }
            consume(actions, at: 0)
        } catch {
            publishSnapshotAndFinish()
        }
    }

    private func consume(_ actions: [TodoWidgetAction], at index: Int) {
        guard index < actions.count else {
            publishSnapshotAndFinish()
            return
        }
        let action = actions[index]
        guard action.kind == .complete else {
            publishSnapshotAndFinish()
            return
        }

        taskStore.completeFromWidget(id: action.taskID) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                do {
                    try self.fileStore.removeAction(id: action.id)
                    self.consume(actions, at: index + 1)
                } catch {
                    self.publishSnapshotAndFinish()
                }
            case .failure:
                self.publishSnapshotAndFinish()
            }
        }
    }

    private func publishSnapshotAndFinish() {
        let snapshot = TodoWidgetSnapshotBuilder.makeSnapshot(
            tasks: taskStore.tasks,
            now: now(),
            calendar: calendar
        )
        do {
            try fileStore.writeSnapshot(snapshot)
            timelineReloader.reloadTodoWidget()
        } catch {
            // A later activation or task change retries the entire synchronization.
        }
        finishSynchronization()
    }

    private func finishSynchronization() {
        isSynchronizing = false
        guard needsAnotherPass else { return }
        needsAnotherPass = false
        synchronize()
    }
}
