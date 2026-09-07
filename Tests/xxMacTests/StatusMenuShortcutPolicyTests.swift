import XCTest
@testable import xxMac

final class StatusMenuShortcutPolicyTests: XCTestCase {
    func testClipboardMenuItemUsesClipboardHotKeyConfiguration() {
        let clipboardConfiguration = HotKeyConfiguration(
            key: .v,
            modifiers: [.command, .shift]
        )

        let resolved = StatusMenuShortcutPolicy.configuration(
            for: .clipboard,
            windowConfigurations: [:],
            clipboardConfiguration: clipboardConfiguration
        )

        XCTAssertEqual(resolved?.key, .v)
        XCTAssertEqual(resolved?.modifiers, [.command, .shift])
    }
}
