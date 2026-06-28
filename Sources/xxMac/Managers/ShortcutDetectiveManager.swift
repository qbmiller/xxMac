import Foundation
import AppKit
import ApplicationServices

struct ShortcutDetection {
    let actionName: String?
    let hotkeyDisplay: String
    let handlerAppName: String
    let handlerBundleIdentifier: String
    let frontmostAppName: String
    let frontmostBundleIdentifier: String
    let timestamp: Date
    let isBackgroundHandler: Bool
    let isSynthesized: Bool
    let suspectedHandlers: [String]

    var displayActionName: String {
        actionName ?? L10n.t("shortcut.detected_shortcut")
    }
}

final class ShortcutDetectiveManager: ObservableObject {
    static let shared = ShortcutDetectiveManager()

    private let enabledKey = "ShortcutDetectiveEnabled"
    private var tipWindowController = ShortcutTipWindowController()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastEventTime: TimeInterval = 0
    private var lastShortcut = ""

    @Published var isEnabled: Bool {
        didSet {
            PreferencesStore.shared.set(isEnabled, forKey: enabledKey)
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }

    @Published private(set) var lastDetection: ShortcutDetection?

    private init() {
        if let stored = PreferencesStore.shared.boolObject(forKey: enabledKey) {
            isEnabled = stored
        } else {
            isEnabled = false
            PreferencesStore.shared.set(false, forKey: enabledKey)
        }
        if isEnabled {
            startMonitoring()
        }
    }

    func recordHotkeyReception(for action: WindowAction, hotkeyDisplay: String) {
        guard isEnabled else { return }

        let app = NSRunningApplication.current
        let frontmost = NSWorkspace.shared.frontmostApplication
        let detection = ShortcutDetection(
            actionName: action.displayName,
            hotkeyDisplay: hotkeyDisplay,
            handlerAppName: app.localizedName ?? "xxMac",
            handlerBundleIdentifier: app.bundleIdentifier ?? Bundle.main.bundleIdentifier ?? L10n.t("shortcut.unknown_bundle"),
            frontmostAppName: frontmost?.localizedName ?? L10n.t("shortcut.unknown_app"),
            frontmostBundleIdentifier: frontmost?.bundleIdentifier ?? L10n.t("shortcut.unknown_bundle"),
            timestamp: Date(),
            isBackgroundHandler: frontmost?.processIdentifier != app.processIdentifier,
            isSynthesized: false,
            suspectedHandlers: []
        )

        publish(detection)
    }

    func clearLastDetection() {
        lastDetection = nil
    }

    private func startMonitoring() {
        guard eventTap == nil else { return }

        guard AccessibilityManager.shared.ensureAccessibilityPermissions() else {
            isEnabled = false
            return
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: shortcutDetectiveEventCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            NSLog("[ShortcutDetective] failed to create CGEventTap")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[ShortcutDetective] event tap started")
    }

    private func stopMonitoring() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        NSLog("[ShortcutDetective] event tap stopped")
    }

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passRetained(event)
        }

        let flags = event.flags
        let modifiers = shortcutModifiers(from: flags)
        guard !modifiers.isEmpty else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let shortcut = modifiers.joined() + keyCodeToString(keyCode)
        let currentTime = Date().timeIntervalSince1970
        let timeSinceLastEvent = currentTime - lastEventTime

        let workspace = NSWorkspace.shared
        let frontmost = workspace.frontmostApplication
        let frontmostName = frontmost?.localizedName ?? L10n.t("shortcut.unknown_app")
        let frontmostBundleID = frontmost?.bundleIdentifier ?? L10n.t("shortcut.unknown_bundle")
        let frontmostPID = frontmost?.processIdentifier ?? 0

        let targetPID = event.getIntegerValueField(.eventTargetUnixProcessID)
        let sourcePID = event.getIntegerValueField(.eventSourceUnixProcessID)
        let isHardwareEvent = sourcePID == 0
        let isSynthesized = !isHardwareEvent || (timeSinceLastEvent < 0.1 && !lastShortcut.isEmpty)

        let handlerApp: NSRunningApplication?
        if isSynthesized, sourcePID != 0 {
            handlerApp = NSRunningApplication(processIdentifier: pid_t(sourcePID))
        } else if targetPID != 0, targetPID != frontmostPID {
            handlerApp = NSRunningApplication(processIdentifier: pid_t(targetPID))
        } else {
            handlerApp = frontmost
        }

        let handlerName = handlerApp?.localizedName ?? frontmostName
        let handlerBundleID = handlerApp?.bundleIdentifier ?? frontmostBundleID
        let suspectedHandlers = knownGlobalShortcutApps(excluding: [frontmostPID, handlerApp?.processIdentifier ?? 0])

