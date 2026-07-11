import SwiftUI
import HotKey
import AppKit

struct SnippetsSettingsView: View {
    @ObservedObject private var manager = SnippetManager.shared
    @Binding var selectedCollectionID: SnippetCollection.ID?
    @State private var selectedEntryID: SnippetEntry.ID?
    @State private var editingEntry: SnippetEntry?

    private var selectedCollection: SnippetCollection? {
        manager.collections.first { $0.id == selectedCollectionID } ?? manager.collections.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("snippets.page_desc"))
                .font(.subheadline)
                .foregroundColor(.secondary)

            settingsSection(title: L10n.t("snippets.section_shortcuts")) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("snippets.viewer_hotkey"))
                        Text(L10n.t("snippets.viewer_hotkey_desc"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    SnippetHotKeyRecorder()
                        .frame(width: 150)
                    if manager.settings.hotKey != nil {
                        Button {
                            manager.settings.hotKey = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            entriesPane
                .frame(minHeight: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            ensureSelection()
        }
        .onChange(of: manager.collections) { _ in
            ensureSelection()
        }
        .onChange(of: manager.entries) { _ in
            ensureEntrySelection()
        }
        .sheet(item: $editingEntry) { entry in
            SnippetEntryEditor(entry: entry) {
                editingEntry = nil
            }
            .frame(width: 560, height: 520)
        }
    }

    private var entriesPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text(selectedCollection?.name ?? L10n.t("snippets.entries"))
                    .font(.headline)
                Spacer()
                Button {
                    deleteSelectedEntry()
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selectedEntryID == nil)
                Button {
                    if let collection = selectedCollection {
                        manager.addEntry(to: collection)
                        if let entry = manager.entries.last {
                            selectedEntryID = entry.id
                            editingEntry = entry
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(selectedCollection == nil)
            }
            .padding(10)

            if manager.entries(in: selectedCollection).isEmpty {
                VStack {
                    Spacer()
                    Text(L10n.t("snippets.empty_entries"))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(selection: $selectedEntryID) {
                    ForEach(manager.entries(in: selectedCollection)) { entry in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.name)
                                    .lineLimit(1)
                                Text(entrySubtitle(entry))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button {
                                selectedEntryID = entry.id
                                editingEntry = entry
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                        .tag(entry.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            selectedEntryID = entry.id
                            editingEntry = entry
                        }
                        .contextMenu {
                            Button {
                                selectedEntryID = entry.id
                                editingEntry = entry
                            } label: {
                                Text(L10n.t("snippets.edit_entry"))
                            }
                            Button(role: .destructive) {
                                manager.removeEntry(entry)
                            } label: {
                                Text(L10n.t("snippets.delete_entry"))
                            }
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
    }

    private func ensureSelection() {
        if selectedCollectionID == nil || !manager.collections.contains(where: { $0.id == selectedCollectionID }) {
            selectedCollectionID = manager.collections.first?.id
        }
        ensureEntrySelection()
    }

    private func ensureEntrySelection() {
        let visibleEntries = manager.entries(in: selectedCollection)
        if selectedEntryID == nil || !visibleEntries.contains(where: { $0.id == selectedEntryID }) {
            selectedEntryID = visibleEntries.first?.id
        }
    }

    private func deleteSelectedEntry() {
        guard let selectedEntryID,
              let entry = manager.entries.first(where: { $0.id == selectedEntryID }) else {
            return
        }
        manager.removeEntry(entry)
        self.selectedEntryID = nil
        ensureEntrySelection()
    }

    private func entrySubtitle(_ entry: SnippetEntry) -> String {
        if !entry.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return entry.keyword
        }
        return entry.content.replacingOccurrences(of: "\n", with: " ")
    }
}

private struct SnippetEntryEditor: View {
    @ObservedObject private var manager = SnippetManager.shared
    @State private var draft: SnippetEntry
    let onClose: () -> Void

    init(entry: SnippetEntry, onClose: @escaping () -> Void) {
        _draft = State(initialValue: entry)
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.t("snippets.editor"))
                    .font(.headline)
                Spacer()
                Button(role: .destructive) {
                    manager.removeEntry(draft)
                    onClose()
                } label: {
                    Label(L10n.t("snippets.delete_entry"), systemImage: "trash")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t("snippets.name"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField(L10n.t("snippets.name"), text: $draft.name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t("snippets.keyword"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField(L10n.t("snippets.keyword"), text: $draft.keyword)
                    .textFieldStyle(.roundedBorder)
            }

            Text(L10n.t("snippets.content"))
                .font(.subheadline)
                .foregroundColor(.secondary)

            TextEditor(text: $draft.content)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 240)
                .padding(6)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))

            HStack {
                Spacer()
                Button(L10n.t("general.cancel")) {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)

                Button(L10n.t("general.done")) {
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        .onChange(of: draft) { newValue in
            manager.updateEntry(newValue)
        }
        .onChange(of: draft.id) { _ in
            manager.updateEntry(draft)
        }
        .background(SnippetEscapeHandler(onEscape: onClose))
    }
}

private struct SnippetEscapeHandler: NSViewRepresentable {
    let onEscape: () -> Void

    func makeNSView(context: Context) -> SnippetEscapeHandlerView {
        let view = SnippetEscapeHandlerView()
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: SnippetEscapeHandlerView, context: Context) {
        nsView.onEscape = onEscape
    }
}

private final class SnippetEscapeHandlerView: NSView {
    var onEscape: (() -> Void)?
    private var monitor: Any?

    deinit {
        removeMonitor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installMonitor()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            removeMonitor()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard let window = self.window, event.window === window else {
                return event
            }

            if event.keyCode == 53 {
                self.onEscape?()
                return nil
            }

            return event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

private struct SnippetHotKeyRecorder: View {
    @ObservedObject private var manager = SnippetManager.shared
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            HStack {
                Spacer()
                if isRecording {
                    Text(L10n.t("snippets.type_hotkey"))
                        .foregroundColor(.blue)
                } else if let hotKey = manager.settings.hotKey {
                    Text(hotKey.modifiers.displayString + hotKey.key.displayString)
                        .fontWeight(.medium)
                } else {
                    Text(L10n.t("clipboard.none"))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(isRecording ? Color.blue.opacity(0.1) : Color(NSColor.textBackgroundColor))
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(isRecording ? Color.blue : Color.gray.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            if let key = Key(carbonKeyCode: UInt32(event.keyCode)) {
                let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
                _ = manager.setHotKey(HotKeyConfiguration(key: key, modifiers: modifiers))
                stopRecording()
                return nil
            }
            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
