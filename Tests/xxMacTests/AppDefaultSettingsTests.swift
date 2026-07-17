import XCTest
@testable import xxMac

final class AppDefaultSettingsTests: XCTestCase {
    func testMenuBarDefaultsUseCalendarIcon() {
        XCTAssertTrue(AppDefaultSettings.General.showMenuBarItem)
        XCTAssertEqual(AppDefaultSettings.Calendar.menuBarDisplayMode, .calendar)
        XCTAssertEqual(AppDefaultSettings.Calendar.menuBarIconStyle, .weekdayDay)
    }

    func testLauncherHistoryKeepsOneHundredItemsByDefault() {
        XCTAssertEqual(AppDefaultSettings.LauncherHistory.maxItems, 100)
    }

    func testBrowserSearchDefaults() {
        XCTAssertTrue(AppDefaultSettings.BrowserSearch.isEnabled)
        XCTAssertEqual(AppDefaultSettings.BrowserSearch.bookmarkKeyword, "bm")
        XCTAssertEqual(AppDefaultSettings.BrowserSearch.historyKeyword, "bh")
    }

    func testClipboardDefaultsIncludeLocalOCR() {
        XCTAssertFalse(AppDefaultSettings.Clipboard.monitoringEnabled)
        XCTAssertTrue(AppDefaultSettings.Clipboard.manageImages)
        XCTAssertTrue(AppDefaultSettings.Clipboard.imageOCREnabled)
        XCTAssertEqual(AppDefaultSettings.Clipboard.maxHistoryItems, 1000)
        XCTAssertEqual(AppDefaultSettings.Clipboard.maxImageStorageSizeMB, 500)
    }

    func testLauncherAppearanceDefaults() {
        XCTAssertEqual(AppDefaultSettings.LauncherAppearance.backgroundHex, "#5C9AAF")
        XCTAssertEqual(AppDefaultSettings.LauncherAppearance.opacity, 0.78)
        XCTAssertEqual(AppDefaultSettings.LauncherAppearance.width, 760)
        XCTAssertEqual(AppDefaultSettings.LauncherAppearance.height, 328)
    }

    func testGeneralDefaults() {
        XCTAssertEqual(AppDefaultSettings.General.appLanguage, .english)
        XCTAssertEqual(
            AppDefaultSettings.General.appSearchPaths,
            ["/Applications", "/System/Applications", "/System/Library/CoreServices"]
        )
        XCTAssertFalse(AppDefaultSettings.General.shortcutDetectiveEnabled)
    }

    func testShortcutDefaults() {
        let pastePath = AppDefaultSettings.HotKeys.configurations[.pasteFinderPath]
        XCTAssertEqual(pastePath?.key, .v)
        XCTAssertEqual(pastePath?.modifiers, [.command, .shift])

        XCTAssertEqual(AppDefaultSettings.Snippets.hotKey.key, .x)
        XCTAssertEqual(AppDefaultSettings.Snippets.hotKey.modifiers, [.control, .option, .command])
    }

    func testQuickShortcutAndLockAIDefaults() {
        XCTAssertEqual(AppDefaultSettings.QuickShortcuts.shellPath, "/bin/zsh")
        XCTAssertFalse(AppDefaultSettings.QuickShortcuts.newItemEnabled)
        XCTAssertEqual(AppDefaultSettings.LockAI.statusText, "AI Working")
    }
}
