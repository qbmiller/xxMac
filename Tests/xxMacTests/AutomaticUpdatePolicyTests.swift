import XCTest
@testable import xxMac

final class AutomaticUpdatePolicyTests: XCTestCase {
    private let key = Data(repeating: 1, count: 32).base64EncodedString()

    func testRequiresHTTPSFeedAndEd25519PublicKey() {
        XCTAssertTrue(AutomaticUpdatePolicy.isConfigured(feedURL: "https://example.com/appcast.xml", publicKey: key))
        XCTAssertFalse(AutomaticUpdatePolicy.isConfigured(feedURL: "http://example.com/appcast.xml", publicKey: key))
        XCTAssertFalse(AutomaticUpdatePolicy.isConfigured(feedURL: "https://example.com/appcast.xml", publicKey: ""))
        XCTAssertFalse(AutomaticUpdatePolicy.isConfigured(feedURL: "https://example.com/appcast.xml", publicKey: Data([1]).base64EncodedString()))
        XCTAssertFalse(AutomaticUpdatePolicy.isConfigured(feedURL: "https:///appcast.xml", publicKey: key))
    }

    func testOnlyRestartsWhenUserHasEnabledAutomaticInstallation() {
        XCTAssertTrue(AutomaticUpdatePolicy.shouldInstallImmediately(automaticInstallation: true, checksEnabled: true))
        XCTAssertFalse(AutomaticUpdatePolicy.shouldInstallImmediately(automaticInstallation: false, checksEnabled: true))
        XCTAssertFalse(AutomaticUpdatePolicy.shouldInstallImmediately(automaticInstallation: true, checksEnabled: false))
    }
}

@MainActor
final class PendingUpdateInstallationTests: XCTestCase {
    func testRetainsInstallationForRetryAfterCancelledTermination() {
        let pending = PendingUpdateInstallation()
        var attempts = 0
        pending.prepare { attempts += 1 }
        XCTAssertTrue(pending.installIfAllowed(automatically: true, automaticInstallation: true, checksEnabled: true))
        XCTAssertTrue(pending.installIfAllowed(automatically: false, automaticInstallation: false, checksEnabled: false))
        XCTAssertEqual(attempts, 2)
        pending.clear()
        XCTAssertFalse(pending.installIfAllowed(automatically: false, automaticInstallation: true, checksEnabled: true))
    }

    func testDisablingAutomaticInstallRetainsManualRecovery() {
        let pending = PendingUpdateInstallation()
        var attempts = 0
        pending.prepare { attempts += 1 }
        XCTAssertFalse(pending.installIfAllowed(automatically: true, automaticInstallation: false, checksEnabled: true))
        XCTAssertFalse(pending.installIfAllowed(automatically: true, automaticInstallation: true, checksEnabled: false))
        XCTAssertEqual(attempts, 0)
        XCTAssertTrue(pending.installIfAllowed(automatically: false, automaticInstallation: false, checksEnabled: false))
        XCTAssertEqual(attempts, 1)
    }
}
