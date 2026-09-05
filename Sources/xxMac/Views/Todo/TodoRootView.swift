import SwiftUI

struct TodoRootView: View {
    @ObservedObject var store: TodoStore
    @ObservedObject var windowController: TodoWindowController

    @State private var selectedView: TodoView = .quadrants
    @State private var searchText = ""
    @State private var selectedTaskID: TodoTask.ID?
    @State private var sheet: Sheet?
    @State private var deleteCandidate: TodoTask?
    @State private var hideCompletedInQuadrants = false
    @State private var listLayout: TodoListLayout = .cards
    @State private var sort: TodoSort = .updatedAt

    private enum Sheet: Identifiable {
        case editor(id: UUID, task: TodoTask?)
        case archive

        var id: String {
            switch self {
            case .editor(let id, _): return "editor-\(id.uuidString)"
            case .archive: return "archive"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TodoHeaderView(
                selectedView: $selectedView,
                searchText: $searchText,
                listLayout: $listLayout,
                sort: $sort,
                hideCompletedInQuadrants: $hideCompletedInQuadrants,
                mode: windowController.mode,
                onCreate: createTask,
                onOpenArchive: { sheet = .archive },
                onToggleBoard: toggleBoard
            )

            Divider()

            if let errorMessage = store.errorMessage {
                TodoErrorBanner(message: errorMessage, onRetry: store.reload)
            }

            TodoTaskCollectionPlaceholder(
                title: selectedView.localizedTitle,
                tasks: visibleTasks,
                selectedTaskID: selectedTaskID,
                showsQuadrant: selectedView != .quadrants,
                density: listLayout == .list ? .compact : .comfortable,
                actions: actions(for:)
            )
        }
        .background(.regularMaterial)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .editor(_, let task):
                TodoEditorView(
                    title: task == nil ? L10n.t("todo.editor.new") : L10n.t("todo.editor.edit"),
                    draft: task.map(TodoTaskDraft.init(task:)) ?? TodoTaskDraft(),
                    onSave: { draft in save(draft, original: task) },
                    onCancel: { self.sheet = nil }
                )
            case .archive:
                TodoArchivePlaceholderView(
                    tasks: TodoTaskQuery.archived(store.tasks),
                    onRestore: store.restore,
                    onDelete: { deleteCandidate = $0 }
                )
            }
        }
        .alert(L10n.t("todo.delete.title"), isPresented: deleteAlertBinding) {
            Button(L10n.t("todo.action.delete"), role: .destructive) {
                if let deleteCandidate {
                    store.delete(id: deleteCandidate.id)
                }
                deleteCandidate = nil
            }
            Button(L10n.t("common.cancel"), role: .cancel) {
                deleteCandidate = nil
            }
        } message: {
            Text(L10n.t("todo.delete.message"))
        }
    }

    private var visibleTasks: [TodoTask] {
        TodoTaskQuery.tasks(
            store.tasks,
            for: selectedView,
            searchText: searchText,
            hideCompletedInQuadrants: hideCompletedInQuadrants,
            sort: sort
        )
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { deleteCandidate != nil },
            set: { if !$0 { deleteCandidate = nil } }
        )
    }

    private func createTask() {
        selectedTaskID = nil
        sheet = .editor(id: UUID(), task: nil)
    }

    private func edit(_ task: TodoTask) {
        selectedTaskID = task.id
        sheet = .editor(id: task.id, task: task)
    }

    private func save(_ draft: TodoTaskDraft, original: TodoTask?) {
        guard draft.canSave else { return }
        if let original {
            store.save(draft.applying(to: original))
        } else {
            store.create(
                title: draft.normalizedTitle,
                notes: draft.notes,
                quadrant: draft.quadrant,
                status: draft.status,
                dueAt: draft.normalizedDueAt()
            )
        }
        sheet = nil
    }

    private func toggleBoard() {
        windowController.setMode(windowController.mode == .compact ? .board : .compact)
    }

    private func actions(for task: TodoTask) -> TodoTaskCardActions {
        TodoTaskCardActions(
            onSelect: { selectedTaskID = task.id },
            onToggleCompletion: {
                if task.status == .completed {
                    store.rollbackStatus(id: task.id)
                } else {
                    store.setStatus(id: task.id, status: .completed)
                }
            },
            onSetStatus: { store.setStatus(id: task.id, status: $0) },
            onRollback: { store.rollbackStatus(id: task.id) },
            onEdit: { edit(task) },
            onArchive: { store.archive(id: task.id) },
            onDelete: { deleteCandidate = task }
        )
    }
}

