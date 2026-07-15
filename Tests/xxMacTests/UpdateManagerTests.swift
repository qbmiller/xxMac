import XCTest
@testable import xxMac

@MainActor
final class UpdateManagerTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testFrequenciesBecomeDueAtExpectedDates() {
        let lastCheck = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertFalse(UpdateCheckFrequency.off.isDue(lastCheckedAt: nil, now: lastCheck, calendar: calendar))
        XCTAssertFalse(UpdateCheckFrequency.daily.isDue(
            lastCheckedAt: lastCheck,
            now: calendar.date(byAdding: .hour, value: 23, to: lastCheck)!,
            calendar: calendar
        ))
        XCTAssertTrue(UpdateCheckFrequency.daily.isDue(
            lastCheckedAt: lastCheck,
            now: calendar.date(byAdding: .day, value: 1, to: lastCheck)!,
            calendar: calendar
        ))
        XCTAssertTrue(UpdateCheckFrequency.weekly.isDue(
            lastCheckedAt: lastCheck,
            now: calendar.date(byAdding: .day, value: 7, to: lastCheck)!,
            calendar: calendar
        ))
        XCTAssertTrue(UpdateCheckFrequency.monthly.isDue(
            lastCheckedAt: lastCheck,
            now: calendar.date(byAdding: .month, value: 1, to: lastCheck)!,
            calendar: calendar
        ))
    }

    func testVersionComparisonHandlesPrefixesAndMissingParts() {
        XCTAssertTrue(UpdateVersion.isNewer("v1.2.0", than: "1.1.9"))
        XCTAssertFalse(UpdateVersion.isNewer("1.2", than: "1.2.0"))
        XCTAssertFalse(UpdateVersion.isNewer("1.1.9", than: "1.2.0"))
    }

    func testNewManagerDefaultsToWeeklyChecks() {
        let manager = UpdateManager(
            store: TestUpdatePreferenceStore(),
            releaseProvider: StubReleaseProvider(result: .success("1.1.0")),
            currentVersion: "1.1.0",
            now: Date.init,
            calendar: calendar
        )

        XCTAssertEqual(manager.frequency, .weekly)
    }

    func testManualCheckWhileAutomaticChecksAreOffDoesNotPublishLauncherIndicator() async throws {
        let store = TestUpdatePreferenceStore()
        store.strings[UpdatePreferencesKey.frequency] = UpdateCheckFrequency.off.rawValue
        let manager = UpdateManager(
            store: store,
            releaseProvider: StubReleaseProvider(result: .success("2.0.0")),
            currentVersion: "1.1.0",
            now: Date.init,
            calendar: calendar
        )

        let outcome = try await manager.checkForUpdates()

        XCTAssertEqual(outcome, .updateAvailable(version: "2.0.0"))
        XCTAssertNil(manager.availableVersion)
        XCTAssertNil(store.strings[UpdatePreferencesKey.availableVersion])
    }

    func testSuccessfulCheckPersistsTimestampAndAvailableVersion() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = TestUpdatePreferenceStore()
        let manager = UpdateManager(
            store: store,
            releaseProvider: StubReleaseProvider(result: .success("1.2.0")),
            currentVersion: "1.1.0",
            now: { now },
            calendar: calendar
        )

        let outcome = try await manager.checkForUpdates()

        XCTAssertEqual(outcome, .updateAvailable(version: "1.2.0"))
        XCTAssertEqual(manager.availableVersion, "1.2.0")
        XCTAssertEqual(store.doubles[UpdatePreferencesKey.lastSuccessfulCheck], now.timeIntervalSince1970)
        XCTAssertEqual(store.strings[UpdatePreferencesKey.availableVersion], "1.2.0")
    }

    func testFailedCheckDoesNotReplaceLastSuccessfulTimestamp() async {
        let previousTimestamp = 1_699_000_000.0
        let store = TestUpdatePreferenceStore()
        store.doubles[UpdatePreferencesKey.lastSuccessfulCheck] = previousTimestamp
        let manager = UpdateManager(
            store: store,
            releaseProvider: StubReleaseProvider(result: .failure(TestError.offline)),
            currentVersion: "1.1.0",
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            calendar: calendar
        )

        do {
            _ = try await manager.checkForUpdates()
            XCTFail("Expected the update check to fail")
        } catch {
            XCTAssertEqual(store.doubles[UpdatePreferencesKey.lastSuccessfulCheck], previousTimestamp)
        }
    }

    func testInitializationClearsPersistedVersionThatIsNoLongerNewer() {
        let store = TestUpdatePreferenceStore()
        store.strings[UpdatePreferencesKey.availableVersion] = "1.1.0"

        let manager = UpdateManager(
            store: store,
            releaseProvider: StubReleaseProvider(result: .success("1.1.0")),
            currentVersion: "1.1.0",
            now: Date.init,
            calendar: calendar
        )

        XCTAssertNil(manager.availableVersion)
        XCTAssertNil(store.strings[UpdatePreferencesKey.availableVersion])
    }
}

private enum TestError: Error {
    case offline
}

private struct StubReleaseProvider: UpdateReleaseProviding {
    let result: Result<String, Error>

    func latestVersion() async throws -> String {
        try result.get()
    }
}

private final class TestUpdatePreferenceStore: UpdatePreferenceStoring {
    var strings: [String: String] = [:]
    var doubles: [String: Double] = [:]

    func string(forKey key: String) -> String? {
        strings[key]
    }

    func doubleObject(forKey key: String) -> Double? {
        doubles[key]
    }

    func set(_ value: String, forKey key: String) {
        strings[key] = value
    }

    func set(_ value: Double, forKey key: String) {
        doubles[key] = value
    }

    func removeObject(forKey key: String) {
        strings.removeValue(forKey: key)
        doubles.removeValue(forKey: key)
    }
}
