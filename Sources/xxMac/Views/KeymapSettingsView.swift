import SwiftUI
import AppKit

struct KeymapSettingsView: View {
    @ObservedObject private var manager = KeymapManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(L10n.t("keymap.enable"), isOn: $manager.isEnabled)
            Text(L10n.t("keymap.desc"))
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: manager.hasAccessibilityPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(manager.hasAccessibilityPermission ? .green : .orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(manager.hasAccessibilityPermission ? L10n.t("keymap.accessibility_granted") : L10n.t("keymap.accessibility_required"))
                        .font(.callout)
                    if !manager.hasAccessibilityPermission {
                        Button(L10n.t("accessibility.open_settings")) {
                            manager.requestAccessibilityPermission()
                        }
                        .controlSize(.small)
                    }
                }
            }
            if manager.isEnabled {
                Label(L10n.t("keymap.trigger"), systemImage: "command")
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .onAppear { manager.refreshPermissionStatus() }
    }
}

struct KeymapPanelView: View {
    @ObservedObject var manager: KeymapManager
    @State private var query = ""

    private var filteredItems: [KeymapMenuItem] {
        guard !query.isEmpty else { return manager.snapshot?.items ?? [] }
        return (manager.snapshot?.items ?? []).filter { $0.title.localizedCaseInsensitiveContains(query) || $0.shortcut.localizedCaseInsensitiveContains(query) }
    }

    private var filteredColumns: [KeymapColumn] {
        guard !query.isEmpty else { return manager.snapshot?.columns ?? [] }
        return (manager.snapshot?.columns ?? []).compactMap { column in
            let items = column.items.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.shortcut.localizedCaseInsensitiveContains(query) }
            return items.isEmpty ? nil : KeymapColumn(title: column.title, items: items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(manager.snapshot?.appName ?? L10n.t("keymap.no_app")).font(.title3).fontWeight(.semibold)
                    Text(L10n.t("keymap.subtitle")).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button { manager.refreshAndShow() } label: { Label(L10n.t("keymap.refresh"), systemImage: "arrow.clockwise") }
            }.padding()
            Divider()
            if !manager.hasAccessibilityPermission {
                VStack(spacing: 12) {
                    Image(systemName: "hand.raised").font(.title)
                    Text(L10n.t("keymap.accessibility_required")).foregroundColor(.secondary)
                    Button(L10n.t("accessibility.open_settings")) { manager.requestAccessibilityPermission() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextField(L10n.t("keymap.search"), text: $query).textFieldStyle(.roundedBorder).padding()
                if filteredColumns.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "command.square").font(.title)
                    Text(L10n.t("keymap.empty")).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 22) {
                        ForEach(filteredColumns) { column in
                            KeymapColumnView(column: column)
                                .frame(minWidth: 250, maxWidth: 340, alignment: .topLeading)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
                }
            }
        }.frame(minWidth: 620, minHeight: 460)
    }
}
