import XCTest
@testable import xxMac

final class KeymapShortcutFormattingTests: XCTestCase {
    func testFormatsAccessibilityLowBitModifiers() {
        XCTAssertEqual(KeymapManager.formatShortcut(character: "w", modifiers: 1), "⌘W")
        XCTAssertEqual(KeymapManager.formatShortcut(character: "z", modifiers: 1 | 2), "⇧⌘Z")
    }

    func testFormatsNSEventRawModifiers() {
        let command = Int(NSEvent.ModifierFlags.command.rawValue)
        let shift = Int(NSEvent.ModifierFlags.shift.rawValue)
        XCTAssertEqual(KeymapManager.formatShortcut(character: "w", modifiers: command), "⌘W")
        XCTAssertEqual(KeymapManager.formatShortcut(character: "z", modifiers: command | shift), "⇧⌘Z")
    }

    func testFormatsCarbonModifierBits() {
        XCTAssertEqual(KeymapManager.formatShortcut(character: "p", modifiers: 256), "⌘P")
        XCTAssertEqual(KeymapManager.formatShortcut(character: "f", modifiers: 256 | 512), "⇧⌘F")
    }
}
