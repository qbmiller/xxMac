import SwiftUI

struct TodoQuadrantView: View {
    let tasks: [TodoTask]
    let selectedTaskID: TodoTask.ID?
    let actions: (TodoTask) -> TodoTaskCardActions

    private let columns = [
        GridItem(.flexible(minimum: 240), spacing: 10),
        GridItem(.flexible(minimum: 240), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(TodoQuadrant.allCases) { quadrant in
                TodoQuadrantCell(
                    quadrant: quadrant,
                    tasks: tasksForQuadrant(quadrant),
                    selectedTaskID: selectedTaskID,
                    actions: actions
                )
            }
        }
        .padding(12)
    }

    private func tasksForQuadrant(_ quadrant: TodoQuadrant) -> [TodoTask] {
        tasks
            .filter { $0.quadrant == quadrant }
            .sorted { left, right in
                left.quadrantRank == right.quadrantRank
                    ? left.updatedAt > right.updatedAt
                    : left.quadrantRank < right.quadrantRank
            }
    }
}

private struct TodoQuadrantCell: View {
    let quadrant: TodoQuadrant
    let tasks: [TodoTask]
    let selectedTaskID: TodoTask.ID?
    let actions: (TodoTask) -> TodoTaskCardActions

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: quadrant.systemImage)
                    .foregroundStyle(quadrant.tintColor)
                Text(quadrant.localizedTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(tasks.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)

            Divider()

            if tasks.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .foregroundStyle(.tertiary)
                    Text(L10n.t("todo.quadrant.empty"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(tasks) { task in
                            let taskActions = actions(task)
                            TodoTaskCard(
                                task: task,
                                density: .compact,
                                isSelected: selectedTaskID == task.id,
                                showsQuadrant: false,
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
                    .padding(8)
                }
            }
        }
        .frame(minHeight: 170, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
        .clipShape(.rect(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(quadrant.tintColor.opacity(0.3), lineWidth: 1)
        }
    }
}