private struct TodoHeaderView: View {
    @Binding var selectedView: TodoView
    @Binding var searchText: String
    @Binding var listLayout: TodoListLayout
    @Binding var sort: TodoSort
    @Binding var hideCompletedInQuadrants: Bool

    let mode: TodoWindowMode
    let onCreate: () -> Void
    let onOpenArchive: () -> Void
    let onToggleBoard: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("todo.title"))
                        .font(.title2.weight(.semibold))
                    Text(Date().formatted(date: .long, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                TextField(L10n.t("todo.search.placeholder"), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 150, idealWidth: 220, maxWidth: 260)

                if selectedView == .all {
                    Picker(L10n.t("todo.layout.title"), selection: $listLayout) {
                        Image(systemName: "rectangle.grid.1x2").tag(TodoListLayout.cards)
                        Image(systemName: "list.bullet").tag(TodoListLayout.list)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 78)

                    Menu {
                        ForEach(TodoSort.allCases) { option in
                            Button {
                                sort = option
                            } label: {
                                if sort == option {
                                    Label(option.localizedTitle, systemImage: "checkmark")
                                } else {
                                    Text(option.localizedTitle)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .help(L10n.t("todo.sort.title"))
                }

                if selectedView == .quadrants {
                    Toggle(isOn: $hideCompletedInQuadrants) {
                        Image(systemName: hideCompletedInQuadrants ? "eye.slash" : "eye")
                    }
                    .toggleStyle(.button)
                    .help(L10n.t("todo.action.hide_completed"))
                }

                Menu {
                    Button(action: onOpenArchive) {
                        Label(L10n.t("todo.archive.title"), systemImage: "archivebox")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help(L10n.t("todo.action.more"))

                Button(action: onToggleBoard) {
                    Image(systemName: mode == .compact ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                }
                .help(mode == .compact ? L10n.t("todo.action.expand_board") : L10n.t("todo.action.compact_window"))

                Button(action: onCreate) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("n", modifiers: .command)
                .help(L10n.t("todo.action.new"))
                .accessibilityLabel(L10n.t("todo.action.new"))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(TodoView.allCases) { item in
                        Button {
                            selectedView = item
                        } label: {
                            Text(item.localizedTitle)
                                .font(.subheadline.weight(selectedView == item ? .semibold : .regular))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    selectedView == item ? Color.accentColor.opacity(0.14) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct TodoTaskCardActions {
    let onSelect: () -> Void
    let onToggleCompletion: () -> Void
    let onSetStatus: (TodoStatus) -> Void
    let onRollback: () -> Void
    let onEdit: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void
}

private struct TodoTaskCollectionPlaceholder: View {
    let title: String
    let tasks: [TodoTask]
    let selectedTaskID: TodoTask.ID?
    let showsQuadrant: Bool
    let density: TodoTaskCardDensity
    let actions: (TodoTask) -> TodoTaskCardActions

    var body: some View {
        if tasks.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "checklist")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                Text(L10n.t("todo.empty.title"))
                    .font(.headline)
                Text(L10n.t("todo.empty.message"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(title)
                            .font(.headline)
                        Text("\(tasks.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.bottom, 2)

                    ForEach(tasks) { task in
                        let taskActions = actions(task)
                        TodoTaskCard(
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
                    }
                }
                .padding(14)
            }
        }
    }
}

private struct TodoArchivePlaceholderView: View {
    let tasks: [TodoTask]
    let onRestore: (UUID) -> Void
    let onDelete: (TodoTask) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t("todo.archive.title"))
                    .font(.title2.weight(.semibold))
                Spacer()
                Button(L10n.t("common.close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            if tasks.isEmpty {
                Text(L10n.t("todo.archive.empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(tasks) { task in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.title)
                                .strikethrough(task.status == .completed)
                            Text(task.quadrant.localizedTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            onRestore(task.id)
                        } label: {
                            Image(systemName: "arrow.uturn.backward.circle")
                        }
                        .help(L10n.t("todo.action.restore"))
                        Button(role: .destructive) {
                            onDelete(task)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help(L10n.t("todo.action.delete"))
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}

private struct TodoErrorBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .lineLimit(2)
            Spacer()
            Button(L10n.t("common.retry"), action: onRetry)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
    }
}
