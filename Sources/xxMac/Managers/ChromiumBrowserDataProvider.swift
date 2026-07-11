import Foundation
import SQLite3

final class ChromiumBrowserDataProvider: BrowserDataProvider {
    let browser: BrowserKind

    private let userDataDirectory: URL
    private let temporaryDirectory: URL
    private let fileManager: FileManager

    init(
        browser: BrowserKind,
        userDataDirectory: URL? = nil,
        temporaryDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.browser = browser
        self.fileManager = fileManager
        self.userDataDirectory = userDataDirectory ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(browser.userDataDirectoryName, isDirectory: true)
        self.temporaryDirectory = temporaryDirectory ?? fileManager.temporaryDirectory
    }

    func currentProfileDirectory() -> URL {
        userDataDirectory.appendingPathComponent(lastUsedProfileName(), isDirectory: true)
    }

    func searchBookmarks(query: String, limit: Int) throws -> [BrowserRecord] {
        let bookmarksURL = currentProfileDirectory().appendingPathComponent("Bookmarks")
        guard fileManager.fileExists(atPath: bookmarksURL.path) else {
            throw BrowserDataError.bookmarksUnavailable
        }

        let data = try Data(contentsOf: bookmarksURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = root["roots"] as? [String: Any] else {
            throw BrowserDataError.invalidBookmarks
        }

        var records: [BrowserRecord] = []
        collectBookmarks(from: roots, into: &records)
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return records
            .filter { record in
                normalizedQuery.isEmpty ||
                    record.title.lowercased().contains(normalizedQuery) ||
                    record.url.absoluteString.lowercased().contains(normalizedQuery)
            }
            .sorted { left, right in
                bookmarkRank(left, query: normalizedQuery) < bookmarkRank(right, query: normalizedQuery)
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    func searchHistory(query: String, limit: Int) throws -> [BrowserRecord] {
        let historyURL = currentProfileDirectory().appendingPathComponent("History")
        guard fileManager.fileExists(atPath: historyURL.path) else {
            throw BrowserDataError.historyUnavailable
        }

        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let copyURL = temporaryDirectory.appendingPathComponent("xxmac-browser-history-\(UUID().uuidString).sqlite")
        try fileManager.copyItem(at: historyURL, to: copyURL)
        let sidecarSuffixes = ["-wal", "-shm"]
        for suffix in sidecarSuffixes {
            let source = URL(fileURLWithPath: historyURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try? fileManager.copyItem(at: source, to: URL(fileURLWithPath: copyURL.path + suffix))
        }
        defer {
            try? fileManager.removeItem(at: copyURL)
            sidecarSuffixes.forEach {
                try? fileManager.removeItem(at: URL(fileURLWithPath: copyURL.path + $0))
            }
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(copyURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            if database != nil { sqlite3_close(database) }
            throw BrowserDataError.historyQueryFailed
        }
        defer { sqlite3_close(database) }

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasQuery = !normalizedQuery.isEmpty
        let sql = hasQuery
            ? "SELECT title, url, last_visit_time FROM urls WHERE title LIKE ? OR url LIKE ? ORDER BY last_visit_time DESC LIMIT ?"
            : "SELECT title, url, last_visit_time FROM urls ORDER BY last_visit_time DESC LIMIT ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw BrowserDataError.historyQueryFailed
        }
        defer { sqlite3_finalize(statement) }

        var limitIndex: Int32 = 1
        if hasQuery {
            let pattern = "%\(normalizedQuery)%"
            sqlite3_bind_text(statement, 1, (pattern as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (pattern as NSString).utf8String, -1, nil)
            limitIndex = 3
        }
        sqlite3_bind_int(statement, limitIndex, Int32(max(0, limit)))

        var records: [BrowserRecord] = []
        var seenURLs = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let urlText = sqlite3_column_text(statement, 1) else { continue }
            let urlString = String(cString: urlText)
            guard seenURLs.insert(urlString).inserted,
                  let url = supportedURL(urlString) else { continue }
            let title = sqlite3_column_text(statement, 0).map(String.init(cString:)) ?? url.host ?? urlString
            let chromiumTime = sqlite3_column_int64(statement, 2)
            records.append(BrowserRecord(
                title: title.isEmpty ? (url.host ?? urlString) : title,
                url: url,
                lastVisitedAt: chromiumDate(chromiumTime)
            ))
        }
        return records
    }

    private func lastUsedProfileName() -> String {
        let localStateURL = userDataDirectory.appendingPathComponent("Local State")
        guard let data = try? Data(contentsOf: localStateURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let lastUsed = profile["last_used"] as? String,
              !lastUsed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Default"
        }
        return lastUsed
    }

    private func collectBookmarks(from value: Any, into records: inout [BrowserRecord]) {
        if let dictionary = value as? [String: Any] {
            if dictionary["type"] as? String == "url",
               let urlString = dictionary["url"] as? String,
               let url = supportedURL(urlString) {
                let title = (dictionary["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                records.append(BrowserRecord(
                    title: title?.isEmpty == false ? title! : (url.host ?? urlString),
                    url: url,
                    lastVisitedAt: nil
                ))
            }
            dictionary.values.forEach { collectBookmarks(from: $0, into: &records) }
        } else if let array = value as? [Any] {
            array.forEach { collectBookmarks(from: $0, into: &records) }
        }
    }

    private func supportedURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    private func bookmarkRank(_ record: BrowserRecord, query: String) -> Int {
        guard !query.isEmpty else { return 0 }
        let title = record.title.lowercased()
        if title.hasPrefix(query) { return 0 }
        if title.contains(query) { return 1 }
        return 2
    }

    private func chromiumDate(_ microseconds: Int64) -> Date? {
        guard microseconds > 0 else { return nil }
        let secondsBetween1601And1970: TimeInterval = 11_644_473_600
        return Date(timeIntervalSince1970: TimeInterval(microseconds) / 1_000_000 - secondsBetween1601And1970)
    }
}
