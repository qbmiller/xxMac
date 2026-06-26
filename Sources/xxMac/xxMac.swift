import SwiftUI
import Combine

@main
struct xxMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
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

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem!
    var launcherPanel: NSPanel!
    var settingsWindow: NSWindow?
    var calendarMenuBarController: CalendarMenuBarController?
    var launcherViewModel = LauncherViewModel()
    var eventMonitor: Any?
    private var toggleLauncherMenuItem: NSMenuItem?
    private var lockAIMenuItem: NSMenuItem?
    private var settingsMenuItem: NSMenuItem?
    private var quitMenuItem: NSMenuItem?
    private var localizationCancellable: AnyCancellable?
    private var launcherPanelCancellables = Set<AnyCancellable>()
    private var isOpeningLauncher = false
    private var pendingLauncherRestore = false
    private var previousFrontmostApp: NSRunningApplication?
    private var lastOpenFallbackAtByBundleID: [String: Date] = [:]
    private let openFallbackCooldown: TimeInterval = 3

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
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize HotKeyManager
        _ = HotKeyManager.shared
        // Initialize AppLauncherManager
        _ = AppLauncherManager.shared
        // Initialize ClipboardManager
        _ = ClipboardManager.shared
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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        let menu = NSMenu()
        let toggleItem = NSMenuItem(title: L10n.t("menu.toggle_launcher"), action: #selector(toggleLauncher), keyEquivalent: " ")
        toggleItem.keyEquivalentModifierMask = [.control, .option]
        toggleLauncherMenuItem = toggleItem
        menu.addItem(toggleItem)
        let lockAIItem = NSMenuItem(title: L10n.t("menu.lock_ai"), action: #selector(lockAI), keyEquivalent: "l")
        lockAIItem.keyEquivalentModifierMask = [.control, .option, .command]
        lockAIMenuItem = lockAIItem
        menu.addItem(lockAIItem)
        let settingsItem = NSMenuItem(title: L10n.t("menu.settings"), action: #selector(openSettings), keyEquivalent: ",")
        settingsMenuItem = settingsItem
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: L10n.t("menu.quit"), action: #selector(confirmQuit), keyEquivalent: "q")
        quitItem.target = self
        quitMenuItem = quitItem
        menu.addItem(quitItem)
        calendarMenuBarController = CalendarMenuBarController(statusItem: statusItem, contextMenu: menu)
        updateMenuTitles()
        
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
        
        // 4. Observers
        NotificationCenter.default.addObserver(self, selector: #selector(toggleLauncher), name: NSNotification.Name("ToggleLauncher"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(closeLauncher), name: NSNotification.Name("CloseLauncher"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(closeLauncherPanelOnly), name: NSNotification.Name("CloseLauncherPanelOnly"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showClipboardHistory), name: NSNotification.Name("ShowClipboardHistory"), object: nil)

        localizationCancellable = LocalizationManager.shared.$language.sink { [weak self] _ in
            self?.updateMenuTitles()
        }
    }
    
    func createLauncherPanel() {
        let contentView = LauncherView(viewModel: launcherViewModel)
        
        launcherPanel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        launcherPanel.contentView = NSHostingView(rootView: contentView)
        launcherPanel.backgroundColor = .clear
        launcherPanel.isOpaque = false
        launcherPanel.hasShadow = true
        launcherPanel.level = .floating
        launcherPanel.center()
        launcherPanel.isMovableByWindowBackground = false
        launcherPanel.becomesKeyOnlyIfNeeded = false
        // .canJoinAllSpaces and .moveToActiveSpace are mutually exclusive for NSPanel.
        launcherPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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
            appearance.$sizeScale.map { _ in () }.eraseToAnyPublisher()
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
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = L10n.t("window.settings")
            window.contentView = NSHostingView(rootView: SettingsView())
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func lockAI() {
        LockAIManager.shared.lock()
    }

    @objc func confirmQuit() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.t("menu.quit_confirm_title")
        alert.informativeText = L10n.t("menu.quit_confirm_message")
        alert.addButton(withTitle: L10n.t("menu.quit"))
        alert.addButton(withTitle: L10n.t("general.cancel"))

        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    NSApp.terminate(nil)
                }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

    @MainActor
    @objc func openCalendar() {
        calendarMenuBarController?.showCalendarWindow()
    }

    @MainActor
    private func updateMenuTitles() {
        toggleLauncherMenuItem?.title = L10n.t("menu.toggle_launcher")
        lockAIMenuItem?.title = L10n.t("menu.lock_ai")
        settingsMenuItem?.title = L10n.t("menu.settings")
        quitMenuItem?.title = L10n.t("menu.quit")
        settingsWindow?.title = L10n.t("window.settings")
        calendarMenuBarController?.refreshStatusItem()
    }
    
    func openLauncher() {
        isOpeningLauncher = true
        pendingLauncherRestore = true
        capturePreviousFrontmostApp(force: false)
        logFocusState("openLauncher.begin")

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
                self.finishOpenLauncher()
            }
        } else if NSApp.isHidden {
            NSApp.unhide(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.bringLauncherToFront()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.bringLauncherToFront()
                self.finishOpenLauncher()
            }
        } else {
            bringLauncherToFront()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                self.bringLauncherToFront()
            }
            finishOpenLauncher()
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

    private func finishOpenLauncher() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: NSNotification.Name("FocusLauncherSearch"), object: nil)
            self.isOpeningLauncher = false
            self.pendingLauncherRestore = false
        }
    }

    private func bringLauncherToFront() {
        NSLog("=== bringLauncherToFront === isHidden:%@ isVisible:%@",
              NSApp.isHidden.description,
              launcherPanel.isVisible.description)
        NSApp.activate(ignoringOtherApps: true)
        updateLauncherPanelFrame(keepingCenter: false)
        launcherPanel.center()
        launcherPanel.makeKeyAndOrderFront(nil)
        launcherPanel.orderFrontRegardless()
    }

    private func restoreLauncherWindow() {
        bringLauncherToFront()
    }
    
    @objc func closeLauncher() {
        launcherPanel.orderOut(nil)
        
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
    }
    
    func windowDidResignKey(_ notification: Notification) {
        if isOpeningLauncher {
            return
        }

        if let window = notification.object as? NSWindow, window == launcherPanel {
            closeLauncher()
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window == launcherPanel {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("FocusLauncherSearch"), object: nil)
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        NSLog("=== applicationDidBecomeActive === pendingRestore:%@",
              pendingLauncherRestore.description)
        if pendingLauncherRestore {
            restoreLauncherWindow()
        }
    }
}
