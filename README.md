# xxMac

[简体中文](README_zh-CN.md) | English

xxMac is a lightweight native macOS status bar productivity tool with an installer of about 2 MB. Built with `SwiftUI + AppKit`, it brings window management, global hotkeys, a launcher, Chinese calendar, shortcut conflict detection, clipboard history, and common productivity workflows into one compact entry point. Its everyday workflow is:

1. A persistent top-right status bar entry.
2. A floating launcher panel opened by a global hotkey.
3. A three-column settings window shown when opening the app directly, with a resizable window and draggable column widths.

## Feature Overview

| Capability | Description | Similar / Alternative |
| --- | --- | --- |
| Launcher | Open a translucent overlay with a global hotkey to search apps, run window commands, and pick clipboard history. The panel reacts immediately after hotkey modifiers are released so rapid first-character input is preserved, and closes as soon as an app launch is submitted without waiting for the target app to finish starting. Supports recent action history, keyboard paging, custom background color, opacity, content size, and window width/height. The panel can be dragged by its background and remembers its last position. | Alfred / Spotlight |
| Launcher Calculator | Type arithmetic expressions such as `4+8`, `(2+3)*4`, or `-3.5/2` directly in the launcher search field to see live results, then press Return to copy the result. | Alfred Calculator / Spotlight |
| App Quick Launch | Bind independent hotkeys to selected apps. Supports launch, activate, hide, and toggle behavior. | Thor |
| Window Management | Quickly move the current window to the left/right half, top/bottom half, four corners, center, maximize, resize, or move it across displays. Requires authorization in System Settings > Privacy & Security > Accessibility; after repackaging or moving the app, remove the old app authorization and add the current app again. | ShiftIt |
| Finder Paste Operations | Press `Command + Shift + V` outside Finder to paste paths for files or folders copied in Finder. With the optional Image to File or Text to File switches enabled under Clipboard > Paste Operations, the same hotkey in Finder saves a raw clipboard image as PNG or plain text as a UTF-8 file in the current folder. Copied files are ignored while Finder is frontmost, so they are never converted or typed back into Finder. | Copy Path / Path Finder |
| Chinese Calendar | Provides a top-right status bar entry, with Chinese lunar calendar, holidays, solar terms, week numbers, and configurable status bar icon styles. | CalendarX |
| Shortcut Capture | Records which app receives a shortcut, helping locate shortcut conflicts. | Shortcut Detective |
| Todo | Open an independent resizable window for local tasks. It includes a dedicated 2 x 2 Eisenhower matrix, All/Today/status views, card and list layouts, and an expandable three-column Todo/In Progress/Completed board. Tasks support title, notes, quadrant, minute-precision deadline, search, editing, archive/permanent delete, status rollback, and drag-and-drop ordering across quadrants or status columns. Task title font size is configurable under Settings > Todo > General. Completed tasks stay visible in their quadrant with strikethrough styling. | Microsoft To Do / TickTick / Trello |
| Todo Desktop Widget | On macOS 14 or later, add the medium xxMac Todo widget from the desktop's Edit Widgets gallery. It includes every incomplete, unarchived task. Settings > Todo > Widget provides a 9–13 pt font size, with 10–7 tasks shown per page depending on the selected size, ordered by Today (overdue and due today), In Progress, then Todo. Use the header arrows to browse every page, complete a task directly from the widget, or click elsewhere to open the Todo window. Use Show Desktop, including F11 when configured for that action, to view it on the desktop. | WidgetKit / TickTick Widget |
| Clipboard History [disabled by default] | Records text and image clipboard items, persists them with SQLite, and supports search, preview, paste-back, favorites, and pinned favorites. Search matches both prefixes and middle substrings, including OCR text and literal symbols. Searching from History merges matching Favorites into the results and removes duplicate records. The panel opens on History by default; use Tab / Shift+Tab to switch between History, Image History, Favorites, and Snippets. Selecting Image History writes `img` into the search field and shows only images. Press Command+Space on a selected image to enlarge its original in an app-managed screen-level preview; plain Space remains available for extending the search query. The preview supports trackpad pinch-to-zoom and panning. At 1x, drag the image to move the preview anywhere on screen; when zoomed in, drag or scroll to inspect the image. Press Command+Space or Escape to close only the image preview and keep the clipboard panel open. Command+Return favorites the selected History or Image History item. Command+Delete removes the selected item from the current History, Image History, or Favorites list; a favorited item removed from History remains available in Favorites. In Favorites, the red star removes an item from Favorites and the pin button pins or unpins it within the Favorites list. Favorited records are protected from automatic and manual history cleanup until removed from Favorites. Large text previews show only the first part while paste-back keeps the full content; images above the configured threshold get thumbnail previews; local OCR is enabled by default and stores recognized image text as searchable metadata. | Clipboard manager |
| Snippets | Provides Alfred-style snippet categories, entries, and keyword search. Open the search panel with a global hotkey, select an entry on the left, preview it on the right, then press Return to type it into the frontmost app and copy it to the system clipboard. | Alfred Snippets |
| Quick Shortcut Search | Trigger web searches from the launcher with custom keywords and URL templates. Typing an exact keyword keeps matching apps visible; adding a space enters shortcut-only mode. Shortcuts can also be pinned into launcher results for Google, Baidu, and similar search entries. | Alfred Web Search |
| Quick Shortcut Scripts | Run local command scripts from launcher keywords. Scripts support no-input, `{query}` single-argument, and `argv` multi-argument modes. They run after input remains stable for about 400 ms, so continuous typing only executes the latest pending input. Complex scripts can live under the configuration folder's `quick/` directory. | Alfred Workflows |
| Browser Search | Use `bm` to search bookmarks and `bh` to search history in the current Chrome/Edge profile. The browser and both keywords are configurable under Search > Browser Search. | Alfred Browser Bookmarks |
| Update Checks | Check GitHub Releases manually or automatically on a daily, weekly, or monthly schedule from About. The GitHub Releases URL shown in About is clickable and opens in the default browser. Automatic checks default to weekly and stay silent; when an update is available, a red update button appears on the right side of the launcher and opens the Releases page. | Sparkle |
| LockJob | Cover all displays and prevent system sleep while Claude, Codex, builds, downloads, and SSH sessions continue running. Shows the time and custom status text, and supports Touch ID or local password unlock. | Screen cover |
| Localization | Includes resource structure for Simplified Chinese, Traditional Chinese, and English. | - |

