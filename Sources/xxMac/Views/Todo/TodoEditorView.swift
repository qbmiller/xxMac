import SwiftUI

struct TodoEditorView: View {
    let navigationTitle: String
    let lists: [TodoList]
    let onSave: (TodoTaskDraft) -> Void
    let onCancel: () -> Void

    @State private var draft: TodoTaskDraft
    @State private var hasDeadline: Bool
    @State private var deadlineDay: Date
    @State private var deadlineHour: Int
    @State private var deadlineMinute: Int
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title
        case notes
    }

    init(
        title: String,
        draft: TodoTaskDraft,
        lists: [TodoList],
        onSave: @escaping (TodoTaskDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        navigationTitle = title
        self.lists = lists
        self.onSave = onSave
        self.onCancel = onCancel

        let calendar = Calendar.current
        let seed = draft.dueAt ?? calendar.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        _draft = State(initialValue: draft)
        _hasDeadline = State(initialValue: draft.dueAt != nil)
        _deadlineDay = State(initialValue: seed)
        _deadlineHour = State(initialValue: calendar.component(.hour, from: seed))
        _deadlineMinute = State(initialValue: calendar.component(.minute, from: seed))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(navigationTitle)
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    editorField(L10n.t("todo.editor.title")) {
                        TextField(L10n.t("todo.editor.title_placeholder"), text: $draft.title)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .title)
                    }

                    if !draft.canSave {
                        Label(L10n.t("todo.editor.title_required"), systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    editorField(L10n.t("todo.editor.notes")) {
                        TextEditor(text: $draft.notes)
                            .font(.body)
                            .focused($focusedField, equals: .notes)
                            .frame(minHeight: 90, maxHeight: 140)
                            .padding(5)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            }
                    }

                    editorField(L10n.t("todo.editor.list")) {
                        Picker(L10n.t("todo.editor.list"), selection: $draft.listID) {
                            Text(L10n.t("todo.list.unassigned")).tag(nil as UUID?)
                            ForEach(lists) { list in
                                Label(list.name, systemImage: "folder").tag(Optional(list.id))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 220, alignment: .leading)
                    }

                    editorField(L10n.t("todo.editor.status")) {
                        Picker(L10n.t("todo.editor.status"), selection: $draft.status) {
                            ForEach(TodoStatus.allCases) { status in
                                Label(status.localizedTitle, systemImage: status.systemImage).tag(status)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 220, alignment: .leading)
                    }

                    editorField(L10n.t("todo.editor.quadrant")) {
                        TodoQuadrantSelector(selection: $draft.quadrant)
                    }

                    Toggle(isOn: $hasDeadline) {
                        Label(L10n.t("todo.editor.deadline"), systemImage: "calendar.badge.clock")
                            .font(.headline)
                    }

                    if hasDeadline {
                        HStack(alignment: .top, spacing: 18) {
                            DatePicker(
                                L10n.t("todo.editor.deadline_date"),
                                selection: $deadlineDay,
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .datePickerStyle(.graphical)

                            VStack(alignment: .leading, spacing: 10) {
                                Text(L10n.t("todo.editor.deadline_time"))
                                    .font(.subheadline.weight(.medium))

                                HStack(spacing: 8) {
                                    Picker(L10n.t("todo.editor.hour"), selection: $deadlineHour) {
                                        ForEach(0..<24, id: \.self) { hour in
                                            Text(String(format: "%02d", hour)).tag(hour)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 72)

                                    Text(":")
                                        .foregroundStyle(.secondary)

                                    Picker(L10n.t("todo.editor.minute"), selection: $deadlineMinute) {
                                        ForEach(0..<60, id: \.self) { minute in
                                            Text(String(format: "%02d", minute)).tag(minute)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 72)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button(L10n.t("common.cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(L10n.t("common.save"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.canSave)
            }
            .padding(16)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 560, idealHeight: 620)
        .defaultFocus($focusedField, .title)
    }

    private func editorField<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.weight(.medium))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        var result = draft
        if hasDeadline {
            var calendar = Calendar.current
            calendar.timeZone = .current
            var components = calendar.dateComponents([.year, .month, .day], from: deadlineDay)
            components.hour = deadlineHour
            components.minute = deadlineMinute
            components.second = 0
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            result.dueAt = components.date
        } else {
            result.dueAt = nil
        }
        onSave(result)
    }
}

private struct TodoQuadrantSelector: View {
    @Binding var selection: TodoQuadrant

    var body: some View {
        HStack(spacing: 8) {
            ForEach(TodoQuadrant.allCases) { quadrant in
                let isSelected = selection == quadrant
                Button {
                    selection = quadrant
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 6) {
                            Image(systemName: quadrant.systemImage)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(
                                    quadrant.tintColor,
                                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                                )

                            Spacer(minLength: 0)

                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(quadrant.tintColor)
                            }
                        }

                        Text(quadrant.localizedTitle)
                            .font(.caption.weight(isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? quadrant.tintColor : .primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                    .background(
                        quadrant.tintColor.opacity(isSelected ? 0.16 : 0.055),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(
                                isSelected
                                    ? quadrant.tintColor.opacity(0.9)
                                    : Color(nsColor: .separatorColor).opacity(0.7),
                                lineWidth: isSelected ? 2 : 1
                            )
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
    }
}
