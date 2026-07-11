import XCTest
import SQLite3
@testable import xxMac

final class ChromiumBrowserDataProviderTests: XCTestCase {
    private var rootURL: URL!
    private var userDataURL: URL!
    private var temporaryURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        userDataURL = rootURL.appendingPathComponent("User Data")
        temporaryURL = rootURL.appendingPathComponent("Temp")
        try FileManager.default.createDirectory(at: userDataURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temporaryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func testUsesLastUsedProfileAndFallsBackToDefault() throws {
        let provider = makeProvider()
        XCTAssertEqual(provider.currentProfileDirectory().lastPathComponent, "Default")

        let localState = #"{"profile":{"last_used":"Profile 2"}}"#
        try Data(localState.utf8).write(to: userDataURL.appendingPathComponent("Local State"))
        XCTAssertEqual(provider.currentProfileDirectory().lastPathComponent, "Profile 2")
    }

    func testSearchesNestedBookmarksAndFiltersUnsupportedURLs() throws {
        try writeProfileFiles(bookmarks: #"{"roots":{"bookmark_bar":{"children":[{"type":"url","name":"Swift Forums","url":"https://forums.swift.org"},{"type":"folder","children":[{"type":"url","name":"GitHub","url":"https://github.com"},{"type":"url","name":"Internal","url":"chrome://settings"}]}]}}}"#)

        let records = try makeProvider().searchBookmarks(query: "git", limit: 10)

        XCTAssertEqual(records.map(\.title), ["GitHub"])
        XCTAssertEqual(records.first?.url.absoluteString, "https://github.com")
    }

    func testSearchesHistoryInRecentOrderAndCleansTemporaryCopy() throws {
        let profileURL = try writeProfileFiles(bookmarks: #"{"roots":{}}"#)
        try createHistoryDatabase(at: profileURL.appendingPathComponent("History"))

        let records = try makeProvider().searchHistory(query: "swift", limit: 10)

        XCTAssertEqual(records.map(\.title), ["New Swift", "Old Swift"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporaryURL.path), [])
    }

    private func makeProvider() -> ChromiumBrowserDataProvider {
        ChromiumBrowserDataProvider(
            browser: .chrome,
            userDataDirectory: userDataURL,
            temporaryDirectory: temporaryURL
        )
    }

    @discardableResult
    private func writeProfileFiles(bookmarks: String) throws -> URL {
        let profileURL = userDataURL.appendingPathComponent("Default")
        try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
        try Data(bookmarks.utf8).write(to: profileURL.appendingPathComponent("Bookmarks"))
        return profileURL
    }

    private func createHistoryDatabase(at url: URL) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, "CREATE TABLE urls (id INTEGER PRIMARY KEY, url TEXT, title TEXT, last_visit_time INTEGER)", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "INSERT INTO urls(url,title,last_visit_time) VALUES ('https://old.example/swift','Old Swift',100),('https://new.example/swift','New Swift',200),('https://other.example','Other',300)", nil, nil, nil), SQLITE_OK)
    }
}
