import XCTest
@testable import xxMac

final class BrowserSearchManagerTests: XCTestCase {
    func testUsesSystemDefaultEdgeOnFirstRun() {
        let manager = makeManager(defaultBrowser: BrowserKind.edge.bundleIdentifier)
        XCTAssertEqual(manager.preferences.browser, .edge)
    }

    func testFallsBackToInstalledChrome() {
        let manager = makeManager(defaultBrowser: "org.example.unsupported", installed: [.chrome])
        XCTAssertEqual(manager.preferences.browser, .chrome)
    }

    func testActivatesDefaultAndCustomKeywords() {
        let manager = makeManager()
        XCTAssertEqual(manager.activationRequest(for: "bm swift"), BrowserSearchRequest(mode: .bookmarks, query: "swift"))
        XCTAssertEqual(manager.activationRequest(for: "bh"), BrowserSearchRequest(mode: .history, query: ""))

        XCTAssertNil(manager.updateKeywords(bookmark: "marks", history: "visits"))
        XCTAssertNil(manager.activationRequest(for: "bm swift"))
        XCTAssertEqual(manager.activationRequest(for: "marks swift"), BrowserSearchRequest(mode: .bookmarks, query: "swift"))
    }

    func testRejectsDuplicateBrowserKeywords() {
        let manager = makeManager()
        XCTAssertNotNil(manager.updateKeywords(bookmark: "find", history: " FIND "))
        XCTAssertEqual(manager.preferences.bookmarkKeyword, "bm")
        XCTAssertEqual(manager.preferences.historyKeyword, "bh")
    }

    func testRejectsKeywordContainingWhitespace() {
        let manager = makeManager()
        XCTAssertNotNil(manager.updateKeywords(bookmark: "book marks", history: "visits"))
        XCTAssertEqual(manager.preferences.bookmarkKeyword, "bm")
    }

    private func makeManager(
        defaultBrowser: String? = BrowserKind.chrome.bundleIdentifier,
        installed: Set<BrowserKind> = Set(BrowserKind.allCases)
    ) -> BrowserSearchManager {
        BrowserSearchManager(
            store: MemoryBrowserSearchStore(),
            providerFactory: { _ in EmptyBrowserProvider() },
            defaultBrowserIdentifier: { defaultBrowser },
            installedBrowser: { installed.contains($0) },
            openURLHandler: { _, _ in }
        )
    }
}

private final class MemoryBrowserSearchStore: BrowserSearchPreferenceStoring {
    private var values: [String: Any] = [:]
    func string(forKey key: String) -> String? { values[key] as? String }
    func boolObject(forKey key: String) -> Bool? { values[key] as? Bool }
    func set(_ value: String, forKey key: String) { values[key] = value }
    func set(_ value: Bool, forKey key: String) { values[key] = value }
}

private struct EmptyBrowserProvider: BrowserDataProvider {
    let browser = BrowserKind.chrome
    func currentProfileDirectory() -> URL { URL(fileURLWithPath: "/tmp") }
    func searchBookmarks(query: String, limit: Int) throws -> [BrowserRecord] { [] }
    func searchHistory(query: String, limit: Int) throws -> [BrowserRecord] { [] }
}
