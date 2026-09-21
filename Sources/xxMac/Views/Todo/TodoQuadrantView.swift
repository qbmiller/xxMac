import SwiftUI

enum TodoQuadrantLayoutPolicy {
    static let contentPadding: CGFloat = 16
    static let columnSpacing: CGFloat = 10
    static let rowSpacing: CGFloat = 12
    static let minimumCellHeight: CGFloat = 190

    static func columnWidth(for availableWidth: CGFloat) -> CGFloat {
        max(0, (availableWidth - columnSpacing) / 2)
    }

    static func cellHeight(for containerHeight: CGFloat) -> CGFloat {
        max(minimumCellHeight, (containerHeight - contentPadding * 2 - rowSpacing) / 2)
    }
}

struct TodoQuadrantView: View {
    let tasks: [TodoTask]
    let selectedTaskID: TodoTask.ID?
    let actions: (TodoTask) -> TodoTaskCardActions
    let onMove: (UUID, TodoQuadrant, UUID?) -> Void

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = max(0, proxy.size.width - TodoQuadrantLayoutPolicy.contentPadding * 2)
            let columnWidth = TodoQuadrantLayoutPolicy.columnWidth(for: availableWidth)
            let cellHeight = TodoQuadrantLayoutPolicy.cellHeight(for: proxy.size.height)
            let columns = [
                GridItem(.fixed(columnWidth), spacing: TodoQuadrantLayoutPolicy.columnSpacing),
                GridItem(.fixed(columnWidth), spacing: TodoQuadrantLayoutPolicy.columnSpacing)
            ]

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: TodoQuadrantLayoutPolicy.rowSpacing) {
                    ForEach(TodoQuadrant.allCases) { quadrant in
                        TodoQuadrantCell(
                            quadrant: quadrant,
                            tasks: tasksForQuadrant(quadrant),
                            selectedTaskID: selectedTaskID,
                            actions: actions,
                            onMove: onMove
                        )
                        .frame(height: cellHeight)
                    }
                }
                .frame(width: availableWidth)
                .padding(TodoQuadrantLayoutPolicy.contentPadding)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
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
    let onMove: (UUID, TodoQuadrant, UUID?) -> Void

    var body: some View {
        TodoLaneDropTarget(
            destination: TodoDropDestination(kind: .quadrant(quadrant), beforeID: nil),
            onMove: handleMove
        ) {
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: quadrant.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(quadrant.tintColor, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    Text(quadrant.localizedTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("\(tasks.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .frame(height: 20)
                        .background(Color(nsColor: .separatorColor).opacity(0.22), in: Capsule())
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(quadrant.tintColor.opacity(0.055))

                Divider()

                if tasks.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "tray")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(quadrant.tintColor.opacity(0.55))
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
                                TodoDraggableTaskCard(
                                    payload: TodoDragPayload(taskID: task.id, source: .quadrant(quadrant)),
                                    destination: TodoDropDestination(kind: .quadrant(quadrant), beforeID: task.id),
                                    onMove: handleMove
                                ) {
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
                        }
                        .padding(9)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(.rect(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.035), radius: 5, y: 1)
        }
    }

    private func handleMove(_ payload: TodoDragPayload, _ destination: TodoDropDestination) {
        guard case .quadrant(let targetQuadrant) = destination.kind else { return }
        onMove(payload.taskID, targetQuadrant, destination.beforeID)
    }
}
