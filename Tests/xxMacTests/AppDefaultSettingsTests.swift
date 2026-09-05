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
        XCTAssertFalse(AppDefaultSettings.Clipboard.imagePasteToFileEnabled)
        XCTAssertFalse(AppDefaultSettings.Clipboard.textPasteToFileEnabled)
        XCTAssertEqual(AppDefaultSettings.Clipboard.maxHistoryItems, 1000)
        XCTAssertEqual(AppDefaultSettings.Clipboard.maxImageStorageSizeMB, 500)
        XCTAssertEqual(AppDefaultSettings.Clipboard.previewFontSize, 16)
    }

    func testLauncherAppearanceDefaults() {
        XCTAssertEqual(AppDefaultSettings.LauncherAppearance.backgroundHex, "#5C9AAF")
        XCTAssertEqual(AppDefaultSettings.LauncherAppearance.opacity, 0.78)
        XCTAssertEqual(AppDefaultSettings.LauncherAppearance.width, 760)
        XCTAssertEqual(AppDefaultSettings.LauncherAppearance.height, 328)
    }

    func testGeneralDefaults() {
        XCTAssertEqual(AppDefaultSettings.General.appLanguage, .english)
        XCTAssertFalse(AppDefaultSettings.General.launcherDefaultsToEnglishInput)
        XCTAssertEqual(
            AppDefaultSettings.General.appSearchPaths,
            ["/Applications", "/System/Applications", "/System/Library/CoreServices"]
        )
        XCTAssertFalse(AppDefaultSettings.General.shortcutDetectiveEnabled)
    }

    func testTodoDefaultsAndSettingsNavigationAreRegistered() {
        XCTAssertEqual(AppDefaultSettings.Todo.selectedView, .quadrants)
        XCTAssertEqual(AppDefaultSettings.Todo.listLayout, .cards)
        XCTAssertFalse(AppDefaultSettings.Todo.hideCompletedInQuadrants)

        let todoTool = ToolOption.allTools.first { $0.type == .todo }
        XCTAssertEqual(todoTool?.functions.map(\.type), [.todoGeneral])
    }

    func testShortcutDefaults() {
        let pastePath = AppDefaultSettings.HotKeys.configurations[.pasteFinderPath]
        XCTAssertEqual(pastePath?.key, .v)
        XCTAssertEqual(pastePath?.modifiers, [.command, .shift])

        let todo = AppDefaultSettings.HotKeys.configurations[.toggleTodo]
        XCTAssertEqual(todo?.key, .t)
        XCTAssertEqual(todo?.modifiers, [.command, .option])

        XCTAssertEqual(AppDefaultSettings.Snippets.hotKey.key, .x)
        XCTAssertEqual(AppDefaultSettings.Snippets.hotKey.modifiers, [.control, .option, .command])
    }

    func testOldHotKeyConfigurationsBackfillTodoUnlessUserClearedIt() {
        let saved: [WindowAction: HotKeyConfiguration] = [
            .toggleLauncher: HotKeyConfiguration(key: .space, modifiers: [.control, .option])
        ]

        let backfilled = HotKeyManager.backfilledConfigurations(saved, clearedActions: [])
        let explicitlyCleared = HotKeyManager.backfilledConfigurations(
            saved,
            clearedActions: [WindowAction.toggleTodo.rawValue]
        )

        XCTAssertEqual(backfilled[.toggleTodo]?.key, .t)
        XCTAssertEqual(backfilled[.toggleTodo]?.modifiers, [.command, .option])
        XCTAssertNil(explicitlyCleared[.toggleTodo])
    }

    func testQuickShortcutAndLockAIDefaults() {
        XCTAssertEqual(AppDefaultSettings.QuickShortcuts.shellPath, "/bin/zsh")
        XCTAssertFalse(AppDefaultSettings.QuickShortcuts.newItemEnabled)
        XCTAssertEqual(AppDefaultSettings.LockAI.statusText, "AI Working")
    }
}
