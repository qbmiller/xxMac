import AppKit
import HotKey
import XCTest
@testable import xxMac

final class AppLauncherHotKeyRoutingTests: XCTestCase {
    func testAppShortcutsHaveEventTapFallbackAndRespectRecordingPause() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let directories = ConfigDirectoryManager(defaults: defaults, applicationSupportURL: root)
        let preferences = try PreferencesStore(configDirectoryManager: directories, legacyDefaults: defaults)
        let shortcut = AppShortcut(appName: "Test App", appPath: "/test/Test.app", key: .f18,
                                   modifiers: [.control, .option], isEnabled: true)
        try preferences.set(JSONEncoder().encode([shortcut]), forKey: "AppLauncherShortcuts")
        var launchedPaths: [String] = []
        let manager = AppLauncherManager(preferencesStore: preferences) { launchedPaths.append($0) }
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil,
                                         virtualKey: CGKeyCode(Key.f18.carbonKeyCode), keyDown: true))
        event.flags = [.maskControl, .maskAlternate]
        func pressShortcut() {
            _ = CarbonHotKeyRegistration.handleTap(type: .keyDown, event: event)
        }

        pressShortcut()
        XCTAssertEqual(launchedPaths, [shortcut.appPath], "App shortcuts must still fire when Carbon delivery is unavailable")

        let first = manager.pauseHotKeys()
        let second = manager.pauseHotKeys()
        pressShortcut()
        XCTAssertEqual(launchedPaths.count, 1)
        manager.resumeHotKeys(first)
        pressShortcut()
        XCTAssertEqual(launchedPaths.count, 1)
        manager.resumeHotKeys(second)
        pressShortcut()
        XCTAssertEqual(launchedPaths.count, 2)

        manager.removeShortcut(id: shortcut.id)
        pressShortcut()
        XCTAssertEqual(launchedPaths.count, 2)
    }
}
