import XCTest
@testable import xxMac

final class KeymapDoubleTapProcessorTests: XCTestCase {
    func testTriggersOnSecondCommandReleaseWithinWindow() {
        var processor = KeymapDoubleTapProcessor(doubleTapWindow: 0.3)
        let start = Date(timeIntervalSince1970: 100)

        XCTAssertEqual(processor.process(commandDown: true, hasOtherModifiers: false, at: start), .none)
        XCTAssertEqual(processor.process(commandDown: false, hasOtherModifiers: false, at: start.addingTimeInterval(0.05)), .none)
        XCTAssertEqual(processor.process(commandDown: true, hasOtherModifiers: false, at: start.addingTimeInterval(0.15)), .none)
        XCTAssertEqual(processor.process(commandDown: false, hasOtherModifiers: false, at: start.addingTimeInterval(0.2)), .triggered)
    }

    func testSlowTapsDoNotTrigger() {
        var processor = KeymapDoubleTapProcessor(doubleTapWindow: 0.3)
        let start = Date(timeIntervalSince1970: 100)

        _ = processor.process(commandDown: true, hasOtherModifiers: false, at: start)
        _ = processor.process(commandDown: false, hasOtherModifiers: false, at: start.addingTimeInterval(0.05))
        XCTAssertEqual(processor.process(commandDown: true, hasOtherModifiers: false, at: start.addingTimeInterval(0.5)), .none)
    }

    func testAddingAnotherModifierCancelsTapSequence() {
        var processor = KeymapDoubleTapProcessor(doubleTapWindow: 0.3)
        let start = Date(timeIntervalSince1970: 100)

        _ = processor.process(commandDown: true, hasOtherModifiers: false, at: start)
        _ = processor.process(commandDown: true, hasOtherModifiers: true, at: start.addingTimeInterval(0.05))
        _ = processor.process(commandDown: false, hasOtherModifiers: false, at: start.addingTimeInterval(0.1))
        XCTAssertEqual(processor.process(commandDown: true, hasOtherModifiers: false, at: start.addingTimeInterval(0.15)), .none)
    }

    func testKeyPressCancelsCommandTapSequence() {
        var processor = KeymapDoubleTapProcessor(doubleTapWindow: 0.3)
        let start = Date(timeIntervalSince1970: 100)

        _ = processor.process(commandDown: true, hasOtherModifiers: false, at: start)
        processor.cancel()
        XCTAssertEqual(processor.process(commandDown: false, hasOtherModifiers: false, at: start.addingTimeInterval(0.05)), .none)
        XCTAssertEqual(processor.process(commandDown: true, hasOtherModifiers: false, at: start.addingTimeInterval(0.1)), .none)
        XCTAssertEqual(processor.process(commandDown: false, hasOtherModifiers: false, at: start.addingTimeInterval(0.15)), .none)
    }
}
