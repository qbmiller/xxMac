import Foundation
import TodoWidgetShared

enum TodoWidgetSnapshotBuilder {
    static func makeSnapshot(
        tasks: [TodoTask],
        now: Date,
        calendar: Calendar = .current
    ) -> TodoWidgetSnapshot {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)
            ?? startOfToday.addingTimeInterval(86_400)
        let incomplete = tasks.filter { $0.archivedAt == nil && $0.status != .completed }

        let todayTasks = incomplete
            .filter { task in
                guard let dueAt = task.dueAt else { return false }
                return dueAt < startOfTomorrow
            }
            .sorted(by: todayOrder)
        let todayIDs = Set(todayTasks.map(\.id))

        let inProgressTasks = incomplete
            .filter { $0.status == .inProgress && !todayIDs.contains($0.id) }
            .sorted(by: statusOrder)
        let todoTasks = incomplete
            .filter { $0.status == .todo && !todayIDs.contains($0.id) }
            .sorted(by: statusOrder)

        let items = (
            todayTasks.map { item(from: $0, category: .today) }
                + inProgressTasks.map { item(from: $0, category: .inProgress) }
                + todoTasks.map { item(from: $0, category: .todo) }
        )

        return TodoWidgetSnapshot(
            generatedAt: now,
            nextRefreshAt: startOfTomorrow,
            totalIncompleteCount: incomplete.count,
            items: items
        )
    }

    private static func item(from task: TodoTask, category: TodoWidgetCategory) -> TodoWidgetItem {
        TodoWidgetItem(
            id: task.id,
            title: task.title,
            category: category,
            dueAt: task.dueAt
        )
    }

    private static func todayOrder(_ left: TodoTask, _ right: TodoTask) -> Bool {
        guard let leftDueAt = left.dueAt, let rightDueAt = right.dueAt else {
            return stableUpdatedOrder(left, right)
        }
        if leftDueAt != rightDueAt {
            return leftDueAt < rightDueAt
        }
        return stableUpdatedOrder(left, right)
    }

    private static func statusOrder(_ left: TodoTask, _ right: TodoTask) -> Bool {
        if left.statusRank != right.statusRank {
            return left.statusRank < right.statusRank
        }
        return stableUpdatedOrder(left, right)
    }

    private static func stableUpdatedOrder(_ left: TodoTask, _ right: TodoTask) -> Bool {
        if left.updatedAt != right.updatedAt {
            return left.updatedAt > right.updatedAt
        }
        return left.id.uuidString < right.id.uuidString
    }
}
