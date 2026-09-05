import SwiftUI

enum TodoTaskCardDensity {
    case comfortable
    case compact
}

struct TodoTaskCardActions {
    let onSelect: () -> Void
    let onToggleCompletion: () -> Void
    let onSetStatus: (TodoStatus) -> Void
    let onRollback: () -> Void
    let onEdit: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void
}

struct TodoTaskCard: View {
    let task: TodoTask
    let density: TodoTaskCardDensity
    let isSelected: Bool
    let showsQuadrant: Bool
    let onSelect: () -> Void
    let onToggleCompletion: () -> Void
    let onSetStatus: (TodoStatus) -> Void
    let onRollback: () -> Void
    let onEdit: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: density == .compact ? 8 : 10) {
            Button(action: onToggleCompletion) {
                Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: density == .compact ? 15 : 17, weight: .medium))
                    .foregroundStyle(task.status == .completed ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.status == .completed ? L10n.t("todo.action.reopen") : L10n.t("todo.action.complete"))

            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: density == .compact ? 3 : 5) {
                    Text(task.title)
                        .font(density == .compact ? .body : .headline)
                        .foregroundStyle(task.status == .completed ? .secondary : .primary)
                        .strikethrough(task.status == .completed)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(task.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(density == .compact ? 1 : 2)
                            .multilineTextAlignment(.leading)
                    }

                    HStack(spacing: 6) {
                        if let dueAt = task.dueAt {
                            TodoTaskBadge(
                                title: dueAt.formatted(date: .abbreviated, time: .shortened),
                                systemImage: "calendar",
                                color: deadlineColor(for: dueAt)
                            )
                        }
                        if showsQuadrant {
                            TodoTaskBadge(
                                title: task.quadrant.localizedTitle,
                                systemImage: task.quadrant.systemImage,
                                color: task.quadrant.tintColor
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture(count: 2).onEnded(onEdit))

            VStack(alignment: .trailing, spacing: 6) {
                Menu {
                    ForEach(TodoStatus.allCases) { status in
                        Button {
                            onSetStatus(status)
                        } label: {
                            Label(status.localizedTitle, systemImage: status.systemImage)
                        }
                        .disabled(status == task.status)
                    }
                } label: {
                    Label(task.status.localizedTitle, systemImage: task.status.systemImage)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(task.status.tintColor)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L10n.t("todo.action.change_status"))

                if task.status.previous != nil {
                    Button(action: onRollback) {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.t("todo.action.rollback"))
                    .accessibilityLabel(L10n.t("todo.action.rollback"))
                }

                Menu {
                    Button(action: onEdit) {
                        Label(L10n.t("todo.action.edit"), systemImage: "pencil")
                    }
                    Button(action: onArchive) {
                        Label(L10n.t("todo.action.archive"), systemImage: "archivebox")
                    }
                    Divider()
                    Button(role: .destructive, action: onDelete) {
                        Label(L10n.t("todo.action.delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L10n.t("todo.action.more"))
            }
        }
        .padding(density == .compact ? 9 : 12)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.75) : Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .opacity(task.status == .completed ? 0.78 : 1)
        .accessibilityElement(children: .contain)
    }

    private func deadlineColor(for dueAt: Date) -> Color {
        guard task.status != .completed else { return .secondary }
        if dueAt < Calendar.current.startOfDay(for: Date()) {
            return .red
        }
        if Calendar.current.isDateInToday(dueAt) {
            return .orange
        }
        return .secondary
    }
}

private struct TodoTaskBadge: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2)
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

extension TodoStatus {
    var localizedTitle: String {
        switch self {
        case .todo: return L10n.t("todo.status.todo")
        case .inProgress: return L10n.t("todo.status.in_progress")
        case .completed: return L10n.t("todo.status.completed")
        }
    }

    var systemImage: String {
        switch self {
        case .todo: return "circle"
        case .inProgress: return "clock.arrow.circlepath"
        case .completed: return "checkmark.circle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .todo: return .secondary
        case .inProgress: return .orange
        case .completed: return .green
        }
    }
}

extension TodoQuadrant {
    var localizedTitle: String {
        switch self {
        case .importantUrgent: return L10n.t("todo.quadrant.important_urgent")
        case .importantNotUrgent: return L10n.t("todo.quadrant.important_not_urgent")
        case .notImportantUrgent: return L10n.t("todo.quadrant.not_important_urgent")
        case .notImportantNotUrgent: return L10n.t("todo.quadrant.not_important_not_urgent")
        }
    }

    var systemImage: String {
        switch self {
        case .importantUrgent: return "exclamationmark.2"
        case .importantNotUrgent: return "star"
        case .notImportantUrgent: return "bolt"
        case .notImportantNotUrgent: return "leaf"
        }
    }

    var tintColor: Color {
        switch self {
        case .importantUrgent: return .red
        case .importantNotUrgent: return .blue
        case .notImportantUrgent: return .orange
        case .notImportantNotUrgent: return .green
        }
    }
}

extension TodoView {
    var localizedTitle: String {
        switch self {
        case .quadrants: return L10n.t("todo.view.quadrants")
        case .all: return L10n.t("todo.view.all")
        case .today: return L10n.t("todo.view.today")
        case .todo: return L10n.t("todo.status.todo")
        case .inProgress: return L10n.t("todo.status.in_progress")
        case .completed: return L10n.t("todo.status.completed")
        }
    }
}

extension TodoSort {
    var localizedTitle: String {
        switch self {
        case .updatedAt: return L10n.t("todo.sort.updated")
        case .createdAt: return L10n.t("todo.sort.created")
        case .dueAt: return L10n.t("todo.sort.due")
        case .status: return L10n.t("todo.sort.status")
        }
    }
}
