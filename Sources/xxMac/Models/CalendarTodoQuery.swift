import Foundation

/// The calendar is a date-based projection of Todo, never a second task store.
enum CalendarTodoQuery {
    static func tasks(
        _ tasks: [TodoTask],
        on date: Date,
        includeCompleted: Bool = false,
        calendar: Calendar = .current
    ) -> [TodoTask] {
        guard let interval = calendar.dateInterval(of: .day, for: date) else { return [] }
        return tasks.filter { task in
            guard task.archivedAt == nil, let dueAt = task.dueAt,
                  includeCompleted || task.status != .completed else { return false }
            return dueAt >= interval.start && dueAt < interval.end
        }.sorted { lhs, rhs in
            if (lhs.status == .completed) != (rhs.status == .completed) {
                return lhs.status != .completed
            }
            if lhs.dueAt != rhs.dueAt { return lhs.dueAt! < rhs.dueAt! }
            if lhs.quadrantRank != rhs.quadrantRank { return lhs.quadrantRank < rhs.quadrantRank }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    static func daysWithOpenTasks(_ tasks: [TodoTask], calendar: Calendar = .current) -> Set<Date> {
        Set(tasks.compactMap { task in
            guard task.archivedAt == nil, task.status != .completed, let dueAt = task.dueAt else { return nil }
            return calendar.startOfDay(for: dueAt)
        })
    }

    /// Tomorrow is relative to the action date. Calendar arithmetic preserves local
    /// wall-clock time across DST; a missing time advances to the next valid time.
    static func deferredDeadline(_ original: Date?, now: Date, calendar: Calendar = .current) -> Date? {
        guard let original,
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
            return nil
        }
        let time = calendar.dateComponents([.hour, .minute, .second], from: original)
        return calendar.date(
            bySettingHour: time.hour ?? 18, minute: time.minute ?? 0, second: time.second ?? 0,
            of: tomorrow, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward
        )
    }
}
