import XCTest
@testable import xxMac

final class ClipboardModelsTests: XCTestCase {
    func testImageSearchableContentIncludesImageAliasesAndDescription() {
        let item = ClipboardItem(
            type: .image,
            content: "cached.png",
            timestamp: Date(),
            size: 1024
        )

        let searchableContent = item.searchableContent(imageDescription: "Image: 702x336 (694.3 KB)")

        XCTAssertTrue(searchableContent.contains("image"))
        XCTAssertTrue(searchableContent.contains("images"))
        XCTAssertTrue(searchableContent.contains("702x336"))
        XCTAssertTrue(searchableContent.contains("cached.png"))
    }

    func testTextSearchableContentOnlyUsesOriginalContent() {
        let item = ClipboardItem(
            type: .text,
            content: "project image note",
            timestamp: Date(),
            size: 18
        )

        XCTAssertEqual(item.searchableContent(), "project image note")
    }

    func testClipboardRecordsWhitespaceOnlyText() {
        XCTAssertTrue(ClipboardManager.shouldRecordText("   \n\t"))
    }

    func testClipboardSkipsOnlyEmptyText() {
        XCTAssertFalse(ClipboardManager.shouldRecordText(""))
    }

    func testClipboardCapturePrioritizesImageSnapshotOverText() {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])

        let payload = ClipboardCaptureDecision.payload(
            hasImage: true,
            imageData: imageData,
            fileURLs: [],
            text: "copied image description"
        )

        XCTAssertEqual(payload, .image(imageData))
    }

    func testClipboardCaptureRetriesWhenAdvertisedImageDataIsUnavailable() {
        let payload = ClipboardCaptureDecision.payload(
            hasImage: true,
            imageData: nil,
            fileURLs: [],
            text: "copied image description"
        )

        XCTAssertEqual(payload, .imagePending)
    }

    func testClipboardCapturePrioritizesImageDataOverFileURLs() {
        let fileURL = URL(fileURLWithPath: "/tmp/WebGLPipeline.7z")

        let payload = ClipboardCaptureDecision.payload(
            hasImage: true,
            imageData: Data([0x49, 0x49, 0x2A, 0x00]),
            fileURLs: [fileURL],
            text: "WebGLPipeline.7z"
        )

        XCTAssertEqual(payload, .image(Data([0x49, 0x49, 0x2A, 0x00])))
    }

    func testClipboardCaptureUsesFileURLsWhenImageDataIsUnavailable() {
        let fileURL = URL(fileURLWithPath: "/tmp/WebGLPipeline.png")

        let payload = ClipboardCaptureDecision.payload(
            hasImage: true,
            imageData: nil,
            fileURLs: [fileURL],
            text: "WebGLPipeline.png"
        )

        XCTAssertEqual(payload, .fileURLs([fileURL]))
    }

    func testClipboardCaptureFallsBackToTextWithoutImage() {
        let payload = ClipboardCaptureDecision.payload(
            hasImage: false,
            imageData: nil,
            fileURLs: [],
            text: "plain text"
        )

        XCTAssertEqual(payload, .text("plain text"))
    }

    func testClipboardLocalOCRIsEnabledByDefault() {
        XCTAssertTrue(ClipboardSettings().imageOCREnabled)
    }

    func testClipboardSettingsWithoutOCRFieldEnablesLocalOCR() throws {
        let settings = try JSONDecoder().decode(ClipboardSettings.self, from: Data("{}".utf8))

        XCTAssertTrue(settings.imageOCREnabled)
    }

    func testClipboardSettingsWithoutPreviewFontSizeUsesDefault() throws {
        let settings = try JSONDecoder().decode(ClipboardSettings.self, from: Data("{}".utf8))

        XCTAssertEqual(settings.previewFontSize, AppDefaultSettings.Clipboard.previewFontSize)
    }

    func testClipboardSettingsClampsPreviewFontSize() throws {
        let small = try JSONDecoder().decode(ClipboardSettings.self, from: Data(#"{"previewFontSize":2}"#.utf8))
        let large = try JSONDecoder().decode(ClipboardSettings.self, from: Data(#"{"previewFontSize":80}"#.utf8))

        XCTAssertEqual(small.previewFontSize, AppDefaultSettings.Clipboard.previewFontSizeRange.lowerBound)
        XCTAssertEqual(large.previewFontSize, AppDefaultSettings.Clipboard.previewFontSizeRange.upperBound)
    }

    func testClipboardSettingsPreservesExplicitlyDisabledLocalOCR() throws {
        let json = #"{"imageOCREnabled":false}"#
        let settings = try JSONDecoder().decode(ClipboardSettings.self, from: Data(json.utf8))

        XCTAssertFalse(settings.imageOCREnabled)
    }

    func testFinderFilePathUsesFullPath() {
        let urls = [URL(fileURLWithPath: "/Users/test/Documents/report.txt")]

        XCTAssertEqual(FilePathPasteManager.pathText(for: urls), "/Users/test/Documents/report.txt")
    }

    func testFinderCopyUsesOnlyFileName() {
        let urls = [URL(fileURLWithPath: "/Users/test/Documents/report.txt")]

        XCTAssertEqual(FilePathPasteManager.nameText(for: urls), "report.txt")
    }

    func testFinderFilePathShellEscapesSpaces() {
        let urls = [URL(fileURLWithPath: "/Users/test/My Folder/report.txt")]

        XCTAssertEqual(FilePathPasteManager.pathText(for: urls), "'/Users/test/My Folder/report.txt'")
    }

    func testMultipleFinderPathsAreRecordedTogether() {
        let urls = [
            URL(fileURLWithPath: "/Users/test/one.txt"),
            URL(fileURLWithPath: "/Users/test/Folder Two")
        ]

        XCTAssertEqual(
            FilePathPasteManager.pathText(for: urls),
            "/Users/test/one.txt '/Users/test/Folder Two'"
        )
    }

    func testMultipleFinderNamesAreRecordedTogether() {
        let urls = [
            URL(fileURLWithPath: "/Users/test/one.txt"),
            URL(fileURLWithPath: "/Users/test/Folder Two")
        ]

        XCTAssertEqual(FilePathPasteManager.nameText(for: urls), "one.txt 'Folder Two'")
    }
}
