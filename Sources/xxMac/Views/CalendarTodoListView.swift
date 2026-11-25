import SwiftUI

struct CalendarTodoListView: View {
    @ObservedObject var store: TodoStore
    let selectedDate: Date
    let calendar: Calendar
    let locale: Locale
    let onOpenTodo: () -> Void

    @State private var showsCompleted = false
    @State private var isAdding = false
    @State private var isSaving = false
    @State private var newTitle = ""
    @FocusState private var titleFocused: Bool

    private var dayTasks: [TodoTask] {
        CalendarTodoQuery.tasks(store.tasks, on: selectedDate, includeCompleted: true, calendar: calendar)
    }

    private var visibleTasks: [TodoTask] {
        dayTasks.filter { showsCompleted || $0.status != .completed }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if isAdding {
                    TextField(L10n.t("calendar.todo.placeholder"), text: $newTitle)
                        .textFieldStyle(.roundedBorder)
                        .focused($titleFocused)
                        .onSubmit(addTask)
                        .onExitCommand(perform: cancelAdding)
                    Button(action: addTask) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help(L10n.t("calendar.todo.add"))
                    Button(action: cancelAdding) { Image(systemName: "xmark") }
                        .help(L10n.t("common.cancel"))
                } else {
                    Text(L10n.t("calendar.todo.title"))
                        .font(.subheadline.weight(.semibold))
                    Text(L10n.f("calendar.todo.open_count", dayTasks.filter { $0.status != .completed }.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button {
                        isAdding = true
                        titleFocused = true
                    } label: {
                        Label(L10n.t("calendar.todo.add"), systemImage: "plus")
                            .font(.caption)
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(height: 26)
            .disabled(isSaving)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let error = store.errorMessage {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                            Button(L10n.t("calendar.todo.retry"), action: store.reload)
                        }
                        .font(.caption)
                        .padding(.vertical, 6)
                    }
                    if visibleTasks.isEmpty {
                        HStack(spacing: 7) {
                            Image(systemName: "checkmark.circle")
                                .font(.body)
                            Text(L10n.t("calendar.todo.empty"))
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 64)
                    } else {
                        ForEach(visibleTasks) { task in
                            CalendarTodoRow(
                                task: task,
                                listName: store.lists.first(where: { $0.id == task.listID })?.name,
                                locale: locale,
                                onToggle: {
                                    if task.status == .completed {
                                        store.rollbackStatus(id: task.id)
                                    } else {
                                        store.setStatus(id: task.id, status: .completed)
                                    }
                                },
                                onDefer: { store.deferToTomorrow(id: task.id, calendar: calendar) }
                            )
                        }
                    }
                }
            }
            .frame(height: visibleTasks.isEmpty && store.errorMessage == nil ? 64 : 182)
            .id(calendar.startOfDay(for: selectedDate))

            Divider()
            HStack {
                Button {
                    showsCompleted.toggle()
                } label: {
                    Text(L10n.t(showsCompleted ? "calendar.todo.hide_completed" : "calendar.todo.show_completed"))
                    Text("\(dayTasks.filter { $0.status == .completed }.count)")
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
                Spacer()
                Button(action: onOpenTodo) {
                    Label(L10n.t("calendar.todo.open"), systemImage: "arrow.up.right")
                }
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
        .onChange(of: selectedDate) { _ in
            if !isSaving { cancelAdding() }
        }
    }

    private func cancelAdding() {
        guard !isSaving else { return }
        titleFocused = false
        isAdding = false
        newTitle = ""
    }

    private func addTask() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSaving, !title.isEmpty,
              let deadline = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: selectedDate) else { return }
        isSaving = true
        store.create(title: title, notes: "", quadrant: .notImportantNotUrgent, status: .todo, dueAt: deadline) { result in
            isSaving = false
            if case .success = result { cancelAdding() }
        }
    }
}

private struct CalendarTodoRow: View {
    let task: TodoTask
    let listName: String?
    let locale: Locale
    let onToggle: () -> Void
    let onDefer: () -> Void

    private var isCompleted: Bool { task.status == .completed }

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onToggle) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isCompleted ? Color.green : Color.secondary)
            }
            .help(L10n.t(isCompleted ? "calendar.todo.reopen" : "calendar.todo.complete"))
            .accessibilityLabel("\(L10n.t(isCompleted ? "calendar.todo.reopen" : "calendar.todo.complete")): \(task.title)")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 12))
                    .strikethrough(isCompleted)
                    .foregroundStyle(isCompleted ? .secondary : .primary)
                    .lineLimit(1)
                    .help(task.title)
                HStack(spacing: 4) {
                    Text(listName ?? L10n.t("todo.list.unassigned"))
                    if task.status == .inProgress {
                        Text("· \(task.status.localizedTitle)")
                    }
                    if task.quadrant == .importantUrgent && !isCompleted {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityLabel(task.quadrant.localizedTitle)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 2)
            if let dueAt = task.dueAt {
                Text(dueAt, format: .dateTime.locale(locale).hour().minute())
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button(action: onDefer) {
                Image(systemName: "arrow.turn.up.right")
                    .font(.system(size: 12))
                    .frame(width: 22, height: 26)
            }
            .disabled(isCompleted)
            .help(L10n.t("calendar.todo.defer"))
            .accessibilityLabel("\(L10n.t("calendar.todo.defer")): \(task.title)")
        }
        .buttonStyle(.plain)
        .frame(height: 51)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }
}
