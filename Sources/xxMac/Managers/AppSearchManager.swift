import AppKit
import Combine
import OSLog

class AppSearchManager: ObservableObject {
    static let shared = AppSearchManager()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "xxMac", category: "AppSearch")

    @Published var apps: [SearchItem] = []
    @Published var isIndexing = false
    @Published var searchPaths: [String] = [] {
        didSet {
            saveSearchPaths()
            scanApplications()
        }
    }

    private let requiredSystemPaths = ["/Applications", "/System/Applications", "/System/Library/CoreServices"]
    private let userDefaultsKey = "AppSearchPaths"
    private let cacheDefaultsKey = "AppSearchIndexCacheV1"
    private var appEntries: [AppEntry] = []

    private struct AppEntry {
        let id: String
        let title: String
        let subtitle: String
        let path: String
        let nameSearchKeys: [String]
        let nameCompactSearchKeys: [String]
        let pathSearchKey: String
        let pathCompactSearchKey: String
    }

    private struct CachedEntry: Codable {
        let id: String
        let title: String
        let subtitle: String
        let path: String
        let nameKeys: [String]
    }

    private init() {
        loadSearchPaths()
        loadCachedIndex()
        scanApplications()
    }

    private func loadSearchPaths() {
        if let savedPaths = UserDefaults.standard.stringArray(forKey: userDefaultsKey) {
            searchPaths = ensureRequiredSearchPaths(in: savedPaths)
        } else {
            searchPaths = requiredSystemPaths
        }
    }

    private func saveSearchPaths() {
        UserDefaults.standard.set(searchPaths, forKey: userDefaultsKey)
    }

    private func loadCachedIndex() {
        guard
            let data = UserDefaults.standard.data(forKey: cacheDefaultsKey),
            let cached = try? JSONDecoder().decode([CachedEntry].self, from: data)
        else {
            return
        }

        let entries = cached.map(makeEntry(fromCached:))
        appEntries = entries
        apps = entries.map(makeSearchItem)
        Self.logger.debug("cache loaded=\(entries.count)")
    }

    private func saveCachedIndex(_ entries: [AppEntry]) {
        let cached = entries.map {
            CachedEntry(id: $0.id, title: $0.title, subtitle: $0.subtitle, path: $0.path, nameKeys: [$0.title])
        }
        guard let data = try? JSONEncoder().encode(cached) else { return }
        UserDefaults.standard.set(data, forKey: cacheDefaultsKey)
    }

    func addPath(_ path: String) {
        if !searchPaths.contains(path) {
            searchPaths.append(path)
        }
    }

    func removePath(_ path: String) {
        searchPaths.removeAll { $0 == path }
    }

    func resetPaths() {
        searchPaths = requiredSystemPaths
    }

    private func ensureRequiredSearchPaths(in paths: [String]) -> [String] {
        var merged = paths
        for requiredPath in requiredSystemPaths where !merged.contains(requiredPath) {
            merged.append(requiredPath)
        }
        return merged
    }

    private func prioritizedPaths(_ paths: [String]) -> [String] {
        let head = paths.filter { $0 == "/Applications" }
        let tail = paths.filter { $0 != "/Applications" }
        return head + tail
    }

    private func makeEntry(fromPath path: String, fileManager: FileManager) -> AppEntry {
        let url = URL(fileURLWithPath: path)
        let fileName = url.deletingPathExtension().lastPathComponent
        let localizedName = fileManager.displayName(atPath: path)

        var nameKeys: Set<String> = [localizedName, fileName]
        if let bundle = Bundle(url: url) {
            if let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, !bundleName.isEmpty {
                nameKeys.insert(bundleName)
            }
            if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !displayName.isEmpty {
                nameKeys.insert(displayName)
            }
        }

        return AppEntry(
            id: "app:\(path)",
            title: localizedName,
            subtitle: path,
            path: path,
            nameSearchKeys: nameKeys.map(Self.normalize),
            nameCompactSearchKeys: nameKeys.map(Self.normalizeCompact),
            pathSearchKey: Self.normalize(path),
            pathCompactSearchKey: Self.normalizeCompact(path)
        )
    }

    private func makeEntry(fromCached entry: CachedEntry) -> AppEntry {
        let keys = Set(entry.nameKeys + [entry.title])
        return AppEntry(
            id: entry.id,
            title: entry.title,
            subtitle: entry.subtitle,
            path: entry.path,
            nameSearchKeys: keys.map(Self.normalize),
            nameCompactSearchKeys: keys.map(Self.normalizeCompact),
            pathSearchKey: Self.normalize(entry.path),
            pathCompactSearchKey: Self.normalizeCompact(entry.path)
        )
    }

    private func makeSearchItem(from entry: AppEntry) -> SearchItem {
        SearchItem(
            id: entry.id,
            title: entry.title,
            subtitle: entry.subtitle,
            iconName: "app.fill",
            type: .app,
            action: {}
        )
    }

    func scanApplications() {
        let pathsToScan = prioritizedPaths(searchPaths)
        isIndexing = true

        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            var foundByPath: [String: AppEntry] = [:]

            for rootPath in pathsToScan {
                guard let subpaths = try? fileManager.subpathsOfDirectory(atPath: rootPath) else {
                    Self.logger.debug("scan skip root='\(rootPath, privacy: .public)' reason='unreadable'")
                    continue
                }

                for subpath in subpaths where subpath.hasSuffix(".app") && !subpath.contains(".app/") {
                    let fullPath = (rootPath as NSString).appendingPathComponent(subpath)
                    foundByPath[fullPath] = self.makeEntry(fromPath: fullPath, fileManager: fileManager)
                }
            }

            let sortedEntries = foundByPath.values.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }

            DispatchQueue.main.async {
                self.appEntries = sortedEntries
                self.apps = sortedEntries.map(self.makeSearchItem)
                self.saveCachedIndex(sortedEntries)
                self.isIndexing = false
                Self.logger.debug("scan roots='\(pathsToScan.joined(separator: ","), privacy: .public)' indexed=\(sortedEntries.count)")
            }
        }
    }

    func search(query: String) -> [SearchItem] {
        let normalizedQuery = Self.normalize(query)
        let compactQuery = Self.normalizeCompact(query)
        let shouldMatchPath = query.contains("/")

        if normalizedQuery.isEmpty {
            return []
        }

        let matched = appEntries.compactMap { entry -> (entry: AppEntry, rank: Int)? in
            var bestRank: Int?

            if !compactQuery.isEmpty {
                for key in entry.nameCompactSearchKeys {
                    if key.hasPrefix(compactQuery) {
                        bestRank = min(bestRank ?? 0, 0)
                    } else if key.contains(compactQuery) {
                        bestRank = min(bestRank ?? 1, 1)
                    }
                }
            }

            for key in entry.nameSearchKeys {
                if key.hasPrefix(normalizedQuery) {
                    bestRank = min(bestRank ?? 0, 0)
                } else if key.contains(normalizedQuery) {
                    bestRank = min(bestRank ?? 1, 1)
                }
            }

            if shouldMatchPath {
                if entry.pathCompactSearchKey.hasPrefix(compactQuery) || entry.pathSearchKey.hasPrefix(normalizedQuery) {
                    bestRank = min(bestRank ?? 2, 2)
                } else if entry.pathCompactSearchKey.contains(compactQuery) || entry.pathSearchKey.contains(normalizedQuery) {
                    bestRank = min(bestRank ?? 3, 3)
                }
            }

            guard let rank = bestRank else { return nil }
            return (entry, rank)
        }.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return lhs.entry.title.localizedStandardCompare(rhs.entry.title) == .orderedAscending
        }

        let results = matched.map { entryMatch in
            let entry = entryMatch.entry
            return SearchItem(
                id: entry.id,
                title: entry.title,
                subtitle: entry.subtitle,
                iconName: "app.fill",
                type: .app,
                action: {
                    NSWorkspace.shared.open(URL(fileURLWithPath: entry.path))
                }
            )
        }

        let preview = results.prefix(8).map { $0.title }.joined(separator: ", ")
        Self.logger.debug("query='\(query, privacy: .public)' normalized='\(normalizedQuery, privacy: .public)' compact='\(compactQuery, privacy: .public)' pathMode=\(shouldMatchPath) results=\(results.count) top=[\(preview, privacy: .public)]")
        return results
    }

    private static func normalize(_ value: String) -> String {
        let folded = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))

        let cleanedScalars = folded.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar) &&
            !CharacterSet.nonBaseCharacters.contains(scalar)
        }
        return String(String.UnicodeScalarView(cleanedScalars)).lowercased()
    }

    private static func normalizeCompact(_ value: String) -> String {
        let lowered = normalize(value)
        let filteredScalars = lowered.unicodeScalars.filter { scalar in
            if CharacterSet.whitespacesAndNewlines.contains(scalar) { return false }
            if CharacterSet.punctuationCharacters.contains(scalar) { return false }
            if CharacterSet.symbols.contains(scalar) { return false }
            return true
        }
        return String(String.UnicodeScalarView(filteredScalars))
    }
}
