import Foundation
import XCTest
@testable import xxMac

final class WindowFrameWriterTests: XCTestCase {
    func testTopRightQuarterCanMoveToLeftHalfWhenResizeRepositionsWindow() {
        var actual = CGRect(x: 720, y: 25, width: 720, height: 437)
        let target = CGRect(x: 0, y: 25, width: 720, height: 874)

        WindowFrameWriter.apply(target, setSize: { size in
            actual.size = size
            // Model an application restoring the right edge during a resize.
            actual.origin.x = 1440 - size.width
        }, setPosition: { position in
            actual.origin = position
        })

        XCTAssertEqual(actual, target)
    }

    func testShrinkingBeforeMovingAvoidsScreenEdgeClamping() {
        var actual = CGRect(x: 0, y: 25, width: 1440, height: 874)
        let target = CGRect(x: 720, y: 462, width: 720, height: 437)

        WindowFrameWriter.apply(target, setSize: { size in
            actual.size = size
        }, setPosition: { position in
            // Model an application keeping its current size within the screen.
            actual.origin.x = min(position.x, 1440 - actual.width)
            actual.origin.y = min(position.y, 899 - actual.height)
        })

        XCTAssertEqual(actual, target)
    }
}
