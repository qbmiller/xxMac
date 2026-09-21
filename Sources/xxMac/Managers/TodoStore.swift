import Combine
import Foundation

extension Notification.Name {
    static let todoStoreTasksDidChange = Notification.Name("TodoStoreTasksDidChange")
}

@MainActor
final class TodoStore: ObservableObject {
    static let shared: TodoStore = {
        let database = try! TodoDatabase(url: ConfigDirectoryManager.shared.todoDatabaseURL)
        return TodoStore(persistence: database)
    }()

    @Published private(set) var tasks: [TodoTask]
    @Published private(set) var lists: [TodoList]
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
        lists = worker.initialLists
        errorMessage = worker.initialError?.localizedDescription
    }

    func reload() {
        isLoading = true
        worker.reload { [weak self] result in
            guard let self else { return }
            self.isLoading = false
            switch result {
            case .success(let state):
                self.lists = state.lists
                self.publish(state.tasks)
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
        let state = try worker.reopen(at: databaseURL.standardizedFileURL)
        lists = state.lists
        publish(state.tasks)
        errorMessage = nil
    }

    func resumeAfterDirectoryMigration() throws {
        guard let migrationSourceURL else { return }
        let state = try worker.reopen(at: migrationSourceURL)
        lists = state.lists
        publish(state.tasks)
        self.migrationSourceURL = nil
        errorMessage = nil
    }

    func create(
        title: String,
        notes: String,
        quadrant: TodoQuadrant,
        status: TodoStatus,
        dueAt: Date?,
        listID: UUID? = nil
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
            task.listID = listID
            task.dueAt = dueAt
            if status != .todo {
                task = task.transitioned(to: status, at: timestamp)
            }
            try persistence.insert(task)
            tasks.append(task)
            return TodoStoreChange(old: nil, new: task)
        }
    }

    func createList(
        name: String,
        id: UUID = UUID(),
        completion: ((Result<UUID, Error>) -> Void)? = nil
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let timestamp = now()
        submitList({ _, lists, persistence in
            let rank = Self.rankAtEnd(lists.map(\.rank))
            let list = TodoList.makeNew(id: id, name: trimmedName, now: timestamp, rank: rank)
            try persistence.insertList(list)
            lists.append(list)
            return false
        }, completion: { result in
            completion?(result.map { _ in id })
        })
    }

    func renameList(id: UUID, name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let timestamp = now()
        submitList { _, lists, persistence in
            guard let index = lists.firstIndex(where: { $0.id == id }) else { return false }
            var updated = lists[index]
            updated.name = trimmedName
            updated.updatedAt = timestamp
            try persistence.updateList(updated)
            lists[index] = updated
            return false
        }
    }

    func deleteList(id: UUID) {
        submitList { tasks, lists, persistence in
            guard lists.contains(where: { $0.id == id }) else { return false }
            try persistence.deleteList(id: id)
            lists.removeAll { $0.id == id }
            var changedTasks = false
            for index in tasks.indices where tasks[index].listID == id {
                tasks[index].listID = nil
                changedTasks = true
            }
            return changedTasks
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
                updated.statusBeforeCompletion = updated.status == .completed ? old.status : nil
                updated.completedAt = updated.status == .completed ? timestamp : nil
                updated.statusRank = Self.rankAtEnd(
                    tasks.filter {
                        $0.id != task.id && $0.archivedAt == nil && $0.status == updated.status
                    }.map(\.statusRank)
                )
            } else {
                updated.completedAt = old.completedAt
                updated.statusBeforeCompletion = old.statusBeforeCompletion
            }
            try persistence.update(updated)
            tasks[index] = updated
            return TodoStoreChange(old: old, new: updated)
        }
    }

    func setStatus(id: UUID, status: TodoStatus) {
        submit(Self.statusMutation(id: id, status: status, timestamp: now(), widgetCompletion: false))
    }

    func completeFromWidget(
        id: UUID,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        submit(
            Self.statusMutation(id: id, status: .completed, timestamp: now(), widgetCompletion: true)
        ) { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func rollbackStatus(id: UUID) {
        worker.read { tasks -> TodoStatus? in
            guard let task = tasks.first(where: { $0.id == id }) else { return nil }
            if task.status == .completed {
                return task.statusBeforeCompletion ?? .inProgress
            }
            return task.status.previous
        } completion: { [weak self] targetStatus in
            guard let self, let targetStatus else { return }
            self.setStatus(id: id, status: targetStatus)
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
            let plan = Self.insertionPlan(in: siblings, beforeID: beforeID, keyPath: \.quadrantRank)
            if plan.didNormalize {
                Self.applyNormalizedRanks(plan.siblings, to: &tasks, keyPath: \.quadrantRank)
            }
            let updated = old.moving(to: quadrant, quadrantRank: plan.rank, at: timestamp)
            if plan.didNormalize {
                try persistence.update(updated, normalizingRanks: plan.siblings)
            } else {
                try persistence.update(updated)
            }
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
            let plan = Self.insertionPlan(in: siblings, beforeID: beforeID, keyPath: \.statusRank)
            if plan.didNormalize {
                Self.applyNormalizedRanks(plan.siblings, to: &tasks, keyPath: \.statusRank)
            }
            var updated = old
            if old.status != status {
                updated = old.transitioned(to: status, at: timestamp)
            } else {
                updated.updatedAt = timestamp
            }
            updated.statusRank = plan.rank
            if plan.didNormalize {
                try persistence.update(updated, normalizingRanks: plan.siblings)
            } else {
                try persistence.update(updated)
            }
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

    private func submit(
        _ mutation: @escaping TodoStoreWorker.Mutation,
        completion: ((Result<TodoStoreWorker.Output, Error>) -> Void)? = nil
    ) {
        worker.perform(mutation) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let output):
                if output.change != nil {
                    self.publish(output.tasks)
                } else {
                    self.tasks = output.tasks
                }
                self.errorMessage = nil
                if let change = output.change {
                    self.notifications.reconcile(old: change.old, new: change.new)
                }
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
            completion?(result)
        }
    }

    private func submitList(
        _ mutation: @escaping TodoStoreWorker.ListMutation,
        completion: ((Result<TodoStoreWorker.ListOutput, Error>) -> Void)? = nil
    ) {
        worker.performList(mutation) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let output):
                self.lists = output.state.lists
                if output.changedTasks {
                    self.publish(output.state.tasks)
                } else {
                    self.tasks = output.state.tasks
                }
                self.errorMessage = nil
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
            completion?(result)
        }
    }

    private func publish(_ newTasks: [TodoTask]) {
        tasks = newTasks
        NotificationCenter.default.post(name: .todoStoreTasksDidChange, object: self)
    }

    private static func statusMutation(
        id: UUID,
        status: TodoStatus,
        timestamp: Date,
        widgetCompletion: Bool
    ) -> TodoStoreWorker.Mutation {
        { tasks, persistence in
            guard let index = tasks.firstIndex(where: { $0.id == id }) else { return nil }
            let old = tasks[index]
            if widgetCompletion && (old.archivedAt != nil || old.status == .completed) {
                return nil
            }
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

    private static func rankAtEnd(_ ranks: [Double]) -> Double {
        TodoRankPolicy.rank(before: ranks.max(), after: nil)
    }

    private static func insertionPlan(
        in siblings: [TodoTask],
        beforeID: UUID?,
        keyPath: WritableKeyPath<TodoTask, Double>
    ) -> TodoRankInsertionPlan {
        var ordered = siblings
        var neighbors = insertionNeighbors(in: ordered, beforeID: beforeID, keyPath: keyPath)
        var didNormalize = false

        if TodoRankPolicy.needsNormalization(before: neighbors.before, after: neighbors.after) {
            let normalized = TodoRankPolicy.normalizedRanks(count: ordered.count)
            for index in ordered.indices {
                ordered[index][keyPath: keyPath] = normalized[index]
            }
            neighbors = insertionNeighbors(in: ordered, beforeID: beforeID, keyPath: keyPath)
            didNormalize = true
        }

        return TodoRankInsertionPlan(
            siblings: ordered,
            rank: TodoRankPolicy.rank(before: neighbors.before, after: neighbors.after),
            didNormalize: didNormalize
        )
    }

    private static func insertionNeighbors(
        in siblings: [TodoTask],
        beforeID: UUID?,
        keyPath: KeyPath<TodoTask, Double>
    ) -> (before: Double?, after: Double?) {
        guard let beforeID,
              let targetIndex = siblings.firstIndex(where: { $0.id == beforeID }) else {
            return (siblings.last?[keyPath: keyPath], nil)
        }
        let beforeRank = targetIndex > 0 ? siblings[targetIndex - 1][keyPath: keyPath] : nil
        return (beforeRank, siblings[targetIndex][keyPath: keyPath])
    }

    private static func applyNormalizedRanks(
        _ normalized: [TodoTask],
        to tasks: inout [TodoTask],
        keyPath: WritableKeyPath<TodoTask, Double>
    ) {
        for task in normalized {
            guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { continue }
            tasks[index][keyPath: keyPath] = task[keyPath: keyPath]
        }
    }
}

private struct TodoRankInsertionPlan {
    let siblings: [TodoTask]
    let rank: Double
    let didNormalize: Bool
}

private struct TodoStoreChange {
    let old: TodoTask?
    let new: TodoTask?
}

private struct TodoStoreState {
    let tasks: [TodoTask]
    let lists: [TodoList]
}

private final class TodoStoreWorker {
    typealias Mutation = (inout [TodoTask], TodoPersisting) throws -> TodoStoreChange?
    typealias Output = (tasks: [TodoTask], change: TodoStoreChange?)
    typealias ListMutation = (inout [TodoTask], inout [TodoList], TodoPersisting) throws -> Bool
    typealias ListOutput = (state: TodoStoreState, changedTasks: Bool)

    let initialTasks: [TodoTask]
    let initialLists: [TodoList]
    let initialError: Error?

    private let persistence: TodoPersisting
    private let queue = DispatchQueue(label: "com.macefficiency.todo.store", qos: .userInitiated)
    private var tasks: [TodoTask]
    private var lists: [TodoList]

    init(persistence: TodoPersisting) {
        self.persistence = persistence
        do {
            let tasks = try persistence.fetchTasks(includeArchived: true)
            let lists = try persistence.fetchLists()
            self.tasks = tasks
            self.lists = lists
            initialTasks = tasks
            initialLists = lists
            initialError = nil
        } catch {
            tasks = []
            lists = []
            initialTasks = []
            initialLists = []
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

    func performList(
        _ mutation: @escaping ListMutation,
        completion: @escaping @MainActor (Result<ListOutput, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            var candidateTasks = self.tasks
            var candidateLists = self.lists
            let result: Result<ListOutput, Error>
            do {
                let changedTasks = try mutation(&candidateTasks, &candidateLists, self.persistence)
                self.tasks = candidateTasks
                self.lists = candidateLists
                result = .success((TodoStoreState(tasks: candidateTasks, lists: candidateLists), changedTasks))
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

    func reopen(at url: URL) throws -> TodoStoreState {
        try queue.sync {
            try persistence.reopen(at: url)
            let reloadedTasks = try persistence.fetchTasks(includeArchived: true)
            let reloadedLists = try persistence.fetchLists()
            tasks = reloadedTasks
            lists = reloadedLists
            return TodoStoreState(tasks: reloadedTasks, lists: reloadedLists)
        }
    }

    func reload(completion: @escaping @MainActor (Result<TodoStoreState, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let result = Result {
                TodoStoreState(
                    tasks: try self.persistence.fetchTasks(includeArchived: true),
                    lists: try self.persistence.fetchLists()
                )
            }
            if case .success(let state) = result {
                self.tasks = state.tasks
                self.lists = state.lists
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
