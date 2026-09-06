import Foundation
import WidgetKit

struct TodoWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: TodoWidgetSnapshot
    let pageIndex: Int
    let fontSize: Int
}

struct TodoWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoWidgetEntry {
        TodoWidgetEntry(
            date: Date(),
            snapshot: Self.placeholderSnapshot,
            pageIndex: 0,
            fontSize: TodoWidgetLayout.defaultFontSize
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TodoWidgetEntry) -> Void) {
        completion(loadEntry(at: Date(), usePlaceholderWhenEmpty: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoWidgetEntry>) -> Void) {
        let now = Date()
        let entry = loadEntry(at: now, usePlaceholderWhenEmpty: false)
        let minimumRefresh = now.addingTimeInterval(60)
        let refreshAt: Date
        if entry.snapshot.items.isEmpty {
            refreshAt = now.addingTimeInterval(15 * 60)
        } else {
            refreshAt = max(entry.snapshot.nextRefreshAt, minimumRefresh)
        }
        completion(Timeline(entries: [entry], policy: .after(refreshAt)))
    }

    private func loadEntry(at date: Date, usePlaceholderWhenEmpty: Bool) -> TodoWidgetEntry {
        let store = TodoWidgetFileStore.shared()
        if let snapshot = try? store.readSnapshot() {
            let fontSize = (try? store.readFontSize()) ?? TodoWidgetLayout.defaultFontSize
            let pageSize = TodoWidgetLayout.pageSize(fontSize: fontSize)
            let pageIndex = TodoWidgetPagination.clampedPageIndex(
                (try? store.readPageIndex()) ?? 0,
                itemCount: snapshot.items.count,
                pageSize: pageSize
            )
            return TodoWidgetEntry(
                date: date,
                snapshot: snapshot,
                pageIndex: pageIndex,
                fontSize: fontSize
            )
        }
        let snapshot = usePlaceholderWhenEmpty ? Self.placeholderSnapshot : Self.emptySnapshot(at: date)
        return TodoWidgetEntry(
            date: date,
            snapshot: snapshot,
            pageIndex: 0,
            fontSize: TodoWidgetLayout.defaultFontSize
        )
    }

    private static func emptySnapshot(at date: Date) -> TodoWidgetSnapshot {
        TodoWidgetSnapshot(
            generatedAt: date,
            nextRefreshAt: date.addingTimeInterval(15 * 60),
            totalIncompleteCount: 0,
            items: []
        )
    }

    private static let placeholderSnapshot = TodoWidgetSnapshot(
        generatedAt: Date(),
        nextRefreshAt: Date().addingTimeInterval(60 * 60),
        totalIncompleteCount: 3,
        items: [
            TodoWidgetItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                title: "Review today tasks",
                category: .today,
                dueAt: Date().addingTimeInterval(60 * 60)
            ),
            TodoWidgetItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                title: "Prepare release notes",
                category: .inProgress,
                dueAt: nil
            ),
            TodoWidgetItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                title: "Plan next task",
                category: .todo,
                dueAt: nil
            )
        ]
    )
}
