import AppKit
import HotKey
import XCTest
@testable import xxMac

final class InputSourceAutomationTests: XCTestCase {
    private var roots: [URL] = []
    private var suites: [String] = []

    override func tearDownWithError() throws {
        roots.forEach { try? FileManager.default.removeItem(at: $0) }
        suites.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
    }

    func testSettingsInputSourceNotificationsDoNotShowAutomaticIndicator() throws {
        let clock = FakeInputClock()
        clock.ownApplicationActive = true
        let indicator = FakeInputSourceIndicator()
        let (manager, controller, _, _) = try makeManager(clock: clock, indicator: indicator)
        manager.settings.showOnChange = true
        // Switching between settings panes can change the system text-input context.
        controller.current = controller.sources[1]
        manager.sourceChanged()
        controller.current = controller.sources[2]
        manager.sourceChanged()
        XCTAssertTrue(indicator.shownSourceIDs.isEmpty)
        XCTAssertEqual(manager.currentSource?.id, "ja", "Suppression must not prevent status updates")
    }

    func testExternalInputSourceChangeStillShowsIndicator() throws {
        let indicator = FakeInputSourceIndicator()
        let (manager, controller, _, _) = try makeManager(indicator: indicator)
        manager.settings.showOnChange = true
        controller.current = controller.sources[1]
        manager.sourceChanged()
        XCTAssertEqual(indicator.shownSourceIDs, ["en"])
    }

    func testLongPressCompletionSuppressesSettingsButStillWorksOutside() throws {
        let clock = FakeInputClock()
        let indicator = FakeInputSourceIndicator()
        let (manager, _, _, _) = try makeManager(clock: clock, indicator: indicator)
        manager.settings.showOnLongPress = true
        // A press can start in another app and finish after xxMac takes focus.
        clock.ownApplicationActive = true
        manager.handleLongPress()
        XCTAssertTrue(indicator.shownSourceIDs.isEmpty)
        clock.ownApplicationActive = false
        manager.handleLongPress()
        XCTAssertEqual(indicator.shownSourceIDs, ["zh"])
    }

    func testExplicitIndicatorPreviewStillWorksInSettings() throws {
        let clock = FakeInputClock()
        clock.ownApplicationActive = true
        let indicator = FakeInputSourceIndicator()
        let (manager, _, _, _) = try makeManager(clock: clock, indicator: indicator)
        manager.previewIndicator()
        XCTAssertEqual(indicator.shownSourceIDs, ["zh"])
    }

    func testAddressBarRestoresPreviousSourceWhenPageHasNoRule() throws {
        let (manager, controller, _, _) = try makeManager()
        manager.settings.enabled = true
        manager.settings.addressBarSourceID = "en"
        manager.acceptContext(.init(bundleID: "com.google.Chrome"))
        manager.acceptContext(.init(bundleID: "com.google.Chrome", addressBarFocused: true))
        XCTAssertEqual(controller.selected, ["en"])
        manager.acceptContext(.init(bundleID: "com.google.Chrome"))
        XCTAssertEqual(controller.selected, ["en", "zh"])
    }

    func testAddressBarReturnsToWebsiteRuleAndIgnoresRepeatedContext() throws {
        let (manager, controller, _, _) = try makeManager()
        manager.settings.enabled = true
        manager.settings.addressBarSourceID = "en"
        manager.settings.websiteRules = [.init(pattern: "example.com", sourceID: "ja")]
        let page = InputSourceContext(bundleID: "com.google.Chrome", url: URL(string: "https://example.com"))
        manager.acceptContext(page)
        manager.acceptContext(.init(bundleID: page.bundleID, url: page.url, addressBarFocused: true))
        manager.acceptContext(page)
        XCTAssertEqual(controller.selected, ["ja", "en", "ja"])
        controller.current = controller.sources[0]
        manager.acceptContext(page)
        XCTAssertEqual(controller.selected.count, 3, "Repeated polls must not override a manual choice")
    }

