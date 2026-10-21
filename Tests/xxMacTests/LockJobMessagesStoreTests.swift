import XCTest
@testable import xxMac

@MainActor
final class LockJobMessagesStoreTests: XCTestCase {
    func testRefreshUsesDailyCacheAndKeepsLastValidMessages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = ConfigDirectoryManager(
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            applicationSupportURL: root
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LockJobURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let store = LockJobMessagesStore(configDirectory: config, session: session)
        let now = Date()

        LockJobURLProtocol.response = (200, Data("[\"Alpha\",\"Beta\"]".utf8))
        LockJobURLProtocol.requestCount = 0
        await store.refreshIfNeeded(now: now)
        XCTAssertEqual(store.messages, ["Alpha", "Beta"])
        XCTAssertEqual(LockJobURLProtocol.requestCount, 1)
        XCTAssertTrue(["Alpha", "Beta"].contains(store.randomMessage()))
        XCTAssertEqual(try Data(contentsOf: config.lockJobMessagesURL), LockJobURLProtocol.response.1)

        await store.refreshIfNeeded(now: now.addingTimeInterval(23 * 60 * 60))
        XCTAssertEqual(LockJobURLProtocol.requestCount, 1)

        LockJobURLProtocol.response = (200, Data("[\"Gamma\"]".utf8))
        let refreshed = await store.refresh(force: true, now: now.addingTimeInterval(23 * 60 * 60))
        XCTAssertTrue(refreshed)
        XCTAssertEqual(LockJobURLProtocol.requestCount, 2)
        XCTAssertEqual(store.messages, ["Gamma"])

        LockJobURLProtocol.response = (200, Data("[]".utf8))
        let invalidRefresh = await store.refresh(force: true, now: now.addingTimeInterval(24 * 60 * 60))
        XCTAssertFalse(invalidRefresh)
        XCTAssertEqual(LockJobURLProtocol.requestCount, 3)
        XCTAssertEqual(store.messages, ["Gamma"])

        let cached = LockJobMessagesStore(configDirectory: config, session: session)
        XCTAssertEqual(cached.messages, ["Gamma"])
    }
}

private final class LockJobURLProtocol: URLProtocol {
    static var response: (Int, Data) = (200, Data())
    static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        let (status, data) = Self.response
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
