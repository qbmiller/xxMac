import XCTest
@testable import xxMac

final class FileBackedPreferencesTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryRoots {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testPersistsSupportedValueTypes() throws {
        let store = FileBackedPreferences(fileURL: makePreferencesURL())

        store.set("zh-Hans", forKey: "AppLanguage")
        store.set(true, forKey: "ShortcutDetectiveEnabled")
        store.set(2, forKey: "CalendarFirstWeekday")
        store.set(0.82, forKey: "LauncherAppearanceOpacity")
        store.set(Data([1, 2, 3]), forKey: "HotKeyConfigurations")
        store.set(["/Applications"], forKey: "AppSearchPaths")
        try store.flush()

        let reloaded = FileBackedPreferences(fileURL: store.fileURL)

        XCTAssertEqual(reloaded.string(forKey: "AppLanguage"), "zh-Hans")
        XCTAssertEqual(reloaded.boolObject(forKey: "ShortcutDetectiveEnabled"), true)
        XCTAssertEqual(reloaded.intObject(forKey: "CalendarFirstWeekday"), 2)
        XCTAssertEqual(reloaded.doubleObject(forKey: "LauncherAppearanceOpacity"), 0.82)
        XCTAssertEqual(reloaded.data(forKey: "HotKeyConfigurations"), Data([1, 2, 3]))
        XCTAssertEqual(reloaded.stringArray(forKey: "AppSearchPaths"), ["/Applications"])
    }

    func testRemoveObjectPersistsDeletion() throws {
        let store = FileBackedPreferences(fileURL: makePreferencesURL())
        store.set("en", forKey: "AppLanguage")
        try store.flush()

        store.removeObject(forKey: "AppLanguage")
        try store.flush()

        let reloaded = FileBackedPreferences(fileURL: store.fileURL)
        XCTAssertNil(reloaded.string(forKey: "AppLanguage"))
    }

    func testInvalidJSONStartsEmptyWithoutOverwritingFile() throws {
        let url = makePreferencesURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{".utf8).write(to: url)

        let store = FileBackedPreferences(fileURL: url)

        XCTAssertNil(store.string(forKey: "AppLanguage"))
        XCTAssertEqual(String(data: try Data(contentsOf: url), encoding: .utf8), "{")
    }

    private func makePreferencesURL() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        temporaryRoots.append(root)
        return root.appendingPathComponent("preferences.json")
    }
}
