import XCTest
@testable import xxMac

final class TodoPreferencesStoreTests: XCTestCase {
    private var temporaryRoot: URL!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoPreferencesStoreTests-\(UUID().uuidString)", isDirectory: true)
        defaults = UserDefaults(suiteName: "TodoPreferencesStoreTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        defaults = nil
        temporaryRoot = nil
    }

    func testFontSizePersistsAndClampsToSupportedRange() throws {
        let preferences = try makePreferencesStore()
        let todo = TodoPreferencesStore(preferences: preferences)

        todo.fontSize = 40

        XCTAssertEqual(todo.fontSize, AppDefaultSettings.Todo.fontSizeRange.upperBound)
        XCTAssertEqual(
            preferences.intObject(forKey: "TodoFontSize"),
            AppDefaultSettings.Todo.fontSizeRange.upperBound
        )
    }

    private func makePreferencesStore() throws -> PreferencesStore {
        let manager = ConfigDirectoryManager(
            defaults: defaults,
            applicationSupportURL: temporaryRoot
        )
        return try PreferencesStore(configDirectoryManager: manager, legacyDefaults: defaults)
    }
}
