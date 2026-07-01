import Foundation

struct ConfigDirectoryValidation {
    let isValid: Bool
    let message: String?

    static let valid = ConfigDirectoryValidation(isValid: true, message: nil)

    static func invalid(_ message: String) -> ConfigDirectoryValidation {
        ConfigDirectoryValidation(isValid: false, message: message)
    }
}

enum ConfigDirectoryError: LocalizedError {
    case invalidDirectory(String)
    case nestedDirectory

    var errorDescription: String? {
        switch self {
        case .invalidDirectory(let message):
            return message
        case .nestedDirectory:
            return "The new configuration directory cannot be inside the current configuration directory."
        }
    }
}

extension Notification.Name {
    static let configDirectoryDidChange = Notification.Name("ConfigDirectoryDidChange")
}

final class ConfigDirectoryManager: ObservableObject {
    static let directoryPathKey = "ConfigDirectoryPath"
    static let shared = ConfigDirectoryManager()

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let applicationSupportURL: URL

    @Published private(set) var currentDirectory: URL

    var defaultDirectory: URL {
        applicationSupportURL.appendingPathComponent("xxMac", isDirectory: true).standardizedFileURL
    }

    var manifestURL: URL {
        currentDirectory.appendingPathComponent("manifest.json")
    }

    var preferencesURL: URL {
        currentDirectory.appendingPathComponent("preferences.json")
    }

    var appSearchIndexURL: URL {
        currentDirectory.appendingPathComponent("app-search-index.json")
    }

    var clipboardDatabaseURL: URL {
        currentDirectory.appendingPathComponent("clipboard.db")
    }

    var clipboardImagesDirectoryURL: URL {
        currentDirectory.appendingPathComponent("clipboard_images", isDirectory: true)
    }

    var clipboardThumbnailsDirectoryURL: URL {
        currentDirectory.appendingPathComponent("clipboard_thumbnails", isDirectory: true)
    }

    var quickDirectoryURL: URL {
        currentDirectory.appendingPathComponent("quick", isDirectory: true)
    }

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.applicationSupportURL = applicationSupportURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

        if let savedPath = defaults.string(forKey: Self.directoryPathKey), !savedPath.isEmpty {
            currentDirectory = URL(fileURLWithPath: savedPath, isDirectory: true).standardizedFileURL
        } else {
            currentDirectory = self.applicationSupportURL
                .appendingPathComponent("xxMac", isDirectory: true)
                .standardizedFileURL
        }

