import XCTest
import HotKey
@testable import xxMac

final class ShortcutRegistryTests: XCTestCase {
    func testLauncherKeywordsAreTrimmedAndCaseInsensitive() {
        XCTAssertEqual(ShortcutRegistry.normalizedKeyword("  BM  "), "bm")
    }

    func testBrowserKeywordsConflictWithEachOther() {
        let registrations = [
            ShortcutRegistration(action: .browserBookmarks, trigger: .launcherKeyword("bm"))
        ]

        let conflict = ShortcutRegistry.conflict(
            for: .launcherKeyword(" BM "),
            action: .browserHistory,
            in: registrations
        )

        XCTAssertEqual(conflict?.action, .browserBookmarks)
    }

    func testBrowserKeywordConflictsWithQuickShortcut() {
        let id = UUID()
        let registrations = [
            ShortcutRegistration(action: .quickShortcut(id), trigger: .launcherKeyword("docs"))
        ]

        let conflict = ShortcutRegistry.conflict(
            for: .launcherKeyword("DOCS"),
            action: .browserBookmarks,
            in: registrations
        )

        XCTAssertEqual(conflict?.action, .quickShortcut(id))
    }

    func testKeyboardShortcutConflictsAcrossFeatures() {
        let configuration = HotKeyConfiguration(key: .space, modifiers: [.control, .option])
        let registrations = [
            ShortcutRegistration(action: .window(.toggleLauncher), trigger: .keyboard(configuration))
        ]

        let conflict = ShortcutRegistry.conflict(
            for: .keyboard(configuration),
            action: .clipboard,
            in: registrations
        )

        XCTAssertEqual(conflict?.action, .window(.toggleLauncher))
    }

    func testKeyboardAndLauncherKeywordDoNotConflict() {
        let registrations = [
            ShortcutRegistration(
                action: .window(.toggleLauncher),
                trigger: .keyboard(HotKeyConfiguration(key: .b, modifiers: [.command]))
            )
        ]

        XCTAssertNil(ShortcutRegistry.conflict(
            for: .launcherKeyword("b"),
            action: .browserBookmarks,
            in: registrations
        ))
    }
}
