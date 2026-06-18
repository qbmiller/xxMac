import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    var id: String { rawValue }

    var localeIdentifier: String { rawValue }

    var displayNameKey: String {
        switch self {
        case .english:
            return "language.english"
        case .simplifiedChinese:
            return "language.simplified"
        case .traditionalChinese:
            return "language.traditional"
        }
    }
}

enum UserDefaultsKeys {
    static let appLanguage = "AppLanguage"
}

final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: UserDefaultsKeys.appLanguage)
        }
    }

    private init() {
        if let rawValue = UserDefaults.standard.string(forKey: UserDefaultsKeys.appLanguage),
           let language = AppLanguage(rawValue: rawValue) {
            self.language = language
        } else {
            self.language = .english
            UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: UserDefaultsKeys.appLanguage)
        }
    }

    var bundle: Bundle {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    func localizedString(_ key: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: bundle, value: key, comment: "")
    }
}

enum L10n {
    static func t(_ key: String) -> String {
        LocalizationManager.shared.localizedString(key)
    }

    static func f(_ key: String, _ args: CVarArg...) -> String {
        let format = LocalizationManager.shared.localizedString(key)
        let locale = Locale(identifier: LocalizationManager.shared.language.localeIdentifier)
        return String(format: format, locale: locale, arguments: args)
    }
}
