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
}
