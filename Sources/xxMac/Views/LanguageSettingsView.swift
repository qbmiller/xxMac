import SwiftUI

struct LanguageSettingsView: View {
    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("language.description"))
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("language.current"))
                    .font(.headline)

                Picker(L10n.t("language.title"), selection: $localization.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(L10n.t(language.displayNameKey)).tag(language)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )

            Toggle(L10n.t("language.launcher_default_english_input"), isOn: $localization.launcherDefaultsToEnglishInput)
                .toggleStyle(.checkbox)

            Text(L10n.t("language.launcher_default_english_input_desc"))
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
    }
}
