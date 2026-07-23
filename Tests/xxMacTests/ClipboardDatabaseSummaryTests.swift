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
        XCTAssertLessThanOrEqual(items[0].previewContent.count, DatabaseManager.defaultTextPreviewLimit)
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
        XCTAssertEqual(storage.searchListItems(query: "C12").first?.id, item.id)

        let fullItem = try XCTUnwrap(storage.getItem(id: item.id))
        XCTAssertEqual(fullItem.imageOCRText, "invoice number ABC123")
        XCTAssertEqual(fullItem.imageOCRStatus, .ready)
        XCTAssertNotNil(fullItem.imageOCRUpdatedAt)
    }

    func testSearchMatchesMiddleTextAndLiteralSymbolsInHistoryAndFavorites() throws {
        let root = makeTemporaryDirectory()
        let storage = ClipboardStorageManager(storageDirectory: root)
        let content = "alpha中文中间omega%_tail"

        storage.saveItem(type: .text, content: content, size: content.utf8.count)
        let item = try XCTUnwrap(storage.getListItems(limit: 1).first)
        storage.setFavorite(id: item.id, isFavorite: true)

        for query in ["pha", "中间", "%_"] {
            XCTAssertEqual(storage.searchListItems(query: query).first?.id, item.id)
            XCTAssertEqual(storage.searchFavoriteListItems(query: query).first?.id, item.id)
        }
    }

    func testSearchPreservesMultiTermMatchingAcrossSeparatedWords() throws {
        let root = makeTemporaryDirectory()
        let storage = ClipboardStorageManager(storageDirectory: root)
        let content = "alpha has text between omega"

        storage.saveItem(type: .text, content: content, size: content.utf8.count)
        let item = try XCTUnwrap(storage.getListItems(limit: 1).first)

        XCTAssertEqual(storage.searchListItems(query: "alpha omega").first?.id, item.id)
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

    func testFavoriteItemsAppearInFavoritesAndRemainInHistory() throws {
        let root = makeTemporaryDirectory()
        let storage = ClipboardStorageManager(storageDirectory: root)

        storage.saveItem(type: .text, content: "favorite token", size: 14)
        storage.saveItem(type: .text, content: "regular token", size: 13)

        let favorite = try XCTUnwrap(storage.searchListItems(query: "favorite").first)
        storage.setFavorite(id: favorite.id, isFavorite: true)

        XCTAssertEqual(storage.searchFavoriteListItems(query: "favorite").first?.id, favorite.id)
        XCTAssertTrue(try XCTUnwrap(storage.getItem(id: favorite.id)).isFavorite)

        storage.setFavorite(id: favorite.id, isFavorite: false)

        XCTAssertTrue(storage.searchFavoriteListItems(query: "favorite").isEmpty)
        XCTAssertEqual(storage.searchListItems(query: "favorite").first?.id, favorite.id)
        XCTAssertFalse(try XCTUnwrap(storage.getItem(id: favorite.id)).isFavorite)
    }

    func testCombinedSearchIncludesFavoriteOutsideGeneralResultLimitWithoutDuplicates() throws {
        let root = makeTemporaryDirectory()
        let storage = ClipboardStorageManager(storageDirectory: root)

        for index in 0..<60 {
            let content = "shared search token regular \(index)"
            storage.saveItem(type: .text, content: content, size: content.utf8.count)
        }
        let favoriteContent = "shared search token favorite"
        storage.saveItem(type: .text, content: favoriteContent, size: favoriteContent.utf8.count)
        let favorite = try XCTUnwrap(storage.searchListItems(query: "favorite").first)
        storage.setFavorite(id: favorite.id, isFavorite: true)

        let results = storage.searchHistoryAndFavoriteListItems(query: "shared", limit: 50)

        XCTAssertTrue(results.contains { $0.id == favorite.id })
        XCTAssertEqual(Set(results.map(\.id)).count, results.count)
    }

    func testPinnedFavoritesSortBeforeUnpinnedFavorites() throws {
        let root = makeTemporaryDirectory()
        let storage = ClipboardStorageManager(storageDirectory: root)

        storage.saveItem(type: .text, content: "older favorite", size: 14)
        storage.saveItem(type: .text, content: "newer favorite", size: 14)

        let older = try XCTUnwrap(storage.searchListItems(query: "older").first)
        let newer = try XCTUnwrap(storage.searchListItems(query: "newer").first)
        storage.setFavorite(id: older.id, isFavorite: true)
        storage.setFavorite(id: newer.id, isFavorite: true)
        storage.setPinned(id: older.id, isPinned: true)

        let favorites = storage.getFavoriteListItems(limit: 10)
        XCTAssertEqual(favorites.first?.id, older.id)
        XCTAssertTrue(try XCTUnwrap(favorites.first).isPinned)
    }

    func testRemovingFavoriteClearsPinnedStateButKeepsHistory() throws {
        let root = makeTemporaryDirectory()
        let storage = ClipboardStorageManager(storageDirectory: root)

        storage.saveItem(type: .text, content: "pinned favorite", size: 15)

        let item = try XCTUnwrap(storage.searchListItems(query: "pinned").first)
        storage.setFavorite(id: item.id, isFavorite: true)
        storage.setPinned(id: item.id, isPinned: true)
        storage.setFavorite(id: item.id, isFavorite: false)

        let fullItem = try XCTUnwrap(storage.getItem(id: item.id))
        XCTAssertFalse(fullItem.isFavorite)
        XCTAssertFalse(fullItem.isPinned)
        XCTAssertEqual(storage.searchListItems(query: "pinned").first?.id, item.id)
    }

    func testClearHistoryKeepsFavoriteItems() throws {
        let root = makeTemporaryDirectory()
        let storage = ClipboardStorageManager(storageDirectory: root)

        storage.saveItem(type: .text, content: "keep me", size: 7)
        storage.saveItem(type: .text, content: "delete me", size: 9)

        let kept = try XCTUnwrap(storage.searchListItems(query: "keep").first)
        storage.setFavorite(id: kept.id, isFavorite: true)

        storage.clearHistory()

        let remaining = storage.getListItems(limit: 10)
        XCTAssertEqual(remaining.map(\.id), [kept.id])
        XCTAssertTrue(remaining[0].isFavorite)
    }

    func testLRUCleanupKeepsFavoritesOutsideHistoryLimit() throws {
        let root = makeTemporaryDirectory()
        let storage = ClipboardStorageManager(storageDirectory: root)
        storage.configureLimits(maxItemsCount: 1, maxImageStorageSizeMB: 1)

        storage.saveItem(type: .text, content: "favorite item", size: 13)
        let favorite = try XCTUnwrap(storage.searchListItems(query: "favorite").first)
        storage.setFavorite(id: favorite.id, isFavorite: true)
        storage.saveItem(type: .text, content: "older regular", size: 13)
        storage.saveItem(type: .text, content: "newer regular", size: 13)

        storage.enforceLimits()

        let remaining = storage.getListItems(limit: 10)
        XCTAssertTrue(remaining.contains { $0.id == favorite.id && $0.isFavorite })
        XCTAssertEqual(remaining.filter { !$0.isFavorite }.count, 1)
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryRoots.append(url)
        return url
    }
}
