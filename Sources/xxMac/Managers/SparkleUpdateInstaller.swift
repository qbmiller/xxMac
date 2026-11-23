import AppKit
import Sparkle

@MainActor
protocol UpdateInstalling: AnyObject {
    var isConfigured: Bool { get }
    var automaticInstallation: Bool { get set }
    var checksEnabled: Bool { get set }
    func start()
    func checkForUpdates(automatically: Bool)
}

/// Sparkle owns downloading, signature verification, replacement, and relaunch.
/// UpdateManager remains the only scheduler, preserving its calendar intervals.
@MainActor
final class SparkleUpdateInstaller: NSObject, UpdateInstalling, SPUUpdaterDelegate {
    var automaticInstallation = false {
        didSet {
            controller?.updater.automaticallyDownloadsUpdates = automaticInstallation && checksEnabled
            resumePendingInstallation(automatically: true)
        }
    }
    var checksEnabled = true {
        didSet {
            controller?.updater.automaticallyDownloadsUpdates = automaticInstallation && checksEnabled
            resumePendingInstallation(automatically: true)
        }
    }
    private let pendingInstallation = PendingUpdateInstallation()
    private var controller: SPUStandardUpdaterController?

    var isConfigured: Bool {
        AutomaticUpdatePolicy.isConfigured(
            feedURL: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            publicKey: Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        ) && Bundle.main.bundleURL.pathExtension == "app"
    }

    func start() {
        guard isConfigured, controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.automaticallyChecksForUpdates = false
        controller.updater.automaticallyDownloadsUpdates = automaticInstallation && checksEnabled
        controller.startUpdater()
    }

    func checkForUpdates(automatically: Bool) {
        start()
        if resumePendingInstallation(automatically: automatically) { return }
        guard let controller else { return }
        if automatically {
            guard automaticInstallation, checksEnabled, !controller.updater.sessionInProgress else { return }
            controller.updater.checkForUpdatesInBackground()
        } else {
            controller.checkForUpdates(nil)
        }
    }

    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { false }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        guard AutomaticUpdatePolicy.shouldInstallImmediately(
            automaticInstallation: automaticInstallation,
            checksEnabled: checksEnabled
        ) else { return false }
        pendingInstallation.prepare(immediateInstallHandler)
        // The handler is usable only after this delegate method has returned true.
        DispatchQueue.main.async { [weak self] in
            self?.resumePendingInstallation(automatically: true)
        }
        return true
    }

    @discardableResult
    private func resumePendingInstallation(automatically: Bool) -> Bool {
        pendingInstallation.installIfAllowed(automatically: automatically,
            automaticInstallation: automaticInstallation, checksEnabled: checksEnabled)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        pendingInstallation.clear()
    }

}
