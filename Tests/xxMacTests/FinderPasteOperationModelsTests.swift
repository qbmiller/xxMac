import XCTest
@testable import xxMac

final class FinderPasteOperationModelsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testCounterStartsAtOneAndAdvancesOnlyAfterSuccess() {
        var counter = DailyPasteCounter()
        let date = makeDate("2026-08-25T10:00:00Z")

        XCTAssertEqual(counter.nextNumber(on: date, calendar: calendar), 1)
        XCTAssertEqual(counter.nextNumber(on: date, calendar: calendar), 1)

        counter.recordSuccess(on: date, calendar: calendar)

        XCTAssertEqual(counter.nextNumber(on: date, calendar: calendar), 2)
    }

    func testCounterResetsWhenDayChanges() {
        let counter = DailyPasteCounter(dateKey: "20260825", nextValue: 18)

        XCTAssertEqual(
            counter.nextNumber(on: makeDate("2026-08-26T00:01:00Z"), calendar: calendar),
            1
        )
    }

    func testManualResetOnlyChangesSelectedCounter() {
        let date = makeDate("2026-08-25T10:00:00Z")
        var settings = FinderPasteOperationSettings(
            imageCounter: .init(dateKey: "20260825", nextValue: 9),
            textCounter: .init(dateKey: "20260825", nextValue: 4)
        )

        settings.imageCounter.reset(on: date, calendar: calendar)

        XCTAssertEqual(settings.imageCounter.nextNumber(on: date, calendar: calendar), 1)
        XCTAssertEqual(settings.textCounter.nextNumber(on: date, calendar: calendar), 4)
    }

    func testFilesAlwaysRouteToPathPaste() {
        let urls = [URL(fileURLWithPath: "/tmp/a.png")]

        XCTAssertEqual(
            FinderPasteRoutingPolicy.route(
                payload: .fileURLs(urls),
                isFinderFrontmost: false,
                settings: .init(imageEnabled: true, textEnabled: true)
            ),
            .pastePaths(urls)
        )
    }

    func testImageRequiresFinderAndImageSwitch() {
        let image = Data([1, 2, 3])

        XCTAssertEqual(route(.image(image), finder: false, image: true, text: true), .none)
        XCTAssertEqual(route(.image(image), finder: true, image: false, text: true), .none)
        XCTAssertEqual(route(.image(image), finder: true, image: true, text: false), .saveImage(image))
    }

    func testTextRequiresFinderAndTextSwitch() {
        XCTAssertEqual(route(.text("{}"), finder: false, image: true, text: true), .none)
        XCTAssertEqual(route(.text("{}"), finder: true, image: true, text: false), .none)
        XCTAssertEqual(route(.text("{}"), finder: true, image: false, text: true), .saveText("{}"))
    }

    private func route(
        _ payload: FinderPastePayload,
        finder: Bool,
        image: Bool,
        text: Bool
    ) -> FinderPasteRoute {
        FinderPasteRoutingPolicy.route(
            payload: payload,
            isFinderFrontmost: finder,
            settings: .init(imageEnabled: image, textEnabled: text)
        )
    }

    private func makeDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
