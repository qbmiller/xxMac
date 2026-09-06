import SwiftUI
import WidgetKit

struct TodoWidget: Widget {
    let kind = TodoWidgetEnvironment.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodoWidgetProvider()) { entry in
            TodoWidgetView(entry: entry)
        }
        .configurationDisplayName(LocalizedStringKey("widget.title"))
        .description(LocalizedStringKey("widget.description"))
        .supportedFamilies([.systemMedium])
    }
}

struct TodoWidgetView: View {
    let entry: TodoWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            header

            if entry.snapshot.items.isEmpty {
                emptyState
            } else {
                ForEach(pageItems) { item in
                    TodoWidgetRow(
                        item: item,
                        referenceDate: entry.date,
                        fontSize: entry.fontSize
                    )
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "xxmac://todo"))
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "checklist")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("widget.title")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(countText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if pageCount > 1 {
                pageButton(systemName: "chevron.left", delta: -1, disabled: entry.pageIndex == 0)
                    .accessibilityLabel(Text("widget.previous_page"))
                pageButton(
                    systemName: "chevron.right",
                    delta: 1,
                    disabled: entry.pageIndex >= pageCount - 1
                )
                .accessibilityLabel(Text("widget.next_page"))
            }
        }
        .frame(height: 13)
    }

    private var emptyState: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("widget.empty")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var pageSize: Int {
        TodoWidgetLayout.pageSize(fontSize: entry.fontSize)
    }

    private var pageItems: [TodoWidgetItem] {
        TodoWidgetPagination.items(
            entry.snapshot.items,
            pageIndex: entry.pageIndex,
            pageSize: pageSize
        )
    }

    private var pageCount: Int {
        TodoWidgetPagination.pageCount(itemCount: entry.snapshot.items.count, pageSize: pageSize)
    }

    private var countText: String {
        String(
            format: NSLocalizedString("widget.page_format", comment: "Current page, page count, total Todo count"),
            entry.pageIndex + 1,
            pageCount,
            entry.snapshot.totalIncompleteCount
        )
    }

    private func pageButton(systemName: String, delta: Int, disabled: Bool) -> some View {
        Button(intent: ChangeTodoPageIntent(delta: delta)) {
            Image(systemName: systemName)
                .font(.system(size: 8, weight: .semibold))
                .frame(width: 12, height: 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

private struct TodoWidgetRow: View {
    let item: TodoWidgetItem
    let referenceDate: Date
    let fontSize: Int

    var body: some View {
        HStack(spacing: 4) {
            Button(intent: CompleteTodoIntent(taskID: item.id.uuidString)) {
                Image(systemName: "circle")
                    .font(.system(size: CGFloat(fontSize), weight: .medium))
                    .frame(
                        width: CGFloat(fontSize + 3),
                        height: CGFloat(TodoWidgetLayout.rowHeight(fontSize: fontSize))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(completeAccessibilityLabel)

            Circle()
                .fill(categoryColor)
                .frame(width: 4, height: 4)
                .accessibilityHidden(true)

            Text(categoryTitle)
                .font(.system(size: CGFloat(max(8, fontSize - 1))))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)
                .lineLimit(1)

            Text(item.title)
                .font(.system(size: CGFloat(fontSize)))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 2)

            if let deadlineText {
                Text(deadlineText)
                    .font(.system(size: CGFloat(max(8, fontSize - 1))).monospacedDigit())
                    .foregroundStyle(isOverdue ? .red : .secondary)
                    .lineLimit(1)
            }
        }
        .frame(height: CGFloat(TodoWidgetLayout.rowHeight(fontSize: fontSize)))
        .accessibilityElement(children: .contain)
    }

    private var categoryTitle: LocalizedStringKey {
        switch item.category {
        case .today: return "widget.category.today"
        case .inProgress: return "widget.category.in_progress"
        case .todo: return "widget.category.todo"
        }
    }

    private var categoryColor: Color {
        switch item.category {
        case .today: return .red
        case .inProgress: return .orange
        case .todo: return .secondary
        }
    }

    private var isOverdue: Bool {
        guard let dueAt = item.dueAt else { return false }
        return dueAt < Calendar.current.startOfDay(for: referenceDate)
    }

    private var deadlineText: String? {
        guard item.category == .today, let dueAt = item.dueAt else { return nil }
        if isOverdue {
            return NSLocalizedString("widget.overdue", comment: "Overdue Todo marker")
        }
        return dueAt.formatted(date: .omitted, time: .shortened)
    }

    private var completeAccessibilityLabel: String {
        String(
            format: NSLocalizedString("widget.complete_accessibility", comment: "Complete Todo button label"),
            item.title
        )
    }
}
