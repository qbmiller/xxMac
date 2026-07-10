import SwiftUI
import Combine
import OSLog

enum MenuBarVisibilityAction: Equatable {
    case create
    case showExisting
    case recreate
    case hide
    case none
}

enum MenuBarVisibilityPolicy {
    static func action(
        shouldShow: Bool,
        hasStatusItem: Bool,
        recreateWhenShowing: Bool
    ) -> MenuBarVisibilityAction {
        if shouldShow {
            if hasStatusItem {
                return recreateWhenShowing ? .recreate : .showExisting
            }
            return .create
        }

        return hasStatusItem ? .hide : .none
    }
}

enum MenuBarStatusItemIdentity {
    static let autosaveName = "xxMac.statusItem"
    static let accessibilityLabel = "xxMac"
    static let accessibilityIdentifier = "xxMac.statusItem"
}

extension Notification.Name {
    static let menuBarStatusReaffirmRequested = Notification.Name("MenuBarStatusReaffirmRequested")
}

struct MenuBarStatusSnapshot {
    let shouldShow: Bool
    let hasStatusItem: Bool
    let isVisible: Bool?
    let hasButton: Bool
    let buttonHasWindow: Bool
    let buttonFrame: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let autosaveName: String
    let displayMode: String
    let imageSize: String
    let imageIsTemplate: Bool?
    let imageVisiblePixelRatio: String
    let lastEvent: String
    let updatedAt: Date

    static let initial = MenuBarStatusSnapshot(
        shouldShow: true,
        hasStatusItem: false,
        isVisible: nil,
        hasButton: false,
        buttonHasWindow: false,
        buttonFrame: "nil",
        accessibilityLabel: "nil",
        accessibilityIdentifier: "nil",
        autosaveName: MenuBarStatusItemIdentity.autosaveName,
        displayMode: "nil",
        imageSize: "nil",
        imageIsTemplate: nil,
        imageVisiblePixelRatio: "nil",
        lastEvent: "initial",
        updatedAt: Date()
    )
}

@MainActor
final class MenuBarStatusDiagnostics: ObservableObject {
    static let shared = MenuBarStatusDiagnostics()

    @Published private(set) var snapshot = MenuBarStatusSnapshot.initial

    func update(_ snapshot: MenuBarStatusSnapshot) {
        self.snapshot = snapshot
    }
}

