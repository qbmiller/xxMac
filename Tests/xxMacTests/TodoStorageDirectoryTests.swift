import XCTest
@testable import xxMac

final class TodoStorageDirectoryTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryRoots {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testTodoDatabaseURLUsesCurrentConfigDirectory() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let root = makeTemporaryDirectory()
        let manager = ConfigDirectoryManager(
            defaults: defaults,
            fileManager: .default,
            applicationSupportURL: root
        )

        XCTAssertEqual(manager.todoDatabaseURL.lastPathComponent, "todo.db")
        XCTAssertEqual(
            manager.todoDatabaseURL.deletingLastPathComponent().standardizedFileURL,
            manager.currentDirectory.standardizedFileURL
        )
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryRoots.append(url)
        return url
    }
}
