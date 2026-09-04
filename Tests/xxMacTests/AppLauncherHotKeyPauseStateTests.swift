import XCTest
@testable import xxMac

final class AppLauncherHotKeyPauseStateTests: XCTestCase {
    func testHotKeysRemainPausedUntilEveryRecordingSessionEnds() {
        var state = AppLauncherHotKeyPauseState()

        let firstToken = state.pause()
        let secondToken = state.pause()

        XCTAssertTrue(state.isPaused)

        state.resume(firstToken)
        XCTAssertTrue(state.isPaused)

        state.resume(secondToken)
        XCTAssertFalse(state.isPaused)
    }

    func testUnknownPauseTokenDoesNotResumeActiveRecordingSession() {
        var state = AppLauncherHotKeyPauseState()
        _ = state.pause()

        state.resume(UUID())

        XCTAssertTrue(state.isPaused)
    }
}
