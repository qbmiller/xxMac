import AppKit
import SwiftUI

struct QuickShortcutItemsSidebar: View {
    @ObservedObject private var manager = QuickShortcutManager.shared
    @Binding var selection: QuickShortcut.ID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t("quick_shortcut.items"))
                    .font(.headline)

                Spacer()

                Menu {
                    Button {
                        manager.addWebSearch()
                        selection = manager.items.last?.id
                    } label: {
                        Label(L10n.t("quick_shortcut.add_web_search"), systemImage: "safari")
                    }

                    Button {
                        manager.addCommandScript()
                        selection = manager.items.last?.id
                    } label: {
                        Label(L10n.t("quick_shortcut.add_command_script"), systemImage: "terminal")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)

                Button {
                    deleteSelectedItem()
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selection == nil)
            }
            .padding(10)

            if manager.items.isEmpty {
                VStack {
                    Spacer()
                    Text(L10n.t("quick_shortcut.empty_list"))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(manager.items) { item in
                        QuickShortcutRow(item: item)
                            .tag(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selection = item.id
                            }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func deleteSelectedItem() {
        guard let selection,
              let selectedItem = manager.items.first(where: { $0.id == selection }) else {
            return
        }
        manager.removeItem(selectedItem)
        self.selection = manager.items.first?.id
    }
}

struct QuickShortcutDetailView: View {
    @ObservedObject private var manager = QuickShortcutManager.shared
    @Binding var selectedItemID: QuickShortcut.ID?

    private var selectedItemBinding: Binding<QuickShortcut>? {
        guard let selectedItemID else { return nil }
        return Binding(
            get: {
                manager.items.first(where: { $0.id == selectedItemID }) ?? QuickShortcut(
                    id: selectedItemID,
                    title: "",
                    keyword: "",
                    actionType: .webSearch,
                    payload: ""
                )
            },
            set: { newValue in
                manager.updateItem(newValue)
            }
        )
    }

    var body: some View {
        Group {
            if let itemBinding = selectedItemBinding {
                QuickShortcutEditor(
                    item: itemBinding,
                    onDelete: {
                        if let item = manager.items.first(where: { $0.id == selectedItemID }) {
                            manager.removeItem(item)
                        }
                        selectedItemID = manager.items.first?.id
                    }
                )
            } else {
                VStack {
                    Spacer()
                    Text(L10n.t("quick_shortcut.empty"))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 420)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            }
        }
    }
}

private struct QuickShortcutRow: View {
    let item: QuickShortcut
    @ObservedObject private var manager = QuickShortcutManager.shared
    @ObservedObject private var iconCache = QuickShortcutIconCacheManager.shared

    var body: some View {
        HStack(spacing: 12) {
            QuickShortcutRowIcon(item: item)
                .id(iconCache.refreshToken)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .lineLimit(1)
                Text(rowSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { item.isEnabled },
                set: { newValue in
                    var updated = item
                    updated.isEnabled = newValue
                    manager.updateItem(updated)
                }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    private var rowSubtitle: String {
        let keyword = item.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if keyword.isEmpty {
            return item.actionType.displayName
        }
        return "\(keyword) · \(item.actionType.displayName)"
    }
}

private struct QuickShortcutRowIcon: View {
    let item: QuickShortcut

    var body: some View {
        Group {
            if let iconURL = QuickShortcutManager.shared.cachedIconURL(for: item),
               let image = NSImage(contentsOf: iconURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: item.actionType.iconName)
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(item.actionType == .webSearch ? .blue : .orange)
                    .padding(2)
            }
        }
        .frame(width: 22, height: 22)
    }
}

private struct QuickShortcutEditor: View {
    @Binding var item: QuickShortcut
    @State private var commandPreviewOutput: String = ""
    @ObservedObject private var manager = QuickShortcutManager.shared
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(L10n.t("quick_shortcut.editor"))
                        .font(.headline)
                    Spacer()
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label(L10n.t("quick_shortcut.delete"), systemImage: "trash")
                    }
                }

                Toggle(L10n.t("quick_shortcut.enabled"), isOn: $item.isEnabled)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(L10n.t("quick_shortcut.show_in_fallback"), isOn: $item.showInFallback)
                    Text(L10n.t("quick_shortcut.show_in_fallback_desc"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("quick_shortcut.title"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField(L10n.t("quick_shortcut.title"), text: $item.title)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("quick_shortcut.keyword"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField(L10n.t("quick_shortcut.keyword"), text: $item.keyword)
                        .textFieldStyle(.roundedBorder)
                    if manager.keywordConflict != nil {
                        Label(L10n.t("shortcut.keyword_conflict"), systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("quick_shortcut.action_type"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Picker("", selection: $item.actionType) {
                        ForEach(QuickShortcutActionType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if item.actionType == .webSearch {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.t("quick_shortcut.web_template"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField(L10n.t("quick_shortcut.web_template"), text: $item.payload)
                            .textFieldStyle(.roundedBorder)
                        Text(L10n.t("quick_shortcut.web_template_desc"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.t("quick_shortcut.input_mode"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Picker("", selection: $item.commandInputMode) {
                            ForEach(QuickShortcutCommandInputMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        Text(L10n.t("quick_shortcut.input_mode_desc"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.t("quick_shortcut.shell_path"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField(L10n.t("quick_shortcut.shell_path"), text: $item.shellPath)
                            .textFieldStyle(.roundedBorder)
                        Text(L10n.t("quick_shortcut.shell_path_desc"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.t("quick_shortcut.script"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextEditor(text: $item.payload)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 220)
                            .padding(6)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                        Text(L10n.t("quick_shortcut.script_desc"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("quick_shortcut.preview_query"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    HStack {
                        TextField(L10n.t("quick_shortcut.preview_query"), text: $item.previewQuery)
                            .textFieldStyle(.roundedBorder)
                        Button(L10n.t("quick_shortcut.test")) {
                            if item.actionType == .commandScript {
                                commandPreviewOutput = QuickShortcutManager.shared.previewCommandOutput(item: item)
                            } else {
                                QuickShortcutManager.shared.execute(item: item, query: item.previewQuery)
                            }
                        }
                    }
                }

                previewPane

                HStack {
                    Spacer()
                    Button(L10n.t("general.done")) {
                        onCommit()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        .onChange(of: item) { newValue in
            QuickShortcutManager.shared.updateItem(newValue)
        }
        .onChange(of: item.id) { _ in
            commandPreviewOutput = ""
        }
        .onChange(of: item.actionType) { _ in
            commandPreviewOutput = ""
        }
    }

    private func onCommit() {
        QuickShortcutManager.shared.updateItem(item)
    }

    @ViewBuilder
    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(previewTitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    QuickShortcutManager.shared.copyToPasteboard(previewText)
                } label: {
                    Label(L10n.t("general.copy"), systemImage: "doc.on.doc")
                }
                .disabled(previewText.isEmpty)
            }

            ScrollView {
                Text(previewText.isEmpty ? L10n.t("quick_shortcut.preview_empty") : previewText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(previewText.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(minHeight: 110, maxHeight: 220)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        }
    }

    private var previewTitle: String {
        item.actionType == .webSearch ? L10n.t("quick_shortcut.preview_url") : L10n.t("quick_shortcut.preview_output")
    }

    private var previewText: String {
        if item.actionType == .webSearch {
            return QuickShortcutManager.shared.renderedWebSearchURL(item: item)
        }
        let arguments = QuickShortcutManager.shared.renderedCommandArguments(item: item)
        let argvPreview = arguments.enumerated()
            .map { index, argument in "$\(index + 1): \(argument)" }
            .joined(separator: "\n")
        guard !argvPreview.isEmpty else { return commandPreviewOutput }
        if commandPreviewOutput.isEmpty {
            return "argv:\n\(argvPreview)"
        }
        return "argv:\n\(argvPreview)\n\n\(commandPreviewOutput)"
    }
}
