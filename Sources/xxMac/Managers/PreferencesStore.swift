import Foundation

final class PreferencesStore {
    static let shared = try! PreferencesStore()

    private let configDirectoryManager: ConfigDirectoryManager
    private let legacyDefaults: UserDefaults
    private var preferences: FileBackedPreferences

    init(
        configDirectoryManager: ConfigDirectoryManager = .shared,
        legacyDefaults: UserDefaults = .standard
    ) throws {
        self.configDirectoryManager = configDirectoryManager
        self.legacyDefaults = legacyDefaults
        self.preferences = FileBackedPreferences(fileURL: configDirectoryManager.preferencesURL)
        try migrateLegacyDefaultsIfNeeded()
    }

    func string(forKey key: String) -> String? {
        preferences.string(forKey: key)
    }

    func stringArray(forKey key: String) -> [String]? {
        preferences.stringArray(forKey: key)
    }

    func data(forKey key: String) -> Data? {
        preferences.data(forKey: key)
    }

    func boolObject(forKey key: String) -> Bool? {
        preferences.boolObject(forKey: key)
    }

    func intObject(forKey key: String) -> Int? {
        preferences.intObject(forKey: key)
    }

    func doubleObject(forKey key: String) -> Double? {
        preferences.doubleObject(forKey: key)
    }

    func set(_ value: String, forKey key: String) {
        preferences.set(value, forKey: key)
        try? preferences.flush()
    }

    func set(_ value: Bool, forKey key: String) {
        preferences.set(value, forKey: key)
        try? preferences.flush()
    }

    func set(_ value: Int, forKey key: String) {
        preferences.set(value, forKey: key)
        try? preferences.flush()
    }

    func set(_ value: Double, forKey key: String) {
        preferences.set(value, forKey: key)
        try? preferences.flush()
    }

    func set(_ value: Data, forKey key: String) {
        preferences.set(value, forKey: key)
        try? preferences.flush()
    }

    func set(_ value: [String], forKey key: String) {
        preferences.set(value, forKey: key)
        try? preferences.flush()
    }

    func removeObject(forKey key: String) {
        preferences.removeObject(forKey: key)
        try? preferences.flush()
    }

    func flush() throws {
        try preferences.flush()
    }

    func reload() throws {
        preferences = FileBackedPreferences(fileURL: configDirectoryManager.preferencesURL)
    }

    private func migrateLegacyDefaultsIfNeeded() throws {
        if !FileManager.default.fileExists(atPath: configDirectoryManager.preferencesURL.path) {
            migratePreferenceKeys()
            try preferences.flush()
        }

        if !FileManager.default.fileExists(atPath: configDirectoryManager.appSearchIndexURL.path),
           let data = legacyDefaults.data(forKey: "AppSearchIndexCacheV1") {
            try FileManager.default.createDirectory(
                at: configDirectoryManager.appSearchIndexURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: configDirectoryManager.appSearchIndexURL, options: .atomic)
        }
    }

    private func migratePreferenceKeys() {
        for key in Self.stringKeys {
            if let value = legacyDefaults.string(forKey: key) {
                preferences.set(value, forKey: key)
            }
        }

        for key in Self.stringArrayKeys {
            if let value = legacyDefaults.stringArray(forKey: key) {
                preferences.set(value, forKey: key)
            }
        }

        for key in Self.dataKeys {
            if let value = legacyDefaults.data(forKey: key) {
                preferences.set(value, forKey: key)
            }
        }

        for key in Self.boolKeys {
            if let value = legacyDefaults.object(forKey: key) as? Bool {
                preferences.set(value, forKey: key)
            }
        }

        for key in Self.intKeys {
            if let value = legacyDefaults.object(forKey: key) as? Int {
                preferences.set(value, forKey: key)
            }
        }

        for key in Self.doubleKeys {
            if legacyDefaults.object(forKey: key) != nil {
                preferences.set(legacyDefaults.double(forKey: key), forKey: key)
            }
        }
    }

    private static let stringKeys = [
        "AppLanguage",
        "LauncherAppearanceBackgroundHex",
        "CalendarMenuBarIconStyle",
        "LockAIStatusText"
    ]

    private static let stringArrayKeys = [
        "AppSearchPaths",
        "ClearedHotKeyActions"
    ]

    private static let dataKeys = [
        "HotKeyConfigurations",
        "AppLauncherShortcuts",
        "QuickShortcutItems",
        "ClipboardSettings",
        "SnippetSettings",
        "SnippetCollections",
        "SnippetEntries"
    ]

    private static let boolKeys = [
        "ShortcutDetectiveEnabled",
        "CalendarShowLunar",
        "CalendarShowWeekNumbers"
    ]

    private static let intKeys = [
        "CalendarFirstWeekday"
    ]

    private static let doubleKeys = [
        "LauncherAppearanceOpacity",
        "LauncherAppearanceSizeScale",
        "LauncherAppearanceTextScale",
        "LauncherAppearanceWidth",
        "LauncherAppearanceHeight"
    ]
}
