import Foundation

enum TodoDeepLinkRoute: Equatable {
    case todo
}

enum TodoDeepLink {
    static func route(for url: URL) -> TodoDeepLinkRoute? {
        guard url.scheme?.lowercased() == "xxmac",
              url.host?.lowercased() == "todo",
              url.path.isEmpty,
              url.query == nil,
              url.fragment == nil,
              url.user == nil,
              url.password == nil,
              url.port == nil else {
            return nil
        }
        return .todo
    }
}
