import XCTest
@testable import xxMac

final class ClipboardFocusRestorationPolicyTests: XCTestCase {
    func testWaitsWhileCapturedApplicationIsNotFrontmost() {
        XCTAssertEqual(
            ClipboardFocusRestorationPolicy.action(
                targetPID: 101,
                frontmostPID: 202,
                retriesRemaining: 3
            ),
            .wait
        )
    }

    func testRestoresWhenCapturedApplicationIsFrontmost() {
        XCTAssertEqual(
            ClipboardFocusRestorationPolicy.action(
                targetPID: 101,
                frontmostPID: 101,
                retriesRemaining: 3
            ),
            .restoreTextInput
        )
    }

    func testRestoresAsFallbackWhenNoCapturedApplicationExists() {
        XCTAssertEqual(
            ClipboardFocusRestorationPolicy.action(
                targetPID: nil,
                frontmostPID: 202,
                retriesRemaining: 3
            ),
            .restoreTextInput
        )
    }

    func testRestoresAsFallbackAfterRetriesAreExhausted() {
        XCTAssertEqual(
            ClipboardFocusRestorationPolicy.action(
                targetPID: 101,
                frontmostPID: 202,
                retriesRemaining: 0
            ),
            .restoreTextInput
        )
    }
}
