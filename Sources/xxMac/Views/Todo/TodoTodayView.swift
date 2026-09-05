import SwiftUI

struct TodoTodayView: View {
    let tasks: [TodoTask]
    let now: Date
    let selectedTaskID: TodoTask.ID?
    let actions: (TodoTask) -> TodoTaskCardActions

    private var groups: [TodoTodayGroup] {
        TodoTaskQuery.todayGroups(tasks, now: now)
    }

    var body: some View {
        if groups.isEmpty {
            TodoEmptyStateView(
                systemImage: "calendar",
                title: L10n.t("todo.today.empty_title"),
                message: L10n.t("todo.today.empty_message")
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(groups, id: \.section) { group in
                        TodoTodaySectionView(
                            group: group,
                            selectedTaskID: selectedTaskID,
                            actions: actions
                        )
                    }
                }
                .padding(14)
            }
        }
    }
}

private struct TodoTodaySectionView: View {
    let group: TodoTodayGroup
    let selectedTaskID: TodoTask.ID?
    let actions: (TodoTask) -> TodoTaskCardActions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: group.section.systemImage)
                    .foregroundStyle(group.section.tintColor)
                Text(group.section.localizedTitle)
                    .font(.headline)
                Text("\(group.tasks.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ForEach(group.tasks) { task in
                let taskActions = actions(task)
                TodoTaskCard(
                    task: task,
                    density: .compact,
                    isSelected: selectedTaskID == task.id,
                    showsQuadrant: true,
                    onSelect: taskActions.onSelect,
                    onToggleCompletion: taskActions.onToggleCompletion,
                    onSetStatus: taskActions.onSetStatus,
                    onRollback: taskActions.onRollback,
                    onEdit: taskActions.onEdit,
                    onArchive: taskActions.onArchive,
                    onDelete: taskActions.onDelete
                )
            }
        }
    }
}

extension TodoTodaySection {
    var localizedTitle: String {
        switch self {
        case .overdue: return L10n.t("todo.today.overdue")
        case .todayOpen: return L10n.t("todo.today.open")
        case .todayCompleted: return L10n.t("todo.today.completed")
        }
    }

    var systemImage: String {
        switch self {
        case .overdue: return "exclamationmark.triangle.fill"
        case .todayOpen: return "clock.fill"
        case .todayCompleted: return "checkmark.circle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .overdue: return .red
        case .todayOpen: return .orange
        case .todayCompleted: return .secondary
        }
    }
}
