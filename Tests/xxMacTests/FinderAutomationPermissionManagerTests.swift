import ApplicationServices
import XCTest
@testable import xxMac

final class FinderAutomationPermissionManagerTests: XCTestCase {
    func testEnsurePermissionOnlyChecksWhenAlreadyAuthorized() {
        var askUserValues: [Bool] = []
        let manager = FinderAutomationPermissionManager(
            determinePermission: { askUser in
                askUserValues.append(askUser)
                return noErr
            },
            openAutomationSettings: {}
        )
        askUserValues.removeAll()

        XCTAssertTrue(manager.ensurePermission(openSettingsIfNeeded: true))
        XCTAssertEqual(askUserValues, [false])
    }

    func testEnsurePermissionChecksBeforeRequestingWhenMissing() {
        var askUserValues: [Bool] = []
        let manager = FinderAutomationPermissionManager(
            determinePermission: { askUser in
                askUserValues.append(askUser)
                return askUser ? noErr : OSStatus(errAEEventWouldRequireUserConsent)
            },
            openAutomationSettings: {}
        )
        askUserValues.removeAll()

        XCTAssertTrue(manager.ensurePermission(openSettingsIfNeeded: true))
        XCTAssertEqual(askUserValues, [false, true])
    }

    func testEnsurePermissionOpensSettingsOnlyAfterRequestStillFails() {
        var askUserValues: [Bool] = []
        var settingsOpenCount = 0
        let manager = FinderAutomationPermissionManager(
            determinePermission: { askUser in
                askUserValues.append(askUser)
                return OSStatus(errAEEventNotPermitted)
            },
            openAutomationSettings: { settingsOpenCount += 1 }
        )
        askUserValues.removeAll()

        XCTAssertFalse(manager.ensurePermission(openSettingsIfNeeded: true))
        XCTAssertEqual(askUserValues, [false, true])
        XCTAssertEqual(settingsOpenCount, 1)
    }

    func testMapsAuthorizedStatus() {
        XCTAssertEqual(FinderAutomationPermissionManager.status(for: noErr), .authorized)
    }

    func testMapsConsentRequiredStatus() {
        XCTAssertEqual(
            FinderAutomationPermissionManager.status(for: errAEEventWouldRequireUserConsent),
            .notDetermined
        )
    }

    func testMapsDeniedStatus() {
        XCTAssertEqual(
            FinderAutomationPermissionManager.status(for: errAEEventNotPermitted),
            .denied
        )
    }

    func testMapsUnexpectedStatusAsUnavailable() {
        XCTAssertEqual(FinderAutomationPermissionManager.status(for: -1), .unavailable)
    }

}
