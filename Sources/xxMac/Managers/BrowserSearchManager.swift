import AppKit
import Combine
import Foundation

protocol BrowserSearchPreferenceStoring {
    func string(forKey key: String) -> String?
    func boolObject(forKey key: String) -> Bool?
    func set(_ value: String, forKey key: String)
    func set(_ value: Bool, forKey key: String)
}

extension PreferencesStore: BrowserSearchPreferenceStoring {}

final class BrowserSearchManager: ObservableObject {
    static let shared = BrowserSearchManager()
    static let settingsDidChange = Notification.Name("BrowserSearchSettingsDidChange")

    private enum Key {
        static let enabled = "BrowserSearchEnabled"
        static let browser = "BrowserSearchBrowser"
        static let bookmarkKeyword = "BrowserSearchBookmarkKeyword"
        static let historyKeyword = "BrowserSearchHistoryKeyword"
    }

    @Published private(set) var preferences: BrowserSearchPreferences
    @Published private(set) var keywordConflict: ShortcutConflict?

    private let store: BrowserSearchPreferenceStoring
    private let providerFactory: (BrowserKind) -> BrowserDataProvider
    private let installedBrowser: (BrowserKind) -> Bool
    private let openURLHandler: (URL, BrowserKind) -> Void
    private let searchQueue: DispatchQueue
    private var activeKeywordActions = Set<ShortcutAction>()

    init(
        store: BrowserSearchPreferenceStoring = PreferencesStore.shared,
        providerFactory: @escaping (BrowserKind) -> BrowserDataProvider = {
            ChromiumBrowserDataProvider(browser: $0)
        },
        defaultBrowserIdentifier: @escaping () -> String? = BrowserSearchManager.systemDefaultBrowserIdentifier,
        installedBrowser: @escaping (BrowserKind) -> Bool = BrowserSearchManager.isBrowserInstalled,
        openURLHandler: @escaping (URL, BrowserKind) -> Void = BrowserSearchManager.openURL,
        searchQueue: DispatchQueue = DispatchQueue(label: "xxmac.browser-search", qos: .userInitiated)
    ) {
        self.store = store
        self.providerFactory = providerFactory
        self.installedBrowser = installedBrowser
        self.openURLHandler = openURLHandler
        self.searchQueue = searchQueue

        let savedBrowser = store.string(forKey: Key.browser).flatMap(BrowserKind.init(rawValue:))
        let browser = savedBrowser ?? Self.initialBrowser(
            defaultBundleIdentifier: defaultBrowserIdentifier(),
            isInstalled: installedBrowser
        )
        preferences = BrowserSearchPreferences(
            isEnabled: store.boolObject(forKey: Key.enabled) ?? AppDefaultSettings.BrowserSearch.isEnabled,
            browser: browser,
            bookmarkKeyword: store.string(forKey: Key.bookmarkKeyword) ?? AppDefaultSettings.BrowserSearch.bookmarkKeyword,
            historyKeyword: store.string(forKey: Key.historyKeyword) ?? AppDefaultSettings.BrowserSearch.historyKeyword
        )
        refreshKeywordRegistrations()
    }

    var isSelectedBrowserInstalled: Bool {
        installedBrowser(preferences.browser)
    }

    func activationRequest(for input: String) -> BrowserSearchRequest? {
        guard preferences.isEnabled else { return nil }
        if let query = invokedQuery(input, keyword: preferences.bookmarkKeyword),
           activeKeywordActions.contains(.browserBookmarks) {
            return BrowserSearchRequest(mode: .bookmarks, query: query)
        }
        if let query = invokedQuery(input, keyword: preferences.historyKeyword),
           activeKeywordActions.contains(.browserHistory) {
            return BrowserSearchRequest(mode: .history, query: query)
        }
        return nil
    }

