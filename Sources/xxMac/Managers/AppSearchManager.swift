import AppKit
import Combine
import Darwin
import OSLog

class AppSearchManager: ObservableObject {
    static let shared = AppSearchManager()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "xxMac", category: "AppSearch")

    @Published var apps: [SearchItem] = []
    @Published var isIndexing = false
    @Published var searchPaths: [String] = [] {
        didSet {
            saveSearchPaths()
            guard !isLoadingSearchPaths else { return }
            scanApplications()
        }
    }

    private let requiredSystemPaths = ["/Applications", "/System/Applications", "/System/Library/CoreServices"]
    private let userDefaultsKey = "AppSearchPaths"
    private let cacheDefaultsKey = "AppSearchIndexCacheV1"
    private var appEntries: [AppEntry] = []
    private var scanGeneration = 0
    private var isLoadingSearchPaths = false
    private var appDirectoryMonitors: [AppDirectoryMonitor] = []
    private var appendWorkItem: DispatchWorkItem?

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
        let nameCompactKeys: [String]?
    }

    private init() {
        loadSearchPaths()
        configureAppDirectoryMonitors()
        if !loadCachedIndex() {
            scanApplications()
        }
    }

    deinit {
        appDirectoryMonitors.removeAll()
        appendWorkItem?.cancel()
    }

    private func loadSearchPaths() {
        isLoadingSearchPaths = true
        defer { isLoadingSearchPaths = false }

        if let savedPaths = PreferencesStore.shared.stringArray(forKey: userDefaultsKey) {
            searchPaths = ensureRequiredSearchPaths(in: savedPaths)
        } else {
            searchPaths = requiredSystemPaths
        }
    }

    private func saveSearchPaths() {
        PreferencesStore.shared.set(searchPaths, forKey: userDefaultsKey)
    }

    @discardableResult
    private func loadCachedIndex() -> Bool {
        guard
            let data = try? Data(contentsOf: ConfigDirectoryManager.shared.appSearchIndexURL),
            let cached = try? JSONDecoder().decode([CachedEntry].self, from: data)
        else {
            return false
        }

        let entries = cached.map(makeEntry(fromCached:))
        appEntries = entries
        apps = entries.map(makeSearchItem)
        Self.logger.debug("cache loaded=\(entries.count)")
        return !entries.isEmpty
    }

    private func saveCachedIndex(_ entries: [AppEntry]) {
        let cached = entries.map {
            CachedEntry(
                id: $0.id,
                title: $0.title,
                subtitle: $0.subtitle,
                path: $0.path,
                nameKeys: $0.nameSearchKeys,
                nameCompactKeys: $0.nameCompactSearchKeys
            )
        }
        guard let data = try? JSONEncoder().encode(cached) else { return }
        try? data.write(to: ConfigDirectoryManager.shared.appSearchIndexURL, options: .atomic)
    }

    func flushIndexCacheIfNeeded() {
        saveCachedIndex(appEntries)
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

    private func configureAppDirectoryMonitors() {
        let pathsToWatch = prioritizedPaths(searchPaths)
        appDirectoryMonitors = pathsToWatch.compactMap { path in
            AppDirectoryMonitor(path: path) { [weak self] in
                self?.scheduleAppendNewApplications()
            }
        }
    }

    private func scheduleAppendNewApplications() {
        appendWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.appendNewApplications()
        }
        appendWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
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

        let searchKeys = AppSearchKeyBuilder.keys(for: Array(nameKeys))

        return AppEntry(
            id: "app:\(path)",
            title: localizedName,
            subtitle: path,
            path: path,
            nameSearchKeys: searchKeys.normalized,
            nameCompactSearchKeys: searchKeys.compact,
            pathSearchKey: AppSearchKeyBuilder.normalize(path),
            pathCompactSearchKey: AppSearchKeyBuilder.normalizeCompact(path)
        )
    }

    private func makeEntry(fromCached entry: CachedEntry) -> AppEntry {
        let keys = Set(entry.nameKeys + [entry.title])
        let generatedKeys = AppSearchKeyBuilder.keys(for: Array(keys))

        return AppEntry(
            id: entry.id,
            title: entry.title,
            subtitle: entry.subtitle,
            path: entry.path,
            nameSearchKeys: generatedKeys.normalized,
            nameCompactSearchKeys: entry.nameCompactKeys ?? generatedKeys.compact,
            pathSearchKey: AppSearchKeyBuilder.normalize(entry.path),
            pathCompactSearchKey: AppSearchKeyBuilder.normalizeCompact(entry.path)
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
        configureAppDirectoryMonitors()
        let pathsToScan = prioritizedPaths(searchPaths)
        scanGeneration += 1
        let generation = scanGeneration
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
                guard generation == self.scanGeneration else { return }
                self.appEntries = sortedEntries
                self.apps = sortedEntries.map(self.makeSearchItem)
                self.saveCachedIndex(sortedEntries)
                self.isIndexing = false
                Self.logger.debug("scan roots='\(pathsToScan.joined(separator: ","), privacy: .public)' indexed=\(sortedEntries.count)")
            }
        }
    }

    private func appendNewApplications() {
        let pathsToScan = prioritizedPaths(searchPaths)
        let existingPaths = Set(appEntries.map(\.path))

        DispatchQueue.global(qos: .utility).async {
            let fileManager = FileManager.default
            var newEntries: [AppEntry] = []
            var seenPaths = existingPaths

            for rootPath in pathsToScan {
                guard let subpaths = try? fileManager.subpathsOfDirectory(atPath: rootPath) else {
                    Self.logger.debug("append skip root='\(rootPath, privacy: .public)' reason='unreadable'")
                    continue
                }

                for subpath in subpaths where subpath.hasSuffix(".app") && !subpath.contains(".app/") {
                    let fullPath = (rootPath as NSString).appendingPathComponent(subpath)
                    guard !seenPaths.contains(fullPath) else { continue }
                    seenPaths.insert(fullPath)
                    newEntries.append(self.makeEntry(fromPath: fullPath, fileManager: fileManager))
                }
            }

            guard !newEntries.isEmpty else { return }

            DispatchQueue.main.async {
                let mergedEntries = (self.appEntries + newEntries).sorted {
                    $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
                self.appEntries = mergedEntries
                self.apps = mergedEntries.map(self.makeSearchItem)
                self.saveCachedIndex(mergedEntries)
                Self.logger.debug("append roots='\(pathsToScan.joined(separator: ","), privacy: .public)' added=\(newEntries.count) indexed=\(mergedEntries.count)")
            }
        }
    }

    func search(query: String) -> [SearchItem] {
        let normalizedQuery = AppSearchKeyBuilder.normalize(query)
        let compactQuery = AppSearchKeyBuilder.normalizeCompact(query)
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

}

private final class AppDirectoryMonitor {
    private let fileDescriptor: CInt
    private let source: DispatchSourceFileSystemObject

    init?(path: String, onChange: @escaping () -> Void) {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }

        fileDescriptor = descriptor
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: .main
        )
        source.setEventHandler(handler: onChange)
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}
