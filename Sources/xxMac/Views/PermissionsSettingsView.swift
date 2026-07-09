import SwiftUI
import AppKit

struct PermissionsSettingsView: View {
    @State private var hasAccessibilityPermission = AccessibilityManager.shared.hasAccessibilityPermissions()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("permissions.description"))
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: hasAccessibilityPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(hasAccessibilityPermission ? .green : .orange)
                        .font(.system(size: 24, weight: .semibold))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("permissions.accessibility"))
                            .font(.headline)
                        Text(hasAccessibilityPermission ? L10n.t("permissions.accessibility_granted") : L10n.t("permissions.accessibility_missing"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                HStack(spacing: 10) {
                    Button {
                        _ = AccessibilityManager.shared.requestAccessibilityPermissions()
                        refreshPermissions()
                    } label: {
                        Label(L10n.t("permissions.request_accessibility"), systemImage: "hand.raised")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        refreshPermissions()
                    } label: {
                        Label(L10n.t("permissions.refresh"), systemImage: "arrow.clockwise")
                    }
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

            Spacer()
        }
        .onAppear(perform: refreshPermissions)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
    }

    private func refreshPermissions() {
        hasAccessibilityPermission = AccessibilityManager.shared.hasAccessibilityPermissions()
    }
}
