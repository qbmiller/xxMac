import Foundation
import SwiftUI
import Combine
import OSLog

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
                guard let self = self, self.mode == .launcher, !self.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
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
            results = []
            selectedIndex = 0
            return
        }

        if handleQuickShortcut(query: trimmedQuery) {
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
        
        let newResults = appResults + windowCommands
        self.results = newResults
        self.selectedIndex = 0
        let preview = newResults.prefix(8).map { $0.title }.joined(separator: ", ")
        Self.logger.debug("query='\(query, privacy: .public)' trimmed='\(trimmedQuery, privacy: .public)' window=\(windowCommands.count) app=\(appResults.count) total=\(newResults.count)")
        Self.logger.debug("top=[\(preview, privacy: .public)]")
    }

    private func handleQuickShortcut(query: String) -> Bool {
        guard let match = QuickShortcutManager.shared.match(query: query) else {
            quickShortcutRunID = nil
            return false
        }

        switch match.item.actionType {
        case .webSearch:
            results = [
                SearchItem(
                    id: "quick_shortcut.\(match.item.id.uuidString)",
                    title: match.item.title,
                    subtitle: QuickShortcutManager.shared.subtitle(for: match.item),
                    iconName: match.item.actionType.iconName,
                    type: .quickShortcut,
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

    private func runQuickShortcutCommand(item: QuickShortcut, query: String) {
        let runID = UUID()
        let sourceInput = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
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
        if results.isEmpty { return }
        selectedIndex = (selectedIndex + 1) % results.count
    }
    
    func selectPrevious() {
        if results.isEmpty { return }
        selectedIndex = (selectedIndex - 1 + results.count) % results.count
    }
    
    func executeSelection(revealInFinder: Bool = false) {
        guard results.indices.contains(selectedIndex) else { return }
        let item = results[selectedIndex]
        if revealInFinder, item.type == .app {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.subtitle)])
        } else {
            item.action()
        }
        // Clipboard and snippet modes own their close/focus/input sequencing inside their managers.
        if mode != .clipboard && mode != .snippets {
            NotificationCenter.default.post(name: NSNotification.Name("CloseLauncher"), object: nil)
        }
    }

}
