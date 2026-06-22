import SwiftUI
import HotKey
import AppKit

// MARK: - HotKey Configuration

struct HotKeyConfiguration: Codable {
    let key: Key
    let modifiers: NSEvent.ModifierFlags
}

// Extend Key and ModifierFlags to be Codable
extension Key: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(UInt32.self)
        guard let key = Key(carbonKeyCode: rawValue) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid carbonKeyCode for Key")
        }
        self = key
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.carbonKeyCode)
    }
    
    var displayString: String {
        switch self {
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        case .upArrow: return "↑"
        case .downArrow: return "↓"
        case .space: return L10n.t("key.space")
        case .return: return "↵"
        case .escape: return "⎋"
        case .delete: return "⌫"
        default: return String(describing: self).uppercased()
        }
    }
}

extension NSEvent.ModifierFlags: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(UInt.self)
        self.init(rawValue: rawValue)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
    
    var displayString: String {
        var str = ""
        if contains(.control) { str += "⌃" }
        if contains(.option) { str += "⌥" }
        if contains(.shift) { str += "⇧" }
        if contains(.command) { str += "⌘" }
        return str
    }
}

// MARK: - Tool Types

enum ToolType: String, CaseIterable, Identifiable {
    case common = "tool.common"
    case search = "tool.search"
    case window = "tool.window"
    case shortcutDetective = "tool.shortcut_detective"
    case clipboard = "tool.clipboard"
    case launcher = "tool.launcher"
    case calendar = "tool.calendar"
    case lockAI = "tool.lock_ai"
    case about = "tool.about"
    
    var id: String { rawValue }

    var displayName: String { L10n.t(rawValue) }
    
    var icon: String {
        switch self {
        case .common: return "gearshape.2"
        case .search: return "magnifyingglass"
        case .window: return "macwindow"
        case .shortcutDetective: return "keyboard"
        case .clipboard: return "doc.on.clipboard"
        case .launcher: return "command"
        case .calendar: return "calendar"
        case .lockAI: return "lock.shield"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Function Types

enum FunctionType: String, CaseIterable, Identifiable {
    // Common
    case commonConfig = "function.configuration"
    case commonLanguage = "function.language"
    case launcherAppearance = "function.launcher.appearance"

    // Search
    case searchGeneral = "function.search.general"
    case searchPaths = "function.search.paths"
    case searchExcluded = "function.search.excluded"
    
    // Window Management
    case wmShortcuts = "function.window.shortcuts"
    case wmSnapZones = "function.window.snap_zones"
    case wmGeneral = "function.window.behavior"

    // Shortcut Detective
    case shortcutDetectiveGeneral = "function.shortcut.detective"
    
    // Clipboard
    case clipboardGeneral = "function.clipboard.general"
    case clipboardHistory = "function.clipboard.history"
    case clipboardIgnored = "function.clipboard.ignored"
    
    // App Launcher
    case launcherApps = "function.launcher.applications"

    // Calendar
    case calendarGeneral = "function.calendar.general"

    // LockJob
    case lockAIGeneral = "function.lock_ai.general"
    case lockAIScreen = "function.lock_ai.screen"
    
    // About
    case aboutInfo = "function.about.info"
    
    var id: String { rawValue }

    var displayName: String { L10n.t(rawValue) }
    
    var icon: String {
        switch self {
        case .commonConfig: return "slider.horizontal.3"
        case .commonLanguage: return "globe"
        case .launcherAppearance: return "paintpalette"
        case .searchPaths: return "folder"
        case .wmShortcuts: return "keyboard"
        case .shortcutDetectiveGeneral: return "eye"
        case .clipboardHistory: return "clock"
        case .launcherApps: return "command.square"
        case .calendarGeneral: return "calendar"
        case .lockAIGeneral: return "lock.shield"
        case .lockAIScreen: return "display"
        case .aboutInfo: return "info.circle"
        default: return "gear"
        }
    }
}

// MARK: - Data Models

struct ToolFunction: Identifiable, Hashable {
    let type: FunctionType
    
    var id: String { type.rawValue }
    var name: String { type.displayName }
    var icon: String { type.icon }
}

struct ToolOption: Identifiable, Hashable {
    let type: ToolType
    let functions: [ToolFunction]
    
    var id: String { type.rawValue }
    
    static let allTools: [ToolOption] = [
        ToolOption(type: .common, functions: [
            ToolFunction(type: .commonConfig),
            ToolFunction(type: .commonLanguage),
            ToolFunction(type: .launcherAppearance)
        ]),
        ToolOption(type: .search, functions: [
            ToolFunction(type: .searchGeneral),
            ToolFunction(type: .searchPaths),
            ToolFunction(type: .searchExcluded)
        ]),
        ToolOption(type: .window, functions: [
            ToolFunction(type: .wmShortcuts),
            ToolFunction(type: .wmSnapZones),
            ToolFunction(type: .wmGeneral)
        ]),
        ToolOption(type: .shortcutDetective, functions: [
            ToolFunction(type: .shortcutDetectiveGeneral)
        ]),
        ToolOption(type: .clipboard, functions: [
            ToolFunction(type: .clipboardGeneral),
            ToolFunction(type: .clipboardHistory),
            ToolFunction(type: .clipboardIgnored)
        ]),
        ToolOption(type: .launcher, functions: [
            ToolFunction(type: .launcherApps)
        ]),
        ToolOption(type: .calendar, functions: [
            ToolFunction(type: .calendarGeneral)
        ]),
        ToolOption(type: .lockAI, functions: [
            ToolFunction(type: .lockAIGeneral),
            ToolFunction(type: .lockAIScreen)
        ]),
        ToolOption(type: .about, functions: [
            ToolFunction(type: .aboutInfo)
        ])
    ]
}
