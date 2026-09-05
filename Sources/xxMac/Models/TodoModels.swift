import Foundation

enum TodoStatus: String, CaseIterable, Codable, Identifiable, Hashable {
    case todo
    case inProgress
    case completed

    var id: String { rawValue }

    var previous: TodoStatus? {
        switch self {
        case .todo:
            return nil
        case .inProgress:
            return .todo
        case .completed:
            return .inProgress
        }
    }
}

enum TodoQuadrant: String, CaseIterable, Codable, Identifiable, Hashable {
    case importantUrgent
    case importantNotUrgent
    case notImportantUrgent
    case notImportantNotUrgent

    var id: String { rawValue }
}

enum TodoView: String, CaseIterable, Codable, Identifiable {
    case quadrants
    case all
    case today
    case todo
    case inProgress
    case completed

    var id: String { rawValue }
}

enum TodoListLayout: String, CaseIterable, Codable, Identifiable {
    case cards
    case list

    var id: String { rawValue }
}

enum TodoSort: String, CaseIterable, Codable, Identifiable {
    case updatedAt
    case createdAt
    case dueAt
    case status

    var id: String { rawValue }
}

enum TodoTodaySection: String, CaseIterable, Identifiable {
    case overdue
    case todayOpen
    case todayCompleted

    var id: String { rawValue }
}

struct TodoTodayGroup: Equatable {
    let section: TodoTodaySection
    let tasks: [TodoTask]
}

struct TodoTask: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var title: String
    var notes: String
    var status: TodoStatus
    var quadrant: TodoQuadrant
    var dueAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var archivedAt: Date?
    var quadrantRank: Double
    var statusRank: Double

    static func makeNew(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        now: Date = Date(),
        quadrantRank: Double = TodoRankPolicy.spacing,
        statusRank: Double = TodoRankPolicy.spacing
    ) -> TodoTask {
        TodoTask(
            id: id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes,
            status: .todo,
            quadrant: .notImportantNotUrgent,
            dueAt: nil,
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            archivedAt: nil,
            quadrantRank: quadrantRank,
            statusRank: statusRank
        )
    }

    func transitioned(to newStatus: TodoStatus, at date: Date = Date()) -> TodoTask {
        var copy = self
        copy.status = newStatus
        copy.updatedAt = date
        copy.completedAt = newStatus == .completed ? date : nil
        return copy
    }

    func moving(
        to newQuadrant: TodoQuadrant,
        quadrantRank newRank: Double,
        at date: Date = Date()
    ) -> TodoTask {
        var copy = self
        copy.quadrant = newQuadrant
        copy.quadrantRank = newRank
        copy.updatedAt = date
        return copy
    }

    func moving(
        to newStatus: TodoStatus,
        statusRank newRank: Double,
        at date: Date = Date()
    ) -> TodoTask {
        var copy = transitioned(to: newStatus, at: date)
        copy.statusRank = newRank
        return copy
    }
}

struct TodoTaskDraft: Equatable {
    var title: String
    var notes: String
    var status: TodoStatus
    var quadrant: TodoQuadrant
    var dueAt: Date?

    init(task: TodoTask) {
        title = task.title
        notes = task.notes
        status = task.status
        quadrant = task.quadrant
        dueAt = task.dueAt
    }
}

enum TodoTaskQuery {
    static func active(_ tasks: [TodoTask]) -> [TodoTask] {
        tasks.filter { $0.archivedAt == nil }
    }

    static func archived(_ tasks: [TodoTask]) -> [TodoTask] {
        tasks.filter { $0.archivedAt != nil }
    }

