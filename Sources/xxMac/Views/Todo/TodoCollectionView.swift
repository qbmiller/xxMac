import SwiftUI

struct TodoCollectionView: View {
    let title: String
    let tasks: [TodoTask]
    let layout: TodoListLayout
    let selectedTaskID: TodoTask.ID?
    let showsQuadrant: Bool
    let reorderStatus: TodoStatus?
    let actions: (TodoTask) -> TodoTaskCardActions
    let onMoveToStatus: (UUID, TodoStatus, UUID?) -> Void

    private let cardColumns = [
        GridItem(.adaptive(minimum: 260, maximum: 400), spacing: 10, alignment: .top)
    ]

    @ViewBuilder
    var body: some View {
        if let reorderStatus {
            TodoLaneDropTarget(
                destination: TodoDropDestination(kind: .status(reorderStatus), beforeID: nil),
                onMove: handleMove
            ) {
                collectionContent
            }
        } else {
            collectionContent
        }
    }

    @ViewBuilder
    private var collectionContent: some View {
        if tasks.isEmpty {
            TodoEmptyStateView(
                systemImage: "checklist",
                title: L10n.t("todo.empty.title"),
                message: L10n.t("todo.empty.message")
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.title3.weight(.semibold))
                        Text("\(tasks.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(Color(nsColor: .separatorColor).opacity(0.22), in: Capsule())
                        Spacer()
                    }

                    if layout == .cards {
                        LazyVGrid(columns: cardColumns, alignment: .leading, spacing: 10) {
                            ForEach(tasks) { task in
                                card(task, density: .comfortable)
                            }
                        }
                    } else {
                        LazyVStack(spacing: 7) {
                            ForEach(tasks) { task in
                                card(task, density: .compact)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    @ViewBuilder
    private func card(_ task: TodoTask, density: TodoTaskCardDensity) -> some View {
        let taskActions = actions(task)
        let card = TodoTaskCard(
            task: task,
            density: density,
            isSelected: selectedTaskID == task.id,
            showsQuadrant: showsQuadrant,
            onSelect: taskActions.onSelect,
            onToggleCompletion: taskActions.onToggleCompletion,
            onSetStatus: taskActions.onSetStatus,
            onRollback: taskActions.onRollback,
            onEdit: taskActions.onEdit,
            onArchive: taskActions.onArchive,
            onDelete: taskActions.onDelete
        )

        if let reorderStatus {
            TodoDraggableTaskCard(
                payload: TodoDragPayload(taskID: task.id, source: .status(reorderStatus)),
                destination: TodoDropDestination(kind: .status(reorderStatus), beforeID: task.id),
                onMove: handleMove
            ) {
                card
            }
        } else {
            card
        }
    }

    private func handleMove(_ payload: TodoDragPayload, _ destination: TodoDropDestination) {
        guard case .status(let status) = destination.kind else { return }
        onMoveToStatus(payload.taskID, status, destination.beforeID)
    }
}

struct TodoEmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 46, height: 46)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