        let detection = ShortcutDetection(
            actionName: nil,
            hotkeyDisplay: shortcut,
            handlerAppName: handlerName,
            handlerBundleIdentifier: handlerBundleID,
            frontmostAppName: frontmostName,
            frontmostBundleIdentifier: frontmostBundleID,
            timestamp: Date(),
            isBackgroundHandler: handlerApp?.processIdentifier != nil && handlerApp?.processIdentifier != frontmostPID,
            isSynthesized: isSynthesized,
            suspectedHandlers: suspectedHandlers
        )
        publish(detection)

        lastEventTime = currentTime
        lastShortcut = shortcut

        return Unmanaged.passRetained(event)
    }

    private func publish(_ detection: ShortcutDetection) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastDetection = detection
            self.tipWindowController.show(message: L10n.f("shortcut.tip_message", detection.handlerAppName, detection.hotkeyDisplay))
        }
    }

    private func shortcutModifiers(from flags: CGEventFlags) -> [String] {
        var modifiers: [String] = []
        if flags.contains(.maskControl) { modifiers.append("⌃") }
        if flags.contains(.maskAlternate) { modifiers.append("⌥") }
        if flags.contains(.maskShift) { modifiers.append("⇧") }
        if flags.contains(.maskCommand) { modifiers.append("⌘") }
        if flags.contains(.maskSecondaryFn) { modifiers.append("fn") }
        return modifiers
    }

    private func knownGlobalShortcutApps(excluding excludedPIDs: [pid_t]) -> [String] {
        let knownBundleIDs = [
            "com.raycast.macos",
            "com.runningwithcrayons.Alfred",
            "com.contextsformac.Contexts",
            "com.divisiblebyzero.Spectacle",
            "com.knollsoft.Rectangle",
            "com.BetterTouchTool",
            "com.manytricks.Moom",
            "com.mizage.divvy",
            "org.pqrs.Karabiner-Elements.Settings",
            "org.pqrs.karabiner.karabiner_console_user_server"
        ]

        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard !excludedPIDs.contains(app.processIdentifier),
                  let bundleID = app.bundleIdentifier,
                  knownBundleIDs.contains(where: { bundleID.contains($0) }),
                  let appName = app.localizedName else {
                return nil
            }
            return "\(appName) (\(bundleID))"
        }
    }

    private func keyCodeToString(_ keyCode: Int64) -> String {
        let keyMap: [Int64: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 50: "`",
            36: "Return", 48: "Tab", 49: "Space", 51: "Delete",
            53: "Escape", 64: "F17", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
            100: "F8", 101: "F9", 103: "F11", 105: "F13", 106: "F16",
            107: "F14", 109: "F10", 111: "F12", 113: "F15", 114: "Help",
            115: "Home", 116: "Page Up", 117: "Forward Delete", 118: "F4",
            119: "End", 120: "F2", 121: "Page Down", 122: "F1",
            123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return keyMap[keyCode] ?? "Key(\(keyCode))"
    }
}

private func shortcutDetectiveEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passRetained(event)
    }
    let manager = Unmanaged<ShortcutDetectiveManager>.fromOpaque(userInfo).takeUnretainedValue()
    return manager.handleEvent(type: type, event: event)
}

private final class ShortcutTipWindowController {
    private var panel: NSPanel?
    private var label: NSTextField?
    private var hideWorkItem: DispatchWorkItem?

    func show(message: String) {
        if Thread.isMainThread {
            showOnMain(message: message)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.showOnMain(message: message)
            }
        }
    }

    private func showOnMain(message: String) {
        ensurePanel()
        guard let panel, let label else { return }

        label.stringValue = message
        label.sizeToFit()

        let horizontalPadding: CGFloat = 20
        let verticalPadding: CGFloat = 14
        let width = min(max(label.frame.width + horizontalPadding * 2, 320), 720)
        let height = max(label.frame.height + verticalPadding * 2, 52)

        panel.setContentSize(NSSize(width: width, height: height))
        label.frame = NSRect(
            x: horizontalPadding,
            y: (height - label.frame.height) / 2,
            width: width - horizontalPadding * 2,
            height: label.frame.height
        )

        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            let x = visible.midX - width / 2
            let y = visible.maxY - height - 56
            panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        }

        hideWorkItem?.cancel()
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        let workItem = DispatchWorkItem { [weak panel] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel?.animator().alphaValue = 0
            } completionHandler: {
                panel?.orderOut(nil)
                panel?.alphaValue = 1
            }
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: workItem)
    }

    private func ensurePanel() {
        guard panel == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.ignoresMouseEvents = true

        let container = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        container.autoresizingMask = [.width, .height]
        container.material = .popover
        container.state = .active
        container.blendingMode = .withinWindow
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.frame = NSRect(x: 20, y: 18, width: 380, height: 20)

        container.addSubview(label)
        panel.contentView = container

        self.panel = panel
        self.label = label
    }
}
