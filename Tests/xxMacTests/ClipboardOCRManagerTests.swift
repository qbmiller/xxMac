import XCTest
@testable import xxMac

final class ClipboardOCRManagerTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryRoots {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testRecognizeImageNowStoresRecognizedText() async throws {
        let root = makeTemporaryDirectory()
        let storage = ClipboardStorageManager(storageDirectory: root)
        storage.saveImageItem(content: "screen.png", size: 1024, width: nil, height: nil, thumbnailFilename: nil)
        let item = try XCTUnwrap(storage.getListItems().first)
        let manager = ClipboardOCRManager(
            recognizer: FakeOCRRecognizer(text: "receipt total 42"),
            storage: storage,
            notificationCenter: .default
        )

        await manager.recognizeImageNow(
            itemID: item.id,
            imageURL: storage.getImagePath(filename: "screen.png"),
            languages: ["en-US"]
        )

        let fullItem = try XCTUnwrap(storage.getItem(id: item.id))
        XCTAssertEqual(fullItem.imageOCRText, "receipt total 42")
        XCTAssertEqual(fullItem.imageOCRStatus, .ready)
        XCTAssertEqual(storage.searchListItems(query: "receipt").first?.id, item.id)
    }

    func testRecognizeImageNowStoresFailedStatusOnError() async throws {
        let root = makeTemporaryDirectory()
        let storage = ClipboardStorageManager(storageDirectory: root)
        storage.saveImageItem(content: "screen.png", size: 1024, width: nil, height: nil, thumbnailFilename: nil)
        let item = try XCTUnwrap(storage.getListItems().first)
        let manager = ClipboardOCRManager(
            recognizer: FakeOCRRecognizer(error: NSError(domain: "FakeOCR", code: 1)),
            storage: storage,
            notificationCenter: .default
        )

        await manager.recognizeImageNow(
            itemID: item.id,
            imageURL: storage.getImagePath(filename: "screen.png"),
            languages: ["en-US"]
        )

        let fullItem = try XCTUnwrap(storage.getItem(id: item.id))
        XCTAssertEqual(fullItem.imageOCRStatus, .failed)
        XCTAssertNil(fullItem.imageOCRText)
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryRoots.append(url)
        return url
    }
}

private struct FakeOCRRecognizer: ClipboardOCRRecognizing {
    let text: String
    let error: Error?

    init(text: String = "", error: Error? = nil) {
        self.text = text
        self.error = error
    }

    func recognizeText(in imageURL: URL, languages: [String]) async throws -> String {
        if let error {
            throw error
        }
        return text
    }
}
