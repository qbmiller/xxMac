import Foundation

enum BrowserKind: String, Codable, CaseIterable, Identifiable {
    case chrome
    case edge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chrome: return "Google Chrome"
        case .edge: return "Microsoft Edge"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .chrome: return "com.google.Chrome"
        case .edge: return "com.microsoft.edgemac"
        }
    }

    var applicationName: String {
        switch self {
        case .chrome: return "Google Chrome.app"
        case .edge: return "Microsoft Edge.app"
        }
    }

    var userDataDirectoryName: String {
        switch self {
        case .chrome: return "Google/Chrome"
        case .edge: return "Microsoft Edge"
        }
    }
}

struct BrowserSearchPreferences: Equatable {
    var isEnabled: Bool
    var browser: BrowserKind
    var bookmarkKeyword: String
    var historyKeyword: String
}

enum BrowserSearchMode: Equatable {
    case bookmarks
    case history
}

struct BrowserSearchRequest: Equatable {
    let mode: BrowserSearchMode
    let query: String
}
