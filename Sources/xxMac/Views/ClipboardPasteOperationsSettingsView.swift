import AppKit
import SwiftUI

struct ClipboardPasteOperationsSettingsView: View {
    @ObservedObject private var manager = FinderPasteOperationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("clipboard_paste.desc"))
                .font(.subheadline)
                .foregroundColor(.secondary)

            settingsSection(title: L10n.t("clipboard_paste.path_title"), systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                HStack(alignment: .center, spacing: 16) {
                    Text(L10n.t("clipboard_paste.path_desc"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 12)

                    HotKeyRecorderView(action: .pasteFinderPath)
                        .frame(width: 200)
                }
            }

            settingsSection(title: L10n.t("clipboard_paste.image_title"), systemImage: "photo.badge.arrow.down") {
                Toggle(isOn: Binding(
                    get: { manager.settings.imageEnabled },
                    set: manager.setImageEnabled
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("clipboard_paste.image_enabled"))
                        Text(L10n.t("clipboard_paste.image_desc"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                counterRow(number: manager.imageNextNumber, reset: manager.resetImageCounter)
            }

            settingsSection(title: L10n.t("clipboard_paste.text_title"), systemImage: "doc.badge.arrow.down") {
                Toggle(isOn: Binding(
                    get: { manager.settings.textEnabled },
                    set: manager.setTextEnabled
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("clipboard_paste.text_enabled"))
                        Text(L10n.t("clipboard_paste.text_desc"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                counterRow(number: manager.textNextNumber, reset: manager.resetTextCounter)
            }

            Spacer()
        }
    }

    private func counterRow(number: Int, reset: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(L10n.t("clipboard_paste.next_number"))
                .foregroundColor(.secondary)
            Text(String(format: "%03d", number))
                .font(.system(.body, design: .monospaced).weight(.medium))
                .frame(width: 64, alignment: .leading)

            Spacer()

            Button(action: reset) {
                Label(L10n.t("clipboard_paste.reset_counter"), systemImage: "arrow.counterclockwise")
            }
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                content()
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
}
