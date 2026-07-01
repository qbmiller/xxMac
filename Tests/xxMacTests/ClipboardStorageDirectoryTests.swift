import XCTest
@testable import xxMac

final class ClipboardStorageDirectoryTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryRoots {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testStoragePathsComeFromConfigDirectory() throws {
        let root = makeTemporaryDirectory()
        let storage = ClipboardStorageManager(storageDirectory: root)

        XCTAssertEqual(storage.storageDirectory.path, root.standardizedFileURL.path)
        XCTAssertEqual(storage.databasePath, root.appendingPathComponent("clipboard.db").path)
        XCTAssertEqual(storage.imagesDirectory.path, root.appendingPathComponent("clipboard_images").path)
        XCTAssertEqual(storage.thumbnailsDirectory.path, root.appendingPathComponent("clipboard_thumbnails").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.imagesDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.thumbnailsDirectory.path))
    }

    func testReloadStorageDirectoryUpdatesPaths() throws {
        let first = makeTemporaryDirectory()
        let second = makeTemporaryDirectory()
        let storage = ClipboardStorageManager(storageDirectory: first)

        storage.reloadStorageDirectory(second)

        XCTAssertEqual(storage.storageDirectory.path, second.standardizedFileURL.path)
        XCTAssertEqual(storage.databasePath, second.appendingPathComponent("clipboard.db").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.imagesDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.thumbnailsDirectory.path))
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryRoots.append(url)
        return url
    }
}