    static func search(_ tasks: [TodoTask], text: String) -> [TodoTask] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return tasks }
        return tasks.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
                $0.notes.localizedCaseInsensitiveContains(query)
        }
    }

    static func tasks(
        _ tasks: [TodoTask],
        for view: TodoView,
        searchText: String = "",
        now: Date = Date(),
        calendar: Calendar = .current,
        hideCompletedInQuadrants: Bool = false,
        sort: TodoSort = .updatedAt
    ) -> [TodoTask] {
        var result = active(tasks)
        switch view {
        case .quadrants:
            if hideCompletedInQuadrants {
                result.removeAll { $0.status == .completed }
            }
            result.sort { quadrantOrder($0, $1) }
        case .all:
            result = sorted(result, by: sort)
        case .today:
            result = todayGroups(result, now: now, calendar: calendar).flatMap(\.tasks)
        case .todo:
            result = result.filter { $0.status == .todo }.sorted { statusOrder($0, $1) }
        case .inProgress:
            result = result.filter { $0.status == .inProgress }.sorted { statusOrder($0, $1) }
        case .completed:
            result = result.filter { $0.status == .completed }.sorted { statusOrder($0, $1) }
        }
        return search(result, text: searchText)
    }

    static func todayGroups(
        _ tasks: [TodoTask],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TodoTodayGroup] {
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let activeTasks = active(tasks)

        let overdue = activeTasks.filter {
            guard let dueAt = $0.dueAt else { return false }
            return $0.status != .completed && dueAt < start
        }.sorted(by: dueDateOrder)

        let todayOpen = activeTasks.filter {
            guard let dueAt = $0.dueAt else { return false }
            return $0.status != .completed && dueAt >= start && dueAt < end
        }.sorted(by: dueDateOrder)

        let todayCompleted = activeTasks.filter {
            guard let dueAt = $0.dueAt else { return false }
            return $0.status == .completed && dueAt >= start && dueAt < end
        }.sorted(by: dueDateOrder)

        return [
            TodoTodayGroup(section: .overdue, tasks: overdue),
            TodoTodayGroup(section: .todayOpen, tasks: todayOpen),
            TodoTodayGroup(section: .todayCompleted, tasks: todayCompleted)
        ].filter { !$0.tasks.isEmpty }
    }

    static func sorted(_ tasks: [TodoTask], by sort: TodoSort) -> [TodoTask] {
        switch sort {
        case .updatedAt:
            return tasks.sorted { $0.updatedAt > $1.updatedAt }
        case .createdAt:
            return tasks.sorted { $0.createdAt > $1.createdAt }
        case .dueAt:
            return tasks.sorted(by: dueDateOrder)
        case .status:
            return tasks.sorted {
                let left = TodoStatus.allCases.firstIndex(of: $0.status) ?? 0
                let right = TodoStatus.allCases.firstIndex(of: $1.status) ?? 0
                return left == right ? $0.statusRank < $1.statusRank : left < right
            }
        }
    }

    private static func dueDateOrder(_ left: TodoTask, _ right: TodoTask) -> Bool {
        switch (left.dueAt, right.dueAt) {
        case let (lhs?, rhs?):
            return lhs == rhs ? left.updatedAt > right.updatedAt : lhs < rhs
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return left.updatedAt > right.updatedAt
        }
    }

    private static func quadrantOrder(_ left: TodoTask, _ right: TodoTask) -> Bool {
        if left.quadrant == right.quadrant {
            return left.quadrantRank < right.quadrantRank
        }
        let lhs = TodoQuadrant.allCases.firstIndex(of: left.quadrant) ?? 0
        let rhs = TodoQuadrant.allCases.firstIndex(of: right.quadrant) ?? 0
        return lhs < rhs
    }

    private static func statusOrder(_ left: TodoTask, _ right: TodoTask) -> Bool {
        left.statusRank == right.statusRank ? left.updatedAt > right.updatedAt : left.statusRank < right.statusRank
    }
}

enum TodoRankPolicy {
    static let spacing = 1_024.0

    static func rank(before: Double?, after: Double?) -> Double {
        switch (before, after) {
        case let (left?, right?):
            return (left + right) / 2
        case let (left?, nil):
            return left + spacing
        case let (nil, right?):
            return right - spacing
        case (nil, nil):
            return spacing
        }
    }

    static func normalizedRanks(count: Int) -> [Double] {
        guard count > 0 else { return [] }
        return (1...count).map { Double($0) * spacing }
    }

    static func needsNormalization(before: Double?, after: Double?) -> Bool {
        guard let before, let after else { return false }
        return abs(after - before) < 0.000_001
    }
}
