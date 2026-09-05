import SwiftUI

struct TodoStatusBoardView: View {
    let tasks: [TodoTask]
    let selectedTaskID: TodoTask.ID?
    let actions: (TodoTask) -> TodoTaskCardActions
    let onMove: (UUID, TodoStatus, UUID?) -> Void

    var body: some View {
        GeometryReader { proxy in
            let columnWidth = max(320, (proxy.size.width - 44) / 3)
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(TodoStatus.allCases) { status in
                        TodoStatusColumn(
                            status: status,
                            tasks: tasksForStatus(status),
                            selectedTaskID: selectedTaskID,
                            actions: actions,
                            onMove: onMove
                        )
                        .frame(width: columnWidth)
                    }
                }
                .padding(12)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
        }
    }

    private func tasksForStatus(_ status: TodoStatus) -> [TodoTask] {
        tasks
            .filter { $0.status == status }
            .sorted { left, right in
                left.statusRank == right.statusRank
                    ? left.updatedAt > right.updatedAt
                    : left.statusRank < right.statusRank
            }
    }
}

private struct TodoStatusColumn: View {
    let status: TodoStatus
    let tasks: [TodoTask]
    let selectedTaskID: TodoTask.ID?
    let actions: (TodoTask) -> TodoTaskCardActions
    let onMove: (UUID, TodoStatus, UUID?) -> Void

    var body: some View {
        TodoLaneDropTarget(
            destination: TodoDropDestination(kind: .status(status), beforeID: nil),
            onMove: handleMove
        ) {
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: status.systemImage)
                        .foregroundStyle(status.tintColor)
                    Text(status.localizedTitle)
                        .font(.headline)
                    Text("\(tasks.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 10)

                Divider()

                if tasks.isEmpty {
                    VStack(spacing: 7) {
                        Image(systemName: "tray")
                            .foregroundStyle(.tertiary)
                        Text(L10n.t("todo.board.empty"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(tasks) { task in
                                let taskActions = actions(task)
                                TodoDraggableTaskCard(
                                    payload: TodoDragPayload(taskID: task.id, source: .status(status)),
                                    destination: TodoDropDestination(kind: .status(status), beforeID: task.id),
                                    onMove: handleMove
                                ) {
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
                        .padding(8)
                    }
                }
            }
            .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
            .clipShape(.rect(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(status.tintColor.opacity(0.28), lineWidth: 1)
            }
        }
    }

    private func handleMove(_ payload: TodoDragPayload, _ destination: TodoDropDestination) {
        guard case .status(let targetStatus) = destination.kind else { return }
        onMove(payload.taskID, targetStatus, destination.beforeID)
    }
}
