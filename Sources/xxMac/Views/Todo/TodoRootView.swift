import SwiftUI

struct TodoRootView: View {
    @ObservedObject var store: TodoStore
    @ObservedObject var windowController: TodoWindowController

    @ObservedObject private var preferences = TodoPreferencesStore.shared
    @State private var searchText = ""
    @State private var selectedTaskID: TodoTask.ID?
    @State private var selectedListID: TodoList.ID?
    @State private var sheet: Sheet?
    @State private var deleteCandidate: TodoTask?
    @State private var listDeleteCandidate: TodoList?
    @State private var sort: TodoSort = .updatedAt

    private enum Sheet: Identifiable {
        case editor(id: UUID, task: TodoTask?)
        case listEditor(id: UUID, list: TodoList?)
        case archive

        var id: String {
            switch self {
            case .editor(let id, _): return "editor-\(id.uuidString)"
            case .listEditor(let id, _): return "list-editor-\(id.uuidString)"
            case .archive: return "archive"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TodoHeaderView(
                selectedView: $preferences.selectedView,
                searchText: $searchText,
                listLayout: $preferences.listLayout,
                sort: $sort,
                hideCompletedInQuadrants: $preferences.hideCompletedInQuadrants,
                isCustomListSelected: selectedList != nil,
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
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .editor(_, let task):
                TodoEditorView(
                    title: task == nil ? L10n.t("todo.editor.new") : L10n.t("todo.editor.edit"),
                    draft: task.map(TodoTaskDraft.init(task:)) ?? TodoTaskDraft(listID: selectedListID),
                    lists: store.lists,
                    onSave: { draft in save(draft, original: task) },
                    onCancel: { self.sheet = nil }
                )
            case .listEditor(_, let list):
                TodoListEditorView(
                    title: list == nil ? L10n.t("todo.list.new") : L10n.t("todo.list.rename"),
                    name: list?.name ?? "",
                    onSave: { name in saveList(name: name, original: list) },
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
        .confirmationDialog(
            L10n.t("todo.list.delete_title"),
            isPresented: listDeleteAlertBinding,
            titleVisibility: .visible
        ) {
            Button(L10n.t("todo.list.delete"), role: .destructive) {
                deleteSelectedList()
            }
            Button(L10n.t("common.cancel"), role: .cancel) {
                listDeleteCandidate = nil
            }
        } message: {
            Text(L10n.t("todo.list.delete_message"))
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if windowController.mode == .board {
            TodoStatusBoardView(
                tasks: visibleBoardTasks,
                selectedTaskID: selectedTaskID,
                actions: actions(for:),
                onMove: { store.moveToStatus(id: $0, status: $1, beforeID: $2) }
            )
        } else {
            HStack(spacing: 0) {
                TodoNavigationSidebar(
                    selectedView: $preferences.selectedView,
                    selectedListID: $selectedListID,
                    lists: store.lists,
                    fontSize: preferences.navigationFontSize,
                    onCreateList: createList,
                    onRenameList: renameList,
                    onDeleteList: { listDeleteCandidate = $0 }
                )
                    .frame(width: 174)

                Divider()

                compactContent(now: now)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func compactContent(now: Date) -> some View {
        if let selectedList {
            TodoCollectionView(
                title: selectedList.name,
                tasks: TodoTaskQuery.tasks(store.tasks, inList: selectedList.id, searchText: searchText),
                layout: .list,
                selectedTaskID: selectedTaskID,
                showsQuadrant: true,
                reorderStatus: nil,
                actions: actions(for:),
                onMoveToStatus: { _, _, _ in }
            )
        } else {
            switch preferences.selectedView {
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
                title: preferences.selectedView.localizedTitle,
                tasks: visibleTasks(now: now),
                layout: preferences.listLayout,
                selectedTaskID: selectedTaskID,
                showsQuadrant: true,
                reorderStatus: nil,
                actions: actions(for:),
                onMoveToStatus: { _, _, _ in }
            )
        case .todo, .inProgress, .completed:
            TodoCollectionView(
                title: preferences.selectedView.localizedTitle,
                tasks: visibleTasks(now: now),
                layout: .list,
                selectedTaskID: selectedTaskID,
                showsQuadrant: true,
                reorderStatus: preferences.selectedView.statusFilter,
                actions: actions(for:),
                onMoveToStatus: { store.moveToStatus(id: $0, status: $1, beforeID: $2) }
            )
            }
        }
    }

    private var searchedActiveTasks: [TodoTask] {
        TodoTaskQuery.search(TodoTaskQuery.active(store.tasks), text: searchText)
    }

    private var visibleBoardTasks: [TodoTask] {
        guard let selectedListID else { return searchedActiveTasks }
        return TodoTaskQuery.tasks(store.tasks, inList: selectedListID, searchText: searchText)
    }

    private var selectedList: TodoList? {
        guard let selectedListID else { return nil }
        return store.lists.first { $0.id == selectedListID }
    }

    private var listDeleteAlertBinding: Binding<Bool> {
        Binding(
            get: { listDeleteCandidate != nil },
            set: { if !$0 { listDeleteCandidate = nil } }
        )
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
            for: preferences.selectedView,
            searchText: searchText,
            now: now,
            hideCompletedInQuadrants: preferences.hideCompletedInQuadrants,
            sort: sort
        )
    }

    private func createTask() {
        selectedTaskID = nil
        sheet = .editor(id: UUID(), task: nil)
    }

    private func createList() {
        sheet = .listEditor(id: UUID(), list: nil)
    }

    private func renameList(_ list: TodoList) {
        sheet = .listEditor(id: list.id, list: list)
    }

    private func saveList(name: String, original: TodoList?) {
        if let original {
            store.renameList(id: original.id, name: name)
        } else {
            let listID = UUID()
            store.createList(name: name, id: listID) { result in
                if case .success = result {
                    selectedListID = listID
                }
            }
        }
        sheet = nil
    }

    private func deleteSelectedList() {
        guard let list = listDeleteCandidate else { return }
        if selectedListID == list.id {
            selectedListID = nil
        }
        store.deleteList(id: list.id)
        listDeleteCandidate = nil
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
                dueAt: draft.normalizedDueAt(),
                listID: draft.listID
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

    let isCustomListSelected: Bool
    let mode: TodoWindowMode
    let onCreate: () -> Void
    let onOpenArchive: () -> Void
    let onToggleBoard: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.t("todo.title"))
                    .font(.title3.weight(.semibold))
                Text(Date().formatted(date: .long, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            TextField(L10n.t("todo.search.placeholder"), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 170, idealWidth: 220, maxWidth: 280)

            if mode == .compact && !isCustomListSelected && selectedView == .all {
                Picker(L10n.t("todo.layout.title"), selection: $listLayout) {
                    Image(systemName: "rectangle.grid.1x2").tag(TodoListLayout.cards)
                    Image(systemName: "list.bullet").tag(TodoListLayout.list)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 76)

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

            if mode == .compact && !isCustomListSelected && selectedView == .quadrants {
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
        .padding(.horizontal, 14)
        .frame(height: 56)
    }
}

private struct TodoNavigationSidebar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedView: TodoView
    @Binding var selectedListID: TodoList.ID?

    let lists: [TodoList]
    let fontSize: Int
    let onCreateList: () -> Void
    let onRenameList: (TodoList) -> Void
    let onDeleteList: (TodoList) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(TodoView.allCases) { item in
                Button {
                    selectedListID = nil
                    selectedView = item
                } label: {
                    navigationLabel(
                        title: item.localizedTitle,
                        systemImage: item.systemImage,
                        tintColor: item.tintColor,
                        isSelected: selectedListID == nil && selectedView == item
                    )
                }
                .buttonStyle(.plain)
            }

            Divider()
                .padding(.vertical, 6)

            HStack(spacing: 6) {
                Text(L10n.t("todo.list.section"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button(action: onCreateList) {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(L10n.t("todo.list.new"))
                .accessibilityLabel(L10n.t("todo.list.new"))
            }
            .padding(.horizontal, 10)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 5) {
                    ForEach(lists) { list in
                        let isSelected = selectedListID == list.id
                        HStack(spacing: 0) {
                            Button {
                                selectedListID = list.id
                            } label: {
                                navigationLabel(
                                    title: list.name,
                                    systemImage: "folder",
                                    tintColor: .blue,
                                    isSelected: isSelected,
                                    reservesTrailingSpace: true
                                )
                            }
                            .buttonStyle(.plain)

                            Menu {
                                Button {
                                    onRenameList(list)
                                } label: {
                                    Label(L10n.t("todo.list.rename"), systemImage: "pencil")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    onDeleteList(list)
                                } label: {
                                    Label(L10n.t("todo.list.delete"), systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(isSelected ? .white : .secondary)
                                    .frame(width: 26, height: 32)
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                        }
                        .background(
                            isSelected ? Color.accentColor : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(10)
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Color.accentColor.opacity(colorScheme == .dark ? 0.13 : 0.055)
            }
        }
    }

    private func navigationLabel(
        title: String,
        systemImage: String,
        tintColor: Color,
        isSelected: Bool,
        reservesTrailingSpace: Bool = false
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 18)
                .foregroundStyle(isSelected ? .white : tintColor)

            Text(title)
                .font(.system(
                    size: CGFloat(fontSize),
                    weight: isSelected ? .semibold : .regular
                ))
                .foregroundStyle(isSelected ? .white : .primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: reservesTrailingSpace ? 26 : 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
        .background(
            isSelected && !reservesTrailingSpace ? Color.accentColor : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .contentShape(Rectangle())
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
