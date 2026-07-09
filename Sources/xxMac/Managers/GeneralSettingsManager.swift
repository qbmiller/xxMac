import Combine
import Foundation

enum GeneralPreferencesKey {
    static let showMenuBarItem = "GeneralShowMenuBarItem"
}

@MainActor
final class GeneralSettingsManager: ObservableObject {
    static let shared = GeneralSettingsManager()

    @Published var showMenuBarItem: Bool {
        didSet {
            PreferencesStore.shared.set(showMenuBarItem, forKey: GeneralPreferencesKey.showMenuBarItem)
        }
    }

    private init() {
        showMenuBarItem = PreferencesStore.shared.boolObject(forKey: GeneralPreferencesKey.showMenuBarItem)
            ?? AppDefaultSettings.General.showMenuBarItem
    }
}
