import Foundation

public enum TodoWidgetEnvironment {
    public static let widgetKind = "com.xiaomi318.xxMac.TodoWidget"
    public static let maximumItemCount = 10
    public static let actionsChangedNotification = "com.xiaomi318.xxMac.todoWidgetActionsChanged"
}

public enum TodoWidgetLayout {
    public static let fontSizeRange = 9...13
    public static let defaultFontSize = 9

    public static func clampedFontSize(_ value: Int) -> Int {
        min(max(value, fontSizeRange.lowerBound), fontSizeRange.upperBound)
    }

    public static func rowHeight(fontSize: Int) -> Int {
        clampedFontSize(fontSize) + 2
    }

    public static func pageSize(fontSize: Int) -> Int {
        max(1, 110 / rowHeight(fontSize: fontSize))
    }
}

public enum TodoWidgetPagination {
    public static func pageCount(
        itemCount: Int,
        pageSize: Int = TodoWidgetEnvironment.maximumItemCount
    ) -> Int {
        let validPageSize = max(1, pageSize)
        return max(1, (max(0, itemCount) + validPageSize - 1) / validPageSize)
    }

    public static func clampedPageIndex(
        _ pageIndex: Int,
        itemCount: Int,
        pageSize: Int = TodoWidgetEnvironment.maximumItemCount
    ) -> Int {
        min(max(0, pageIndex), pageCount(itemCount: itemCount, pageSize: pageSize) - 1)
    }

    public static func items<Element>(
        _ items: [Element],
        pageIndex: Int,
        pageSize: Int = TodoWidgetEnvironment.maximumItemCount
    ) -> [Element] {
        guard !items.isEmpty else { return [] }
        let validPageSize = max(1, pageSize)
        let page = clampedPageIndex(pageIndex, itemCount: items.count, pageSize: validPageSize)
        let start = page * validPageSize
        let end = min(items.count, start + validPageSize)
        return Array(items[start..<end])
    }
}

public struct TodoWidgetPresentationState: Codable, Equatable, Sendable {
    public let pageIndex: Int
    public let fontSize: Int

    public init(pageIndex: Int = 0, fontSize: Int = TodoWidgetLayout.defaultFontSize) {
        self.pageIndex = max(0, pageIndex)
        self.fontSize = TodoWidgetLayout.clampedFontSize(fontSize)
    }

    private enum CodingKeys: String, CodingKey {
        case pageIndex
        case fontSize
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            pageIndex: try container.decodeIfPresent(Int.self, forKey: .pageIndex) ?? 0,
            fontSize: try container.decodeIfPresent(Int.self, forKey: .fontSize)
                ?? TodoWidgetLayout.defaultFontSize
        )
    }
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