<p align="center">
  <img src="docs/images/003.png" width="49%" alt="">
  <img src="docs/images/004.png" width="49%" alt="">
</p>

<p align="center">
  <img src="docs/images/005.png" width="49%" alt="">
  <img src="docs/images/006.png" width="49%" alt="">
</p>

<p align="center">
  <img src="docs/images/007.png" width="49%" alt="">
  <img src="docs/images/008.png" width="49%" alt="">
</p>

<p align="center">
  <img src="docs/images/009.png" width="49%" alt="">
  <img src="docs/images/010.png" width="49%" alt="">
</p>

<p align="center">
  <img src="docs/images/image.png" width="45%" alt="">
</p>

## 友情链接
- [亚洲规模最大的大模型 API 网关之一，全球规模仅次于 OpenRouter](https://www.orcarouter.ai/ref/ref_d47b119eebf4f9e2efd8)也长期提供免费模型使用

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
| `Control + Option + Command + L` | LockJob: cover the displays and keep work running |
| `Control + Option + Command + X` | Open Snippets search |
| `Command + Shift + V` | Paste copied Finder paths, or run enabled image/text-to-file operations in Finder |
| `Command + Option + T` | Open or close the independent Todo window |

All of these hotkeys can be changed in the settings window. xxMac checks window, common, app-launch, clipboard, and Snippets hotkeys together and rejects duplicate combinations inside the app. Launcher text keywords use a separate conflict namespace.

After searching for an app, use `Up`/`Down` or `Page Up`/`Page Down` to select a result, then press `Return` to open it. Arithmetic expressions such as `4+8` and `(2+3)*4` show a live result that can be copied with `Return`. Holding `Command` changes the selected app action to `Reveal in Finder`. The launcher records recently executed apps, window commands, quick shortcuts, and calculator results, keeping up to 100 entries by default; this can be adjusted or cleared under Search > General. With an empty query, pinned quick shortcuts remain visible, and pressing a direction key switches the result list to recent action history while showing the selected action's complete input in the search field. Clipboard history and Snippets are never added to launcher action history.

Browser Search initially selects Chrome or Microsoft Edge from the macOS default browser and can then be overridden in settings. xxMac uses the most recently used profile recorded in Chromium `Local State`; this release does not merge profiles or expose profile selection. Type `bm query` for bookmarks or `bh query` for history, or enter only the keyword for unfiltered candidates. Both keywords are configurable and cannot duplicate each other or an enabled Quick Shortcut. Return always opens the result in the browser selected in xxMac.

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
make build
# Equivalent: bash bundle_app.sh
```

After bundling, the script asks whether to replace `/Applications/xxMac.app`; the default is no. Enter `y` or `yes` to close the running xxMac, replace the installed app, reload the Todo widget extension, and reopen xxMac automatically. Use `INSTALL_TO_APPLICATIONS=1 bash bundle_app.sh` to explicitly skip the prompt and replace it automatically.

Build a `.dmg` release:

```bash
make deploy
# Equivalent: bash publish_dmg.sh
```

The release script first prints the current version recorded in `Sources/xxMac/Info.plist`, then prompts for the release version. The version is written back to `CFBundleShortVersionString` and `CFBundleVersion`, the latest update date is written to `XXLastUpdated`, and the generated DMG is named `xxMac-version.dmg` by default.

After entering the version, choose whether to publish a GitHub Release. When enabled, the script checks `gh auth status`, prompts for a release title, and opens a temporary Markdown file in `${VISUAL:-${EDITOR:-vi}}`. After the editor exits, the script previews the release notes; enter `e` to edit again, `y` to accept them, or `n` to cancel GitHub publishing while continuing the local DMG build. Set `EDITOR='code --wait'` to use VS Code. The script builds and verifies the DMG, then shows a final summary before calling `gh release create`. Run `gh auth login -h github.com` first when authentication has expired. The script does not run `git commit` or `git push`; if the numeric release tag does not already exist, GitHub creates it from the latest default branch.

`bundle_app.sh` and `publish_dmg.sh` use the fixed signing identity `qbmiller` by default and do not fall back to ad-hoc signing. This helps macOS associate Accessibility permission with a stable app identity and reduces the need to remove and re-add authorization after rebuilding. Set the `SIGNING_IDENTITY` environment variable to temporarily use another certificate.

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
2. Automation: required for Finder image/text-to-file paste operations and may also be used by app activation, reopening windows, and clipboard paste-back flows. xxMac checks existing Finder permission first, then requests it only when needed from General > Permissions or the first Finder conversion. If it was denied, enable System Settings > Privacy & Security > Automation > xxMac > Finder.

You can check Accessibility authorization under xxMac > General > Permission Settings and use Get Accessibility Permission to open the corresponding macOS settings page.

If window control, global hotkeys, or clipboard paste-back stop working after repackaging, first check whether the app authorized in the system Accessibility list is the `xxMac.app` at the current path. macOS Accessibility authorization is affected by the app path and signing state, so repackaging or moving the app may require removing the old authorization and adding it again.

## Configuration and Data

- The default configuration folder is `~/Library/Application Support/xxMac`, and it can be changed from General > Configuration. Changing it moves the current preferences, app index cache, clipboard SQLite database, Todo SQLite database, and image cache to the new folder, then removes xxMac data from the old folder.
- The top-right status bar entry is shown by default. If the icon disappears or you want to hide it, use General > Configuration > Show in top-right status bar. The same area includes status bar diagnostics and a Refresh/Recreate button to confirm whether the `NSStatusItem` exists, is visible, and is attached to the system status bar.
- The configuration folder can be local or managed by a sync service such as iCloud Drive or Dropbox, as long as files stay available offline. Avoid system folders, the app bundle, and temporary removable drives.
- Hotkey settings, app quick-launch settings, launcher appearance, overall scale, text size, launcher action history, language preferences (including the off-by-default English input option when opening Launcher), application search and excluded paths, quick shortcuts, browser search, Snippets, calendar preferences, and update-check state are stored in `preferences.json` inside the configuration folder. When enabled, the input option switches to the macOS ABC English input source as Launcher opens. Update checking stores `UpdateCheckFrequency`, `UpdateLastSuccessfulCheck`, and `UpdateAvailableVersion`; the first-run interval is weekly. Launcher action history stores only metadata for apps, window commands, quick shortcuts, and calculator results; it excludes clipboard history and Snippets. It keeps up to 100 entries by default and can be configured under Search > General. Calendar status bar display defaults to the calendar icon and can be changed to the App icon. First-run defaults are centralized in `Sources/xxMac/AppDefaultSettings.swift`, where comments can document each default switch.
- Finder paste-operation switches and their independent daily image/text counters are stored in `preferences.json`. Both conversion switches default to off. Generated files stay in the selected Finder folder, are not copied into the xxMac configuration directory, and are not included by Export Configuration.
- xxMac creates `quick/` inside the configuration folder for complex quick shortcut scripts. Command scripts receive `XXMAC_HOME` for the configuration folder and `XXMAC_QUICK_HOME` for `quick/`, for example `python "$XXMAC_QUICK_HOME/xxx/a.py" {query}`. Web-search shortcut favicons are cached in `quick_icons/` for the settings list and launcher results; deleting a shortcut or changing its website removes the corresponding cached icon.
- App search covers `/Applications`, `/System/Applications`, and `/System/Library/CoreServices` by default, with support for custom search paths. Search > Excluded Paths accepts user-selected directories and omits applications in those directories and all of their descendants from launcher results. Index rebuilds use macOS Spotlight to discover applications first and automatically fall back to directory scanning when Spotlight is unavailable or returns no usable results. The app index cache is stored as `app-search-index.json` in the configuration folder and is validated against existing app bundles before use, so deleted apps, excluded paths, and transient `.app.installing` paths are filtered out. New apps added to these search folders are appended to the existing index, and removed apps are pruned without rebuilding the whole index; Index Applications under General > Configuration performs a manual rebuild. Chinese app names are indexed by original text, full pinyin, and pinyin initials; English app names are also indexed by word initials.
- Browser bookmarks and history remain in Chrome/Edge's own directories and are read locally and read-only. History search creates a uniquely named system-temporary copy and removes it immediately after the query; browser data is not written, exported, or migrated into the xxMac configuration folder.
- The clipboard database, original image cache, and thumbnail cache are stored as `clipboard.db`, `clipboard_images/`, and `clipboard_thumbnails/` inside the configuration folder. Clipboard favorite, favorite-pin, and history visibility state is stored in `clipboard.db`; removing an item from Favorites keeps the underlying history record and clears its favorite pin when the item is still visible in History.
- Todo tasks are stored locally in `todo.db` inside the configuration folder. The database and its SQLite sidecar files move when the configuration folder changes. Regenerable widget snapshots, widget appearance settings, page state, and pending completion actions stay in `~/Library/Application Support/xxMac/Widget/` and do not move with the configuration folder. The Widget sandbox is granted access only to that dedicated directory. Todo does not implement iCloud or CloudKit sync.
- To add the desktop widget on macOS 14 or later, right-click the desktop, choose Edit Widgets, search for xxMac Todo, and add the medium widget. Its placement is managed by macOS and is independent of the Todo app window.
- Clipboard history records every non-empty text value that reaches the system clipboard. If a browser or password manager allows a password to be copied to the system clipboard, it will be recorded too. If the page or app does not actually write to the system clipboard, xxMac cannot capture it.
- Export Configuration only exports configurable settings. It does not export Todo tasks, `todo.db`, clipboard history, `clipboard.db`, image cache, thumbnail cache, quick-shortcut favicon cache, or app index cache; use the configuration folder switch for a full migration.
- Image and text conversion use separate daily sequences such as `20260825-001.png` and `20260825-001.json`. Each sequence resets to `001` on a new day and can also be reset under Clipboard > Paste Operations. xxMac does not scan the target folder to restore a counter and never overwrites an existing file; a collision adds a Unix timestamp. Images are always encoded as PNG. Text detection supports JSON, plist, XML, YAML (`.yml`), TOML, INI, and ENV; text without a reliable match is saved without an extension.
- General > Configuration includes a Quit Application button at the bottom and asks for confirmation before quitting.
- The maximum clipboard history count, image cache limit, and clipboard text preview font size can be configured in Clipboard General. Defaults are 1000 items, 500 MB, and 16 pt.
- Image thumbnails are generated only when an image exceeds the configured threshold. The default threshold is 5 MB and can be changed in Clipboard General.
- Image OCR is enabled by default. xxMac uses macOS Vision locally on this Mac and does not upload images. Recognized text is stored in `clipboard.db` as image metadata for clipboard search; Export Configuration does not export OCR history metadata.
- In the settings window, the first column is tool categories with color-coded icons and a current-plan indicator, the second column is feature items, and the third column contains detailed configuration. All users currently see Free; the indicator can switch to VIP after paid membership is introduced.

## Directory Structure

```text
xxMac/
├── Package.swift
├── README.md
├── README_zh-CN.md
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
