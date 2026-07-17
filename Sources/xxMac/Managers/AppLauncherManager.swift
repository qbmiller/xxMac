import Foundation
import AppKit
import HotKey

class AppLauncherManager: ObservableObject {
    static let shared = AppLauncherManager()
    
    @Published var shortcuts: [AppShortcut] = [] {
        didSet {
            saveShortcuts()
            refreshHotKeys()
        }
    }
    
    private var hotKeys: [UUID: HotKey] = [:]
    private var registeredShortcutIDs = Set<UUID>()
    private let userDefaultsKey = "AppLauncherShortcuts"
    private var lastOpenFallbackAtByBundleID: [String: Date] = [:]
    private let openFallbackCooldown: TimeInterval = 3
    
    private init() {
        loadShortcuts()
    }
    
    private func loadShortcuts() {
        if let data = PreferencesStore.shared.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([AppShortcut].self, from: data) {
            shortcuts = decoded
        }
        
        // Ensure Finder is present
        let finderPath = AppDefaultSettings.AppLauncher.finderPath
        if !shortcuts.contains(where: { $0.appPath == finderPath }) {
            let finderShortcut = AppShortcut(
                appName: "Finder",
                appPath: finderPath,
                key: AppDefaultSettings.AppLauncher.finderKey,
                modifiers: [],
                isEnabled: AppDefaultSettings.AppLauncher.finderEnabled
            )
            shortcuts.insert(finderShortcut, at: 0) // Add to top
        }
        
        refreshHotKeys()
    }
    
    private func saveShortcuts() {
        if let encoded = try? JSONEncoder().encode(shortcuts) {
            PreferencesStore.shared.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    func addShortcut(_ shortcut: AppShortcut) {
        shortcuts.append(shortcut)
    }
    
    func removeShortcut(id: UUID) {
        shortcuts.removeAll { $0.id == id }
    }
    
    @discardableResult
    func toggleShortcut(id: UUID) -> ShortcutConflict? {
        if let index = shortcuts.firstIndex(where: { $0.id == id }) {
            let shortcut = shortcuts[index]
            // We need to create a new struct with toggled enabled state since struct is immutable
            let newShortcut = AppShortcut(
                id: shortcut.id,
                appName: shortcut.appName,
                appPath: shortcut.appPath,
                key: shortcut.key,
                modifiers: shortcut.modifiers,
                isEnabled: !shortcut.isEnabled
            )
            if newShortcut.isEnabled, let conflict = conflict(for: newShortcut) {
                return conflict
            }
            shortcuts[index] = newShortcut
        }
        return nil
    }
    
    private func refreshHotKeys() {
        // Clear existing hotkeys
        hotKeys.values.forEach { $0.keyDownHandler = nil }
        hotKeys.removeAll()
        registeredShortcutIDs.forEach {
            ShortcutRegistryStore.shared.unregister(action: .appLauncher($0))
        }
        registeredShortcutIDs.removeAll()
        
        // Register new hotkeys
        for shortcut in shortcuts where shortcut.isEnabled {
            let configuration = HotKeyConfiguration(key: shortcut.key, modifiers: shortcut.modifiers)
            guard ShortcutRegistryStore.shared.register(
                action: .appLauncher(shortcut.id),
                trigger: .keyboard(configuration)
            ) == nil else {
                continue
            }
            let hotKey = HotKey(key: shortcut.key, modifiers: shortcut.modifiers)
            hotKey.keyDownHandler = { [weak self] in
                self?.launchOrActivateApp(path: shortcut.appPath)
            }
            hotKeys[shortcut.id] = hotKey
            registeredShortcutIDs.insert(shortcut.id)
        }
    }

    func conflict(for shortcut: AppShortcut) -> ShortcutConflict? {
        ShortcutRegistryStore.shared.conflict(
            for: .appLauncher(shortcut.id),
            trigger: .keyboard(HotKeyConfiguration(key: shortcut.key, modifiers: shortcut.modifiers))
        )
    }

    @discardableResult
    func updateShortcut(id: UUID, key: Key, modifiers: NSEvent.ModifierFlags) -> ShortcutConflict? {
        guard let index = shortcuts.firstIndex(where: { $0.id == id }) else { return nil }
        let current = shortcuts[index]
        let updated = AppShortcut(
            id: current.id,
            appName: current.appName,
            appPath: current.appPath,
            key: key,
            modifiers: modifiers,
            isEnabled: true
        )
        if let conflict = conflict(for: updated) { return conflict }
        shortcuts[index] = updated
        return nil
    }
    
    private func launchOrActivateApp(path: String) {
        let url = URL(fileURLWithPath: path)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        
        // Check if app is running
        let runningApps = NSWorkspace.shared.runningApplications
        if let app = runningApps.first(where: { $0.bundleURL?.path == path }) {
            // App is running
            if app.isActive {
                app.hide()
            } else {
                activateRunningApp(app, fallbackURL: url, config: config)
            }
        } else {
            // App is not running, launch it
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if let error = error {
                    print("Failed to launch app: \(error.localizedDescription)")
                }
            }
        }
    }

    // Reopen + activate covers:
    // 1) hidden apps
    // 2) apps with only miniaturized windows
    // 3) apps still running but all windows closed
    private func activateRunningApp(_ app: NSRunningApplication, fallbackURL: URL, config: NSWorkspace.OpenConfiguration) {
        if app.isHidden {
            app.unhide()
        }

        // First try native activation to switch Space and bring all windows.
        let activated = app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])

        // Then send "reopen" to recover closed/minimized-window scenarios for document apps.
        let reopenSucceeded = sendReopenAndActivateAppleScript(to: app)

        if !activated && !reopenSucceeded && shouldOpenApplicationFallback(for: app, fallbackURL: fallbackURL) {
            NSWorkspace.shared.openApplication(at: fallbackURL, configuration: config) { _, error in
                if let error = error {
                    print("Failed to activate app: \(error.localizedDescription)")
                }
            }
        }
    }

    private func shouldOpenApplicationFallback(for app: NSRunningApplication, fallbackURL: URL) -> Bool {
        guard app.isTerminated == false else { return false }
        guard fallbackURL.isFileURL, fallbackURL.pathExtension == "app" else { return false }
        guard FileManager.default.fileExists(atPath: fallbackURL.path) else { return false }
        guard let bundleID = app.bundleIdentifier else { return false }

        let now = Date()
        if let lastTime = lastOpenFallbackAtByBundleID[bundleID],
           now.timeIntervalSince(lastTime) < openFallbackCooldown {
            return false
        }

        lastOpenFallbackAtByBundleID[bundleID] = now
        return true
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
}
