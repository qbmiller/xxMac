import XCTest
@testable import xxMac

@MainActor
final class RecommendationsStoreTests: XCTestCase {
    func testCreatesDefaultFileAndLoadsCustomCategories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ConfigDirectoryManager(
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            applicationSupportURL: root
        )
        let store = RecommendationsStore(configDirectory: manager, preferences: try PreferencesStore(configDirectoryManager: manager))

        store.load()
        XCTAssertEqual(store.sourceURL, "https://cf.xiaomi318.com/xxmac/xxmac.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.recommendationsURL.path))
        XCTAssertEqual(store.categories.map(\.id), ["tools", "websites"])

        let custom = """
        {"categories":[{"id":"docs","title":"文档","symbol":"book","items":[{"id":"swift","title":"Swift","description":"语言文档","url":"https://swift.org","iconURL":"https://swift.org/favicon.ico"}]}]}
        """
        try Data(custom.utf8).write(to: manager.recommendationsURL)
        store.load()
        XCTAssertEqual(store.categories.map(\.id), ["docs"])
        XCTAssertEqual(store.categories[0].items[0].destination?.host, "swift.org")
    }

    func testInvalidJSONIsNotOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ConfigDirectoryManager(
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            applicationSupportURL: root
        )
        let invalid = Data("{ invalid".utf8)
        try invalid.write(to: manager.recommendationsURL)

        let store = RecommendationsStore(configDirectory: manager, preferences: try PreferencesStore(configDirectoryManager: manager))
        store.load()
        XCTAssertNotNil(store.error)
        XCTAssertEqual(try Data(contentsOf: manager.recommendationsURL), invalid)
    }

    func testRemoteRefreshUpdatesCacheAndKeepsItOnFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ConfigDirectoryManager(
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            applicationSupportURL: root
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecommendationURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let store = RecommendationsStore(
            configDirectory: manager,
            session: session,
            preferences: try PreferencesStore(configDirectoryManager: manager)
        )
        store.load()
        XCTAssertThrowsError(try store.setSourceURL("http://example.com/recommendations.json"))
        try store.setSourceURL("https://example.pages.dev/recommendations.json")

        let remote = Data("""
        {"categories":[{"id":"new","title":"新分类","items":[]}]}
        """.utf8)
        RecommendationURLProtocol.response = (200, remote)
        await store.refresh()
        XCTAssertEqual(store.categories.map(\.id), ["new"])
        XCTAssertEqual(try Data(contentsOf: manager.recommendationsURL), remote)

        RecommendationURLProtocol.response = (503, Data())
        await store.refresh()
        XCTAssertEqual(store.categories.map(\.id), ["new"])
        XCTAssertNotNil(store.error)
    }
}

private final class RecommendationURLProtocol: URLProtocol {
    static var response: (Int, Data) = (200, Data())

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, data) = Self.response
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
