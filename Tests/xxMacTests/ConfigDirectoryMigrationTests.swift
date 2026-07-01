import XCTest
@testable import xxMac

final class ConfigDirectoryMigrationTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryRoots {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testChangingDirectoryMovesCurrentDataAndPersistsPath() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let sourceRoot = makeTemporaryDirectory()
        let targetRoot = makeTemporaryDirectory()
        let manager = ConfigDirectoryManager(
            defaults: defaults,
            fileManager: .default,
            applicationSupportURL: sourceRoot
        )
        try Data("prefs".utf8).write(to: manager.preferencesURL)
        try Data("index".utf8).write(to: manager.appSearchIndexURL)
        try Data("db".utf8).write(to: manager.clipboardDatabaseURL)
        try Data("wal".utf8).write(to: manager.currentDirectory.appendingPathComponent("clipboard.db-wal"))
        let imageURL = manager.clipboardImagesDirectoryURL.appendingPathComponent("a.png")
        try Data("image".utf8).write(to: imageURL)
        let thumbnailURL = manager.clipboardThumbnailsDirectoryURL.appendingPathComponent("a-thumb.png")
        try Data("thumbnail".utf8).write(to: thumbnailURL)
        let originalDirectory = manager.currentDirectory

        try manager.changeDirectory(to: targetRoot)

        XCTAssertEqual(manager.currentDirectory.path, targetRoot.standardizedFileURL.path)
        XCTAssertEqual(defaults.string(forKey: ConfigDirectoryManager.directoryPathKey), targetRoot.standardizedFileURL.path)
        XCTAssertEqual(try String(contentsOf: manager.preferencesURL, encoding: .utf8), "prefs")
        XCTAssertEqual(try String(contentsOf: manager.appSearchIndexURL, encoding: .utf8), "index")
        XCTAssertEqual(try String(contentsOf: manager.clipboardDatabaseURL, encoding: .utf8), "db")
        XCTAssertEqual(
            try String(contentsOf: manager.currentDirectory.appendingPathComponent("clipboard.db-wal"), encoding: .utf8),
            "wal"
        )
        XCTAssertEqual(
            try String(contentsOf: manager.clipboardImagesDirectoryURL.appendingPathComponent("a.png"), encoding: .utf8),
            "image"
        )
        XCTAssertEqual(
            try String(contentsOf: manager.clipboardThumbnailsDirectoryURL.appendingPathComponent("a-thumb.png"), encoding: .utf8),
            "thumbnail"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalDirectory.path))
    }

    func testInvalidTargetDoesNotChangeCurrentDirectory() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let sourceRoot = makeTemporaryDirectory()
        let manager = ConfigDirectoryManager(
            defaults: defaults,
            fileManager: .default,
            applicationSupportURL: sourceRoot
        )
        let originalPath = manager.currentDirectory.path
        let file = makeTemporaryDirectory().appendingPathComponent("not-a-directory")
        try Data("x".utf8).write(to: file)

        XCTAssertThrowsError(try manager.changeDirectory(to: file))
        XCTAssertEqual(manager.currentDirectory.path, originalPath)
        XCTAssertNil(defaults.string(forKey: ConfigDirectoryManager.directoryPathKey))
    }

    func testRejectsTargetInsideCurrentDirectory() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let sourceRoot = makeTemporaryDirectory()
        let manager = ConfigDirectoryManager(
            defaults: defaults,
            fileManager: .default,
            applicationSupportURL: sourceRoot
        )
        let nestedTarget = manager.currentDirectory.appendingPathComponent("nested", isDirectory: true)

        XCTAssertThrowsError(try manager.changeDirectory(to: nestedTarget))
        XCTAssertEqual(manager.currentDirectory.path, sourceRoot.appendingPathComponent("xxMac").path)
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryRoots.append(url)
        return url
    }
}
