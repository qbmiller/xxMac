import XCTest
@testable import xxMac

final class MenuBarVisibilityPolicyTests: XCTestCase {
    func testCreatesStatusItemWhenShowingWithoutExistingItem() {
        XCTAssertEqual(
            MenuBarVisibilityPolicy.action(
                shouldShow: true,
                hasStatusItem: false
            ),
            .create
        )
    }

    func testShowsExistingStatusItemWhenRefreshing() {
        XCTAssertEqual(
            MenuBarVisibilityPolicy.action(
                shouldShow: true,
                hasStatusItem: true
            ),
            .showExisting
        )
    }

    func testHidesExistingStatusItemWhenPreferenceIsOff() {
        XCTAssertEqual(
            MenuBarVisibilityPolicy.action(
                shouldShow: false,
                hasStatusItem: true
            ),
            .hide
        )
    }

    func testDoesNothingWhenHiddenAndNoStatusItemExists() {
        XCTAssertEqual(
            MenuBarVisibilityPolicy.action(
                shouldShow: false,
                hasStatusItem: false
            ),
            .none
        )
    }
}
