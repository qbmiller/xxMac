import AppKit
import ApplicationServices
import Combine
import OSLog

final class SnippetManager: ObservableObject {
    static let shared = SnippetManager()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "xxMac", category: "SnippetFlow")

    @Published var settings = SnippetSettings() {
        didSet {
            saveSettings()
            updateHotKey()
        }
    }
    @Published var collections: [SnippetCollection] = [] {
        didSet { saveCollections() }
    }
    @Published var entries: [SnippetEntry] = [] {
        didSet { saveEntries() }
    }

    private let settingsKey = "SnippetSettings"
    private let collectionsKey = "SnippetCollections"
    private let entriesKey = "SnippetEntries"
    private var hotKey: CarbonHotKeyRegistration?
    private var previousFrontmostApp: NSRunningApplication?

    private init() {
        loadSettings()
        loadCollections()
        loadEntries()
        seedDefaultDataIfNeeded()
        updateHotKey()
    }

    func addCollection(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        collections.append(SnippetCollection(name: trimmed))
    }

    func updateCollection(_ collection: SnippetCollection, name: String) {
        guard let index = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        collections[index].name = trimmed
    }

    func removeCollection(_ collection: SnippetCollection) {
        collections.removeAll { $0.id == collection.id }
        entries.removeAll { $0.collectionID == collection.id }
    }

    func addEntry(to collection: SnippetCollection) {
        entries.append(SnippetEntry(
            collectionID: collection.id,
            name: L10n.t("snippets.new_entry"),
            keyword: "",
            content: ""
        ))
    }

    func updateEntry(_ entry: SnippetEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
    }

    func removeEntry(_ entry: SnippetEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    func entries(in collection: SnippetCollection?) -> [SnippetEntry] {
        guard let collection else { return [] }
        return entries.filter { $0.collectionID == collection.id }
    }

    func search(query: String) -> [SearchItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = trimmedQuery.lowercased()
        let collectionNames = Dictionary(uniqueKeysWithValues: collections.map { ($0.id, $0.name) })

        let filteredEntries: [SnippetEntry]
        if normalizedQuery.isEmpty {
            filteredEntries = entries
        } else {
            filteredEntries = entries.filter { entry in
                entry.name.lowercased().contains(normalizedQuery) ||
                entry.keyword.lowercased().contains(normalizedQuery) ||
                entry.content.lowercased().contains(normalizedQuery) ||
                (collectionNames[entry.collectionID]?.lowercased().contains(normalizedQuery) ?? false)
            }
        }

        return filteredEntries.map { entry in
            let keyword = entry.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            let collection = collectionNames[entry.collectionID] ?? L10n.t("snippets.uncategorized")
            let subtitle = keyword.isEmpty ? collection : "\(collection) · \(keyword)"
            return SearchItem(
                id: "snippet.\(entry.id.uuidString)",
                title: entry.name,
                subtitle: subtitle,
                iconName: "text.quote",
                type: .snippet,
                snippetPreview: SnippetPreviewData(content: entry.content),
                action: { [weak self] in self?.paste(entry) }
            )
        }
    }

    private func paste(_ entry: SnippetEntry) {
        DispatchQueue.main.async { [weak self] in
            self?.typeInCapturedApp(entry.content)
        }
    }

    private func typeInCapturedApp(_ text: String) {
        guard !text.isEmpty else { return }
        copySnippetToPasteboard(text)
        NotificationCenter.default.post(name: NSNotification.Name("CloseLauncherPanelOnly"), object: nil)
        AccessibilityManager.shared.restoreSuspendedTextInputFocus()
        restoreFocusToCapturedApp()
        sendTextWhenReady(text, retries: 8)
    }

    private func copySnippetToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let copied = pasteboard.setString(text, forType: .string)
        Self.logger.notice("snippet copied to pasteboard copied=\(copied)")
    }

    private func sendTextWhenReady(_ text: String, retries: Int) {
        let targetPID = previousFrontmostApp?.processIdentifier
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        if targetPID == nil || targetPID == frontmostPID || retries <= 0 {
            typeText(text)
            previousFrontmostApp = nil
            return
        }

        restoreFocusToCapturedApp()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.sendTextWhenReady(text, retries: retries - 1)
        }
    }

    private func restoreFocusToCapturedApp() {
        guard let app = previousFrontmostApp else { return }
        if app.isHidden {
            app.unhide()
        }
        _ = app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        _ = sendReopenAndActivateAppleScript(to: app)
    }

    private func sendReopenAndActivateAppleScript(to app: NSRunningApplication) -> Bool {
        guard let bundleIdentifier = app.bundleIdentifier else { return false }
        let safeBundleIdentifier = bundleIdentifier.replacingOccurrences(of: "\"", with: "\\\"")
        let scriptSource = """
        tell application id "\(safeBundleIdentifier)"
            reopen
            activate
        end tell
        """

        guard let script = NSAppleScript(source: scriptSource) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return error == nil
    }

    private func typeText(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for scalar in text.unicodeScalars {
            var units = Array(String(scalar).utf16)
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                continue
            }
            units.withUnsafeMutableBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
                keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
            }
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func updateHotKey() {
        hotKey = nil
        if let config = settings.hotKey {
            hotKey = CarbonHotKeyRegistration(configuration: config, name: "snippets") { [weak self] in
                self?.showSnippets()
            }
        }
    }

    func captureCurrentFrontmostApp() {
        if let app = NSWorkspace.shared.frontmostApplication,
           app.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousFrontmostApp = app
        }
    }

    private func logSnippetFlow(_ stage: String) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let bundleID = frontmost?.bundleIdentifier ?? "nil"
        let pid = frontmost?.processIdentifier ?? 0
        let previous = previousFrontmostApp?.bundleIdentifier ?? "nil"
        let previousPID = previousFrontmostApp?.processIdentifier ?? 0
        Self.logger.notice("stage=\(stage, privacy: .public) frontmost=\(bundleID, privacy: .public)#\(pid) previous=\(previous, privacy: .public)#\(previousPID) appActive=\(NSApp.isActive) appHidden=\(NSApp.isHidden)")
    }

    private func showSnippets() {
        DispatchQueue.main.async {
            self.logSnippetFlow("showSnippets.begin")
            self.captureCurrentFrontmostApp()
            AccessibilityManager.shared.suspendFocusedTextInputForOverlay()
            self.logSnippetFlow("showSnippets.postNotification")
            NotificationCenter.default.post(name: NSNotification.Name("ShowSnippets"), object: nil)
        }
    }

    private func loadSettings() {
        if let data = PreferencesStore.shared.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(SnippetSettings.self, from: data) {
            settings = decoded
        }
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            PreferencesStore.shared.set(data, forKey: settingsKey)
        }
    }

    private func loadCollections() {
        if let data = PreferencesStore.shared.data(forKey: collectionsKey),
           let decoded = try? JSONDecoder().decode([SnippetCollection].self, from: data) {
            collections = decoded
        }
    }

    private func saveCollections() {
        if let data = try? JSONEncoder().encode(collections) {
            PreferencesStore.shared.set(data, forKey: collectionsKey)
        }
    }

    private func loadEntries() {
        if let data = PreferencesStore.shared.data(forKey: entriesKey),
           let decoded = try? JSONDecoder().decode([SnippetEntry].self, from: data) {
            entries = decoded
        }
    }

    private func saveEntries() {
        if let data = try? JSONEncoder().encode(entries) {
            PreferencesStore.shared.set(data, forKey: entriesKey)
        }
    }

    private func seedDefaultDataIfNeeded() {
        guard collections.isEmpty, entries.isEmpty else { return }
        let collection = SnippetCollection(name: L10n.t("snippets.default_collection"))
        collections = [collection]
        entries = [
            SnippetEntry(
                collectionID: collection.id,
                name: L10n.t("snippets.default_entry_name"),
                keyword: "addr",
                content: L10n.t("snippets.default_entry_content")
            )
        ]
    }
}
