import XCTest
@testable import xxMac

final class MenuBarVisibilityPolicyTests: XCTestCase {
    func testCreatesStatusItemWhenShowingWithoutExistingItem() {
        XCTAssertEqual(
            MenuBarVisibilityPolicy.action(
                shouldShow: true,
                hasStatusItem: false,
                recreateWhenShowing: false
            ),
            .create
        )
    }

    func testRecreatesExistingStatusItemWhenSettingsToggleTurnsShowingBackOn() {
        XCTAssertEqual(
            MenuBarVisibilityPolicy.action(
                shouldShow: true,
                hasStatusItem: true,
                recreateWhenShowing: true
            ),
            .recreate
        )
    }

    func testShowsExistingStatusItemWhenRefreshingWithoutRecreateRequest() {
        XCTAssertEqual(
            MenuBarVisibilityPolicy.action(
                shouldShow: true,
                hasStatusItem: true,
                recreateWhenShowing: false
            ),
            .showExisting
        )
    }

    func testHidesExistingStatusItemWhenPreferenceIsOff() {
        XCTAssertEqual(
            MenuBarVisibilityPolicy.action(
                shouldShow: false,
                hasStatusItem: true,
                recreateWhenShowing: false
            ),
            .hide
        )
    }

    func testDoesNothingWhenHiddenAndNoStatusItemExists() {
        XCTAssertEqual(
            MenuBarVisibilityPolicy.action(
                shouldShow: false,
                hasStatusItem: false,
                recreateWhenShowing: false
            ),
            .none
        )
    }
}
