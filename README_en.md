# xxMac

[简体中文](README.md) | English

xxMac is a native macOS menu bar productivity tool built with `SwiftUI + AppKit`. It brings a launcher, app-specific hotkeys, window management, Chinese calendar, shortcut conflict detection, and clipboard history into one lightweight entry point. Its everyday workflow is:

1. A persistent menu bar entry.
2. A floating launcher panel opened by a global hotkey.
3. A three-column settings window.

## Feature Overview

| Capability | Description | Similar / Alternative |
| --- | --- | --- |
| Launcher | Open a translucent overlay with a global hotkey to search apps, run window commands, and pick clipboard history. Supports custom background color, opacity, content size, and window width/height. | Alfred / Spotlight |
| App Quick Launch | Bind independent hotkeys to selected apps. Supports launch, activate, hide, and toggle behavior. | Thor |
| Window Management | Quickly move the current window to the left/right half, top/bottom half, four corners, center, maximize, resize, or move it across displays. Requires authorization in System Settings > Privacy & Security > Accessibility; after repackaging or moving the app, remove the old app authorization and add the current app again. | ShiftIt |
| Chinese Calendar | Shows the date in the menu bar, with Chinese lunar calendar, holidays, solar terms, week numbers, and configurable menu bar style. | CalendarX |
| Shortcut Capture | Records which app receives a shortcut, helping locate shortcut conflicts. | Shortcut Detective |
| Clipboard History [disabled by default] | Records text and image clipboard items, persists them with SQLite, and supports search, preview, and paste-back. | Clipboard manager |
| Quick Shortcuts | Use launcher keywords to trigger web searches or command scripts. Command scripts support no-input, `{query}` single-argument, and `argv` multi-argument modes; shortcuts can also be pinned into launcher results, useful for Google, Baidu, and similar search entries. | Alfred Web Search / Workflows |
| Localization | Includes resource structure for Simplified Chinese, Traditional Chinese, and English. | - |

## Default Hotkeys

| Hotkey | Action |
| --- | --- |
| `Control + Option + Space` | Open or close the launcher |
| `Control + Option + Command + ←/→/↑/↓` | Move the current window to the left/right/top/bottom half |
| `Control + Option + Command + 1/2/3/4` | Move the current window to one of the four corners |
| `Control + Option + Command + C` | Center the current window |
| `Control + Option + Command + M` | Maximize the current window |
| `Control + Option + Command + F` | Toggle fullscreen |
| `Control + Option + Command + =/-` | Enlarge or shrink the window |
| `Control + Option + Command + N/P` | Move to the next/previous display |

All of these hotkeys can be changed in the settings window.

## Quick Start

Requirements:

1. macOS 13 or later.
2. Xcode Command Line Tools or Xcode.
3. A Swift 5.9-compatible toolchain.

Run in development:

```bash
swift build
swift run xxMac
```

Bundle as an `.app`:

```bash
bash bundle_app.sh
open xxMac.app
```

Build a `.dmg` release:

```bash
bash publish_dmg.sh
```

The release script first prints the current version recorded in `Sources/xxMac/Info.plist`, then prompts for the release version. The version is written back to `CFBundleShortVersionString` and `CFBundleVersion`, the latest update date is written to `XXLastUpdated`, and the generated DMG is named `xxMac-version.dmg` by default.

If you do not have a developer account, macOS may mark the app as quarantined after it is copied to `/Applications`, preventing it from opening. Clear the quarantine attribute before launching:

```bash
xattr -cr /Applications/xxMac.app
open /Applications/xxMac.app
```

To sign with a developer certificate:

```bash
SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" bash bundle_app.sh
```

## System Permissions

After the first launch, grant permissions in System Settings > Privacy & Security:

1. Accessibility: required for window management, global hotkeys, and simulated paste.
2. Automation: may be used by app activation, reopening windows, and clipboard paste-back flows.

If window control, global hotkeys, or clipboard paste-back stop working after repackaging, first check whether the app authorized in the system Accessibility list is the `xxMac.app` at the current path. macOS Accessibility authorization is affected by the app path and signing state, so repackaging or moving the app may require removing the old authorization and adding it again.

## Configuration and Data

- The default configuration folder is `~/Library/Application Support/xxMac`, and it can be changed from General > Configuration. Changing it moves the current preferences, app index cache, clipboard SQLite database, and image cache to the new folder, then removes xxMac data from the old folder.
- The configuration folder can be local or managed by a sync service such as iCloud Drive or Dropbox, as long as files stay available offline. Avoid system folders, the app bundle, and temporary removable drives.
- Hotkey settings, app quick-launch settings, launcher appearance and size, language preference, quick shortcuts, Snippets, and calendar preferences are stored in `preferences.json` inside the configuration folder.
- xxMac creates `quick/` inside the configuration folder for complex quick shortcut scripts. Command scripts receive `XXMAC_HOME` for the configuration folder and `XXMAC_QUICK_HOME` for `quick/`, for example `python "$XXMAC_QUICK_HOME/xxx/a.py" {query}`.
- App search scans `/Applications`, `/System/Applications`, and `/System/Library/CoreServices` by default. Custom search paths can also be added in settings; the app index cache is stored as `app-search-index.json` in the configuration folder and can be rebuilt from General > Configuration with “Index Applications”. Chinese app names are indexed by original text, full pinyin, and pinyin initials; English app names are also indexed by word initials.
- The clipboard database and image cache are stored as `clipboard.db` and `clipboard_images/` inside the configuration folder.
- Export Configuration only exports configurable settings. It does not export clipboard history, the SQLite database, image cache, or app index cache; use the configuration folder switch for a full migration.
- The maximum clipboard history count and image cache limit can be configured in Clipboard General. Defaults are 1000 items and 500 MB.
- In the settings window, the first column is tool categories, the second column is feature items, and the third column contains detailed configuration.

## Directory Structure

```text
xxMac/
├── Package.swift
├── README.md
├── README_en.md
├── PACKAGING_GUIDE.md
├── bundle_app.sh
├── publish_dmg.sh
├── Resources/
│   ├── AppIcon.icns
│   ├── *.lproj/
│   └── calendar_*.json
├── Sources/xxMac/
│   ├── xxMac.swift
│   ├── Managers/
│   ├── Models/
│   ├── ViewModels/
│   └── Views/
└── docs/
    └── ARCHITECTURE.md
```

## Common Commands

```bash
swift build
swift run xxMac
bash bundle_app.sh
bash publish_dmg.sh
VERSION=0.0.1 bash publish_dmg.sh
xattr -cr /Applications/xxMac.app
log stream --style compact --predicate 'process == "xxMac"'
codesign -v xxMac.app
```

## Documentation

- `docs/ARCHITECTURE.md`: Project architecture, module responsibilities, runtime flow, data configuration, and future task map.
- `PACKAGING_GUIDE.md`: Packaging, signing, permissions, logging, and hotkey troubleshooting.
