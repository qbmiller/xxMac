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

    func testResizeClampsTopAndRightEdgesToVisibleFrame() {
        let currentFrame = NSRect(x: 1_500, y: 1_000, width: 600, height: 100)
        let visibleFrame = NSRect(x: 0, y: 25, width: 1_920, height: 1_055)

        let resizedFrame = LauncherPanelFramePolicy.resizedFrame(
            currentFrame: currentFrame,
            newSize: NSSize(width: 800, height: 400),
            preserveVisiblePosition: true,
            visibleFrame: visibleFrame
        )

        XCTAssertLessThanOrEqual(resizedFrame.maxX, visibleFrame.maxX)
        XCTAssertLessThanOrEqual(resizedFrame.maxY, visibleFrame.maxY)
        XCTAssertGreaterThanOrEqual(resizedFrame.minX, visibleFrame.minX)
        XCTAssertGreaterThanOrEqual(resizedFrame.minY, visibleFrame.minY)
    }

    func testHiddenLauncherResizeClampsStoredOriginWhenOffscreen() {
        let currentFrame = NSRect(x: 1_500, y: 1_000, width: 600, height: 100)
        let visibleFrame = NSRect(x: 0, y: 25, width: 1_920, height: 1_055)

        let resizedFrame = LauncherPanelFramePolicy.resizedFrame(
            currentFrame: currentFrame,
            newSize: NSSize(width: 800, height: 400),
            preserveVisiblePosition: false,
            visibleFrame: visibleFrame
        )

        XCTAssertLessThanOrEqual(resizedFrame.maxX, visibleFrame.maxX)
        XCTAssertLessThanOrEqual(resizedFrame.maxY, visibleFrame.maxY)
        XCTAssertGreaterThanOrEqual(resizedFrame.minX, visibleFrame.minX)
        XCTAssertGreaterThanOrEqual(resizedFrame.minY, visibleFrame.minY)
    }

    func testHiddenLauncherResizeKeepsStoredOriginWhenAlreadyVisible() {
        let currentFrame = NSRect(x: 100, y: 500, width: 600, height: 100)

        let resizedFrame = LauncherPanelFramePolicy.resizedFrame(
            currentFrame: currentFrame,
            newSize: NSSize(width: 800, height: 400),
            preserveVisiblePosition: false
        )

        XCTAssertEqual(resizedFrame.origin, currentFrame.origin)
    }

    func testResizeCycleKeepsTopCenterAnchor() {
        let visibleFrame = NSRect(x: 0, y: 25, width: 1_920, height: 1_055)
        let anchor = NSPoint(x: 960, y: 980)
        let largeSize = NSSize(width: 800, height: 400)
        let smallSize = NSSize(width: 800, height: 100)

        let largeFrame = NSRect(
            x: anchor.x - largeSize.width / 2,
            y: anchor.y - largeSize.height,
            width: largeSize.width,
            height: largeSize.height
        )
        let smallFrame = LauncherPanelFramePolicy.resizedFrame(
            currentFrame: largeFrame,
            newSize: smallSize,
            preserveVisiblePosition: true,
            visibleFrame: visibleFrame
        )
        let restoredLargeFrame = NSRect(
            x: anchor.x - smallFrame.width / 2,
            y: anchor.y - smallFrame.height,
            width: smallFrame.width,
            height: smallFrame.height
        )
        let finalFrame = LauncherPanelFramePolicy.resizedFrame(
            currentFrame: restoredLargeFrame,
            newSize: largeSize,
            preserveVisiblePosition: true,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(smallFrame.midX, anchor.x, accuracy: 0.001)
        XCTAssertEqual(smallFrame.maxY, anchor.y, accuracy: 0.001)
        XCTAssertEqual(finalFrame.midX, anchor.x, accuracy: 0.001)
        XCTAssertEqual(finalFrame.maxY, anchor.y, accuracy: 0.001)
    }
}
