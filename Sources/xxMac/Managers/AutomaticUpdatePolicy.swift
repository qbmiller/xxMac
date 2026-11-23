import Foundation

/// Pure policy shared by the updater and its tests. Installation always fails closed.
enum AutomaticUpdatePolicy {
    static func isConfigured(feedURL: String?, publicKey: String?) -> Bool {
        guard let feedURL, let url = URL(string: feedURL),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              let publicKey, let key = Data(base64Encoded: publicKey), key.count == 32 else {
            return false
        }
        return true
    }

    static func shouldInstallImmediately(automaticInstallation: Bool, checksEnabled: Bool) -> Bool {
        automaticInstallation && checksEnabled
    }
}

/// Sparkle stalls its session when we take ownership of installation. Keep the
/// handler until the cycle finishes so cancelled termination can be retried.
@MainActor
final class PendingUpdateInstallation {
    private var handler: (() -> Void)?

    func prepare(_ handler: @escaping () -> Void) { self.handler = handler }
    func clear() { handler = nil }

    @discardableResult
    func installIfAllowed(automatically: Bool, automaticInstallation: Bool, checksEnabled: Bool) -> Bool {
        guard let handler else { return false }
        guard !automatically || AutomaticUpdatePolicy.shouldInstallImmediately(
            automaticInstallation: automaticInstallation, checksEnabled: checksEnabled
        ) else { return false }
        handler()
        return true
    }
}
