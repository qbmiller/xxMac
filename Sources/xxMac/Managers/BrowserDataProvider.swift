import Foundation

struct BrowserRecord: Equatable {
    let title: String
    let url: URL
    let lastVisitedAt: Date?
}

enum BrowserDataError: LocalizedError, Equatable {
    case profileUnavailable
    case bookmarksUnavailable
    case historyUnavailable
    case invalidBookmarks
    case historyQueryFailed

    var errorDescription: String? {
        switch self {
        case .profileUnavailable: return "Browser profile is unavailable."
        case .bookmarksUnavailable: return "Browser bookmarks are unavailable."
        case .historyUnavailable: return "Browser history is unavailable."
        case .invalidBookmarks: return "Browser bookmarks could not be read."
        case .historyQueryFailed: return "Browser history could not be searched."
        }
    }
}

protocol BrowserDataProvider {
    var browser: BrowserKind { get }
    func currentProfileDirectory() -> URL
    func searchBookmarks(query: String, limit: Int) throws -> [BrowserRecord]
    func searchHistory(query: String, limit: Int) throws -> [BrowserRecord]
}