    func search(
        request: BrowserSearchRequest,
        limit: Int = 30,
        completion: @escaping (Result<[BrowserRecord], Error>) -> Void
    ) {
        let provider = providerFactory(preferences.browser)
        searchQueue.async {
            let result: Result<[BrowserRecord], Error>
            do {
                switch request.mode {
                case .bookmarks:
                    result = .success(try provider.searchBookmarks(query: request.query, limit: limit))
                case .history:
                    result = .success(try provider.searchHistory(query: request.query, limit: limit))
                }
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    @discardableResult
    func updateKeywords(bookmark: String, history: String) -> ShortcutConflict? {
        let normalizedBookmark = ShortcutRegistry.normalizedKeyword(bookmark)
        let normalizedHistory = ShortcutRegistry.normalizedKeyword(history)
        let whitespace = CharacterSet.whitespacesAndNewlines
        guard !normalizedBookmark.isEmpty, !normalizedHistory.isEmpty else {
            return ShortcutConflict(action: normalizedBookmark.isEmpty ? .browserBookmarks : .browserHistory)
        }
        guard normalizedBookmark != normalizedHistory else {
            return ShortcutConflict(action: .browserBookmarks)
        }
        guard normalizedBookmark.rangeOfCharacter(from: whitespace) == nil,
              normalizedHistory.rangeOfCharacter(from: whitespace) == nil else {
            return ShortcutConflict(action: .browserBookmarks)
        }

        unregisterKeywords()
        if let conflict = ShortcutRegistryStore.shared.conflict(
            for: .browserBookmarks,
            trigger: .launcherKeyword(normalizedBookmark)
        ) ?? ShortcutRegistryStore.shared.conflict(
            for: .browserHistory,
            trigger: .launcherKeyword(normalizedHistory)
        ) {
            keywordConflict = conflict
            refreshKeywordRegistrations()
            return conflict
        }

        preferences.bookmarkKeyword = normalizedBookmark
        preferences.historyKeyword = normalizedHistory
        store.set(normalizedBookmark, forKey: Key.bookmarkKeyword)
        store.set(normalizedHistory, forKey: Key.historyKeyword)
        keywordConflict = nil
        refreshKeywordRegistrations()
        notifySettingsChanged()
        return nil
    }

    func updateBrowser(_ browser: BrowserKind) {
        preferences.browser = browser
        store.set(browser.rawValue, forKey: Key.browser)
        notifySettingsChanged()
    }

    func updateEnabled(_ enabled: Bool) {
        preferences.isEnabled = enabled
        store.set(enabled, forKey: Key.enabled)
        refreshKeywordRegistrations()
        notifySettingsChanged()
    }

    func open(_ url: URL) {
        openURLHandler(url, preferences.browser)
    }

    static func initialBrowser(
        defaultBundleIdentifier: String?,
        isInstalled: (BrowserKind) -> Bool
    ) -> BrowserKind {
        if let match = BrowserKind.allCases.first(where: { $0.bundleIdentifier == defaultBundleIdentifier }) {
            return match
        }
        return BrowserKind.allCases.first(where: isInstalled) ?? .chrome
    }

    private func invokedQuery(_ input: String, keyword: String) -> String? {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedInput = trimmedInput.lowercased()
        let normalizedKeyword = ShortcutRegistry.normalizedKeyword(keyword)
        guard !normalizedKeyword.isEmpty,
              normalizedInput == normalizedKeyword || normalizedInput.hasPrefix(normalizedKeyword + " ") else {
            return nil
        }
        return String(trimmedInput.dropFirst(normalizedKeyword.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func refreshKeywordRegistrations() {
        unregisterKeywords()
        guard preferences.isEnabled else { return }

        let pairs: [(ShortcutAction, String)] = [
            (.browserBookmarks, preferences.bookmarkKeyword),
            (.browserHistory, preferences.historyKeyword)
        ]
        for (action, keyword) in pairs {
            if let conflict = ShortcutRegistryStore.shared.register(
                action: action,
                trigger: .launcherKeyword(keyword)
            ) {
                keywordConflict = conflict
                continue
            }
            activeKeywordActions.insert(action)
        }
    }

    private func unregisterKeywords() {
        ShortcutRegistryStore.shared.unregister(action: .browserBookmarks)
        ShortcutRegistryStore.shared.unregister(action: .browserHistory)
        activeKeywordActions.removeAll()
    }

    private func notifySettingsChanged() {
        NotificationCenter.default.post(name: Self.settingsDidChange, object: self)
    }

    private static func systemDefaultBrowserIdentifier() -> String? {
        guard let url = URL(string: "https://example.com"),
              let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: url) else { return nil }
        return Bundle(url: applicationURL)?.bundleIdentifier
    }

    private static func isBrowserInstalled(_ browser: BrowserKind) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleIdentifier) != nil
    }

    private static func openURL(_ url: URL, browser: BrowserKind) {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleIdentifier) else {
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: applicationURL,
            configuration: configuration,
            completionHandler: nil
        )
    }
}
