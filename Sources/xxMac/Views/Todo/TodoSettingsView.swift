import AppKit
import SwiftUI
import UserNotifications

struct TodoSettingsView: View {
    @ObservedObject private var hotKeyManager = HotKeyManager.shared
    @State private var authorizationStatus = UNAuthorizationStatus.notDetermined

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.t("todo.settings.description"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            GroupBox(L10n.t("todo.settings.window")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Text(L10n.t("todo.settings.hotkey"))
                        Spacer()
                        HotKeyRecorderView(action: .toggleTodo)
                            .frame(width: 210)
                    }

                    Divider()

                    HStack {
                        Text(L10n.t("todo.settings.open_window_desc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            TodoWindowController.shared.show()
                        } label: {
                            Label(L10n.t("todo.settings.open_window"), systemImage: "macwindow")
                        }
                    }
                }
                .padding(8)
            }

            GroupBox(L10n.t("todo.settings.notifications")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 9) {
                        Image(systemName: notificationSystemImage)
                            .foregroundStyle(notificationColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(notificationTitle)
                                .font(.headline)
                            Text(L10n.t("todo.settings.notifications_desc"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    HStack {
                        Button {
                            refreshAuthorizationStatus()
                        } label: {
                            Label(L10n.t("permissions.refresh"), systemImage: "arrow.clockwise")
                        }
                        Spacer()
                        Button {
                            TodoNotificationManager.shared.openSystemSettings()
                        } label: {
                            Label(L10n.t("todo.settings.open_notification_settings"), systemImage: "gearshape")
                        }
                    }
                }
                .padding(8)
            }

            GroupBox(L10n.t("todo.settings.storage")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.t("todo.settings.storage_desc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(ConfigDirectoryManager.shared.todoDatabaseURL.path)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))

                    HStack {
                        Spacer()
                        Button(action: revealDatabase) {
                            Label(L10n.t("todo.settings.reveal_database"), systemImage: "folder")
                        }
                    }
                }
                .padding(8)
            }

            Spacer()
        }
        .onAppear(perform: refreshAuthorizationStatus)
    }

    private var notificationTitle: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return L10n.t("todo.settings.notification_authorized")
        case .denied:
            return L10n.t("todo.settings.notification_denied")
        case .notDetermined:
            return L10n.t("todo.settings.notification_not_determined")
        @unknown default:
            return L10n.t("todo.settings.notification_unknown")
        }
    }

    private var notificationSystemImage: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .notDetermined: return "questionmark.circle"
        @unknown default: return "exclamationmark.circle"
        }
    }

    private var notificationColor: Color {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .green
        case .denied: return .red
        case .notDetermined: return .secondary
        @unknown default: return .orange
        }
    }

    private func refreshAuthorizationStatus() {
        TodoNotificationManager.shared.authorizationStatus { status in
            authorizationStatus = status
        }
    }

    private func revealDatabase() {
        let databaseURL = ConfigDirectoryManager.shared.todoDatabaseURL
        if FileManager.default.fileExists(atPath: databaseURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([databaseURL])
        } else {
            NSWorkspace.shared.open(databaseURL.deletingLastPathComponent())
        }
    }
}
