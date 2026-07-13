import Foundation
import SwiftUI
import Combine
import OSLog
import AppKit

enum LauncherMode {
    case launcher
    case clipboard
    case snippets
}

class LauncherViewModel: ObservableObject {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "xxMac", category: "LauncherSearch")
    @Published var query: String = ""
    @Published var results: [SearchItem] = []
    @Published var selectedIndex: Int = 0
    @Published var mode: LauncherMode = .launcher
    @Published var searchID = UUID()
    
    private var cancellables = Set<AnyCancellable>()
    private var quickShortcutRunID: UUID?
    private var browserSearchRunID: UUID?
    private var isBrowsingEmptyHistory = false
    
    init() {
        $query
            .receive(on: RunLoop.main)
            .sink { [weak self] searchText in
                self?.performSearch(query: searchText)
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.addObserver(self, selector: #selector(onShowClipboardHistory), name: NSNotification.Name("ShowClipboardHistory"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onShowSnippets), name: NSNotification.Name("ShowSnippets"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onCloseLauncher), name: NSNotification.Name("CloseLauncher"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onToggleLauncher), name: NSNotification.Name("ToggleLauncher"), object: nil)
        
        // Observe ClipboardManager history
        ClipboardManager.shared.$history
            .receive(on: RunLoop.main)
            .sink { [weak self] history in
                if self?.mode == .clipboard {
                    self?.results = history
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(SnippetManager.shared.$collections, SnippetManager.shared.$entries)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                guard let self = self, self.mode == .snippets else { return }
                self.performSnippetSearch(query: self.query)
            }
            .store(in: &cancellables)

        QuickShortcutManager.shared.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self, self.mode == .launcher else { return }
                self.performLauncherSearch(query: self.query)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: BrowserSearchManager.settingsDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.mode == .launcher else { return }
                self.performLauncherSearch(query: self.query)
            }
            .store(in: &cancellables)

        // Refresh launcher results when app index changes (e.g. after path updates / async rescan).
        AppSearchManager.shared.$apps
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self, self.mode == .launcher, !self.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                self.performLauncherSearch(query: self.query)
            }
            .store(in: &cancellables)

        LauncherHistoryManager.shared.$records
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self,
                      self.mode == .launcher,
                      self.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      self.isBrowsingEmptyHistory else { return }
                self.performLauncherSearch(query: "")
            }
            .store(in: &cancellables)
    }
    
    @objc func onCloseLauncher() {
        resetToDefaultState()
    }
    
    @objc func onToggleLauncher() {
        resetToDefaultState()
    }
    
    @objc func onShowClipboardHistory() {
        mode = .clipboard
        resetSearchState()
        
        // Ensure UI state is reset on the main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.selectedIndex = 0
            self.performSearch()
        }
    }

    @objc func onShowSnippets() {
        mode = .snippets
        resetSearchState()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.selectedIndex = 0
            self.performSearch()
        }
    }
    
    private func resetToDefaultState() {
        mode = .launcher
        resetSearchState()
    }
    
    private func resetSearchState() {
        query = ""
        results = []
        selectedIndex = 0
        searchID = UUID()
        quickShortcutRunID = nil
        browserSearchRunID = nil
        isBrowsingEmptyHistory = false
    }
    
    func performSearch(query: String? = nil) {
        let searchText = query ?? self.query
        switch mode {
        case .launcher:
            performLauncherSearch(query: searchText)
        case .clipboard:
            performClipboardSearch(query: searchText)
        case .snippets:
            performSnippetSearch(query: searchText)
        }
    }
    
    private func performLauncherSearch(query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
            results = isBrowsingEmptyHistory
                ? LauncherHistoryManager.shared.search(query: "")
                : QuickShortcutManager.shared.fallbackSearchItems(query: "") { [weak self] item, query in
                    self?.runQuickShortcutCommand(item: item, query: query)
                }
            selectedIndex = 0
            return
        }

        isBrowsingEmptyHistory = false

        if handleQuickShortcut(query: trimmedQuery) {
            selectedIndex = 0
            return
        }

        if handleBrowserSearch(query: trimmedQuery) {
            selectedIndex = 0
            return
        }

        if let calculatorResult = CalculatorExpressionEvaluator.evaluate(trimmedQuery) {
            results = [
                SearchItem(
                    id: "calculator.\(calculatorResult.expression)",
                    title: calculatorResult.value,
                    subtitle: L10n.t("calculator.copy_result"),
                    iconName: "function",
                    type: .calculator,
                    action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(calculatorResult.value, forType: .string)
                    }
                )
            ]
            selectedIndex = 0
            return
        }
        
        // 1. Window Commands (only if query is not empty)
        let windowSubtitle = L10n.t("tool.window")
        let windowCommands = [
            SearchItem(id: "window.left", title: L10n.t("window_action.left"), subtitle: windowSubtitle, iconName: "rectangle.leadinghalf.inset.filled", type: .windowAction, action: { AccessibilityManager.shared.leftHalf() }),
            SearchItem(id: "window.right", title: L10n.t("window_action.right"), subtitle: windowSubtitle, iconName: "rectangle.trailinghalf.inset.filled", type: .windowAction, action: { AccessibilityManager.shared.rightHalf() }),
            SearchItem(id: "window.top", title: L10n.t("window_action.top"), subtitle: windowSubtitle, iconName: "rectangle.tophalf.inset.filled", type: .windowAction, action: { AccessibilityManager.shared.topHalf() }),
            SearchItem(id: "window.bottom", title: L10n.t("window_action.bottom"), subtitle: windowSubtitle, iconName: "rectangle.bottomhalf.inset.filled", type: .windowAction, action: { AccessibilityManager.shared.bottomHalf() }),
            SearchItem(id: "window.top_left", title: L10n.t("window_action.top_left"), subtitle: windowSubtitle, iconName: "uiwindow.split.2x1", type: .windowAction, action: { AccessibilityManager.shared.topLeft() }),
            SearchItem(id: "window.top_right", title: L10n.t("window_action.top_right"), subtitle: windowSubtitle, iconName: "uiwindow.split.2x1", type: .windowAction, action: { AccessibilityManager.shared.topRight() }),
            SearchItem(id: "window.bottom_left", title: L10n.t("window_action.bottom_left"), subtitle: windowSubtitle, iconName: "uiwindow.split.2x1", type: .windowAction, action: { AccessibilityManager.shared.bottomLeft() }),
            SearchItem(id: "window.bottom_right", title: L10n.t("window_action.bottom_right"), subtitle: windowSubtitle, iconName: "uiwindow.split.2x1", type: .windowAction, action: { AccessibilityManager.shared.bottomRight() }),
            SearchItem(id: "window.maximize", title: L10n.t("window_action.maximize"), subtitle: windowSubtitle, iconName: "rectangle.inset.filled", type: .windowAction, action: { AccessibilityManager.shared.maximize() }),
            SearchItem(id: "window.center", title: L10n.t("window_action.center"), subtitle: windowSubtitle, iconName: "rectangle.center.inset.filled", type: .windowAction, action: { AccessibilityManager.shared.center() }),
            SearchItem(id: "window.next_screen", title: L10n.t("window_action.next_screen"), subtitle: windowSubtitle, iconName: "arrow.right.to.line", type: .windowAction, action: { AccessibilityManager.shared.nextScreen() }),
            SearchItem(id: "window.previous_screen", title: L10n.t("window_action.previous_screen"), subtitle: windowSubtitle, iconName: "arrow.left.to.line", type: .windowAction, action: { AccessibilityManager.shared.previousScreen() })
        ].filter { $0.title.localizedCaseInsensitiveContains(trimmedQuery) }
        
        // 2. Apps (修复搜索状态)
        let appResults = AppSearchManager.shared.search(query: trimmedQuery)
        
        let fallbackShortcuts = QuickShortcutManager.shared.fallbackSearchItems(query: trimmedQuery) { [weak self] item, query in
            self?.runQuickShortcutCommand(item: item, query: query)
        }
        let newResults = appResults + windowCommands + fallbackShortcuts
        self.results = newResults
        self.selectedIndex = 0
        let preview = newResults.prefix(8).map { $0.title }.joined(separator: ", ")
        Self.logger.debug("query='\(query, privacy: .public)' trimmed='\(trimmedQuery, privacy: .public)' window=\(windowCommands.count) app=\(appResults.count) total=\(newResults.count)")
        Self.logger.debug("top=[\(preview, privacy: .public)]")
    }

    private func handleQuickShortcut(query: String) -> Bool {
        switch QuickShortcutManager.shared.activationState(query: query) {
        case .none:
            quickShortcutRunID = nil
            return false
        case .waitingForInput(let item):
            quickShortcutRunID = nil
            results = [
                SearchItem(
                    id: "quick_shortcut.waiting.\(item.id.uuidString)",
                    title: item.title,
                    subtitle: L10n.t("quick_shortcut.input_required"),
                    iconName: item.actionType.iconName,
                    iconFileURL: QuickShortcutManager.shared.iconURL(for: item),
                    type: .quickShortcut,
                    action: {}
                )
            ]
            return true
        case .ready(let match):
            switch match.item.actionType {
            case .webSearch:
                results = [
                    SearchItem(
                        id: "quick_shortcut.\(match.item.id.uuidString)",
                        title: match.item.title,
                        subtitle: QuickShortcutManager.shared.subtitle(for: match.item),
                        iconName: match.item.actionType.iconName,
                        iconFileURL: QuickShortcutManager.shared.iconURL(for: match.item),
                        type: .quickShortcut,
                        launcherHistorySnapshot: LauncherHistorySnapshot(
                            kind: .quickShortcut,
                            sourceID: match.item.id.uuidString,
                            title: match.item.title,
                            subtitle: QuickShortcutManager.shared.subtitle(for: match.item),
                            iconName: match.item.actionType.iconName,
                            query: match.query
                        ),
                        action: {
                            QuickShortcutManager.shared.execute(item: match.item, query: match.query)
                        }
                    )
                ]
                return true
            case .commandScript:
                runQuickShortcutCommand(item: match.item, query: match.query)
                return true
            }
        }
    }

    private func handleBrowserSearch(query: String) -> Bool {
        guard let request = BrowserSearchManager.shared.activationRequest(for: query) else {
            browserSearchRunID = nil
            return false
        }

        let runID = UUID()
        browserSearchRunID = runID
        results = [
            SearchItem(
                id: "browser_search.loading",
                title: L10n.t("browser_search.searching"),
                subtitle: BrowserSearchManager.shared.preferences.browser.displayName,
                iconName: "hourglass",
                type: request.mode == .bookmarks ? .bookmark : .browserHistory,
                action: {}
            )
        ]

        BrowserSearchManager.shared.search(request: request) { [weak self] result in
            guard let self,
                  self.mode == .launcher,
                  self.browserSearchRunID == runID,
                  BrowserSearchManager.shared.activationRequest(for: self.query) == request else { return }
            switch result {
            case .success(let records):
                self.results = records.map { record in
                    SearchItem(
                        id: "browser.\(request.mode).\(record.url.absoluteString)",
                        title: record.title,
                        subtitle: "\(BrowserSearchManager.shared.preferences.browser.displayName) · \(record.url.host ?? record.url.absoluteString)",
                        iconName: request.mode == .bookmarks ? "bookmark" : "clock.arrow.circlepath",
                        type: request.mode == .bookmarks ? .bookmark : .browserHistory,
                        action: { BrowserSearchManager.shared.open(record.url) }
                    )
                }
                if self.results.isEmpty {
                    self.results = [self.browserStatusItem(
                        title: L10n.t("browser_search.no_results"),
                        mode: request.mode
                    )]
                }
            case .failure:
                self.results = [self.browserStatusItem(
                    title: L10n.t("browser_search.unavailable"),
                    mode: request.mode
                )]
            }
            self.selectedIndex = 0
        }
        return true
    }

    private func browserStatusItem(title: String, mode: BrowserSearchMode) -> SearchItem {
        SearchItem(
            id: "browser_search.status",
            title: title,
            subtitle: BrowserSearchManager.shared.preferences.browser.displayName,
            iconName: "exclamationmark.circle",
            type: mode == .bookmarks ? .bookmark : .browserHistory,
            action: {}
        )
    }

    private func runQuickShortcutCommand(item: QuickShortcut, query: String) {
        let runID = UUID()
        let sourceInput = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
        recordQuickShortcutHistory(item: item, query: query)
        quickShortcutRunID = runID
        results = [
            SearchItem(
                id: "quick_shortcut.running.\(item.id.uuidString)",
                title: L10n.t("quick_shortcut.running"),
                subtitle: item.title,
                iconName: "hourglass",
                type: .quickShortcutOutput,
                action: {}
            )
        ]

        QuickShortcutManager.shared.runCommandScript(item: item, query: query) { [weak self] output in
            guard let self = self,
                  self.mode == .launcher,
                  self.quickShortcutRunID == runID,
                  self.query.trimmingCharacters(in: .whitespacesAndNewlines) == sourceInput else {
                return
            }
            self.results = self.outputResults(for: item, output: output)
            self.selectedIndex = 0
        }
    }

    private func outputResults(for item: QuickShortcut, output: String) -> [SearchItem] {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        let visibleLines = lines.isEmpty ? [output] : lines
        return visibleLines.enumerated().map { index, line in
            SearchItem(
                id: "quick_shortcut.output.\(item.id.uuidString).\(index)",
                title: line,
                subtitle: index == 0 ? L10n.t("quick_shortcut.copy_output") : item.title,
                iconName: "doc.text",
                type: .quickShortcutOutput,
                action: {
                    QuickShortcutManager.shared.copyToPasteboard(line)
                    NotificationCenter.default.post(name: NSNotification.Name("CloseLauncher"), object: nil)
                }
            )
        }
    }

    private func performClipboardSearch(query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        ClipboardManager.shared.searchClipboard(query: trimmedQuery)
    }

    private func performSnippetSearch(query: String) {
        results = SnippetManager.shared.search(query: query)
        selectedIndex = 0
    }
    
    func selectNext() {
        if enterEmptyHistoryBrowsingIfNeeded() { return }
        if results.isEmpty { return }
        selectedIndex = (selectedIndex + 1) % results.count
    }
    
    func selectPrevious() {
        if enterEmptyHistoryBrowsingIfNeeded() { return }
        if results.isEmpty { return }
        selectedIndex = (selectedIndex - 1 + results.count) % results.count
    }

    func selectNextPage() {
        if enterEmptyHistoryBrowsingIfNeeded() { return }
        selectPage(offset: 5)
    }

    func selectPreviousPage() {
        if enterEmptyHistoryBrowsingIfNeeded() { return }
        selectPage(offset: -5)
    }
    
    func executeSelection(revealInFinder: Bool = false) {
        guard results.indices.contains(selectedIndex) else { return }
        let item = results[selectedIndex]
        if mode == .launcher, !revealInFinder {
            LauncherHistoryManager.shared.record(item: item, query: query)
        }

        // Clipboard and snippet modes own their close/focus/input sequencing inside their managers.
        if mode != .clipboard && mode != .snippets && item.type != .quickShortcutOutput {
            NotificationCenter.default.post(name: NSNotification.Name("CloseLauncher"), object: nil)
        }

        if revealInFinder, item.type == .app {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.subtitle)])
        } else {
            item.action()
        }
    }

    private func selectPage(offset: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + offset, 0), results.count - 1)
    }

    private func enterEmptyHistoryBrowsingIfNeeded() -> Bool {
        guard mode == .launcher,
              query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isBrowsingEmptyHistory else {
            return false
        }

        let historyResults = LauncherHistoryManager.shared.search(query: "")
        guard !historyResults.isEmpty else { return false }
        isBrowsingEmptyHistory = true
        results = historyResults
        selectedIndex = 0
        return true
    }

    private func recordQuickShortcutHistory(item: QuickShortcut, query: String) {
        let subtitle = QuickShortcutManager.shared.subtitle(for: item)
        let searchItem = SearchItem(
            title: item.title,
            subtitle: subtitle,
            iconName: item.actionType.iconName,
            type: .quickShortcut,
            launcherHistorySnapshot: LauncherHistorySnapshot(
                kind: .quickShortcut,
                sourceID: item.id.uuidString,
                title: item.title,
                subtitle: subtitle,
                iconName: item.actionType.iconName,
                query: query
            ),
            action: {}
        )
        LauncherHistoryManager.shared.record(item: searchItem, query: query)
    }

}
