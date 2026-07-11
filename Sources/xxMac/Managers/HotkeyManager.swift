import Foundation
import HotKey
import AppKit

enum WindowAction: String, CaseIterable, Codable {
    case left = "Left"
    case right = "Right"
    case top = "Top"
    case bottom = "Bottom"
    case topLeft = "Top Left"
    case topRight = "Top Right"
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"
    case center = "Center"
    case toggleZoom = "Toggle Zoom"
    case maximize = "Maximize"
    case toggleFullscreen = "Toggle Full Screen"
    case increase = "Increase"
    case reduce = "Reduce"
    case nextScreen = "Next Screen"
    case previousScreen = "Previous Screen"
    case toggleLauncher = "Toggle Launcher"
    case pasteFinderPath = "Paste Finder Path"
    case lockAI = "LockAI"

    static let windowManagementCases: [WindowAction] = [
        .left,
        .right,
        .top,
        .bottom,
        .topLeft,
        .topRight,
        .bottomLeft,
        .bottomRight,
        .center,
        .toggleZoom,
        .maximize,
        .toggleFullscreen,
        .increase,
        .reduce,
        .nextScreen,
        .previousScreen
    ]

    static let commonShortcutCases: [WindowAction] = [
        .toggleLauncher,
        .pasteFinderPath
    ]

    var displayName: String {
        switch self {
        case .left: return L10n.t("window_action.left")
        case .right: return L10n.t("window_action.right")
        case .top: return L10n.t("window_action.top")
        case .bottom: return L10n.t("window_action.bottom")
        case .topLeft: return L10n.t("window_action.top_left")
        case .topRight: return L10n.t("window_action.top_right")
        case .bottomLeft: return L10n.t("window_action.bottom_left")
        case .bottomRight: return L10n.t("window_action.bottom_right")
        case .center: return L10n.t("window_action.center")
        case .toggleZoom: return L10n.t("window_action.toggle_zoom")
        case .maximize: return L10n.t("window_action.maximize")
        case .toggleFullscreen: return L10n.t("window_action.toggle_fullscreen")
        case .increase: return L10n.t("window_action.increase")
        case .reduce: return L10n.t("window_action.reduce")
        case .nextScreen: return L10n.t("window_action.next_screen")
        case .previousScreen: return L10n.t("window_action.previous_screen")
        case .toggleLauncher: return L10n.t("window_action.toggle_launcher")
        case .pasteFinderPath: return L10n.t("window_action.paste_finder_path")
        case .lockAI: return L10n.t("window_action.lock_ai")
        }
    }
}

