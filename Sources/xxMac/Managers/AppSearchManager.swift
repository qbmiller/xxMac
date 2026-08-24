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
    @Published var excludedPaths: [String] = [] {
        didSet {
            saveExcludedPaths()
            guard !isLoadingExcludedPaths else { return }
            scanApplications()
        }
    }

    private let requiredSystemPaths = AppDefaultSettings.General.appSearchPaths
    private let userDefaultsKey = "AppSearchPaths"
    private let excludedPathsDefaultsKey = "AppSearchExcludedPaths"
    private let cacheDefaultsKey = "AppSearchIndexCacheV2"
    private var appEntries: [AppEntry] = []
    private var scanGeneration = 0
    private var isLoadingSearchPaths = false
    private var isLoadingExcludedPaths = false
    private var appDirectoryMonitors: [AppDirectoryMonitor] = []
    private var appendWorkItem: DispatchWorkItem?
    private let spotlightApplicationFinder = SpotlightApplicationFinder()

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

    static func shouldIndexApplicationPath(
        _ path: String,
        roots: [String],
        excludedPaths: [String] = []
    ) -> Bool {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let normalizedExcludedPaths = excludedPaths.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        }
        guard normalizedPath.hasSuffix(".app"),
              roots.contains(where: { isPath(normalizedPath, inside: $0) }),
              !normalizedExcludedPaths.contains(where: { isPath(normalizedPath, inside: $0) }),
              !containsNestedApplicationOrInstaller(normalizedPath, relativeTo: roots) else {
            return false
        }
        return true
    }

    static func applicationExists(at path: String, fileManager: FileManager = .default) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private init() {
        loadSearchPaths()
        loadExcludedPaths()
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

    private func loadExcludedPaths() {
        isLoadingExcludedPaths = true
        defer { isLoadingExcludedPaths = false }
        excludedPaths = PreferencesStore.shared.stringArray(forKey: excludedPathsDefaultsKey)
            ?? AppDefaultSettings.General.appSearchExcludedPaths
    }

    private func saveExcludedPaths() {
        PreferencesStore.shared.set(excludedPaths, forKey: excludedPathsDefaultsKey)
    }

    @discardableResult
    private func loadCachedIndex() -> Bool {
        guard
            let data = try? Data(contentsOf: ConfigDirectoryManager.shared.appSearchIndexURL),
            let cached = try? JSONDecoder().decode([CachedEntry].self, from: data)
        else {
            return false
        }

        let roots = prioritizedPaths(searchPaths)
        let entries = cached
            .map(makeEntry(fromCached:))
            .filter { entry in
                Self.shouldIndexApplicationPath(entry.path, roots: roots, excludedPaths: excludedPaths) &&
                Self.applicationExists(at: entry.path)
            }
        appEntries = entries
        apps = entries.map(makeSearchItem)
        if entries.count != cached.count {
            saveCachedIndex(entries)
        }
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

    func addExcludedPath(_ path: String) {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        if !excludedPaths.contains(normalizedPath) {
            excludedPaths.append(normalizedPath)
        }
    }

    func removeExcludedPath(_ path: String) {
        excludedPaths.removeAll { $0 == path }
    }

    func resetExcludedPaths() {
        excludedPaths = AppDefaultSettings.General.appSearchExcludedPaths
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

    private static func isPath(_ path: String, inside root: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    private static func containsNestedApplicationOrInstaller(_ path: String, relativeTo roots: [String]) -> Bool {
        guard let root = roots.filter({ isPath(path, inside: $0) }).max(by: { $0.count < $1.count }) else {
            return true
        }

        let relativePath = String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parentComponents = relativePath.split(separator: "/").dropLast()
        return parentComponents.contains { component in
            let lowercased = component.lowercased()
            return lowercased.hasSuffix(".app") || lowercased.hasSuffix(".app.installing")
        }
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
        let compactKeys = Set((entry.nameCompactKeys ?? []) + generatedKeys.compact)

        return AppEntry(
            id: entry.id,
            title: entry.title,
            subtitle: entry.subtitle,
            path: entry.path,
            nameSearchKeys: generatedKeys.normalized,
            nameCompactSearchKeys: compactKeys.sorted(),
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
        let pathsToExclude = excludedPaths
        scanGeneration += 1
        let generation = scanGeneration
        isIndexing = true

        spotlightApplicationFinder.findApplicationPaths(in: pathsToScan) { [weak self] result in
            guard let self, generation == self.scanGeneration else { return }
            switch result {
            case .success(let paths) where !paths.isEmpty:
                self.buildIndex(
                    from: paths,
                    roots: pathsToScan,
                    excludedPaths: pathsToExclude,
                    generation: generation,
                    source: "spotlight"
                )
            case .success:
                Self.logger.debug("spotlight roots='\(pathsToScan.joined(separator: ","), privacy: .public)' returned no applications; using directory scan")
                self.scanApplicationDirectories(
                    pathsToScan,
                    excludedPaths: pathsToExclude,
                    generation: generation
                )
            case .failure(let error):
                Self.logger.debug("spotlight roots='\(pathsToScan.joined(separator: ","), privacy: .public)' failed='\(error.localizedDescription, privacy: .public)'; using directory scan")
                self.scanApplicationDirectories(
                    pathsToScan,
                    excludedPaths: pathsToExclude,
                    generation: generation
                )
            }
        }
    }

    private func buildIndex(
        from paths: [String],
        roots: [String],
        excludedPaths: [String],
        generation: Int,
        source: String
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            var foundByPath: [String: AppEntry] = [:]
            for path in paths {
                guard Self.shouldIndexApplicationPath(path, roots: roots, excludedPaths: excludedPaths),
                      Self.applicationExists(at: path, fileManager: fileManager) else { continue }
                foundByPath[path] = self.makeEntry(fromPath: path, fileManager: fileManager)
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
                Self.logger.debug("\(source, privacy: .public) roots='\(roots.joined(separator: ","), privacy: .public)' indexed=\(sortedEntries.count)")
            }
        }
    }

    private func scanApplicationDirectories(
        _ pathsToScan: [String],
        excludedPaths: [String],
        generation: Int
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            var paths: [String] = []

            for rootPath in pathsToScan {
                guard let subpaths = try? fileManager.subpathsOfDirectory(atPath: rootPath) else {
                    Self.logger.debug("scan skip root='\(rootPath, privacy: .public)' reason='unreadable'")
                    continue
                }

                paths.append(contentsOf: subpaths.compactMap { subpath in
                    guard subpath.hasSuffix(".app"), !subpath.contains(".app/") else { return nil }
                    let fullPath = (rootPath as NSString).appendingPathComponent(subpath)
                    guard Self.shouldIndexApplicationPath(
                        fullPath,
                        roots: pathsToScan,
                        excludedPaths: excludedPaths
                    ) else { return nil }
                    return fullPath
                })
            }

            self.buildIndex(
                from: paths,
                roots: pathsToScan,
                excludedPaths: excludedPaths,
                generation: generation,
                source: "directory scan"
            )
        }
    }

    private func appendNewApplications() {
        let pathsToScan = prioritizedPaths(searchPaths)
        let pathsToExclude = excludedPaths
        let currentEntries = appEntries

        DispatchQueue.global(qos: .utility).async {
            let fileManager = FileManager.default
            let existingEntries = currentEntries.filter { entry in
                Self.shouldIndexApplicationPath(
                    entry.path,
                    roots: pathsToScan,
                    excludedPaths: pathsToExclude
                ) &&
                Self.applicationExists(at: entry.path, fileManager: fileManager)
            }
            let existingPaths = Set(existingEntries.map(\.path))
            var newEntries: [AppEntry] = []
            var seenPaths = existingPaths

            for rootPath in pathsToScan {
                guard let subpaths = try? fileManager.subpathsOfDirectory(atPath: rootPath) else {
                    Self.logger.debug("append skip root='\(rootPath, privacy: .public)' reason='unreadable'")
                    continue
                }

                for subpath in subpaths where subpath.hasSuffix(".app") && !subpath.contains(".app/") {
                    let fullPath = (rootPath as NSString).appendingPathComponent(subpath)
                    guard !seenPaths.contains(fullPath),
                          Self.shouldIndexApplicationPath(
                              fullPath,
                              roots: pathsToScan,
                              excludedPaths: pathsToExclude
                          ),
                          Self.applicationExists(at: fullPath, fileManager: fileManager) else { continue }
                    seenPaths.insert(fullPath)
                    newEntries.append(self.makeEntry(fromPath: fullPath, fileManager: fileManager))
                }
            }

            guard !newEntries.isEmpty || existingEntries.count != currentEntries.count else { return }

            DispatchQueue.main.async {
                let mergedEntries = (existingEntries + newEntries).sorted {
                    $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
                self.appEntries = mergedEntries
                self.apps = mergedEntries.map(self.makeSearchItem)
                self.saveCachedIndex(mergedEntries)
                Self.logger.debug("append roots='\(pathsToScan.joined(separator: ","), privacy: .public)' added=\(newEntries.count) removed=\(currentEntries.count - existingEntries.count) indexed=\(mergedEntries.count)")
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
            guard Self.shouldIndexApplicationPath(
                entry.path,
                roots: searchPaths,
                excludedPaths: excludedPaths
            ), Self.applicationExists(at: entry.path) else { return nil }
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
                    let url = URL(fileURLWithPath: entry.path)
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = true
                    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                        if let error {
                            Self.logger.error("open app path='\(entry.path, privacy: .public)' failed='\(error.localizedDescription, privacy: .public)'")
                        }
                    }
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
