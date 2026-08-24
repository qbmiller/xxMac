import SwiftUI
import AppKit

struct PermissionsSettingsView: View {
    @State private var hasAccessibilityPermission = AccessibilityManager.shared.hasAccessibilityPermissions()
    @StateObject private var finderPermissionManager = FinderAutomationPermissionManager.shared

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

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: finderPermissionManager.status == .authorized ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(finderPermissionManager.status == .authorized ? .green : .orange)
                        .font(.system(size: 24, weight: .semibold))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("permissions.finder_automation"))
                            .font(.headline)
                        Text(finderAutomationStatusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                if finderPermissionManager.status != .authorized {
                    Button {
                        finderPermissionManager.requestPermission()
                    } label: {
                        Label(finderAutomationButtonText, systemImage: "folder.badge.gearshape")
                    }
                    .buttonStyle(.borderedProminent)
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
        finderPermissionManager.refresh()
    }

    private var finderAutomationStatusText: String {
        switch finderPermissionManager.status {
        case .authorized:
            return L10n.t("permissions.finder_automation_granted")
        case .notDetermined:
            return L10n.t("permissions.finder_automation_not_determined")
        case .denied:
            return L10n.t("permissions.finder_automation_denied")
        case .unavailable:
            return L10n.t("permissions.finder_automation_unavailable")
        }
    }

    private var finderAutomationButtonText: String {
        switch finderPermissionManager.status {
        case .notDetermined, .unavailable:
            return L10n.t("permissions.request_finder_automation")
        case .denied:
            return L10n.t("permissions.open_automation_settings")
        case .authorized:
            return ""
        }
    }
}
