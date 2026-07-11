import XCTest
@testable import xxMac

final class QuickShortcutIconCacheManagerTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryRoots {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testRemoveIconDeletesOnlyMatchingShortcutFiles() throws {
        let configDirectoryManager = ConfigDirectoryManager(
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            fileManager: .default,
            applicationSupportURL: makeTemporaryDirectory()
        )
        let cache = QuickShortcutIconCacheManager(configDirectoryManager: configDirectoryManager)
        let itemID = UUID()
        let otherItemID = UUID()
        let item = QuickShortcut(
            id: itemID,
            title: "Google",
            keyword: "g",
            actionType: .webSearch,
            payload: "https://www.google.com/search?q={query}"
        )
        let iconURL = configDirectoryManager.quickShortcutIconsDirectoryURL
            .appendingPathComponent("\(itemID.uuidString)-www.google.com.png")
        let otherIconURL = configDirectoryManager.quickShortcutIconsDirectoryURL
            .appendingPathComponent("\(otherItemID.uuidString)-www.google.com.png")
        try Data("icon".utf8).write(to: iconURL)
        try Data("other".utf8).write(to: otherIconURL)

        XCTAssertNotNil(cache.cachedIconURL(for: item))

        cache.removeIcon(for: item)

        XCTAssertFalse(FileManager.default.fileExists(atPath: iconURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: otherIconURL.path))
    }

    func testFaviconURLsFallBackToDomainIconService() {
        let cache = QuickShortcutIconCacheManager()

        XCTAssertEqual(cache.faviconURLs(for: "www.npmjs.com").map(\.absoluteString), [
            "https://www.npmjs.com/favicon.ico",
            "https://icons.duckduckgo.com/ip3/www.npmjs.com.ico"
        ])
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryRoots.append(url)
        return url
    }
}
