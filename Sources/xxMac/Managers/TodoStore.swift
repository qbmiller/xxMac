import Combine
import Foundation

@MainActor
final class TodoStore: ObservableObject {
    static let shared: TodoStore = {
        let database = try! TodoDatabase(url: ConfigDirectoryManager.shared.todoDatabaseURL)
        return TodoStore(persistence: database)
    }()

    @Published private(set) var tasks: [TodoTask]
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let worker: TodoStoreWorker
    private let notifications: TodoNotificationScheduling
    private let now: () -> Date
    private var migrationSourceURL: URL?

    init(
        persistence: TodoPersisting,
        notifications: TodoNotificationScheduling = TodoNotificationManager.shared,
        now: @escaping () -> Date = Date.init
    ) {
        let worker = TodoStoreWorker(persistence: persistence)
        self.worker = worker
        self.notifications = notifications
        self.now = now
        tasks = worker.initialTasks
        errorMessage = worker.initialError?.localizedDescription
    }

    func reload() {
        isLoading = true
        worker.reload { [weak self] result in
            guard let self else { return }
            self.isLoading = false
            switch result {
            case .success(let tasks):
                self.tasks = tasks
                self.errorMessage = nil
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func prepareForDirectoryMigration(
        currentDatabaseURL: URL = ConfigDirectoryManager.shared.todoDatabaseURL
    ) {
        migrationSourceURL = currentDatabaseURL.standardizedFileURL
        worker.checkpointAndClose()
    }

    func reloadStorageDirectory(
        _ databaseURL: URL = ConfigDirectoryManager.shared.todoDatabaseURL
    ) throws {
        tasks = try worker.reopen(at: databaseURL.standardizedFileURL)
        errorMessage = nil
    }

    func resumeAfterDirectoryMigration() throws {
        guard let migrationSourceURL else { return }
        tasks = try worker.reopen(at: migrationSourceURL)
        self.migrationSourceURL = nil
        errorMessage = nil
    }

    func create(
        title: String,
        notes: String,
        quadrant: TodoQuadrant,
        status: TodoStatus,
        dueAt: Date?
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let timestamp = now()

        submit { tasks, persistence in
            let quadrantRank = Self.rankAtEnd(
                tasks.filter { $0.archivedAt == nil && $0.quadrant == quadrant }.map(\.quadrantRank)
            )
            let statusRank = Self.rankAtEnd(
                tasks.filter { $0.archivedAt == nil && $0.status == status }.map(\.statusRank)
            )
            var task = TodoTask.makeNew(
                title: trimmedTitle,
                notes: notes,
                now: timestamp,
                quadrantRank: quadrantRank,
                statusRank: statusRank
            )
            task.quadrant = quadrant
            task.dueAt = dueAt
            if status != .todo {
                task = task.transitioned(to: status, at: timestamp)
            }
            try persistence.insert(task)
            tasks.append(task)
            return TodoStoreChange(old: nil, new: task)
        }
    }

    func save(_ task: TodoTask) {
        let trimmedTitle = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let timestamp = now()

        submit { tasks, persistence in
            guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return nil }
            let old = tasks[index]
            var updated = task
            updated.title = trimmedTitle
            updated.createdAt = old.createdAt
            updated.updatedAt = timestamp
            if old.status != updated.status {
                updated.completedAt = updated.status == .completed ? timestamp : nil
                updated.statusRank = Self.rankAtEnd(
                    tasks.filter {
                        $0.id != task.id && $0.archivedAt == nil && $0.status == updated.status
                    }.map(\.statusRank)
                )
            } else {
                updated.completedAt = old.completedAt
            }
            try persistence.update(updated)
            tasks[index] = updated
            return TodoStoreChange(old: old, new: updated)
        }
    }

    func setStatus(id: UUID, status: TodoStatus) {
        let timestamp = now()
        submit { tasks, persistence in
            guard let index = tasks.firstIndex(where: { $0.id == id }) else { return nil }
            let old = tasks[index]
            guard old.status != status else { return nil }
            let newRank = Self.rankAtEnd(
                tasks.filter { $0.id != id && $0.archivedAt == nil && $0.status == status }.map(\.statusRank)
            )
            let updated = old.moving(to: status, statusRank: newRank, at: timestamp)
            try persistence.update(updated)
            tasks[index] = updated
            return TodoStoreChange(old: old, new: updated)
        }
    }

    func rollbackStatus(id: UUID) {
        worker.read { tasks in
            tasks.first(where: { $0.id == id })?.status.previous
        } completion: { [weak self] previous in
            guard let self, let previous else { return }
            self.setStatus(id: id, status: previous)
        }
    }

    func moveToQuadrant(id: UUID, quadrant: TodoQuadrant, beforeID: UUID?) {
        let timestamp = now()
        submit { tasks, persistence in
            guard let index = tasks.firstIndex(where: { $0.id == id }) else { return nil }
            let old = tasks[index]
            let siblings = tasks
                .filter { $0.id != id && $0.archivedAt == nil && $0.quadrant == quadrant }
                .sorted { $0.quadrantRank < $1.quadrantRank }
            let rank = Self.insertionRank(in: siblings, beforeID: beforeID, keyPath: \.quadrantRank)
            let updated = old.moving(to: quadrant, quadrantRank: rank, at: timestamp)
            try persistence.update(updated)
            tasks[index] = updated
            return TodoStoreChange(old: old, new: updated)
        }
    }

    func moveToStatus(id: UUID, status: TodoStatus, beforeID: UUID?) {
        let timestamp = now()
        submit { tasks, persistence in
            guard let index = tasks.firstIndex(where: { $0.id == id }) else { return nil }
            let old = tasks[index]
            let siblings = tasks
                .filter { $0.id != id && $0.archivedAt == nil && $0.status == status }
                .sorted { $0.statusRank < $1.statusRank }
            let rank = Self.insertionRank(in: siblings, beforeID: beforeID, keyPath: \.statusRank)
            var updated = old
            if old.status != status {
                updated = old.transitioned(to: status, at: timestamp)
            } else {
                updated.updatedAt = timestamp
            }
            updated.statusRank = rank
            try persistence.update(updated)
            tasks[index] = updated
            return TodoStoreChange(old: old, new: updated)
        }
    }

    func archive(id: UUID) {
        let timestamp = now()
        submit { tasks, persistence in
            guard let index = tasks.firstIndex(where: { $0.id == id }) else { return nil }
            let old = tasks[index]
            guard old.archivedAt == nil else { return nil }
            var updated = old
            updated.archivedAt = timestamp
            updated.updatedAt = timestamp
            try persistence.update(updated)
            tasks[index] = updated
            return TodoStoreChange(old: old, new: updated)
        }
    }

    func restore(id: UUID) {
        let timestamp = now()
        submit { tasks, persistence in
            guard let index = tasks.firstIndex(where: { $0.id == id }) else { return nil }
            let old = tasks[index]
            guard old.archivedAt != nil else { return nil }
            var updated = old
            updated.archivedAt = nil
            updated.updatedAt = timestamp
            try persistence.update(updated)
            tasks[index] = updated
            return TodoStoreChange(old: old, new: updated)
        }
    }

    func delete(id: UUID) {
        submit { tasks, persistence in
            guard let index = tasks.firstIndex(where: { $0.id == id }) else { return nil }
            let old = tasks[index]
            try persistence.delete(id: id)
            tasks.remove(at: index)
            return TodoStoreChange(old: old, new: nil)
        }
    }

    private func submit(_ mutation: @escaping TodoStoreWorker.Mutation) {
        worker.perform(mutation) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let output):
                self.tasks = output.tasks
                self.errorMessage = nil
                if let change = output.change {
                    self.notifications.reconcile(old: change.old, new: change.new)
                }
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private static func rankAtEnd(_ ranks: [Double]) -> Double {
        TodoRankPolicy.rank(before: ranks.max(), after: nil)
    }

    private static func insertionRank(
        in siblings: [TodoTask],
        beforeID: UUID?,
        keyPath: KeyPath<TodoTask, Double>
    ) -> Double {
        guard let beforeID,
              let targetIndex = siblings.firstIndex(where: { $0.id == beforeID }) else {
            return TodoRankPolicy.rank(before: siblings.last?[keyPath: keyPath], after: nil)
        }
        let beforeRank = targetIndex > 0 ? siblings[targetIndex - 1][keyPath: keyPath] : nil
        let afterRank = siblings[targetIndex][keyPath: keyPath]
        return TodoRankPolicy.rank(before: beforeRank, after: afterRank)
    }
}

private struct TodoStoreChange {
    let old: TodoTask?
    let new: TodoTask?
}

private final class TodoStoreWorker {
    typealias Mutation = (inout [TodoTask], TodoPersisting) throws -> TodoStoreChange?
    typealias Output = (tasks: [TodoTask], change: TodoStoreChange?)

    let initialTasks: [TodoTask]
    let initialError: Error?

    private let persistence: TodoPersisting
    private let queue = DispatchQueue(label: "com.macefficiency.todo.store", qos: .userInitiated)
    private var tasks: [TodoTask]

    init(persistence: TodoPersisting) {
        self.persistence = persistence
        do {
            let tasks = try persistence.fetchTasks(includeArchived: true)
            self.tasks = tasks
            initialTasks = tasks
            initialError = nil
        } catch {
            tasks = []
            initialTasks = []
            initialError = error
        }
    }

    func perform(
        _ mutation: @escaping Mutation,
        completion: @escaping @MainActor (Result<Output, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            var candidate = self.tasks
            let result: Result<Output, Error>
            do {
                let change = try mutation(&candidate, self.persistence)
                self.tasks = candidate
                result = .success((candidate, change))
            } catch {
                result = .failure(error)
            }
            Task { @MainActor in
                completion(result)
            }
        }
    }

    func checkpointAndClose() {
        queue.sync {
            persistence.checkpointAndClose()
        }
    }

    func reopen(at url: URL) throws -> [TodoTask] {
        try queue.sync {
            try persistence.reopen(at: url)
            let reloaded = try persistence.fetchTasks(includeArchived: true)
            tasks = reloaded
            return reloaded
        }
    }

    func reload(completion: @escaping @MainActor (Result<[TodoTask], Error>) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let result = Result { try self.persistence.fetchTasks(includeArchived: true) }
            if case .success(let tasks) = result {
                self.tasks = tasks
            }
            Task { @MainActor in
                completion(result)
            }
        }
    }

    func read<T>(_ body: @escaping ([TodoTask]) -> T, completion: @escaping @MainActor (T) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let value = body(self.tasks)
            Task { @MainActor in
                completion(value)
            }
        }
    }
}
