import XCTest
@testable import xxMac

final class CalendarAlmanacTests: XCTestCase {
    private var resources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Almanac")
    }

    func testGeneratedNewYearLeapMonthAndYearBoundary() throws {
        let store = CalendarAlmanacStore(directory: resources)
        let newYear = try XCTUnwrap(store.entry(forKey: "2026-02-17"))
        XCTAssertEqual(newYear.lunarMonth, 1)
        XCTAssertEqual(newYear.lunarDay, 1)
        XCTAssertFalse(newYear.isLeap)
        let leap = try XCTUnwrap(store.entry(forKey: "2025-07-25"))
        XCTAssertEqual(leap.lunarMonth, 6)
        XCTAssertEqual(leap.lunarDay, 1)
        XCTAssertTrue(leap.isLeap)
        XCTAssertNotNil(store.entry(forKey: "2026-12-31"))
        XCTAssertNotNil(store.entry(forKey: "2027-01-01"))
        XCTAssertNotNil(store.entry(forKey: "2099-12-31"))
        XCTAssertNil(store.entry(forKey: "2100-01-01"))
        XCTAssertNil(store.entry(forKey: "1901-02-18"))
        XCTAssertNotNil(store.entry(forKey: "1901-02-19"))
        XCTAssertNil(store.entry(forKey: "2101-01-01"))
    }

    func testQueryUsesCalendarLocalDay() throws {
        let store = CalendarAlmanacStore(directory: resources)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = ISO8601DateFormatter().date(from: "2026-02-18T07:30:00Z")!
        XCTAssertEqual(store.entry(for: date, calendar: calendar)?.lunarDay, 1)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        XCTAssertEqual(store.entry(for: date, calendar: calendar)?.lunarDay, 2)
    }

    func testSolarTermAndPopulatedDetails() throws {
        let entry = try XCTUnwrap(CalendarAlmanacStore(directory: resources).entry(forKey: "2026-02-04"))
        XCTAssertEqual(entry.solarTerm, "立春")
        XCTAssertFalse(entry.pillars.isEmpty)
        XCTAssertFalse(entry.good.isEmpty && entry.bad.isEmpty)
        XCTAssertFalse(entry.god.isEmpty)
        XCTAssertFalse(entry.peng.isEmpty)
    }

    func testCivilDayQueryDoesNotUseBuddhistEraAsResourceYear() throws {
        let store = CalendarAlmanacStore(directory: resources)
        var calendar = Calendar(identifier: .buddhist)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let date = ISO8601DateFormatter().date(from: "2026-02-17T04:00:00Z")!
        XCTAssertEqual(store.entry(for: date, calendar: calendar)?.lunarDay, 1)
    }

    func testMissingOrCorruptResourceReturnsNoData() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let store = CalendarAlmanacStore(directory: temp)
        XCTAssertNil(store.entry(forKey: "2026-11-25"))
        try Data("invalid".utf8).write(to: temp.appendingPathComponent("2027.json.deflate"))
        XCTAssertNil(store.entry(forKey: "2027-01-01"))
    }
}

final class CalendarAlmanacPlacementTests: XCTestCase {
    func testDetailStaysBesideCalendarAndWithinScreen() {
        let screen = CGRect(x: 0, y: 25, width: 1440, height: 850)
        let result = CalendarAlmanacPlacement.frames(parent: CGRect(x: 850, y: 100, width: 430, height: 650), screen: screen)
        XCTAssertEqual(result.parent.minX, 850)
        XCTAssertEqual(result.detail.maxX + 6, result.parent.minX)
        XCTAssertEqual(result.detail.maxY, result.parent.maxY - 12)
        XCTAssertTrue(screen.contains(result.detail))
    }

    func testGroupMovesRightAtLeftScreenEdgeAndWorksOnNegativeOriginMonitor() {
        let screen = CGRect(x: -1440, y: 25, width: 1440, height: 850)
        let result = CalendarAlmanacPlacement.frames(parent: CGRect(x: -1430, y: 100, width: 430, height: 650), screen: screen)
        XCTAssertEqual(result.detail.minX, screen.minX)
        XCTAssertEqual(result.detail.maxX + 6, result.parent.minX)
        XCTAssertTrue(screen.contains(result.detail))
        XCTAssertTrue(screen.contains(result.parent))
    }

    func testDetailClampsHeightOnSmallScreen() {
        let screen = CGRect(x: 0, y: 25, width: 800, height: 400)
        let result = CalendarAlmanacPlacement.frames(parent: CGRect(x: 500, y: -100, width: 430, height: 700), screen: screen)
        XCTAssertEqual(result.detail.height, 400)
        XCTAssertTrue(screen.contains(result.detail))
        XCTAssertLessThanOrEqual(result.parent.maxX, screen.maxX)
    }
}
