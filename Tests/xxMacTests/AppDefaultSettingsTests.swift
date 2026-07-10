import XCTest
@testable import xxMac

final class AppDefaultSettingsTests: XCTestCase {
    func testMenuBarDefaultsUseCalendarIcon() {
        XCTAssertTrue(AppDefaultSettings.General.showMenuBarItem)
        XCTAssertEqual(AppDefaultSettings.Calendar.menuBarDisplayMode, .calendar)
        XCTAssertEqual(AppDefaultSettings.Calendar.menuBarIconStyle, .weekdayDay)
    }

    func testLauncherHistoryKeepsOneHundredItemsByDefault() {
        XCTAssertEqual(AppDefaultSettings.LauncherHistory.maxItems, 100)
    }
}