@main
struct xxMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L10n.t("menu.settings")) {
                    appDelegate.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

class FloatingPanel: NSPanel {
    var keyDownHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func cancelOperation(_ sender: Any?) {
        NotificationCenter.default.post(name: NSNotification.Name("CloseLauncher"), object: nil)
    }
    
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if let handler = keyDownHandler, handler(event) {
                return
            }
        }
        super.sendEvent(event)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private static let launcherLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "xxMac", category: "LauncherPanel")
    private static let menuBarLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "xxMac", category: "MenuBar")

    var statusItem: NSStatusItem?
    var launcherPanel: NSPanel!
    var settingsWindow: NSWindow?
    var calendarMenuBarController: CalendarMenuBarController?
    var launcherViewModel = LauncherViewModel()
    var eventMonitor: Any?
    var launcherMouseMonitor: Any?
    private var toggleLauncherMenuItem: NSMenuItem?
    private var showClipboardHistoryMenuItem: NSMenuItem?
    private var lockAIMenuItem: NSMenuItem?
    private var settingsMenuItem: NSMenuItem?
    private var quitMenuItem: NSMenuItem?
    private var localizationCancellable: AnyCancellable?
    private var generalSettingsCancellable: AnyCancellable?
    private var launcherPanelCancellables = Set<AnyCancellable>()
    private var isOpeningLauncher = false
    private var pendingLauncherRestore = false
    private var ignoreLauncherResignKeyUntil = Date.distantPast
    private var launcherOpenAttempt = 0
    private var previousFrontmostApp: NSRunningApplication?
    private var lastOpenFallbackAtByBundleID: [String: Date] = [:]
    private let openFallbackCooldown: TimeInterval = 3
    private let launcherRestingLevel: NSWindow.Level = .floating
    private let launcherPresentationLevel: NSWindow.Level = .statusBar

    private var launcherCollectionBehavior: NSWindow.CollectionBehavior {
        [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    private func appDescriptor(_ app: NSRunningApplication?) -> String {
        guard let app = app else { return "nil" }
        let bundleID = app.bundleIdentifier ?? "unknown.bundle"
        return "\(bundleID)#\(app.processIdentifier)"
    }

    private func logFocusState(_ stage: String) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        NSLog("[ClipboardFocus][%@] frontmost=%@ previous=%@ appActive=%@ appHidden=%@ launcherVisible=%@",
              stage,
              appDescriptor(frontmost),
              appDescriptor(previousFrontmostApp),
              NSApp.isActive.description,
              NSApp.isHidden.description,
              launcherPanel?.isVisible.description ?? "false")
    }

    private var launcherModeDescription: String {
        switch launcherViewModel.mode {
        case .launcher:
            return "launcher"
        case .clipboard:
            return "clipboard"
        case .snippets:
            return "snippets"
        }
    }

    private func launcherStateDescription() -> String {
        guard let launcherPanel else {
            return "panel=nil"
        }

        return [
            "visible=\(launcherPanel.isVisible)",
            "key=\(launcherPanel.isKeyWindow)",
            "miniaturized=\(launcherPanel.isMiniaturized)",
            "level=\(launcherPanel.level.rawValue)",
            "appActive=\(NSApp.isActive)",
            "appHidden=\(NSApp.isHidden)",
            "frontmost=\(appDescriptor(NSWorkspace.shared.frontmostApplication))"
        ].joined(separator: " ")
    }

    private func logLauncherState(_ stage: String) {
        Self.launcherLogger.notice("\(stage, privacy: .public) mode=\(self.launcherModeDescription, privacy: .public) \(self.launcherStateDescription(), privacy: .public)")
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize file-backed configuration before any manager reads settings.
        _ = ConfigDirectoryManager.shared
        _ = PreferencesStore.shared
        _ = GeneralSettingsManager.shared
        // Initialize HotKeyManager
        _ = HotKeyManager.shared
        // Initialize AppLauncherManager
        _ = AppLauncherManager.shared
        // Initialize ClipboardManager
        _ = ClipboardManager.shared
        // Initialize SnippetManager
        _ = SnippetManager.shared
        // Initialize LockAIManager
        _ = LockAIManager.shared
        
        // Request accessibility permissions (critical for hotkeys to work)
        _ = AccessibilityManager.shared.checkAccessibilityPermissions()
        // if !hasAccessibility {
        //     let alert = NSAlert()
        //     alert.messageText = "Accessibility Permission Required"
        //     alert.informativeText = "xxMac needs accessibility permission to manage windows and register global hotkeys.\n\n1. Go to System Settings > Privacy & Security > Accessibility\n2. Add 'xxMac' to the allowed apps\n3. Restart the application\n\nWithout this permission, window management and hotkeys won't work."
        //     alert.addButton(withTitle: "Open System Settings")
        //     alert.addButton(withTitle: "Remind Later")
            
        //     if alert.runModal() == .alertFirstButtonReturn {
        //         // Open System Settings to Accessibility
        //         if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
        //             NSWorkspace.shared.open(url)
        //         }
        //     }
        // }
        
        // 1. Setup Menu Bar
        syncMenuBarVisibility()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.reaffirmMenuBarItemIfNeeded(trigger: "launch")
        }
        
        // 2. Setup Launcher Window
        createLauncherPanel()
        
        // 3. Setup Global Hotkey
        // Keyboard navigation monitor
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if self.launcherPanel.isVisible {
                if self.handleLauncherKeyDown(event) {
                    return nil
                }
            }
            return event
        }

        launcherMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, self.launcherPanel.isVisible else { return }
                self.logLauncherState("globalMouseDown.close")
                self.closeLauncher()
            }
        }
        
        // 4. Observers
        NotificationCenter.default.addObserver(self, selector: #selector(toggleLauncher), name: NSNotification.Name("ToggleLauncher"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(closeLauncher), name: NSNotification.Name("CloseLauncher"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(closeLauncherPanelOnly), name: NSNotification.Name("CloseLauncherPanelOnly"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showClipboardHistory), name: NSNotification.Name("ShowClipboardHistory"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showSnippets), name: NSNotification.Name("ShowSnippets"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reaffirmMenuBarStatusFromNotification), name: .menuBarStatusReaffirmRequested, object: nil)

        localizationCancellable = LocalizationManager.shared.$language.sink { [weak self] _ in
            self?.updateMenuTitles()
        }
        generalSettingsCancellable = GeneralSettingsManager.shared.$showMenuBarItem
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] showMenuBarItem in
                Task { @MainActor in
                    self?.syncMenuBarVisibility(recreateWhenShowing: showMenuBarItem)
                }
            }
        NotificationCenter.default.addObserver(self, selector: #selector(updateMenuShortcuts), name: HotKeyManager.configurationsDidChangeNotification, object: nil)
        updateMenuShortcuts()
        openSettings()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    @MainActor
    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let toggleItem = NSMenuItem(title: L10n.t("menu.toggle_launcher"), action: #selector(toggleLauncher), keyEquivalent: "")
        toggleItem.target = self
        toggleLauncherMenuItem = toggleItem
        menu.addItem(toggleItem)

        let clipboardItem = NSMenuItem(title: L10n.t("menu.clipboard_history"), action: #selector(openClipboardHistoryFromMenu), keyEquivalent: "")
        clipboardItem.target = self
        showClipboardHistoryMenuItem = clipboardItem
        menu.addItem(clipboardItem)

        let lockAIItem = NSMenuItem(title: L10n.t("menu.lock_ai"), action: #selector(lockAI), keyEquivalent: "")
        lockAIItem.target = self
        lockAIMenuItem = lockAIItem
        menu.addItem(lockAIItem)

        let settingsItem = NSMenuItem(title: L10n.t("menu.settings"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsMenuItem = settingsItem
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: L10n.t("menu.quit"), action: #selector(confirmQuit), keyEquivalent: "q")
        quitItem.target = self
        quitMenuItem = quitItem
        menu.addItem(quitItem)

        return menu
    }

    @MainActor
    private func syncMenuBarVisibility(recreateWhenShowing: Bool = false) {
        let shouldShow = GeneralSettingsManager.shared.showMenuBarItem
        let action = MenuBarVisibilityPolicy.action(
            shouldShow: shouldShow,
            hasStatusItem: statusItem != nil,
            recreateWhenShowing: recreateWhenShowing
        )

        Self.menuBarLogger.notice("sync requested show=\(shouldShow) hasStatusItem=\(self.statusItem != nil) recreate=\(recreateWhenShowing) action=\(String(describing: action), privacy: .public)")

        switch action {
        case .create, .showExisting:
            ensureMenuBarItem()
        case .recreate:
            destroyMenuBarItemForRecreation()
            ensureMenuBarItem()
        case .hide:
            removeMenuBarItem()
        case .none:
            break
        }
    }

    @objc private func reaffirmMenuBarStatusFromNotification() {
        reaffirmMenuBarItemIfNeeded(trigger: "diagnostics")
    }

    @MainActor
    private func updateMenuBarDiagnostics(event: String) {
        let item = statusItem
        let button = item?.button
        let frameDescription = button.map { NSStringFromRect($0.frame) } ?? "nil"
        let label = button?.accessibilityLabel() ?? "nil"
        let identifier = button?.accessibilityIdentifier() ?? button?.identifier?.rawValue ?? "nil"
        let autosaveName = item.map { String(describing: $0.autosaveName) } ?? "nil"
        let imageSize = button?.image.map { NSStringFromSize($0.size) } ?? "nil"
        let imageIsTemplate = button?.image?.isTemplate
        let imageVisiblePixelRatio = Self.visiblePixelRatioDescription(for: button?.image)

        MenuBarStatusDiagnostics.shared.update(
            MenuBarStatusSnapshot(
                shouldShow: GeneralSettingsManager.shared.showMenuBarItem,
                hasStatusItem: item != nil,
                isVisible: item?.isVisible,
                hasButton: button != nil,
                buttonHasWindow: button?.window != nil,
                buttonFrame: frameDescription,
                accessibilityLabel: label,
                accessibilityIdentifier: identifier,
                autosaveName: autosaveName,
                displayMode: CalendarPreferencesStore.shared.menuBarDisplayMode.rawValue,
                imageSize: imageSize,
                imageIsTemplate: imageIsTemplate,
                imageVisiblePixelRatio: imageVisiblePixelRatio,
                lastEvent: event,
                updatedAt: Date()
            )
        )
    }

    private static func visiblePixelRatioDescription(for image: NSImage?) -> String {
        guard let image,
              let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data) else {
            return "nil"
        }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 0, height > 0 else { return "nil" }

        var visiblePixels = 0
        for y in 0..<height {
            for x in 0..<width where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                visiblePixels += 1
            }
        }

        let ratio = Double(visiblePixels) / Double(width * height)
        return String(format: "%.3f", ratio)
    }

    @MainActor
    private func configureMenuBarStatusItemIdentity(_ statusItem: NSStatusItem) {
        statusItem.autosaveName = NSStatusItem.AutosaveName(MenuBarStatusItemIdentity.autosaveName)
        guard let button = statusItem.button else { return }
        button.identifier = NSUserInterfaceItemIdentifier(MenuBarStatusItemIdentity.accessibilityIdentifier)
        button.setAccessibilityLabel(MenuBarStatusItemIdentity.accessibilityLabel)
        button.setAccessibilityIdentifier(MenuBarStatusItemIdentity.accessibilityIdentifier)
    }

    @MainActor
    private func reaffirmMenuBarItemIfNeeded(trigger: String) {
        guard GeneralSettingsManager.shared.showMenuBarItem else { return }

        guard let existingStatusItem = statusItem else {
            ensureMenuBarItem()
            updateMenuBarDiagnostics(event: "reaffirm-create:\(trigger)")
            Self.menuBarLogger.notice("status item reaffirmed by creating trigger=\(trigger, privacy: .public)")
            return
        }

        if existingStatusItem.isVisible {
            existingStatusItem.isVisible = true
            configureMenuBarStatusItemIdentity(existingStatusItem)
            calendarMenuBarController?.refreshStatusItem()
            updateMenuBarDiagnostics(event: "reaffirm-existing:\(trigger)")
            Self.menuBarLogger.notice("status item reaffirmed existing trigger=\(trigger, privacy: .public)")
            return
        }

        destroyMenuBarItemForRecreation()
        ensureMenuBarItem()
        updateMenuBarDiagnostics(event: "reaffirm-recreate:\(trigger)")
        Self.menuBarLogger.notice("status item reaffirmed by recreating hidden item trigger=\(trigger, privacy: .public)")
    }

    @MainActor
    private func ensureMenuBarItem() {
        guard statusItem == nil else {
            statusItem?.isVisible = true
            if let statusItem {
                configureMenuBarStatusItemIdentity(statusItem)
            }
            calendarMenuBarController?.refreshStatusItem()
            updateMenuTitles()
            updateMenuShortcuts()
            updateMenuBarDiagnostics(event: "show-existing")
            Self.menuBarLogger.notice("status item shown existing")
            return
        }

        let newStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        newStatusItem.length = CalendarPreferencesStore.shared.menuBarDisplayMode == .appIcon ? NSStatusItem.squareLength : 28
        configureMenuBarStatusItemIdentity(newStatusItem)
        statusItem = newStatusItem
        calendarMenuBarController = CalendarMenuBarController(statusItem: newStatusItem, contextMenu: makeStatusMenu())
        updateMenuTitles()
        updateMenuShortcuts()
        newStatusItem.isVisible = true
        updateMenuBarDiagnostics(event: "create")
        Self.menuBarLogger.notice("status item created and shown")
    }

    @MainActor
    private func removeMenuBarItem() {
        guard let existingStatusItem = statusItem else {
            Self.menuBarLogger.notice("hide skipped: no status item")
            return
        }

        calendarMenuBarController?.closeTransientUI()
        existingStatusItem.isVisible = false
        updateMenuBarDiagnostics(event: "hide")
        Self.menuBarLogger.notice("status item hidden via isVisible=false")
    }

    @MainActor
    private func destroyMenuBarItemForRecreation() {
        guard let existingStatusItem = statusItem else {
            Self.menuBarLogger.notice("recreate skipped destroy: no status item")
            return
        }

        calendarMenuBarController?.closeTransientUI()
        calendarMenuBarController = nil
        NSStatusBar.system.removeStatusItem(existingStatusItem)
        statusItem = nil
        toggleLauncherMenuItem = nil
        showClipboardHistoryMenuItem = nil
        lockAIMenuItem = nil
        settingsMenuItem = nil
        quitMenuItem = nil
        updateMenuBarDiagnostics(event: "destroy")
        Self.menuBarLogger.notice("status item destroyed for recreation")
    }

    func menuWillOpen(_ menu: NSMenu) {
        ClipboardManager.shared.captureCurrentFrontmostApp()
    }
    
    func createLauncherPanel() {
        let contentView = LauncherView(viewModel: launcherViewModel)
        
        launcherPanel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        launcherPanel.contentView = NSHostingView(rootView: contentView)
        launcherPanel.backgroundColor = .clear
        launcherPanel.isOpaque = false
        launcherPanel.hasShadow = true
        launcherPanel.level = launcherRestingLevel
        launcherPanel.center()
        launcherPanel.isMovableByWindowBackground = false
        launcherPanel.becomesKeyOnlyIfNeeded = false
        launcherPanel.hidesOnDeactivate = false
        launcherPanel.isReleasedWhenClosed = false
        // .canJoinAllSpaces and .moveToActiveSpace are mutually exclusive for NSPanel.
        launcherPanel.collectionBehavior = launcherCollectionBehavior
        launcherPanel.delegate = self
        
        (launcherPanel as? FloatingPanel)?.keyDownHandler = { [weak self] event in
            guard let self = self else { return false }
            return self.handleLauncherKeyDown(event)
        }

        bindLauncherPanelSizing()
        updateLauncherPanelFrame(keepingCenter: false)
    }

    private func bindLauncherPanelSizing() {
        let appearance = LauncherAppearanceManager.shared
        let updates: [AnyPublisher<Void, Never>] = [
            launcherViewModel.$query.map { _ in () }.eraseToAnyPublisher(),
            launcherViewModel.$results.map { _ in () }.eraseToAnyPublisher(),
            launcherViewModel.$mode.map { _ in () }.eraseToAnyPublisher(),
            AppSearchManager.shared.$isIndexing.map { _ in () }.eraseToAnyPublisher(),
            appearance.$launcherWidth.map { _ in () }.eraseToAnyPublisher(),
            appearance.$launcherHeight.map { _ in () }.eraseToAnyPublisher(),
            appearance.$sizeScale.map { _ in () }.eraseToAnyPublisher(),
            appearance.$textScale.map { _ in () }.eraseToAnyPublisher()
        ]

        Publishers.MergeMany(updates)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateLauncherPanelFrame(keepingCenter: self?.launcherPanel.isVisible == true)
            }
            .store(in: &launcherPanelCancellables)
    }

    private func updateLauncherPanelFrame(keepingCenter: Bool) {
        guard launcherPanel != nil else { return }

        let appearance = LauncherAppearanceManager.shared
        let scale = appearance.sizeScale
        let searchRowHeight = 86 * scale
        let resultRowHeight = 86 * scale
        let dividerHeight = 1.0
        let indexingHeight = 31 * scale
        let hasQuery = !launcherViewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let width: CGFloat
        let height: CGFloat

        switch launcherViewModel.mode {
        case .clipboard:
            width = CGFloat(max(appearance.launcherWidth, 920))
            height = CGFloat(searchRowHeight + dividerHeight + appearance.launcherHeight)
        case .snippets:
            width = CGFloat(appearance.launcherWidth)
            let resultHeight = min(Double(max(launcherViewModel.results.count, 1)) * resultRowHeight, appearance.launcherHeight)
            height = CGFloat(searchRowHeight + dividerHeight + resultHeight)
        case .launcher:
            width = CGFloat(appearance.launcherWidth)
            var contentHeight = searchRowHeight

            if hasQuery && AppSearchManager.shared.isIndexing {
                contentHeight += dividerHeight + indexingHeight
            }

            if hasQuery && !launcherViewModel.results.isEmpty {
                let resultHeight = min(Double(launcherViewModel.results.count) * resultRowHeight, appearance.launcherHeight)
                contentHeight += dividerHeight + resultHeight
            }

            height = CGFloat(contentHeight)
        }

        let currentFrame = launcherPanel.frame
        let center = NSPoint(x: currentFrame.midX, y: currentFrame.midY)
        var newFrame = NSRect(origin: currentFrame.origin, size: NSSize(width: width, height: height))

        if keepingCenter {
            newFrame.origin.x = center.x - width / 2
            newFrame.origin.y = center.y - height / 2
        }

        launcherPanel.setFrame(newFrame, display: true)
    }

    private func handleLauncherKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 125: // Arrow Down
            launcherViewModel.selectNext()
            return true
        case 126: // Arrow Up
            launcherViewModel.selectPrevious()
            return true
        case 36: // Enter
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            launcherViewModel.executeSelection(revealInFinder: modifiers.contains(.command))
            return true
        case 53: // ESC
            closeLauncher()
            return true
        default:
            return false
        }
    }
    
    @objc func showClipboardHistory() {
        openLauncher()
    }

    @objc func showSnippets() {
        openLauncher()
    }

    @objc func openClipboardHistoryFromMenu() {
        ClipboardManager.shared.showClipboardHistory()
    }
    
    @objc func toggleLauncher() {
        NSLog("=== toggleLauncher === isVisible:%@ isMiniaturized:%@ isKeyWindow:%@ appActive:%@",
              launcherPanel.isVisible.description,
              launcherPanel.isMiniaturized.description,
              launcherPanel.isKeyWindow.description,
              NSApp.isActive.description)

        let isLauncherFrontmost = launcherPanel.isVisible &&
            launcherPanel.isKeyWindow &&
            NSApp.isActive &&
            !launcherPanel.isMiniaturized

        if isLauncherFrontmost {
            closeLauncher()
        } else {
            // Reset to launcher mode when opening normally
            launcherViewModel.onToggleLauncher()
            openLauncher()
        }
    }
    
    @objc func openSettings() {
        dismissLauncherBeforeOpeningSettings()

        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = L10n.t("window.settings")
            window.contentView = NSHostingView(rootView: SettingsView())
            configureSettingsWindow(window)
            window.setFrameAutosaveName("SettingsWindow")
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }

        if let settingsWindow {
            configureSettingsWindow(settingsWindow)
        }
        
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func configureSettingsWindow(_ window: NSWindow) {
        SettingsWindowConfiguration.apply(to: window)
    }

    @objc func lockAI() {
        LockAIManager.shared.lock()
    }

    @objc func confirmQuit() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.t("menu.quit_confirm_title")
        alert.informativeText = L10n.t("menu.quit_confirm_message")
        let cancelButton = alert.addButton(withTitle: L10n.t("general.cancel"))
        let quitButton = alert.addButton(withTitle: L10n.t("menu.quit"))
        cancelButton.keyEquivalent = "\r"
        quitButton.keyEquivalent = ""

        if let window = NSApp.keyWindow {
            var escapeMonitor: Any?
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53 else { return event }
                window.endSheet(alert.window, returnCode: .alertFirstButtonReturn)
                return nil
            }
            alert.beginSheetModal(for: window) { response in
                if let escapeMonitor {
                    NSEvent.removeMonitor(escapeMonitor)
                }
                if response == .alertSecondButtonReturn {
                    NSApp.terminate(nil)
                }
            }
        } else {
            var escapeMonitor: Any?
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53 else { return event }
                NSApp.stopModal(withCode: .alertFirstButtonReturn)
                alert.window.orderOut(nil)
                return nil
            }
            let response = alert.runModal()
            if let escapeMonitor {
                NSEvent.removeMonitor(escapeMonitor)
            }
            if response == .alertSecondButtonReturn {
                NSApp.terminate(nil)
            }
        }
    }

    @MainActor
    @objc func openCalendar() {
        calendarMenuBarController?.showCalendarWindow()
    }

    @MainActor
    private func updateMenuTitles() {
        toggleLauncherMenuItem?.title = L10n.t("menu.toggle_launcher")
        showClipboardHistoryMenuItem?.title = L10n.t("menu.clipboard_history")
        lockAIMenuItem?.title = L10n.t("menu.lock_ai")
        settingsMenuItem?.title = L10n.t("menu.settings")
        quitMenuItem?.title = L10n.t("menu.quit")
        settingsWindow?.title = L10n.t("window.settings")
        calendarMenuBarController?.refreshStatusItem()
    }

    @MainActor
    @objc private func updateMenuShortcuts() {
        applyMenuShortcut(for: .toggleLauncher, to: toggleLauncherMenuItem)
        applyMenuShortcut(for: .lockAI, to: lockAIMenuItem)
    }

    private func applyMenuShortcut(for action: WindowAction, to menuItem: NSMenuItem?) {
        guard let menuItem else { return }

        if let configuration = HotKeyManager.shared.configurations[action],
           !configuration.menuKeyEquivalent.isEmpty {
            menuItem.keyEquivalent = configuration.menuKeyEquivalent
            menuItem.keyEquivalentModifierMask = configuration.modifiers.intersection(.deviceIndependentFlagsMask)
        } else {
            menuItem.keyEquivalent = ""
            menuItem.keyEquivalentModifierMask = []
        }
    }
    
    func openLauncher() {
        launcherOpenAttempt += 1
        let openAttempt = launcherOpenAttempt
        isOpeningLauncher = true
        pendingLauncherRestore = true
        ignoreLauncherResignKeyUntil = Date().addingTimeInterval(0.8)
        capturePreviousFrontmostApp(force: false)
        logFocusState("openLauncher.begin")
        logLauncherState("openLauncher.begin attempt=\(openAttempt)")

        NSLog("=== openLauncher === isHidden:%@ isMiniaturized:%@ isVisible:%@",
              NSApp.isHidden.description,
              launcherPanel.isMiniaturized.description,
              launcherPanel.isVisible.description)
        
        // 1. Restore all miniaturized windows except launcherPanel which is handled below
        for window in NSApp.windows {
            if window.isMiniaturized && window != launcherPanel {
                window.deminiaturize(nil)
                window.makeKeyAndOrderFront(nil)
            }
        }

        if launcherPanel.isMiniaturized {
            launcherPanel.deminiaturize(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.bringLauncherToFront()
                self.finishOpenLauncher(openAttempt: openAttempt)
            }
        } else if NSApp.isHidden {
            NSApp.unhide(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.bringLauncherToFront()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.bringLauncherToFront()
                self.finishOpenLauncher(openAttempt: openAttempt)
            }
        } else {
            bringLauncherToFront()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                self.bringLauncherToFront()
            }
            finishOpenLauncher(openAttempt: openAttempt)
        }
    }

    private func capturePreviousFrontmostApp(force: Bool = false) {
        if !force, previousFrontmostApp != nil {
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        previousFrontmostApp = app
        logFocusState(force ? "capturePrevious.force" : "capturePrevious.normal")
    }

    func capturePreviousFrontmostAppForClipboard() {
        capturePreviousFrontmostApp(force: true)
    }

    func activatePreviousFrontmostApp() {
        guard let app = previousFrontmostApp else { return }
        app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
    }

    @discardableResult
    func restoreFocusToPreviousAppForClipboard() -> Bool {
        guard let app = previousFrontmostApp else { return false }
        logFocusState("restore.begin")

        if app.isHidden {
            app.unhide()
        }

        let activated = app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        let reopened = sendReopenAndActivateAppleScript(to: app)

        if !activated && !reopened,
           let bundleURL = app.bundleURL,
           shouldOpenApplicationFallback(for: app, bundleURL: bundleURL) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in }
            logFocusState("restore.openApplicationFallback")
        }

        let otherVisibleWindows = NSApp.windows.filter { window in
            window.isVisible && window != launcherPanel
        }
        if otherVisibleWindows.isEmpty {
            NSRunningApplication.current.hide()
            logFocusState("restore.hideSelf")
        }

        logFocusState("restore.end activated=\(activated) reopened=\(reopened)")
        return activated || reopened
    }

    private func shouldOpenApplicationFallback(for app: NSRunningApplication, bundleURL: URL) -> Bool {
        guard app.isTerminated == false else { return false }
        guard bundleURL.isFileURL, bundleURL.pathExtension == "app" else { return false }
        guard FileManager.default.fileExists(atPath: bundleURL.path) else { return false }
        guard let bundleID = app.bundleIdentifier else { return false }

        let now = Date()
        if let lastTime = lastOpenFallbackAtByBundleID[bundleID],
           now.timeIntervalSince(lastTime) < openFallbackCooldown {
            return false
        }

        lastOpenFallbackAtByBundleID[bundleID] = now
        return true
    }

    func isPreviousFrontmostAppActive() -> Bool {
        guard let app = previousFrontmostApp else { return true }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }

    func clearPreviousFrontmostApp() {
        logFocusState("clearPrevious.before")
        previousFrontmostApp = nil
        logFocusState("clearPrevious.after")
    }

    func relinquishFocusForClipboardPaste() {
        _ = restoreFocusToPreviousAppForClipboard()
    }

    func closeLauncherForClipboardPaste() {
        logFocusState("closeLauncherForPaste.before")
        launcherPanel.orderOut(nil)
        resetLauncherPanelPresentation()
        isOpeningLauncher = false
        pendingLauncherRestore = false
        launcherViewModel.onCloseLauncher()
        logFocusState("closeLauncherForPaste.after")
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

    private func finishOpenLauncher(openAttempt: Int) {
        verifyLauncherPresentation(openAttempt: openAttempt, pass: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard self.launcherOpenAttempt == openAttempt else { return }
            NotificationCenter.default.post(name: NSNotification.Name("FocusLauncherSearch"), object: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard self.launcherOpenAttempt == openAttempt else { return }
            self.verifyLauncherPresentation(openAttempt: openAttempt, pass: 3)
            NotificationCenter.default.post(name: NSNotification.Name("FocusLauncherSearch"), object: nil)
            self.isOpeningLauncher = false
            self.pendingLauncherRestore = false
            self.logLauncherState("openLauncher.finish attempt=\(openAttempt)")
        }
    }

    private func bringLauncherToFront() {
        NSLog("=== bringLauncherToFront === isHidden:%@ isVisible:%@",
              NSApp.isHidden.description,
              launcherPanel.isVisible.description)
        logLauncherState("bringLauncherToFront.before")
        prepareLauncherPanelForPresentation()
        updateLauncherPanelFrame(keepingCenter: false)
        launcherPanel.center()
        launcherPanel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        launcherPanel.makeKeyAndOrderFront(nil)
        launcherPanel.orderFrontRegardless()
        NotificationCenter.default.post(name: NSNotification.Name("FocusLauncherSearch"), object: nil)
        logLauncherState("bringLauncherToFront.after")
    }

    private func prepareLauncherPanelForPresentation() {
        launcherPanel.hidesOnDeactivate = false
        launcherPanel.level = launcherPresentationLevel
        launcherPanel.collectionBehavior = launcherCollectionBehavior
    }

    private func resetLauncherPanelPresentation() {
        guard launcherPanel != nil else { return }
        launcherPanel.level = launcherRestingLevel
        launcherPanel.collectionBehavior = launcherCollectionBehavior
    }

    private func verifyLauncherPresentation(openAttempt: Int, pass: Int) {
        guard launcherOpenAttempt == openAttempt else { return }
        logLauncherState("launcherPresentation.verify attempt=\(openAttempt) pass=\(pass)")

        if !launcherPanel.isVisible {
            prepareLauncherPanelForPresentation()
            launcherPanel.orderFrontRegardless()
        }

        if !launcherPanel.isKeyWindow {
            NSApp.activate(ignoringOtherApps: true)
            launcherPanel.makeKeyAndOrderFront(nil)
            launcherPanel.orderFrontRegardless()
        }

        guard pass < 2, (!launcherPanel.isVisible || !launcherPanel.isKeyWindow) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            self.verifyLauncherPresentation(openAttempt: openAttempt, pass: pass + 1)
        }
    }

    private func restoreLauncherWindow() {
        bringLauncherToFront()
    }

    private func dismissLauncherBeforeOpeningSettings() {
        isOpeningLauncher = false
        pendingLauncherRestore = false

        guard launcherPanel != nil, launcherPanel.isVisible else { return }
        ignoreLauncherResignKeyUntil = Date().addingTimeInterval(0.5)
        launcherPanel.orderOut(nil)
        resetLauncherPanelPresentation()
        launcherViewModel.onCloseLauncher()
    }
    
    @objc func closeLauncher() {
        launcherPanel.orderOut(nil)
        resetLauncherPanelPresentation()
        AccessibilityManager.shared.restoreSuspendedTextInputFocus()
        
        // Check if there are other visible windows (like Settings)
        let otherVisibleWindows = NSApp.windows.filter { window in
            return window.isVisible && window != launcherPanel
        }
        
        if otherVisibleWindows.isEmpty {
            NSApp.hide(nil) // Return focus to previous app
        }
    }

    @objc func closeLauncherPanelOnly() {
        launcherPanel.orderOut(nil)
        resetLauncherPanelPresentation()
    }
    
    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == launcherPanel else {
            return
        }

        if isOpeningLauncher {
            logLauncherState("windowDidResignKey.ignored opening")
            return
        }

        if Date() < ignoreLauncherResignKeyUntil {
            logLauncherState("windowDidResignKey.ignored grace")
            return
        }

        logLauncherState("windowDidResignKey.close")
        closeLauncher()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window == launcherPanel {
            logLauncherState("windowDidBecomeKey")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("FocusLauncherSearch"), object: nil)
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        NSLog("=== applicationDidBecomeActive === pendingRestore:%@",
              pendingLauncherRestore.description)
        logLauncherState("applicationDidBecomeActive pendingRestore=\(pendingLauncherRestore)")
        reaffirmMenuBarItemIfNeeded(trigger: "appActive")
        if pendingLauncherRestore {
            restoreLauncherWindow()
        }
    }
}
