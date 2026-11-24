import Foundation

struct InputSourceDescriptor: Identifiable, Equatable {
    let sourceID: String
    var modeID: String? = nil
    let name: String
    var id: String { modeID.map { sourceID + "::" + $0 } ?? sourceID }
}

enum InputSourceAppPolicy: String, Codable, CaseIterable {
    case fixed, remember, keepCurrent
    var title: String { L10n.t("input.policy." + rawValue) }
}

struct InputSourceAppRule: Codable, Equatable, Identifiable {
    var id = UUID()
    var bundleID: String
    var name: String
    var policy: InputSourceAppPolicy = .fixed
    var sourceID = ""
    var enabled = true
}

enum InputSourceWebsiteMatch: String, Codable, CaseIterable {
    case domain, domainAndSubdomains, urlPrefix
    var title: String { L10n.t("input.match." + rawValue) }
}

struct InputSourceWebsiteRule: Codable, Equatable, Identifiable {
    var id = UUID()
    var pattern: String
    var match: InputSourceWebsiteMatch = .domainAndSubdomains
    var sourceID: String
    var browserID = ""
    var enabled = true

    var isValid: Bool {
        if match == .urlPrefix { return Self.webURL(pattern.trimmingCharacters(in: .whitespacesAndNewlines)) != nil }
        let domain = Self.normalizedDomain(pattern)
        guard !domain.isEmpty, !domain.contains(where: { $0.isWhitespace }),
              !domain.contains("/"), !domain.contains(":"), !domain.contains("@"),
              let url = URL(string: "https://" + domain), url.host != nil else { return false }
        return true
    }

    func matches(_ url: URL) -> Bool {
        guard isValid, let host = url.host?.lowercased(), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return false }
        let value = Self.normalizedDomain(pattern)
        switch match {
        case .domain: return Self.normalizedDomain(host) == value
        case .domainAndSubdomains: return Self.normalizedDomain(host) == value || host.hasSuffix("." + value)
        case .urlPrefix:
            guard let prefix = Self.webURL(pattern.trimmingCharacters(in: .whitespacesAndNewlines)),
                  prefix.scheme?.lowercased() == url.scheme?.lowercased(),
                  prefix.host?.lowercased() == host,
                  Self.effectivePort(prefix) == Self.effectivePort(url),
                  prefix.user == nil, prefix.password == nil else { return false }
            let path = prefix.path
            guard path.isEmpty || path == "/" || url.path == path || url.path.hasPrefix(path.hasSuffix("/") ? path : path + "/") else { return false }
            if let query = prefix.query, !(url.query ?? "").hasPrefix(query) { return false }
            return true
        }
    }

    private static func effectivePort(_ url: URL) -> Int { url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80) }
    private static func normalizedDomain(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
    }
    private static func webURL(_ text: String) -> URL? {
        guard let url = URL(string: text), let host = url.host, !host.isEmpty,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.user == nil, url.password == nil else { return nil }
        return url
    }
}

struct InputSourceShortcut: Codable, Identifiable {
    var id = UUID()
    var sourceIDs: [String] = []
    var configuration: HotKeyConfiguration?
}

extension InputSourceShortcut: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.sourceIDs == rhs.sourceIDs &&
        lhs.configuration?.key == rhs.configuration?.key && lhs.configuration?.modifiers == rhs.configuration?.modifiers
    }
}

enum InputSourceIndicatorPosition: String, Codable, CaseIterable {
    case pointer, screenBottom
    var title: String { L10n.t("input.position." + rawValue) }
}

struct InputSourceSettings: Codable, Equatable {
    var enabled = AppDefaultSettings.InputSource.automaticSwitching
    var defaultSourceID = ""
    var addressBarSourceID = ""
    var appRules: [InputSourceAppRule] = []
    var websiteRules: [InputSourceWebsiteRule] = []
    var shortcuts: [InputSourceShortcut] = []
    var showOnChange = AppDefaultSettings.InputSource.showOnChange
    var showOnAppSwitch = AppDefaultSettings.InputSource.showOnAppSwitch
    var showOnLongPress = AppDefaultSettings.InputSource.showOnLongPress
    var indicatorPosition: InputSourceIndicatorPosition = .pointer
    var indicatorDuration: Double = 0.9
    var indicatorFontSize: Double = 18
    var indicatorColor = "#2563EB"
    var indicatorAbbreviated = false
}

struct InputSourceContext: Equatable {
    var bundleID: String
    var url: URL? = nil
    var addressBarFocused = false
}

struct InputSourceDecision: Equatable {
    var sourceID: String?
    var reason: String
}

enum InputSourcePolicy {
    static let browsers: [String: String] = ["com.google.Chrome": "Chrome", "com.microsoft.edgemac": "Edge", "com.apple.Safari": "Safari"]

    static func resolve(settings: InputSourceSettings, context: InputSourceContext, memory: [String: String]) -> InputSourceDecision {
        guard settings.enabled else { return .init(reason: "input.status.disabled") }
        if browsers[context.bundleID] != nil {
            if context.addressBarFocused, !settings.addressBarSourceID.isEmpty {
                return .init(sourceID: settings.addressBarSourceID, reason: "input.status.address")
            }
            if let url = context.url, let rule = settings.websiteRules.first(where: {
                $0.enabled && ($0.browserID.isEmpty || $0.browserID == context.bundleID) && $0.matches(url)
            }) { return .init(sourceID: rule.sourceID, reason: "input.status.website") }
        }
        if let rule = settings.appRules.first(where: { $0.enabled && $0.bundleID == context.bundleID }) {
            switch rule.policy {
            case .fixed: return .init(sourceID: rule.sourceID, reason: "input.status.app")
            case .remember: return .init(sourceID: memory[context.bundleID], reason: "input.status.memory")
            case .keepCurrent: return .init(reason: "input.status.keep")
            }
        }
        return .init(sourceID: settings.defaultSourceID.isEmpty ? nil : settings.defaultSourceID, reason: "input.status.default")
    }
}

/// Tracks automatic selections across rapid context changes, including delayed TIS notifications.
struct InputSourceSelectionState {
    private var automaticTargets: [String: TimeInterval] = [:]

    mutating func beginAutomaticSelection(target: String, now: TimeInterval) {
        automaticTargets = automaticTargets.filter { $0.value > now }
        automaticTargets[target] = now + 1.5
    }

    mutating func shouldRemember(sourceID: String, now: TimeInterval) -> Bool {
        automaticTargets = automaticTargets.filter { $0.value > now }
        return automaticTargets.removeValue(forKey: sourceID) == nil
    }

    mutating func userSelected(_ sourceID: String) {
        automaticTargets.removeValue(forKey: sourceID)
    }
}

/// A new focus event supersedes any browser read already running on the serial queue.
struct InputSourceBrowserRequestState {
    private var revision = 0
    private var inFlight = false

    mutating func begin(invalidateCurrent: Bool) -> Int? {
        if invalidateCurrent { revision += 1 }
        guard !inFlight else { return nil }
        inFlight = true
        return revision
    }

    mutating func finish(_ token: Int) -> Bool {
        inFlight = false
        return token == revision
    }
}

/// An app-switch hint waits for both rule resolution and the selected system source.
struct InputSourceAppIndicatorRequest {
    private var requested = false
    private var resolved = false
    private var target: String?

    mutating func request() {
        requested = true
        resolved = false
        target = nil
    }

    mutating func resolve(target: String?) {
        self.target = target
        resolved = true
    }

    mutating func takeIfReady(currentSourceID: String) -> Bool {
        guard requested, resolved, target == nil || target == currentSourceID else { return false }
        requested = false
        return true
    }
}
