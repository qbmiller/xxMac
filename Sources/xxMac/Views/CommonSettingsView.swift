import SwiftUI
import AppKit

struct CommonSettingsView: View {
    @State private var showingExportSuccess = false
    @State private var showingImportSuccess = false
    @State private var importError: String?
    
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
    
    struct AppConfiguration: Codable {
        let searchPaths: [String]?
        // We use AnyCodable wrapper or Data for flexible storage if models change, 
        // but since we know the keys, we can store raw Data or specific structs.
        // Storing as Data allows us to just dump it back to UserDefaults.
        let hotKeyConfigurations: Data?
        let appLauncherShortcuts: Data?
        let shortcutDetectiveEnabled: Bool?
    }
    
    private func collectConfigurations() throws -> AppConfiguration {
        let defaults = UserDefaults.standard
        
        let searchPaths = defaults.stringArray(forKey: "AppSearchPaths")
        let hotKeyConfig = defaults.data(forKey: "HotKeyConfigurations")
        let appLauncherShortcuts = defaults.data(forKey: "AppLauncherShortcuts")
        let shortcutDetectiveEnabled = defaults.object(forKey: "ShortcutDetectiveEnabled") as? Bool
        
        return AppConfiguration(
            searchPaths: searchPaths,
            hotKeyConfigurations: hotKeyConfig,
            appLauncherShortcuts: appLauncherShortcuts,
            shortcutDetectiveEnabled: shortcutDetectiveEnabled
        )
    }
    
    private func restoreConfigurations(_ config: AppConfiguration) {
        let defaults = UserDefaults.standard
        
        if let paths = config.searchPaths {
            // AppSearchManager handles saving when property is set
            AppSearchManager.shared.searchPaths = paths
        }
        
        if let hotKeys = config.hotKeyConfigurations {
            defaults.set(hotKeys, forKey: "HotKeyConfigurations")
            HotKeyManager.shared.loadConfigurations()
        }
        
        if let shortcutsData = config.appLauncherShortcuts {
            if let decoded = try? JSONDecoder().decode([AppShortcut].self, from: shortcutsData) {
                 // AppLauncherManager handles saving when property is set
                 AppLauncherManager.shared.shortcuts = decoded
            }
        }

        if let shortcutDetectiveEnabled = config.shortcutDetectiveEnabled {
            ShortcutDetectiveManager.shared.isEnabled = shortcutDetectiveEnabled
        }
    }
}
