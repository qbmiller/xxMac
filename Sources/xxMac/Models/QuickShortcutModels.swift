import Foundation

enum QuickShortcutActionType: String, Codable, CaseIterable, Identifiable {
    case webSearch
    case commandScript

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .webSearch:
            return L10n.t("quick_shortcut.type_web_search")
        case .commandScript:
            return L10n.t("quick_shortcut.type_command_script")
        }
    }

    var iconName: String {
        switch self {
        case .webSearch:
            return "safari"
        case .commandScript:
            return "terminal"
        }
    }
}

enum QuickShortcutCommandInputMode: String, Codable, CaseIterable, Identifiable {
    case noInput
    case queryPlaceholder
    case argv

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .noInput:
            return L10n.t("quick_shortcut.input_mode_none")
        case .queryPlaceholder:
            return L10n.t("quick_shortcut.input_mode_query")
        case .argv:
            return L10n.t("quick_shortcut.input_mode_argv")
        }
    }

    var requiresInput: Bool {
        switch self {
        case .noInput:
            return false
        case .queryPlaceholder, .argv:
            return true
        }
    }
}

struct QuickShortcut: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String
    var keyword: String
    var actionType: QuickShortcutActionType
    var payload: String
    var shellPath: String
    var commandInputMode: QuickShortcutCommandInputMode
    var previewQuery: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        title: String,
        keyword: String,
        actionType: QuickShortcutActionType,
        payload: String,
        shellPath: String = "/bin/zsh",
        commandInputMode: QuickShortcutCommandInputMode = .queryPlaceholder,
        previewQuery: String = "",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.keyword = keyword
        self.actionType = actionType
        self.payload = payload
        self.shellPath = shellPath
        self.commandInputMode = commandInputMode
        self.previewQuery = previewQuery
        self.isEnabled = isEnabled
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case keyword
        case actionType
        case payload
        case shellPath
        case commandInputMode
        case previewQuery
        case isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        keyword = try container.decode(String.self, forKey: .keyword)
        actionType = try container.decode(QuickShortcutActionType.self, forKey: .actionType)
        payload = try container.decode(String.self, forKey: .payload)
        shellPath = try container.decodeIfPresent(String.self, forKey: .shellPath) ?? "/bin/zsh"
        commandInputMode = try container.decodeIfPresent(QuickShortcutCommandInputMode.self, forKey: .commandInputMode) ?? .queryPlaceholder
        previewQuery = try container.decodeIfPresent(String.self, forKey: .previewQuery) ?? ""
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
    }
}
