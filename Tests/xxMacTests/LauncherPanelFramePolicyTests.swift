import AppKit
import XCTest
@testable import xxMac

final class LauncherPanelFramePolicyTests: XCTestCase {
    func testVisibleLauncherResizeKeepsUserPositionedTopCenter() {
        let currentFrame = NSRect(x: 100, y: 500, width: 600, height: 100)

        let resizedFrame = LauncherPanelFramePolicy.resizedFrame(
            currentFrame: currentFrame,
            newSize: NSSize(width: 800, height: 400),
            preserveVisiblePosition: true
        )

        XCTAssertEqual(resizedFrame.midX, currentFrame.midX)
        XCTAssertEqual(resizedFrame.maxY, currentFrame.maxY)
        XCTAssertEqual(resizedFrame.size, NSSize(width: 800, height: 400))
    }

    func testHiddenLauncherResizeKeepsStoredOrigin() {
        let currentFrame = NSRect(x: 100, y: 500, width: 600, height: 100)

        let resizedFrame = LauncherPanelFramePolicy.resizedFrame(
            currentFrame: currentFrame,
            newSize: NSSize(width: 800, height: 400),
            preserveVisiblePosition: false
        )

        XCTAssertEqual(resizedFrame.origin, currentFrame.origin)
    }
}
