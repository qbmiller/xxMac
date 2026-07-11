import SwiftUI

struct BrowserSearchSettingsView: View {
    @ObservedObject private var manager = BrowserSearchManager.shared
    @State private var bookmarkKeyword = ""
    @State private var historyKeyword = ""
    @State private var conflictMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.t("browser_search.settings_desc"))
                .font(.subheadline)
                .foregroundColor(.secondary)

            Toggle(
                L10n.t("browser_search.enabled"),
                isOn: Binding(
                    get: { manager.preferences.isEnabled },
                    set: { manager.updateEnabled($0) }
                )
            )

            Divider()

            HStack {
                Text(L10n.t("browser_search.browser"))
                    .frame(width: 150, alignment: .leading)
                Picker("", selection: Binding(
                    get: { manager.preferences.browser },
                    set: { manager.updateBrowser($0) }
                )) {
                    ForEach(BrowserKind.allCases) { browser in
                        Text(browser.displayName).tag(browser)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
                Spacer()
            }

            Label(
                manager.isSelectedBrowserInstalled
                    ? L10n.t("browser_search.browser_available")
                    : L10n.t("browser_search.browser_not_installed"),
                systemImage: manager.isSelectedBrowserInstalled ? "checkmark.circle" : "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundColor(manager.isSelectedBrowserInstalled ? .secondary : .orange)

            Divider()

            keywordRow(
                title: L10n.t("browser_search.bookmark_keyword"),
                text: $bookmarkKeyword,
                hint: L10n.t("browser_search.bookmark_keyword_hint")
            )

            keywordRow(
                title: L10n.t("browser_search.history_keyword"),
                text: $historyKeyword,
                hint: L10n.t("browser_search.history_keyword_hint")
            )

            if let message = validationMessage ?? conflictMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button(L10n.t("browser_search.save_keywords")) {
                    saveKeywords()
                }
                .buttonStyle(.borderedProminent)
                .disabled(validationMessage != nil)
            }

            Text(L10n.t("browser_search.privacy_desc"))
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            bookmarkKeyword = manager.preferences.bookmarkKeyword
            historyKeyword = manager.preferences.historyKeyword
        }
    }

    private func keywordRow(title: String, text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .frame(width: 150, alignment: .leading)
                TextField(title, text: text)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Spacer()
            }
            Text(hint)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 150)
        }
    }

    private var validationMessage: String? {
        let bookmark = ShortcutRegistry.normalizedKeyword(bookmarkKeyword)
        let history = ShortcutRegistry.normalizedKeyword(historyKeyword)
        if bookmark.isEmpty || history.isEmpty {
            return L10n.t("browser_search.keyword_empty")
        }
        if bookmark.rangeOfCharacter(from: .whitespacesAndNewlines) != nil ||
            history.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            return L10n.t("browser_search.keyword_whitespace")
        }
        if bookmark == history {
            return L10n.t("browser_search.keyword_duplicate")
        }
        return nil
    }

    private func saveKeywords() {
        guard validationMessage == nil else { return }
        if manager.updateKeywords(bookmark: bookmarkKeyword, history: historyKeyword) == nil {
            bookmarkKeyword = manager.preferences.bookmarkKeyword
            historyKeyword = manager.preferences.historyKeyword
            conflictMessage = nil
        } else {
            conflictMessage = L10n.t("browser_search.keyword_conflict")
        }
    }
}
