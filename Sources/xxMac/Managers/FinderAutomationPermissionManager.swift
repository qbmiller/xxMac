import AppKit
import ApplicationServices
import Combine
import OSLog

enum FinderAutomationPermissionStatus: Equatable {
    case authorized
    case notDetermined
    case denied
    case unavailable
}

final class FinderAutomationPermissionManager: ObservableObject {
    static let shared = FinderAutomationPermissionManager()
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "xxMac",
        category: "FinderAutomationPermission"
    )

    @Published private(set) var status: FinderAutomationPermissionStatus = .unavailable

    private let determinePermission: (Bool) -> OSStatus
    private let openAutomationSettingsHandler: () -> Void

    init(
        determinePermission: @escaping (Bool) -> OSStatus = FinderAutomationPermissionManager.determineSystemPermission,
        openAutomationSettings: @escaping () -> Void = FinderAutomationPermissionManager.openSystemAutomationSettings
    ) {
        self.determinePermission = determinePermission
        openAutomationSettingsHandler = openAutomationSettings
        refresh()
    }

    func refresh() {
        status = determineStatus(askUserIfNeeded: false)
    }

    func requestPermission() {
        _ = ensurePermission(openSettingsIfNeeded: true)
    }

    @discardableResult
    func ensurePermission(openSettingsIfNeeded: Bool) -> Bool {
        refresh()
        guard status != .authorized else { return true }

        status = determineStatus(askUserIfNeeded: true)
        guard status == .authorized else {
            if openSettingsIfNeeded {
                openAutomationSettings()
            }
            return false
        }
        return true
    }

    func openAutomationSettings() {
        openAutomationSettingsHandler()
    }

    static func status<T: BinaryInteger>(for result: T) -> FinderAutomationPermissionStatus {
        switch OSStatus(truncatingIfNeeded: result) {
        case noErr:
            return .authorized
        case OSStatus(errAEEventWouldRequireUserConsent):
            return .notDetermined
        case OSStatus(errAEEventNotPermitted):
            return .denied
        default:
            return .unavailable
        }
    }

    private static func determineSystemPermission(askUserIfNeeded: Bool) -> OSStatus {
        let finderTarget = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        return AEDeterminePermissionToAutomateTarget(
            finderTarget.aeDesc,
            typeWildCard,
            typeWildCard,
            askUserIfNeeded
        )
    }

    private static func openSystemAutomationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func determineStatus(askUserIfNeeded: Bool) -> FinderAutomationPermissionStatus {
        let result = determinePermission(askUserIfNeeded)
        let mappedStatus = Self.status(for: result)
        Self.logger.notice(
            "Finder automation check askUser=\(askUserIfNeeded) result=\(result) status=\(String(describing: mappedStatus), privacy: .public)"
        )
        return mappedStatus
    }
}
