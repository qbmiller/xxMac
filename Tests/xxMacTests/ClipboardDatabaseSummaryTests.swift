import XCTest
@testable import xxMac

final class ClipboardDatabaseSummaryTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryRoots {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testListItemsReturnTruncatedTextPreview() throws {
        let root = makeTemporaryDirectory()
        let storage = ClipboardStorageManager(storageDirectory: root)
        let largeText = String(repeating: "abcdef", count: 10_000)

        storage.saveItem(type: .text, content: largeText, size: largeText.utf8.count)

        let items = storage.getListItems(limit: 10)
        XCTAssertEqual(items.count, 1)
        XCTAssertLessThan(items[0].previewContent.count, largeText.count)
        XCTAssertEqual(items[0].fullContentLength, largeText.count)
    }

    func testCanLoadFullItemByIDAfterSummaryQuery() throws {
        let root = makeTemporaryDirectory()
        let storage = ClipboardStorageManager(storageDirectory: root)
        let largeText = String(repeating: "full-content", count: 2_000)

        storage.saveItem(type: .text, content: largeText, size: largeText.utf8.count)

        let summary = try XCTUnwrap(storage.getListItems(limit: 1).first)
        let fullItem = try XCTUnwrap(storage.getItem(id: summary.id))
        XCTAssertEqual(fullItem.content, largeText)
    }

    func testImageOCRMetadataPersistsAndIsSearchable() throws {
        let root = makeTemporaryDirectory()
        let storage = ClipboardStorageManager(storageDirectory: root)

        storage.saveImageItem(
            content: "screen.png",
            size: 1024,
            width: 800,
            height: 600,
            thumbnailFilename: nil
        )

        let item = try XCTUnwrap(storage.getListItems(limit: 1).first)
        storage.updateImageOCR(
            id: item.id,
            text: "invoice number ABC123",
            status: .ready
        )

        let results = storage.searchListItems(query: "ABC123")
        XCTAssertEqual(results.first?.id, item.id)

        let fullItem = try XCTUnwrap(storage.getItem(id: item.id))
        XCTAssertEqual(fullItem.imageOCRText, "invoice number ABC123")
        XCTAssertEqual(fullItem.imageOCRStatus, .ready)
        XCTAssertNotNil(fullItem.imageOCRUpdatedAt)
    }

    func testDeletingImageRemovesOCRSearchIndex() throws {
        let root = makeTemporaryDirectory()
        let storage = ClipboardStorageManager(storageDirectory: root)

        storage.saveImageItem(content: "ocr.png", size: 1024, width: nil, height: nil, thumbnailFilename: nil)
        let item = try XCTUnwrap(storage.getItem(id: try XCTUnwrap(storage.getListItems().first).id))

        storage.updateImageOCR(id: item.id, text: "temporary searchable text", status: .ready)
        XCTAssertFalse(storage.searchListItems(query: "temporary").isEmpty)

        storage.deleteItem(item)
        XCTAssertTrue(storage.searchListItems(query: "temporary").isEmpty)
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryRoots.append(url)
        return url
    }
}