        try? ensureDirectoryReady()
    }

    static func validateDirectory(_ url: URL, fileManager: FileManager = .default) -> ConfigDirectoryValidation {
        let standardized = url.standardizedFileURL
        let path = standardized.path

        if path == "/" || path == "/System" || path.hasPrefix("/System/") ||
            path == "/Library" || path == "/Applications" {
            return .invalid("The selected directory is a system location.")
        }

        if let bundlePath = Bundle.main.bundleURL.standardizedFileURL.path as String?,
           path == bundlePath || path.hasPrefix(bundlePath + "/") {
            return .invalid("The selected directory is inside the application bundle.")
        }

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                return .invalid("The selected path is not a directory.")
            }
        } else {
            do {
                try fileManager.createDirectory(at: standardized, withIntermediateDirectories: true)
            } catch {
                return .invalid(error.localizedDescription)
            }
        }

        let testURL = standardized.appendingPathComponent(".xxmac-write-test-\(UUID().uuidString)")
        do {
            try Data("ok".utf8).write(to: testURL, options: .atomic)
            _ = try Data(contentsOf: testURL)
            try fileManager.removeItem(at: testURL)
        } catch {
            try? fileManager.removeItem(at: testURL)
            return .invalid(error.localizedDescription)
        }

        return .valid
    }

    func setDirectory(_ url: URL) throws {
        try changeDirectory(to: url)
    }

    func changeDirectory(to url: URL) throws {
        let standardized = url.standardizedFileURL
        let validation = Self.validateDirectory(standardized, fileManager: fileManager)
        guard validation.isValid else {
            throw ConfigDirectoryError.invalidDirectory(validation.message ?? "Invalid config directory.")
        }

        let sourceDirectory = currentDirectory
        guard standardized.path != sourceDirectory.path else {
            try ensureDirectoryReady()
            return
        }
        guard !standardized.path.hasPrefix(sourceDirectory.path + "/") else {
            throw ConfigDirectoryError.nestedDirectory
        }

        try moveConfigData(from: sourceDirectory, to: standardized)

        currentDirectory = standardized
        defaults.set(standardized.path, forKey: Self.directoryPathKey)
        try ensureDirectoryReady()
    }

    func migrateRuntimeDirectory(to url: URL) throws {
        try PreferencesStore.shared.flush()
        AppSearchManager.shared.flushIndexCacheIfNeeded()
        ClipboardStorageManager.shared.prepareForDirectoryMigration()
        do {
            try changeDirectory(to: url)
            try PreferencesStore.shared.reload()
            ClipboardStorageManager.shared.reloadStorageDirectory()
            NotificationCenter.default.post(name: .configDirectoryDidChange, object: self)
        } catch {
            ClipboardStorageManager.shared.resumeAfterDirectoryMigration()
            throw error
        }
    }

    func resetToDefault() throws {
        try setDirectory(defaultDirectory)
    }

    private func ensureDirectoryReady() throws {
        try fileManager.createDirectory(at: currentDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: clipboardImagesDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: clipboardThumbnailsDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: quickDirectoryURL, withIntermediateDirectories: true)

        guard !fileManager.fileExists(atPath: manifestURL.path) else { return }

        let manifest = ConfigDirectoryManifest(
            version: 1,
            appName: "xxMac",
            createdAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    private func moveConfigData(from sourceDirectory: URL, to targetDirectory: URL) throws {
        try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

        let fileNames = [
            "manifest.json",
            "preferences.json",
            "app-search-index.json",
            "clipboard.db",
            "clipboard.db-wal",
            "clipboard.db-shm"
        ]

        for fileName in fileNames {
            let sourceURL = sourceDirectory.appendingPathComponent(fileName)
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            let targetURL = targetDirectory.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.copyItem(at: sourceURL, to: targetURL)
        }

        let sourceImagesURL = sourceDirectory.appendingPathComponent("clipboard_images", isDirectory: true)
        let targetImagesURL = targetDirectory.appendingPathComponent("clipboard_images", isDirectory: true)
        if fileManager.fileExists(atPath: sourceImagesURL.path) {
            if fileManager.fileExists(atPath: targetImagesURL.path) {
                try fileManager.removeItem(at: targetImagesURL)
            }
            try fileManager.copyItem(at: sourceImagesURL, to: targetImagesURL)
        } else {
            try fileManager.createDirectory(at: targetImagesURL, withIntermediateDirectories: true)
        }

        let sourceThumbnailsURL = sourceDirectory.appendingPathComponent("clipboard_thumbnails", isDirectory: true)
        let targetThumbnailsURL = targetDirectory.appendingPathComponent("clipboard_thumbnails", isDirectory: true)
        if fileManager.fileExists(atPath: sourceThumbnailsURL.path) {
            if fileManager.fileExists(atPath: targetThumbnailsURL.path) {
                try fileManager.removeItem(at: targetThumbnailsURL)
            }
            try fileManager.copyItem(at: sourceThumbnailsURL, to: targetThumbnailsURL)
        } else {
            try fileManager.createDirectory(at: targetThumbnailsURL, withIntermediateDirectories: true)
        }

        let sourceQuickURL = sourceDirectory.appendingPathComponent("quick", isDirectory: true)
        let targetQuickURL = targetDirectory.appendingPathComponent("quick", isDirectory: true)
        if fileManager.fileExists(atPath: sourceQuickURL.path) {
            if fileManager.fileExists(atPath: targetQuickURL.path) {
                try fileManager.removeItem(at: targetQuickURL)
            }
            try fileManager.copyItem(at: sourceQuickURL, to: targetQuickURL)
        } else {
            try fileManager.createDirectory(at: targetQuickURL, withIntermediateDirectories: true)
        }

        try fileManager.removeItem(at: sourceDirectory)
    }
}

private struct ConfigDirectoryManifest: Codable {
    let version: Int
    let appName: String
    let createdAt: Date
}
