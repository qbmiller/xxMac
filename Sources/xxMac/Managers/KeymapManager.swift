import AppKit
import SwiftUI
import ApplicationServices
import Carbon.HIToolbox

struct KeymapMenuItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let shortcut: String
    let depth: Int
    let enabled: Bool
}

struct KeymapColumn: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let items: [KeymapMenuItem]
}

struct KeymapSnapshot {
    let appName: String
    let bundleIdentifier: String
    let items: [KeymapMenuItem]
    let columns: [KeymapColumn]
    let capturedAt: Date
}

struct KeymapDoubleTapProcessor {
    enum Output: Equatable { case none, triggered }

    private let doubleTapWindow: TimeInterval
    private var commandHeld = false
    private var awaitingSecondTap = false
    private var secondTapCandidate = false
    private var lastTapAt: Date?

    init(doubleTapWindow: TimeInterval = 0.3) {
        self.doubleTapWindow = doubleTapWindow
    }

    mutating func process(commandDown: Bool, hasOtherModifiers: Bool, at date: Date) -> Output {
        if hasOtherModifiers {
            commandHeld = false
            awaitingSecondTap = false
            secondTapCandidate = false
            lastTapAt = nil
            return .none
        }

        if commandDown {
            guard !commandHeld else { return .none }
            commandHeld = true
            secondTapCandidate = awaitingSecondTap && lastTapAt.map { date.timeIntervalSince($0) < doubleTapWindow } == true
            return .none
        }

        guard commandHeld else { return .none }
        commandHeld = false
        if secondTapCandidate {
            awaitingSecondTap = false
            secondTapCandidate = false
            lastTapAt = nil
            return .triggered
        }

        awaitingSecondTap = true
        lastTapAt = date
        return .none
    }

    mutating func cancel() {
        commandHeld = false
        awaitingSecondTap = false
        secondTapCandidate = false
        lastTapAt = nil
    }
}

final class KeymapManager: ObservableObject {
    static let shared = KeymapManager()
    private let enabledKey = "KeymapEnabled"
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var doubleTapProcessor = KeymapDoubleTapProcessor()
    private var panelController: KeymapPanelController?

    @Published var isEnabled: Bool {
        didSet {
            if isEnabled {
                refreshPermissionStatus()
                guard hasAccessibilityPermission else {
                    isEnabled = false
                    return
                }
            }
            PreferencesStore.shared.set(isEnabled, forKey: enabledKey)
            isEnabled ? startMonitoring() : stopMonitoring()
        }
    }
    @Published private(set) var hasAccessibilityPermission: Bool
    @Published private(set) var snapshot: KeymapSnapshot?

    private init() {
        hasAccessibilityPermission = AccessibilityManager.shared.hasAccessibilityPermissions()
        isEnabled = PreferencesStore.shared.boolObject(forKey: enabledKey) ?? AppDefaultSettings.General.keymapEnabled
        if isEnabled && hasAccessibilityPermission { startMonitoring() }
    }

    func togglePanel() {
        if panelController?.window?.isVisible == true {
            panelController?.close()
        } else {
            refreshAndShow()
        }
    }

    func refreshAndShow() {
        panelController = panelController ?? KeymapPanelController(manager: self)
        refreshPermissionStatus()
        guard hasAccessibilityPermission else {
            panelController?.show(snapshot: nil)
            return
        }
        snapshot = Self.readMenus(from: NSWorkspace.shared.frontmostApplication)
        panelController?.show(snapshot: snapshot)
    }

