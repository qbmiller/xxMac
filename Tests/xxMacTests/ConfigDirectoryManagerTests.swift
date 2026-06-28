import XCTest
@testable import xxMac

final class ConfigDirectoryManagerTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryRoots {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testDefaultDirectoryUsesApplicationSupportXXMac() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let manager = ConfigDirectoryManager(
            defaults: defaults,
            fileManager: .default,
            applicationSupportURL: URL(fileURLWithPath: "/tmp/AppSupport", isDirectory: true)
        )

        XCTAssertEqual(manager.currentDirectory.path, "/tmp/AppSupport/xxMac")
    }

    func testSavedDirectoryIsReloaded() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let customDirectory = makeTemporaryDirectory()

        defaults.set(customDirectory.path, forKey: ConfigDirectoryManager.directoryPathKey)

        let manager = ConfigDirectoryManager(
            defaults: defaults,
            fileManager: .default,
            applicationSupportURL: makeTemporaryDirectory()
        )

        XCTAssertEqual(manager.currentDirectory.path, customDirectory.standardizedFileURL.path)
    }

    func testRejectsFileAsConfigDirectory() throws {
        let root = makeTemporaryDirectory()
        let file = root.appendingPathComponent("not-a-directory")
        try Data("x".utf8).write(to: file)

        let result = ConfigDirectoryManager.validateDirectory(file, fileManager: .default)

        XCTAssertFalse(result.isValid)
    }

    func testRejectsRootDirectory() throws {
        let result = ConfigDirectoryManager.validateDirectory(URL(fileURLWithPath: "/"), fileManager: .default)

        XCTAssertFalse(result.isValid)
    }

    func testSetDirectoryPersistsStandardizedPath() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let target = makeTemporaryDirectory()
        let manager = ConfigDirectoryManager(
            defaults: defaults,
            fileManager: .default,
            applicationSupportURL: makeTemporaryDirectory()
        )

        try manager.setDirectory(target)

        XCTAssertEqual(manager.currentDirectory.path, target.standardizedFileURL.path)
        XCTAssertEqual(defaults.string(forKey: ConfigDirectoryManager.directoryPathKey), target.standardizedFileURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.manifestURL.path))
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryRoots.append(url)
        return url
    }
}
