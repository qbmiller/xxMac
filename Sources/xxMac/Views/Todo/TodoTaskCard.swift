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

    @State private var isHovered = false
    @ObservedObject private var preferences = TodoPreferencesStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 7 : 9) {
            HStack(alignment: .top, spacing: density == .compact ? 8 : 10) {
                Button(action: onToggleCompletion) {
                    Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: density == .compact ? 15 : 17, weight: .medium))
                        .foregroundStyle(task.status == .completed ? Color.accentColor : task.quadrant.tintColor)
                }
                .buttonStyle(.plain)
                .padding(.top, 1)
                .accessibilityLabel(task.status == .completed ? L10n.t("todo.action.reopen") : L10n.t("todo.action.complete"))

                Button(action: onSelect) {
                    VStack(alignment: .leading, spacing: density == .compact ? 3 : 5) {
                        Text(task.title)
                            .font(.system(
                                size: CGFloat(preferences.fontSize),
                                weight: density == .compact ? .regular : .semibold
                            ))
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
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture(count: 2).onEnded(onEdit))

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
                        .frame(width: 18, height: 18)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L10n.t("todo.action.more"))
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

                Spacer(minLength: 4)

                if task.status.previous != nil {
                    Button(action: onRollback) {
                        Image(systemName: "arrow.uturn.backward")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.t("todo.action.rollback"))
                    .accessibilityLabel(L10n.t("todo.action.rollback"))
                }

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
                        .font(.caption)
                        .foregroundStyle(task.status.tintColor)
                        .padding(.horizontal, 6)
                        .frame(height: 22)
                        .background(task.status.tintColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L10n.t("todo.action.change_status"))
            }
        }
        .padding(.leading, density == .compact ? 11 : 13)
        .padding(.trailing, density == .compact ? 9 : 11)
        .padding(.vertical, density == .compact ? 9 : 11)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(cardBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.78) : Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(task.quadrant.tintColor.opacity(task.status == .completed ? 0.4 : 0.85))
                .frame(width: 3)
                .padding(.vertical, 7)
        }
        .shadow(color: .black.opacity(isHovered && !isSelected ? 0.06 : 0), radius: 4, y: 1)
        .opacity(task.status == .completed ? 0.78 : 1)
        .accessibilityElement(children: .contain)
        .onHover { isHovered = $0 }
    }

    private var cardBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }
        if isHovered {
            return Color(nsColor: .selectedContentBackgroundColor).opacity(0.08)
        }
        return Color(nsColor: .controlBackgroundColor)
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
            .frame(height: 22)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
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

    var statusFilter: TodoStatus? {
        switch self {
        case .todo: return .todo
        case .inProgress: return .inProgress
        case .completed: return .completed
        case .quadrants, .all, .today: return nil
        }
    }

    var systemImage: String {
        switch self {
        case .quadrants: return "square.grid.2x2"
        case .all: return "tray.full"
        case .today: return "calendar"
        case .todo: return "circle"
        case .inProgress: return "clock.arrow.circlepath"
        case .completed: return "checkmark.circle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .quadrants: return .purple
        case .all: return .blue
        case .today: return .orange
        case .todo: return .secondary
        case .inProgress: return .orange
        case .completed: return .green
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
