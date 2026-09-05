import SwiftUI

struct TodoArchiveView: View {
    let tasks: [TodoTask]
    let onEdit: (TodoTask) -> Void
    let onRestore: (UUID) -> Void
    let onDelete: (TodoTask) -> Void
    let onClose: () -> Void

    @State private var searchText = ""

    private var visibleTasks: [TodoTask] {
        TodoTaskQuery.search(tasks, text: searchText)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("todo.archive.title"))
                        .font(.title2.weight(.semibold))
                    Text(L10n.f("todo.archive.count", tasks.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField(L10n.t("todo.search.placeholder"), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Button(L10n.t("common.close"), action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            if visibleTasks.isEmpty {
                TodoEmptyStateView(
                    systemImage: "archivebox",
                    title: L10n.t("todo.archive.empty"),
                    message: searchText.isEmpty ? L10n.t("todo.archive.empty_message") : L10n.t("todo.search.empty")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(visibleTasks) { task in
                            TodoArchiveRow(
                                task: task,
                                onEdit: { onEdit(task) },
                                onRestore: { onRestore(task.id) },
                                onDelete: { onDelete(task) }
                            )
                        }
                    }
                    .padding(14)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 440)
    }
}

private struct TodoArchiveRow: View {
    let task: TodoTask
    let onEdit: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.headline)
                        .strikethrough(task.status == .completed)
                        .foregroundStyle(task.status == .completed ? .secondary : .primary)
                    if !task.notes.isEmpty {
                        Text(task.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 8) {
                        Label(task.status.localizedTitle, systemImage: task.status.systemImage)
                            .foregroundStyle(task.status.tintColor)
                        Label(task.quadrant.localizedTitle, systemImage: task.quadrant.systemImage)
                            .foregroundStyle(task.quadrant.tintColor)
                        if let archivedAt = task.archivedAt {
                            Label(archivedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "archivebox")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onRestore) {
                Image(systemName: "arrow.uturn.backward.circle")
            }
            .help(L10n.t("todo.action.restore"))
            .accessibilityLabel(L10n.t("todo.action.restore"))

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .help(L10n.t("todo.action.delete"))
            .accessibilityLabel(L10n.t("todo.action.delete"))
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }
}