    func testUnavailableSourceDoesNotFallThroughToDefaultAndSelectionFailureIsReported() throws {
        let (manager, controller, _, _) = try makeManager()
        manager.settings.enabled = true
        manager.settings.defaultSourceID = "en"
        manager.settings.appRules = [.init(bundleID: "app", name: "App", sourceID: "removed")]
        manager.acceptContext(.init(bundleID: "app"))
        XCTAssertTrue(controller.selected.isEmpty)
        XCTAssertEqual(manager.issueKey, "input.error.unavailable")
        controller.succeeds = false
        XCTAssertFalse(manager.select("en", automatic: true))
        XCTAssertEqual(manager.issueKey, "input.error.selection")
    }

    func testManualChoiceIsPersistedButAutomaticAndPausedChangesAreNot() throws {
        let clock = FakeInputClock()
        let (manager, controller, store, _) = try makeManager(clock: clock)
        manager.settings.enabled = true
        manager.settings.appRules = [.init(bundleID: "app", name: "App", policy: .remember)]
        manager.acceptContext(.init(bundleID: "app"))
        clock.now += 1
        XCTAssertTrue(manager.select("en", automatic: true))
        XCTAssertNil(manager.memory["app"])
        clock.now += 2
        controller.current = controller.sources[2]
        manager.sourceChanged()
        XCTAssertEqual(manager.memory["app"], "ja")
        XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: XCTUnwrap(store.data(forKey: InputSourceAutomationManager.memoryKey)))["app"], "ja")
        manager.isPaused = true
        controller.current = controller.sources[0]
        manager.sourceChanged()
        XCTAssertEqual(manager.memory["app"], "ja")
    }

    func testWebsiteAndAddressChoicesDoNotOverwriteAppMemory() throws {
        let clock = FakeInputClock()
        clock.bundleID = "com.google.Chrome"
        let (manager, controller, _, _) = try makeManager(clock: clock)
        manager.settings.enabled = true
        manager.settings.appRules = [.init(bundleID: "com.google.Chrome", name: "Chrome", policy: .remember)]
        manager.settings.websiteRules = [.init(pattern: "example.com", sourceID: "en")]
        manager.acceptContext(.init(bundleID: "com.google.Chrome", url: URL(string: "https://example.com")))
        clock.now += 3
        controller.current = controller.sources[2]
        manager.sourceChanged()
        XCTAssertNil(manager.memory["com.google.Chrome"])
        manager.settings.websiteRules = []
        manager.settings.addressBarSourceID = "en"
        manager.acceptContext(.init(bundleID: "com.google.Chrome", addressBarFocused: true))
        clock.now += 3
        controller.current = controller.sources[0]
        manager.sourceChanged()
        XCTAssertNil(manager.memory["com.google.Chrome"])
    }

    func testAddressBarRestoresManualChoiceBeforeAppDefault() throws {
        let (manager, controller, _, _) = try makeManager()
        manager.settings.enabled = true
        manager.settings.defaultSourceID = "en"
        manager.settings.addressBarSourceID = "en"
        let page = InputSourceContext(bundleID: "com.google.Chrome")
        manager.acceptContext(page)
        _ = manager.select("ja", automatic: false)
        manager.acceptContext(.init(bundleID: page.bundleID, addressBarFocused: true))
        manager.acceptContext(page)
        XCTAssertEqual(controller.current?.id, "ja")
    }

    func testManualReturnToConfirmedAutomaticSourceUpdatesMemory() throws {
        let clock = FakeInputClock()
        let (manager, _, _, _) = try makeManager(clock: clock)
        manager.settings.enabled = true
        manager.settings.appRules = [.init(bundleID: "app", name: "App", policy: .remember)]
        manager.acceptContext(.init(bundleID: "app"))
        clock.now += 0.3
        _ = manager.select("en", automatic: true)
        clock.now += 0.1
        _ = manager.select("ja", automatic: false)
        clock.now += 0.1
        _ = manager.select("en", automatic: false)
        XCTAssertEqual(manager.memory["app"], "en")
    }

    func testLauncherSuppressesExternalRules() throws {
        let (manager, controller, _, _) = try makeManager()
        manager.settings.enabled = true
        manager.settings.defaultSourceID = "ja"
        manager.launcherWillOpen()
        manager.acceptContext(.init(bundleID: "app"))
        XCTAssertTrue(controller.selected.isEmpty)
        manager.launcherDidClose()
        manager.acceptContext(.init(bundleID: "app"))
        XCTAssertEqual(controller.selected, ["ja"])
    }

    func testSystemInputSourceEnumerationIncludesCurrentSource() throws {
        let system = SystemInputSourceController()
        guard let current = system.currentSource() else { throw XCTSkip("No interactive input source is available") }
        XCTAssertTrue(system.availableSources().contains { $0.id == current.id })
    }

    func testFailedAutomaticSelectionDoesNotSuppressLaterManualChoice() throws {
        let clock = FakeInputClock()
        let (manager, controller, _, _) = try makeManager(clock: clock)
        manager.settings.enabled = true
        manager.settings.appRules = [.init(bundleID: "app", name: "App", policy: .remember)]
        manager.acceptContext(.init(bundleID: "app"))
        clock.now += 0.3
        controller.succeeds = false
        XCTAssertFalse(manager.select("en", automatic: true))
        controller.current = controller.sources[1]
        manager.sourceChanged()
        XCTAssertEqual(manager.memory["app"], "en")
    }

    func testWakeDoesNotResumeUntilScreenIsUnlocked() throws {
        let (manager, controller, _, _) = try makeManager()
        manager.settings.enabled = true
        manager.settings.defaultSourceID = "en"
        manager.setScreenLocked(true)
        manager.setSleeping(true)
        manager.setSleeping(false)
        manager.acceptContext(.init(bundleID: "app"))
        XCTAssertTrue(controller.selected.isEmpty)
        manager.setScreenLocked(false)
        manager.acceptContext(.init(bundleID: "app"))
        XCTAssertEqual(controller.selected, ["en"])
    }

    func testOnlyOneShortcutRecordingSessionCanRemainActive() {
        var firstEnded = 0
        var secondEnded = 0
        let first = CarbonHotKeyRegistration.beginRecording({ _ in }, didEnd: { firstEnded += 1 })
        let second = CarbonHotKeyRegistration.beginRecording({ _ in }, didEnd: { secondEnded += 1 })
        XCTAssertEqual(firstEnded, 1)
        CarbonHotKeyRegistration.endRecording(first)
        XCTAssertEqual(secondEnded, 0)
        CarbonHotKeyRegistration.endRecording(second)
        XCTAssertEqual(secondEnded, 1)
    }

    func testBackupValidatesInputSourceFieldsBeforeApplyingAnything() throws {
        let corrupt = try JSONSerialization.data(withJSONObject: ["inputSourceSettings": Data("bad".utf8).base64EncodedString()])
        let config = try JSONDecoder().decode(CommonSettingsView.AppConfiguration.self, from: corrupt)
        XCTAssertThrowsError(try config.validateInputSources())
        let old = try JSONDecoder().decode(CommonSettingsView.AppConfiguration.self, from: Data("{}".utf8))
        XCTAssertNoThrow(try old.validateInputSources())
        let badMemory = try JSONSerialization.data(withJSONObject: ["inputSourceAppMemory": Data("[]".utf8).base64EncodedString()])
        let configWithBadMemory = try JSONDecoder().decode(CommonSettingsView.AppConfiguration.self, from: badMemory)
        XCTAssertThrowsError(try configWithBadMemory.validateInputSources())
    }

    func testMigrationReloadAndOlderBackupCompatibility() throws {
        let (manager, _, store, directory) = try makeManager()
        manager.settings.enabled = true
        manager.settings.appRules = [.init(bundleID: "app", name: "App", sourceID: "en")]
        let destination = temporaryDirectory()
        let oldDirectory = directory.currentDirectory
        try directory.changeDirectory(to: destination)
        try store.reload()
        manager.reload()
        XCTAssertTrue(manager.settings.enabled)
        XCTAssertEqual(manager.settings.appRules.first?.sourceID, "en")
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldDirectory.path))
        let backup = try JSONDecoder().decode(CommonSettingsView.AppConfiguration.self, from: Data("{}".utf8))
        XCTAssertNil(backup.inputSourceSettings)
        XCTAssertNil(backup.inputSourceAppMemory)
        XCTAssertFalse(manager.importSettings(Data("bad".utf8)))
        XCTAssertTrue(manager.settings.enabled)
    }

    func testShortcutConflictsPreservePreviousBinding() throws {
        let (manager, _, _, _) = try makeManager()
        let id = UUID()
        manager.settings.shortcuts = [.init(id: id, sourceIDs: ["en"])]
        let conflictID = UUID()
        let configuration = HotKeyConfiguration(key: .k, modifiers: [.command, .option, .shift])
        let action = ShortcutAction.quickShortcut(conflictID)
        XCTAssertNil(ShortcutRegistryStore.shared.register(action: action, trigger: .keyboard(configuration)))
        defer { ShortcutRegistryStore.shared.unregister(action: action) }
        XCTAssertFalse(manager.updateShortcut(id, configuration: configuration))
        XCTAssertNil(manager.settings.shortcuts[0].configuration)
        XCTAssertFalse(manager.updateShortcut(id, configuration: .init(key: .a, modifiers: [])))
        XCTAssertTrue(manager.updateShortcut(id, configuration: .init(key: .j, modifiers: [.control, .option])))
        let secondID = UUID()
        manager.settings.shortcuts.append(.init(id: secondID, sourceIDs: ["zh"]))
        XCTAssertFalse(manager.updateShortcut(secondID, configuration: .init(key: .j, modifiers: [.control, .option])))
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xxmac-input-tests-" + UUID().uuidString)
        roots.append(url)
        return url
    }

    private func makeManager(clock: FakeInputClock = FakeInputClock(), indicator: InputSourceIndicatorPresenting = FakeInputSourceIndicator()) throws -> (InputSourceAutomationManager, FakeInputSourceController, PreferencesStore, ConfigDirectoryManager) {
        let suite = "xxMac.input.tests." + UUID().uuidString
        suites.append(suite)
        let defaults = UserDefaults(suiteName: suite)!
        let directory = ConfigDirectoryManager(defaults: defaults, applicationSupportURL: temporaryDirectory())
        let store = try PreferencesStore(configDirectoryManager: directory, legacyDefaults: defaults)
        let controller = FakeInputSourceController()
        let manager = InputSourceAutomationManager(store: store, controller: controller, indicator: indicator,
                                                  isOwnApplicationActive: { clock.ownApplicationActive }, uptime: { clock.now }, frontmostBundleID: { clock.bundleID })
        return (manager, controller, store, directory)
    }
}

private final class FakeInputClock {
    var now: TimeInterval = 100
    var bundleID = "app"
    var ownApplicationActive = false
}

private final class FakeInputSourceController: InputSourceControlling {
    let sources = [InputSourceDescriptor(sourceID: "zh", name: "Chinese"),
                   InputSourceDescriptor(sourceID: "en", name: "English"),
                   InputSourceDescriptor(sourceID: "ja", name: "Japanese")]
    var current: InputSourceDescriptor?
    var selected: [String] = []
    var succeeds = true
    init() { current = sources[0] }
    func availableSources() -> [InputSourceDescriptor] { sources }
    func currentSource() -> InputSourceDescriptor? { current }
    func selectSource(id: String) -> Bool {
        guard succeeds, let source = sources.first(where: { $0.id == id }) else { return false }
        selected.append(id)
        current = source
        return true
    }
}

private final class FakeInputSourceIndicator: InputSourceIndicatorPresenting {
    var shownSourceIDs: [String] = []
    func show(source: InputSourceDescriptor, settings: InputSourceSettings) { shownSourceIDs.append(source.id) }
    func hide() {}
}
