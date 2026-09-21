import SwiftUI

struct TodoListEditorView: View {
    let navigationTitle: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @FocusState private var isNameFocused: Bool

    init(
        title: String,
        name: String,
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        navigationTitle = title
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: name)
    }

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(navigationTitle)
                .font(.title2.weight(.semibold))

            TextField(L10n.t("todo.list.name_placeholder"), text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)

            HStack {
                Spacer()
                Button(L10n.t("common.cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(L10n.t("common.save")) {
                    onSave(normalizedName)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(normalizedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .defaultFocus($isNameFocused, true)
    }
}
