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
    case lockAI = "LockAI"

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
        case .lockAI: return L10n.t("window_action.lock_ai")
        }
    }
}

class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()
    
    private var hotKeys: [WindowAction: HotKey] = [:]
    
    @Published var configurations: [WindowAction: HotKeyConfiguration] = [:]
    
    var isPaused = false {
        didSet {
            if isPaused {
                hotKeys.values.forEach { $0.isPaused = true }
            } else {
                hotKeys.values.forEach { $0.isPaused = false }
            }
        }
    }
    
    private init() {
        loadConfigurations()
    }
    
    
    func loadConfigurations() {
        // Load from UserDefaults or use defaults
        if let data = UserDefaults.standard.data(forKey: "HotKeyConfigurations"),
           let decoded = try? JSONDecoder().decode([WindowAction: HotKeyConfiguration].self, from: data) {
            configurations = decoded
        } else {
            setupDefaultConfigurations()
        }
        refreshHotKeys()
    }
    
    func saveConfigurations() {
        if let encoded = try? JSONEncoder().encode(configurations) {
            UserDefaults.standard.set(encoded, forKey: "HotKeyConfigurations")
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
            .lockAI: HotKeyConfiguration(key: .l, modifiers: defaultModifiers)
        ]
        
        // Adjust for non-keypad numbers if needed, but ShiftIt screenshot shows ^⌥⌘1 etc.
        configurations[.topLeft] = HotKeyConfiguration(key: .one, modifiers: defaultModifiers)
        configurations[.topRight] = HotKeyConfiguration(key: .two, modifiers: defaultModifiers)
        configurations[.bottomLeft] = HotKeyConfiguration(key: .three, modifiers: defaultModifiers)
        configurations[.bottomRight] = HotKeyConfiguration(key: .four, modifiers: defaultModifiers)
    }
    
    func refreshHotKeys() {
        hotKeys.values.forEach { $0.keyDownHandler = nil }
        hotKeys.removeAll()
        
        for (action, config) in configurations {
            let hotKey = HotKey(key: config.key, modifiers: config.modifiers)
            hotKey.isPaused = isPaused
            hotKey.keyDownHandler = { [weak self] in
                self?.performAction(action)
            }
            hotKeys[action] = hotKey
        }
    }
    
    func updateConfiguration(for action: WindowAction, key: Key, modifiers: NSEvent.ModifierFlags) {
        configurations[action] = HotKeyConfiguration(key: key, modifiers: modifiers)
        saveConfigurations()
        refreshHotKeys()
    }
    
    func removeConfiguration(for action: WindowAction) {
        configurations.removeValue(forKey: action)
        saveConfigurations()
        refreshHotKeys()
    }
    
    private func performAction(_ action: WindowAction) {
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
                // 1. Unhide and Activate
                if NSApp.isHidden {
                    NSApp.unhide(nil)
                }
                NSApp.activate(ignoringOtherApps: true)
                
                // 2. Just post the notification and let the handler deal with window states
                // Small delay to ensure activation is processed by the system
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NotificationCenter.default.post(name: NSNotification.Name("ToggleLauncher"), object: nil)
                }
            }
        case .lockAI:
            DispatchQueue.main.async {
                LockAIManager.shared.lock()
            }
        }
    }
}
