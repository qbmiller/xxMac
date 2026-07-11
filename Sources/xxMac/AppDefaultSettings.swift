import Foundation

/// App-level defaults used only when the user has not saved a preference yet.
///
/// Keep these values centralized so first-run behavior is easy to audit.
/// Existing users keep their saved values from `preferences.json`; changing a
/// value here only affects fresh installs or preferences without that key.
enum AppDefaultSettings {
    enum General {
        /// Whether xxMac creates the top-right status bar item on first launch.
        static let showMenuBarItem = true
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
}
