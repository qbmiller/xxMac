import AppKit
import XCTest
@testable import xxMac

final class TodoWindowFramePolicyTests: XCTestCase {
    func testFrameStateStoresCompactAndBoardFramesIndependently() {
        let compact = NSRect(x: 100, y: 200, width: 820, height: 720)
        let board = NSRect(x: 40, y: 120, width: 1_240, height: 760)
        var state = TodoWindowFrameState()

        state.setFrame(compact, for: .compact)
        state.setFrame(board, for: .board)

        XCTAssertEqual(state.frame(for: .compact), compact)
        XCTAssertEqual(state.frame(for: .board), board)
    }

    func testClampingKeepsWindowInsideVisibleFrame() {
        let visibleFrame = NSRect(x: 100, y: 50, width: 1_200, height: 800)
        let offscreen = NSRect(x: 1_250, y: 760, width: 820, height: 720)

        let frame = TodoWindowFramePolicy.clamped(offscreen, to: visibleFrame)

        XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX)
        XCTAssertGreaterThanOrEqual(frame.minY, visibleFrame.minY)
        XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX)
        XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY)
    }

    func testClampingShrinksBoardToSmallVisibleFrame() {
        let visibleFrame = NSRect(x: 0, y: 25, width: 900, height: 650)
        let board = NSRect(x: -200, y: -100, width: 1_240, height: 720)

        let frame = TodoWindowFramePolicy.clamped(board, to: visibleFrame)

        XCTAssertEqual(frame, visibleFrame)
    }

    func testDefaultFramesUseModeSpecificSizesAndCenter() {
        let visibleFrame = NSRect(x: 100, y: 50, width: 1_600, height: 1_000)

        let compact = TodoWindowFramePolicy.defaultFrame(for: .compact, in: visibleFrame)
        let board = TodoWindowFramePolicy.defaultFrame(for: .board, in: visibleFrame)

        XCTAssertEqual(compact.size, TodoWindowFramePolicy.compactSize)
        XCTAssertEqual(board.size, TodoWindowFramePolicy.boardSize)
        XCTAssertEqual(compact.midX, visibleFrame.midX, accuracy: 0.001)
        XCTAssertEqual(compact.midY, visibleFrame.midY, accuracy: 0.001)
        XCTAssertEqual(board.midX, visibleFrame.midX, accuracy: 0.001)
        XCTAssertEqual(board.midY, visibleFrame.midY, accuracy: 0.001)
    }
}