    func requestAccessibilityPermission() {
        _ = AccessibilityManager.shared.requestAccessibilityPermissions()
        refreshPermissionStatus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.refreshPermissionStatus()
            if self.hasAccessibilityPermission && self.isEnabled { self.startMonitoring() }
        }
    }

    func refreshPermissionStatus() {
        hasAccessibilityPermission = AccessibilityManager.shared.hasAccessibilityPermissions()
    }

    private func startMonitoring() {
        guard eventTap == nil else { return }
        refreshPermissionStatus()
        guard hasAccessibilityPermission else { return }
        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)
        )
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: keymapEventCallback,
                                          userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())) else {
            NSLog("[Keymap] failed to create event tap")
            return
        }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource { CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopMonitoring() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        doubleTapProcessor = KeymapDoubleTapProcessor()
    }

    fileprivate func handle(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.type == .keyDown {
            doubleTapProcessor.cancel()
            return Unmanaged.passRetained(event)
        }
        guard event.type == .flagsChanged else { return Unmanaged.passRetained(event) }
        let flags = event.flags
        let hasOtherModifiers = flags.contains(.maskControl) ||
            flags.contains(.maskAlternate) ||
            flags.contains(.maskShift) ||
            flags.contains(.maskSecondaryFn)
        let output = doubleTapProcessor.process(
            commandDown: flags.contains(.maskCommand),
            hasOtherModifiers: hasOtherModifiers,
            at: Date()
        )
        if output == .triggered {
            DispatchQueue.main.async { [weak self] in self?.togglePanel() }
        }
        return Unmanaged.passRetained(event)
    }

    static func readMenus(from app: NSRunningApplication?) -> KeymapSnapshot? {
        guard let app else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMenuBarAttribute as CFString, &value) == .success,
              let value else { return KeymapSnapshot(appName: app.localizedName ?? "", bundleIdentifier: app.bundleIdentifier ?? "", items: [], columns: [], capturedAt: Date()) }
        var items: [KeymapMenuItem] = []
        var columns: [KeymapColumn] = []
        let menuBar = value as! AXUIElement
        var childrenValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement] {
            for child in children {
                let title = stringAttribute(child, kAXTitleAttribute as CFString) ?? ""
                guard !title.isEmpty else { continue }
                var columnItems: [KeymapMenuItem] = []
                collectMenus(child, depth: 0, into: &columnItems)
                if !columnItems.isEmpty {
                    columns.append(KeymapColumn(title: title, items: columnItems))
                    items.append(contentsOf: columnItems)
                }
            }
        }
        return KeymapSnapshot(appName: app.localizedName ?? "", bundleIdentifier: app.bundleIdentifier ?? "", items: items, columns: columns, capturedAt: Date())
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    private static func collectMenus(_ element: AXUIElement, depth: Int, into items: inout [KeymapMenuItem]) {
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else { return }
        for child in children {
            var titleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleValue)
            let title = titleValue as? String ?? ""
            var charValue: CFTypeRef?
            AXUIElementCopyAttributeValue(child, "AXMenuItemCmdChar" as CFString, &charValue)
            var character = charValue as? String ?? ""
            if character.isEmpty {
                var glyphValue: CFTypeRef?
                AXUIElementCopyAttributeValue(child, "AXMenuItemCmdGlyph" as CFString, &glyphValue)
                if let glyph = (glyphValue as? NSNumber)?.intValue {
                    character = glyphCharacter(glyph)
                }
            }
            var modifiersValue: CFTypeRef?
            AXUIElementCopyAttributeValue(child, "AXMenuItemCmdModifiers" as CFString, &modifiersValue)
            let modifiers = (modifiersValue as? NSNumber)?.intValue ?? 0
            var enabledValue: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXEnabledAttribute as CFString, &enabledValue)
            let enabled = (enabledValue as? NSNumber)?.boolValue ?? true
            if !title.isEmpty && !character.isEmpty {
                items.append(KeymapMenuItem(title: title, shortcut: Self.formatShortcut(character: character, modifiers: modifiers), depth: depth, enabled: enabled))
            }
            collectMenus(child, depth: depth + 1, into: &items)
        }
    }

    static func formatShortcut(character: String, modifiers: Int) -> String {
        var result = ""
        if containsModifier(modifiers, lowBit: 8, rawValue: NSEvent.ModifierFlags.control.rawValue, carbonBit: 4096) { result += "⌃" }
        if containsModifier(modifiers, lowBit: 4, rawValue: NSEvent.ModifierFlags.option.rawValue, carbonBit: 2048) { result += "⌥" }
        if containsModifier(modifiers, lowBit: 2, rawValue: NSEvent.ModifierFlags.shift.rawValue, carbonBit: 512) { result += "⇧" }
        if containsModifier(modifiers, lowBit: 1, rawValue: NSEvent.ModifierFlags.command.rawValue, carbonBit: 256) { result += "⌘" }
        return result + character.uppercased()
    }

    private static func containsModifier(_ modifiers: Int, lowBit: Int, rawValue: UInt, carbonBit: Int) -> Bool {
        let raw = Int(rawValue)
        return modifiers & lowBit != 0 || modifiers & raw != 0 || modifiers & carbonBit != 0
    }

    private static func glyphCharacter(_ glyph: Int) -> String {
        switch glyph {
        case 0xF700: return "↑"
        case 0xF701: return "↓"
        case 0xF702: return "←"
        case 0xF703: return "→"
        case 0xF704: return "↖"
        case 0xF705: return "↘"
        case 0xF706: return "↙"
        case 0xF707: return "↗"
        case 0xF708: return "⇞"
        case 0xF709: return "⇟"
        case 0xF72C: return "↩"
        case 0xF72B: return "⌫"
        case 0xF721: return "↖"
        case 0xF729: return "↘"
        case 0xF72D: return "⎋"
        default:
            guard let scalar = UnicodeScalar(glyph) else { return "" }
            return String(scalar)
        }
    }
}

private func keymapEventCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passRetained(event) }
    return Unmanaged<KeymapManager>.fromOpaque(userInfo).takeUnretainedValue().handle(event)
}

final class KeymapPanelController: NSWindowController {
    init(manager: KeymapManager) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560), styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Keymap"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: KeymapPanelView(manager: manager))
        super.init(window: panel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(snapshot: KeymapSnapshot?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
