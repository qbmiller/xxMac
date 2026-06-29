import XCTest
@testable import xxMac

final class PreferencesStoreMigrationTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryRoots {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testMigratesKnownUserDefaultsKeysIntoPreferencesFile() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let configManager = makeConfigManager(defaults: defaults)

        defaults.set("zh-Hans", forKey: "AppLanguage")
        defaults.set(["/Applications"], forKey: "AppSearchPaths")
        defaults.set(Data([1, 2, 3]), forKey: "HotKeyConfigurations")
        defaults.set(["window.leftHalf"], forKey: "ClearedHotKeyActions")
        defaults.set("#123456", forKey: "LauncherAppearanceBackgroundHex")
        defaults.set(0.75, forKey: "LauncherAppearanceOpacity")
        defaults.set(1.1, forKey: "LauncherAppearanceSizeScale")
        defaults.set(0.85, forKey: "LauncherAppearanceTextScale")
        defaults.set(720.0, forKey: "LauncherAppearanceWidth")
        defaults.set(480.0, forKey: "LauncherAppearanceHeight")
        defaults.set(Data([4]), forKey: "AppLauncherShortcuts")
        defaults.set(Data([5]), forKey: "QuickShortcutItems")
        defaults.set(Data([6]), forKey: "ClipboardSettings")
        defaults.set(true, forKey: "ShortcutDetectiveEnabled")
        defaults.set(Data([7]), forKey: "SnippetSettings")
        defaults.set(Data([8]), forKey: "SnippetCollections")
        defaults.set(Data([9]), forKey: "SnippetEntries")
        defaults.set(false, forKey: "CalendarShowLunar")
        defaults.set(true, forKey: "CalendarShowWeekNumbers")
        defaults.set(2, forKey: "CalendarFirstWeekday")
        defaults.set("monthDay", forKey: "CalendarMenuBarIconStyle")
        defaults.set("Working", forKey: "LockAIStatusText")
        defaults.set(Data([10]), forKey: "AppSearchIndexCacheV1")

        let store = try PreferencesStore(
            configDirectoryManager: configManager,
            legacyDefaults: defaults
        )

        XCTAssertEqual(store.string(forKey: "AppLanguage"), "zh-Hans")
        XCTAssertEqual(store.stringArray(forKey: "AppSearchPaths"), ["/Applications"])
        XCTAssertEqual(store.data(forKey: "HotKeyConfigurations"), Data([1, 2, 3]))
        XCTAssertEqual(store.stringArray(forKey: "ClearedHotKeyActions"), ["window.leftHalf"])
        XCTAssertEqual(store.string(forKey: "LauncherAppearanceBackgroundHex"), "#123456")
        XCTAssertEqual(store.doubleObject(forKey: "LauncherAppearanceOpacity"), 0.75)
        XCTAssertEqual(store.doubleObject(forKey: "LauncherAppearanceSizeScale"), 1.1)
        XCTAssertEqual(store.doubleObject(forKey: "LauncherAppearanceTextScale"), 0.85)
        XCTAssertEqual(store.doubleObject(forKey: "LauncherAppearanceWidth"), 720.0)
        XCTAssertEqual(store.doubleObject(forKey: "LauncherAppearanceHeight"), 480.0)
        XCTAssertEqual(store.data(forKey: "AppLauncherShortcuts"), Data([4]))
        XCTAssertEqual(store.data(forKey: "QuickShortcutItems"), Data([5]))
        XCTAssertEqual(store.data(forKey: "ClipboardSettings"), Data([6]))
        XCTAssertEqual(store.boolObject(forKey: "ShortcutDetectiveEnabled"), true)
        XCTAssertEqual(store.data(forKey: "SnippetSettings"), Data([7]))
        XCTAssertEqual(store.data(forKey: "SnippetCollections"), Data([8]))
        XCTAssertEqual(store.data(forKey: "SnippetEntries"), Data([9]))
        XCTAssertEqual(store.boolObject(forKey: "CalendarShowLunar"), false)
        XCTAssertEqual(store.boolObject(forKey: "CalendarShowWeekNumbers"), true)
        XCTAssertEqual(store.intObject(forKey: "CalendarFirstWeekday"), 2)
        XCTAssertEqual(store.string(forKey: "CalendarMenuBarIconStyle"), "monthDay")
        XCTAssertEqual(store.string(forKey: "LockAIStatusText"), "Working")
        XCTAssertEqual(try Data(contentsOf: configManager.appSearchIndexURL), Data([10]))
    }

    func testExistingPreferencesFileWinsOverLegacyDefaults() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let configManager = makeConfigManager(defaults: defaults)
        let existing = FileBackedPreferences(fileURL: configManager.preferencesURL)
        existing.set("en", forKey: "AppLanguage")
        try existing.flush()
        defaults.set("zh-Hans", forKey: "AppLanguage")

        let store = try PreferencesStore(
            configDirectoryManager: configManager,
            legacyDefaults: defaults
        )

        XCTAssertEqual(store.string(forKey: "AppLanguage"), "en")
    }

    private func makeConfigManager(defaults: UserDefaults) -> ConfigDirectoryManager {
        let applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        temporaryRoots.append(applicationSupportURL)
        return ConfigDirectoryManager(
            defaults: defaults,
            fileManager: .default,
            applicationSupportURL: applicationSupportURL
        )
    }
}
