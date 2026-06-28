import SwiftUI
import AppKit

struct CommonSettingsView: View {
    @ObservedObject private var appSearchManager = AppSearchManager.shared
    @ObservedObject private var configDirectoryManager = ConfigDirectoryManager.shared
    @State private var showingExportSuccess = false
    @State private var showingImportSuccess = false
    @State private var importError: String?
    @State private var configDirectoryError: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.t("common.manage_configurations"))
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 16) {
                // Global Hotkey Section
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("common.global_hotkey"))
                        .font(.headline)
                    Text(L10n.t("common.global_hotkey_desc"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text(L10n.t("common.toggle_launcher"))
                            .foregroundColor(.secondary)
                        
                        HotKeyRecorderView(action: .toggleLauncher)
                            .frame(maxWidth: 200)
                        
                        Spacer()
                    }
                    .padding(.top, 4)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )

                // App Index Section
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("common.app_index"))
                        .font(.headline)
                    Text(L10n.t("common.app_index_desc"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 10) {
                        Button {
                            appSearchManager.scanApplications()
                        } label: {
                            Label(L10n.t("common.index_apps"), systemImage: "arrow.clockwise")
                        }
                        .disabled(appSearchManager.isIndexing)

                        if appSearchManager.isIndexing {
                            ProgressView()
                                .controlSize(.small)
                            Text(L10n.t("common.indexing_apps"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text(L10n.f("common.indexed_apps_format", appSearchManager.apps.count))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.top, 4)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("common.config_directory"))
                        .font(.headline)
                    Text(L10n.t("common.config_directory_desc"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(configDirectoryManager.currentDirectory.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                        .padding(.top, 2)

                    HStack(spacing: 10) {
                        Button {
                            chooseConfigDirectory()
                        } label: {
                            Label(L10n.t("common.set_config_directory"), systemImage: "folder")
                        }

                        Button {
                            revealConfigDirectory()
                        } label: {
                            Label(L10n.t("common.reveal_config_directory"), systemImage: "arrow.up.forward.app")
                        }

                        Button {
                            resetConfigDirectory()
                        } label: {
                            Label(L10n.t("common.reset_config_directory"), systemImage: "arrow.counterclockwise")
                        }

                        Spacer()
                    }

                    if let configDirectoryError {
                        Text(configDirectoryError)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )

                // Export Section
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("common.backup_config"))
                        .font(.headline)
                    Text(L10n.t("common.backup_desc"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button(L10n.t("common.export_config")) {
                        exportConfiguration()
                    }
                    
                    if showingExportSuccess {
                        Text(L10n.t("common.export_success"))
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                
                // Import Section
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("common.restore_config"))
                        .font(.headline)
                    Text(L10n.t("common.restore_desc"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button(L10n.t("common.import_config")) {
                        importConfiguration()
                    }
                    
                    if showingImportSuccess {
                        Text(L10n.t("common.import_success"))
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                    
                    if let error = importError {
                        Text(L10n.f("common.error_format", error))
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            }
            
            Spacer()
        }
    }
    
    private func exportConfiguration() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = L10n.t("common.export_filename")
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let config = try collectConfigurations()
                let data = try JSONEncoder().encode(config)
                try data.write(to: url)
                
                showingExportSuccess = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    showingExportSuccess = false
                }
            } catch {
                print("Export failed: \(error)")
            }
        }
    }
    
    private func importConfiguration() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                let config = try JSONDecoder().decode(AppConfiguration.self, from: data)
                restoreConfigurations(config)
                
                showingImportSuccess = true
                importError = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    showingImportSuccess = false
                }
            } catch {
                importError = error.localizedDescription
            }
        }
    }
    
    // MARK: - Configuration Logic

    private func chooseConfigDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = configDirectoryManager.currentDirectory

        if panel.runModal() == .OK, let url = panel.url {
            applyConfigDirectory(url)
        }
    }

    private func revealConfigDirectory() {
        NSWorkspace.shared.activateFileViewerSelecting([configDirectoryManager.currentDirectory])
    }

    private func resetConfigDirectory() {
        applyConfigDirectory(configDirectoryManager.defaultDirectory)
    }

    private func applyConfigDirectory(_ url: URL) {
        do {
            try configDirectoryManager.migrateRuntimeDirectory(to: url)
            configDirectoryError = nil
        } catch {
            configDirectoryError = error.localizedDescription
        }
    }
    
    struct AppConfiguration: Codable {
        let appLanguage: String?
        let searchPaths: [String]?
        let hotKeyConfigurations: Data?
        let clearedHotKeyActions: [String]?
        let launcherAppearanceBackgroundHex: String?
        let launcherAppearanceOpacity: Double?
        let launcherAppearanceSizeScale: Double?
        let launcherAppearanceWidth: Double?
        let launcherAppearanceHeight: Double?
        let appLauncherShortcuts: Data?
        let quickShortcutItems: Data?
        let clipboardSettings: Data?
        let shortcutDetectiveEnabled: Bool?
        let snippetSettings: Data?
        let snippetCollections: Data?
        let snippetEntries: Data?
        let calendarShowLunar: Bool?
        let calendarShowWeekNumbers: Bool?
        let calendarFirstWeekday: Int?
        let calendarMenuBarIconStyle: String?
        let lockAIStatusText: String?
    }
    
    private func collectConfigurations() throws -> AppConfiguration {
        let store = PreferencesStore.shared
        
        return AppConfiguration(
            appLanguage: store.string(forKey: UserDefaultsKeys.appLanguage),
            searchPaths: store.stringArray(forKey: "AppSearchPaths"),
            hotKeyConfigurations: store.data(forKey: "HotKeyConfigurations"),
            clearedHotKeyActions: store.stringArray(forKey: "ClearedHotKeyActions"),
            launcherAppearanceBackgroundHex: store.string(forKey: "LauncherAppearanceBackgroundHex"),
            launcherAppearanceOpacity: store.doubleObject(forKey: "LauncherAppearanceOpacity"),
            launcherAppearanceSizeScale: store.doubleObject(forKey: "LauncherAppearanceSizeScale"),
            launcherAppearanceWidth: store.doubleObject(forKey: "LauncherAppearanceWidth"),
            launcherAppearanceHeight: store.doubleObject(forKey: "LauncherAppearanceHeight"),
            appLauncherShortcuts: store.data(forKey: "AppLauncherShortcuts"),
            quickShortcutItems: store.data(forKey: "QuickShortcutItems"),
            clipboardSettings: store.data(forKey: "ClipboardSettings"),
            shortcutDetectiveEnabled: store.boolObject(forKey: "ShortcutDetectiveEnabled"),
            snippetSettings: store.data(forKey: "SnippetSettings"),
            snippetCollections: store.data(forKey: "SnippetCollections"),
            snippetEntries: store.data(forKey: "SnippetEntries"),
            calendarShowLunar: store.boolObject(forKey: CalendarPreferencesKey.showLunar),
            calendarShowWeekNumbers: store.boolObject(forKey: CalendarPreferencesKey.showWeekNumbers),
            calendarFirstWeekday: store.intObject(forKey: CalendarPreferencesKey.firstWeekday),
            calendarMenuBarIconStyle: store.string(forKey: CalendarPreferencesKey.menuBarIconStyle),
            lockAIStatusText: store.string(forKey: "LockAIStatusText")
        )
    }
    
    private func restoreConfigurations(_ config: AppConfiguration) {
        let store = PreferencesStore.shared

        if let appLanguage = config.appLanguage,
           let language = AppLanguage(rawValue: appLanguage) {
            LocalizationManager.shared.language = language
        }
        
        if let paths = config.searchPaths {
            // AppSearchManager handles saving when property is set
            AppSearchManager.shared.searchPaths = paths
        }
        
        if let hotKeys = config.hotKeyConfigurations {
            store.set(hotKeys, forKey: "HotKeyConfigurations")
            if let clearedHotKeyActions = config.clearedHotKeyActions {
                store.set(clearedHotKeyActions, forKey: "ClearedHotKeyActions")
            }
            HotKeyManager.shared.loadConfigurations()
        }

        if let backgroundHex = config.launcherAppearanceBackgroundHex {
            LauncherAppearanceManager.shared.backgroundHex = backgroundHex
        }

        if let opacity = config.launcherAppearanceOpacity {
            LauncherAppearanceManager.shared.opacity = opacity
        }

        if let sizeScale = config.launcherAppearanceSizeScale {
            LauncherAppearanceManager.shared.sizeScale = sizeScale
        }

        if let width = config.launcherAppearanceWidth {
            LauncherAppearanceManager.shared.launcherWidth = width
        }

        if let height = config.launcherAppearanceHeight {
            LauncherAppearanceManager.shared.launcherHeight = height
        }
        
        if let shortcutsData = config.appLauncherShortcuts {
            if let decoded = try? JSONDecoder().decode([AppShortcut].self, from: shortcutsData) {
                 // AppLauncherManager handles saving when property is set
                 AppLauncherManager.shared.shortcuts = decoded
            }
        }

        if let quickShortcutItemsData = config.quickShortcutItems,
           let decoded = try? JSONDecoder().decode([QuickShortcut].self, from: quickShortcutItemsData) {
            QuickShortcutManager.shared.items = decoded
        }

        if let clipboardSettingsData = config.clipboardSettings,
           let decoded = try? JSONDecoder().decode(ClipboardSettings.self, from: clipboardSettingsData) {
            ClipboardManager.shared.settings = decoded
        }

        if let shortcutDetectiveEnabled = config.shortcutDetectiveEnabled {
            ShortcutDetectiveManager.shared.isEnabled = shortcutDetectiveEnabled
        }

        if let snippetSettingsData = config.snippetSettings,
           let decoded = try? JSONDecoder().decode(SnippetSettings.self, from: snippetSettingsData) {
            SnippetManager.shared.settings = decoded
        }

        if let snippetCollectionsData = config.snippetCollections,
           let decoded = try? JSONDecoder().decode([SnippetCollection].self, from: snippetCollectionsData) {
            SnippetManager.shared.collections = decoded
        }

        if let snippetEntriesData = config.snippetEntries,
           let decoded = try? JSONDecoder().decode([SnippetEntry].self, from: snippetEntriesData) {
            SnippetManager.shared.entries = decoded
        }

        if let showLunar = config.calendarShowLunar {
            CalendarPreferencesStore.shared.showLunar = showLunar
        }

        if let showWeekNumbers = config.calendarShowWeekNumbers {
            CalendarPreferencesStore.shared.showWeekNumbers = showWeekNumbers
        }

        if let firstWeekday = config.calendarFirstWeekday {
            CalendarPreferencesStore.shared.firstWeekday = firstWeekday
        }

        if let rawStyle = config.calendarMenuBarIconStyle,
           let style = CalendarMenuBarIconStyle(rawValue: rawStyle) {
            CalendarPreferencesStore.shared.menuBarIconStyle = style
        }

        if let lockAIStatusText = config.lockAIStatusText {
            LockAIManager.shared.statusText = lockAIStatusText
        }
    }
}
