import XCTest
@testable import xxMac

final class FinderPasteFileNamingTests: XCTestCase {
    private let directory = URL(fileURLWithPath: "/tmp/finder-paste", isDirectory: true)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testFormatsDateAndAtLeastThreeDigitNumber() {
        XCTAssertEqual(name(number: 1, extension: "png"), "20260825-001.png")
        XCTAssertEqual(name(number: 18, extension: "json"), "20260825-018.json")
        XCTAssertEqual(name(number: 1000, extension: nil), "20260825-1000")
    }

    func testUsesSecondsWhenBaseNameAlreadyExists() {
        let existing = Set(["20260825-001.png"])

        XCTAssertEqual(name(existing: existing), "20260825-001-1787623456.png")
    }

    func testUsesMillisecondsWhenSecondsNameAlsoExists() {
        let existing = Set([
            "20260825-001.png",
            "20260825-001-1787623456.png"
        ])

        XCTAssertEqual(name(existing: existing), "20260825-001-1787623456789.png")
    }

    func testUsesSmallestSuffixWhenAllTimestampNamesExist() {
        let existing = Set([
            "20260825-001.png",
            "20260825-001-1787623456.png",
            "20260825-001-1787623456789.png",
            "20260825-001-1787623456789-1.png"
        ])

        XCTAssertEqual(name(existing: existing), "20260825-001-1787623456789-2.png")
    }

    private func name(
        number: Int = 1,
        extension fileExtension: String? = "png",
        existing: Set<String> = []
    ) -> String {
        FinderPasteFileNamer.destinationURL(
            directory: directory,
            date: Date(timeIntervalSince1970: 1_787_623_456.789),
            number: number,
            fileExtension: fileExtension,
            calendar: calendar,
            fileExists: { existing.contains($0.lastPathComponent) }
        ).lastPathComponent
    }
}
