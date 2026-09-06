import Foundation

public enum TodoWidgetEnvironment {
    public static let appGroupIdentifier = "group.com.xiaomi318.xxMac"
    public static let widgetKind = "com.xiaomi318.xxMac.TodoWidget"
    public static let maximumItemCount = 10
    public static let actionsChangedNotification = "com.xiaomi318.xxMac.todoWidgetActionsChanged"
}

public enum TodoWidgetCategory: String, Codable, Equatable, Sendable {
    case today
    case inProgress
    case todo
}

public struct TodoWidgetItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let category: TodoWidgetCategory
    public let dueAt: Date?

    public init(id: UUID, title: String, category: TodoWidgetCategory, dueAt: Date?) {
        self.id = id
        self.title = title
        self.category = category
        self.dueAt = dueAt
    }
}

public struct TodoWidgetSnapshot: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let nextRefreshAt: Date
    public let totalIncompleteCount: Int
    public let items: [TodoWidgetItem]

    public init(
        generatedAt: Date,
        nextRefreshAt: Date,
        totalIncompleteCount: Int,
        items: [TodoWidgetItem]
    ) {
        self.generatedAt = generatedAt
        self.nextRefreshAt = nextRefreshAt
        self.totalIncompleteCount = totalIncompleteCount
        self.items = items
    }

    public func removingItem(id: UUID) -> TodoWidgetSnapshot {
        let filtered = items.filter { $0.id != id }
        guard filtered.count != items.count else { return self }
        return TodoWidgetSnapshot(
            generatedAt: generatedAt,
            nextRefreshAt: nextRefreshAt,
            totalIncompleteCount: max(0, totalIncompleteCount - 1),
            items: filtered
        )
    }
}

public enum TodoWidgetActionKind: String, Codable, Equatable, Sendable {
    case complete
}

public struct TodoWidgetAction: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let taskID: UUID
    public let kind: TodoWidgetActionKind
    public let createdAt: Date

    public init(id: UUID, taskID: UUID, kind: TodoWidgetActionKind, createdAt: Date) {
        self.id = id
        self.taskID = taskID
        self.kind = kind
        self.createdAt = createdAt
    }
}
