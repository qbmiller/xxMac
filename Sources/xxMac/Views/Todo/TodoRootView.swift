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

            TimelineView(.periodic(from: Date(), by: 60)) { context in
                content(now: context.date)
            }
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
                TodoArchiveView(
                    tasks: TodoTaskQuery.archived(store.tasks),
                    onEdit: edit,
                    onRestore: store.restore,
                    onDelete: { deleteCandidate = $0 },
                    onClose: { self.sheet = nil }
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

    @ViewBuilder
    private func content(now: Date) -> some View {
        if windowController.mode == .board {
            TodoStatusBoardView(
                tasks: searchedActiveTasks,
                selectedTaskID: selectedTaskID,
                actions: actions(for:),
                onMove: { store.moveToStatus(id: $0, status: $1, beforeID: $2) }
            )
        } else {
            switch selectedView {
            case .quadrants:
                TodoQuadrantView(
                    tasks: visibleTasks(now: now),
                    selectedTaskID: selectedTaskID,
                    actions: actions(for:),
                    onMove: { store.moveToQuadrant(id: $0, quadrant: $1, beforeID: $2) }
                )
            case .today:
                TodoTodayView(
                    tasks: searchedActiveTasks,
                    now: now,
                    selectedTaskID: selectedTaskID,
                    actions: actions(for:)
                )
            case .all:
                TodoCollectionView(
                    title: selectedView.localizedTitle,
                    tasks: visibleTasks(now: now),
                    layout: listLayout,
                    selectedTaskID: selectedTaskID,
                    showsQuadrant: true,
                    reorderStatus: nil,
                    actions: actions(for:),
                    onMoveToStatus: { _, _, _ in }
                )
            case .todo, .inProgress, .completed:
                TodoCollectionView(
                    title: selectedView.localizedTitle,
                    tasks: visibleTasks(now: now),
                    layout: .list,
                    selectedTaskID: selectedTaskID,
                    showsQuadrant: true,
                    reorderStatus: selectedView.statusFilter,
                    actions: actions(for:),
                    onMoveToStatus: { store.moveToStatus(id: $0, status: $1, beforeID: $2) }
                )
            }
        }
    }

    private var searchedActiveTasks: [TodoTask] {
        TodoTaskQuery.search(TodoTaskQuery.active(store.tasks), text: searchText)
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { deleteCandidate != nil },
            set: { if !$0 { deleteCandidate = nil } }
        )
    }

    private func visibleTasks(now: Date) -> [TodoTask] {
        TodoTaskQuery.tasks(
            store.tasks,
            for: selectedView,
            searchText: searchText,
            now: now,
            hideCompletedInQuadrants: hideCompletedInQuadrants,
            sort: sort
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

                if mode == .compact && selectedView == .all {
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

                if mode == .compact && selectedView == .quadrants {
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

            if mode == .compact {
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
