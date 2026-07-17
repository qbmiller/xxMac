import AppKit
import Foundation
import HotKey

/// App-level defaults used only when the user has not saved a preference yet.
///
/// Keep these values centralized so first-run behavior is easy to audit.
/// Existing users keep their saved values from `preferences.json`; changing a
/// value here only affects fresh installs or preferences without that key.
enum AppDefaultSettings {
    enum General {
        /// Whether xxMac creates the top-right status bar item on first launch.
        static let showMenuBarItem = true
        static let appLanguage = AppLanguage.english
        static let appSearchPaths = ["/Applications", "/System/Applications", "/System/Library/CoreServices"]
        static let shortcutDetectiveEnabled = false
    }

    enum Clipboard {
        static let monitoringEnabled = false
        static let manageImages = true
        static let imageCacheDurationDays = 7
        static let textCacheDurationDays = 30
        static let maxImageSizeMB = 100
        static let maxHistoryItems = 1000
        static let maxImageStorageSizeMB = 500
        static let thumbnailGenerationThresholdMB = 5
        static let imageOCREnabled = true
        static let maxOCRImageSizeMB = 20
        static let imageOCRLanguages = ["zh-Hans", "en-US"]
    }

    enum LauncherAppearance {
        static let backgroundHex = "#5C9AAF"
        static let opacity = 0.78
        static let sizeScale = 0.82
        static let textScale = 1.0
        static let width = 760.0
        static let height = 328.0
    }

    enum AppLauncher {
        static let finderPath = "/System/Library/CoreServices/Finder.app"
        static let finderKey = Key.f1
        static let finderEnabled = false
    }

    enum HotKeys {
        private static let windowModifiers: NSEvent.ModifierFlags = [.control, .option, .command]

        static let configurations: [WindowAction: HotKeyConfiguration] = [
            .left: HotKeyConfiguration(key: .leftArrow, modifiers: windowModifiers),
            .right: HotKeyConfiguration(key: .rightArrow, modifiers: windowModifiers),
            .top: HotKeyConfiguration(key: .upArrow, modifiers: windowModifiers),
            .bottom: HotKeyConfiguration(key: .downArrow, modifiers: windowModifiers),
            .topLeft: HotKeyConfiguration(key: .one, modifiers: windowModifiers),
            .topRight: HotKeyConfiguration(key: .two, modifiers: windowModifiers),
            .bottomLeft: HotKeyConfiguration(key: .three, modifiers: windowModifiers),
            .bottomRight: HotKeyConfiguration(key: .four, modifiers: windowModifiers),
            .center: HotKeyConfiguration(key: .c, modifiers: windowModifiers),
            .toggleZoom: HotKeyConfiguration(key: .z, modifiers: windowModifiers),
            .maximize: HotKeyConfiguration(key: .m, modifiers: windowModifiers),
            .toggleFullscreen: HotKeyConfiguration(key: .f, modifiers: windowModifiers),
            .increase: HotKeyConfiguration(key: .equal, modifiers: windowModifiers),
            .reduce: HotKeyConfiguration(key: .minus, modifiers: windowModifiers),
            .nextScreen: HotKeyConfiguration(key: .n, modifiers: windowModifiers),
            .previousScreen: HotKeyConfiguration(key: .p, modifiers: windowModifiers),
            .toggleLauncher: HotKeyConfiguration(key: .space, modifiers: [.control, .option]),
            .pasteFinderPath: HotKeyConfiguration(key: .v, modifiers: [.command, .shift]),
            .lockAI: HotKeyConfiguration(key: .l, modifiers: windowModifiers)
        ]
    }

    enum Snippets {
        static let hotKey = HotKeyConfiguration(key: .x, modifiers: [.control, .option, .command])
    }

    enum QuickShortcuts {
        static let shellPath = "/bin/zsh"
        static let commandInputMode = QuickShortcutCommandInputMode.queryPlaceholder
        static let showInFallback = false
        static let webSearchPayload = "https://www.google.com/search?q={query}"
        static let commandPayload = #"""

"""#
        static let commandPreviewQuery = "2026-06-27 21:21:38"
        static let newItemEnabled = false
    }

    enum LockAI {
        static let statusText = "AI Working"
    }

    enum Calendar {
        /// Calendar popover defaults.
        static let showLunar = true
        static let showWeekNumbers = true
        static let firstWeekday = 2

        /// Status bar icon defaults.
        ///
        /// `.calendar` shows the date-style calendar icon.
        /// `.appIcon` shows the xxMac app icon.
        static let menuBarDisplayMode = CalendarMenuBarDisplayMode.calendar
        static let menuBarIconStyle = CalendarMenuBarIconStyle.weekdayDay
    }

    enum LauncherHistory {
        /// Recent launcher actions kept for searchable history replay.
        static let maxItems = 100
    }

    enum BrowserSearch {
        static let isEnabled = true
        static let bookmarkKeyword = "bm"
        static let historyKeyword = "bh"
    }

    enum Updates {
        /// Automatic update checks run weekly unless the user chooses another interval.
        static let frequency = UpdateCheckFrequency.weekly
    }
}