class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()
    static let configurationsDidChangeNotification = Notification.Name("HotKeyConfigurationsDidChange")
    private static let clearedActionsKey = "ClearedHotKeyActions"
    
    private var hotKeys: [WindowAction: CarbonHotKeyRegistration] = [:]
    private var pauseTokens = Set<UUID>()
    
    @Published var configurations: [WindowAction: HotKeyConfiguration] = [:]
    
    private(set) var isPaused = false
    
    private init() {
        loadConfigurations()
    }
    
    
    func loadConfigurations() {
        if let data = PreferencesStore.shared.data(forKey: "HotKeyConfigurations"),
           let decoded = try? JSONDecoder().decode([WindowAction: HotKeyConfiguration].self, from: data) {
            configurations = decoded
            ensureDefaultConfiguration(for: .lockAI)
            ensureDefaultConfiguration(for: .pasteFinderPath)
        } else {
            setupDefaultConfigurations()
        }
        refreshHotKeys()
    }
    
    func saveConfigurations(notify: Bool = true) {
        if let encoded = try? JSONEncoder().encode(configurations) {
            PreferencesStore.shared.set(encoded, forKey: "HotKeyConfigurations")
        }
        if notify {
            NotificationCenter.default.post(name: Self.configurationsDidChangeNotification, object: self)
        }
    }
    
    func setupDefaultConfigurations() {
        let defaultModifiers: NSEvent.ModifierFlags = [.control, .option, .command]
        
        configurations = [
            .left: HotKeyConfiguration(key: .leftArrow, modifiers: defaultModifiers),
            .right: HotKeyConfiguration(key: .rightArrow, modifiers: defaultModifiers),
            .top: HotKeyConfiguration(key: .upArrow, modifiers: defaultModifiers),
            .bottom: HotKeyConfiguration(key: .downArrow, modifiers: defaultModifiers),
            .topLeft: HotKeyConfiguration(key: .keypad1, modifiers: defaultModifiers), // ShiftIt uses 1, 2, 3, 4 for corners usually or similar
            .topRight: HotKeyConfiguration(key: .keypad2, modifiers: defaultModifiers),
            .bottomLeft: HotKeyConfiguration(key: .keypad3, modifiers: defaultModifiers),
            .bottomRight: HotKeyConfiguration(key: .keypad4, modifiers: defaultModifiers),
            .center: HotKeyConfiguration(key: .c, modifiers: defaultModifiers),
            .toggleZoom: HotKeyConfiguration(key: .z, modifiers: defaultModifiers),
            .maximize: HotKeyConfiguration(key: .m, modifiers: defaultModifiers),
            .toggleFullscreen: HotKeyConfiguration(key: .f, modifiers: defaultModifiers),
            .increase: HotKeyConfiguration(key: .equal, modifiers: defaultModifiers),
            .reduce: HotKeyConfiguration(key: .minus, modifiers: defaultModifiers),
            .nextScreen: HotKeyConfiguration(key: .n, modifiers: defaultModifiers),
            .previousScreen: HotKeyConfiguration(key: .p, modifiers: defaultModifiers),
            .toggleLauncher: HotKeyConfiguration(key: .space, modifiers: [.control, .option]),
            .pasteFinderPath: HotKeyConfiguration(key: .v, modifiers: [.command, .shift]),
            .lockAI: HotKeyConfiguration(key: .l, modifiers: defaultModifiers)
        ]
        
        // Adjust for non-keypad numbers if needed, but ShiftIt screenshot shows ^⌥⌘1 etc.
        configurations[.topLeft] = HotKeyConfiguration(key: .one, modifiers: defaultModifiers)
        configurations[.topRight] = HotKeyConfiguration(key: .two, modifiers: defaultModifiers)
        configurations[.bottomLeft] = HotKeyConfiguration(key: .three, modifiers: defaultModifiers)
        configurations[.bottomRight] = HotKeyConfiguration(key: .four, modifiers: defaultModifiers)
        PreferencesStore.shared.removeObject(forKey: Self.clearedActionsKey)
    }

    private func defaultConfiguration(for action: WindowAction) -> HotKeyConfiguration? {
        let defaultModifiers: NSEvent.ModifierFlags = [.control, .option, .command]

        switch action {
        case .toggleLauncher:
            return HotKeyConfiguration(key: .space, modifiers: [.control, .option])
        case .lockAI:
            return HotKeyConfiguration(key: .l, modifiers: defaultModifiers)
        case .pasteFinderPath:
            return HotKeyConfiguration(key: .v, modifiers: [.command, .shift])
        default:
            return nil
        }
    }

    func defaultConfigurationForUserReset(_ action: WindowAction) -> HotKeyConfiguration? {
        defaultConfiguration(for: action)
    }

    private func ensureDefaultConfiguration(for action: WindowAction) {
        guard configurations[action] == nil,
              !clearedActions().contains(action.rawValue),
              let defaultConfiguration = defaultConfiguration(for: action) else {
            return
        }

        configurations[action] = defaultConfiguration
        saveConfigurations(notify: false)
    }
    
    func refreshHotKeys() {
        hotKeys.removeAll()

        WindowAction.allCases.forEach { ShortcutRegistryStore.shared.unregister(action: .window($0)) }
        for action in WindowAction.allCases {
            guard let config = configurations[action] else { continue }
            guard ShortcutRegistryStore.shared.register(
                action: .window(action),
                trigger: .keyboard(config)
            ) == nil else {
                continue
            }
            guard let hotKey = CarbonHotKeyRegistration(configuration: config, name: "window.\(action.rawValue)", handler: { [weak self] in
                self?.performAction(action)
            }) else {
                continue
            }
            hotKeys[action] = hotKey
        }
        NSLog("[HotKeyManager] refreshed %d hotkeys, paused=%@", hotKeys.count, isPaused.description)
    }

    func pauseHotKeys() -> UUID {
        let token = UUID()
        pauseTokens.insert(token)
        updatePausedState()
        return token
    }

    func resumeHotKeys(_ token: UUID?) {
        guard let token else { return }
        pauseTokens.remove(token)
        updatePausedState()
    }

    private func updatePausedState() {
        let shouldPause = !pauseTokens.isEmpty
        guard shouldPause != isPaused else { return }

        isPaused = shouldPause
        NSLog("[HotKeyManager] hotkeys paused=%@ activePauseTokens=%d", shouldPause.description, pauseTokens.count)
    }
    
    @discardableResult
    func updateConfiguration(for action: WindowAction, key: Key, modifiers: NSEvent.ModifierFlags) -> ShortcutConflict? {
        let configuration = HotKeyConfiguration(key: key, modifiers: modifiers)
        if let conflict = ShortcutRegistryStore.shared.conflict(
            for: .window(action),
            trigger: .keyboard(configuration)
        ) {
            return conflict
        }
        configurations[action] = configuration
        unmarkCleared(action)
        saveConfigurations()
        refreshHotKeys()
        return nil
    }
    
    func removeConfiguration(for action: WindowAction) {
        configurations.removeValue(forKey: action)
        ShortcutRegistryStore.shared.unregister(action: .window(action))
        markCleared(action)
        saveConfigurations()
        refreshHotKeys()
    }

    private func clearedActions() -> Set<String> {
        Set(PreferencesStore.shared.stringArray(forKey: Self.clearedActionsKey) ?? [])
    }

    private func markCleared(_ action: WindowAction) {
        var actions = clearedActions()
        actions.insert(action.rawValue)
        PreferencesStore.shared.set(Array(actions), forKey: Self.clearedActionsKey)
    }

    private func unmarkCleared(_ action: WindowAction) {
        var actions = clearedActions()
        guard actions.remove(action.rawValue) != nil else { return }
        PreferencesStore.shared.set(Array(actions), forKey: Self.clearedActionsKey)
    }
    
    private func performAction(_ action: WindowAction) {
        guard !isPaused else { return }

        let hotkeyDisplay = configurations[action].map {
            $0.modifiers.displayString + $0.key.displayString
        } ?? L10n.t("general.unknown")
        ShortcutDetectiveManager.shared.recordHotkeyReception(for: action, hotkeyDisplay: hotkeyDisplay)

        let am = AccessibilityManager.shared
        switch action {
        case .left: am.leftHalf()
        case .right: am.rightHalf()
        case .top: am.topHalf()
        case .bottom: am.bottomHalf()
        case .topLeft: am.topLeft()
        case .topRight: am.topRight()
        case .bottomLeft: am.bottomLeft()
        case .bottomRight: am.bottomRight()
        case .center: am.center()
        case .toggleZoom: am.toggleZoom()
        case .maximize: am.maximize()
        case .toggleFullscreen: am.toggleFullscreen()
        case .increase: am.increase()
        case .reduce: am.reduce()
        case .nextScreen: am.nextScreen()
        case .previousScreen: am.previousScreen()
        case .toggleLauncher:
            DispatchQueue.main.async {
                if NSApp.isHidden {
                    NSApp.unhide(nil)
                }
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: NSNotification.Name("ToggleLauncher"), object: nil)
            }
        case .pasteFinderPath:
            DispatchQueue.main.async {
                FilePathPasteManager.shared.pasteFinderPaths()
            }
        case .lockAI:
            DispatchQueue.main.async {
                LockAIManager.shared.lock()
            }
        }
    }
}
