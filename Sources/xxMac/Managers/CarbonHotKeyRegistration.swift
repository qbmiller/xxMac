import AppKit
import Carbon
import HotKey
import OSLog

final class CarbonHotKeyRegistration {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "xxMac", category: "CarbonHotKey")
    private static let eventTarget = GetApplicationEventTarget()

    private struct TapRegistration {
        let keyCode: Int64
        let modifiers: CGEventFlags
        let name: String
        let handler: () -> Void
    }

    private static var nextID: UInt32 = 1
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var tapRegistrations: [UInt32: TapRegistration] = [:]
    private static var lastHandledAt: [UInt32: Date] = [:]
    private static var eventHandler: EventHandlerRef?
    private static var eventTap: CFMachPort?
    private static var eventTapRunLoopSource: CFRunLoopSource?
    private static let signature: FourCharCode = {
        var result: FourCharCode = 0
        for character in "XxHK".utf16 {
            result = (result << 8) + FourCharCode(character)
        }
        return result
    }()

    private let id: UInt32
    private let name: String
    private var eventHotKey: EventHotKeyRef?

    init?(configuration: HotKeyConfiguration, name: String = "unnamed", handler: @escaping () -> Void) {
        Self.installEventHandlerIfNeeded()

        id = Self.nextID
        Self.nextID += 1
        self.name = name

        Self.handlers[id] = handler
        Self.tapRegistrations[id] = TapRegistration(
            keyCode: Int64(configuration.key.carbonKeyCode),
            modifiers: Self.cgEventFlags(from: configuration.modifiers),
            name: name,
            handler: handler
        )
        Self.installEventTapIfNeeded()

        var registeredHotKey: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var status = RegisterEventHotKey(
            configuration.key.carbonKeyCode,
            configuration.modifiers.carbonFlags,
            hotKeyID,
            Self.eventTarget,
            UInt32(kEventHotKeyExclusive),
            &registeredHotKey
        )
        var registrationMode = "exclusive"

        if status != noErr {
            status = RegisterEventHotKey(
                configuration.key.carbonKeyCode,
                configuration.modifiers.carbonFlags,
                hotKeyID,
                Self.eventTarget,
                UInt32(kEventHotKeyNoOptions),
                &registeredHotKey
            )
            registrationMode = "shared"
        }

        if status == noErr, let registeredHotKey {
            eventHotKey = registeredHotKey
            Self.logger.notice("registered name=\(name, privacy: .public) mode=\(registrationMode, privacy: .public) target=application key=\(configuration.displayString, privacy: .public) id=\(self.id)")
        } else {
            Self.logger.error("register failed name=\(name, privacy: .public) target=application key=\(configuration.displayString, privacy: .public) status=\(status)")
        }
    }

    deinit {
        Self.handlers.removeValue(forKey: id)
        Self.tapRegistrations.removeValue(forKey: id)
        Self.lastHandledAt.removeValue(forKey: id)
        if let eventHotKey {
            UnregisterEventHotKey(eventHotKey)
        }
        Self.stopEventTapIfUnused()
    }

    private static func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        let eventSpecs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let status = eventSpecs.withUnsafeBufferPointer { buffer in
            InstallEventHandler(
                eventTarget,
                carbonHotKeyEventHandler,
                buffer.count,
                buffer.baseAddress,
                nil,
                &eventHandler
            )
        }
        if status != noErr {
            logger.error("install handler failed status=\(status)")
        } else {
            logger.notice("event handler installed target=application")
        }
    }

    static func handle(_ event: EventRef?) -> OSStatus {
        guard let event else { return OSStatus(eventNotHandledErr) }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            UInt32(kEventParamDirectObject),
            UInt32(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return status }
        guard hotKeyID.signature == signature, let handler = handlers[hotKeyID.id] else {
            return OSStatus(eventNotHandledErr)
        }

        guard GetEventKind(event) == UInt32(kEventHotKeyPressed) else {
            return noErr
        }

        fire(id: hotKeyID.id, source: "carbon", handler: handler)
        return noErr
    }

    private static func installEventTapIfNeeded() {
        guard eventTap == nil else { return }

        guard AccessibilityManager.shared.checkAccessibilityPermissions() else {
            logger.warning("event tap fallback disabled: accessibility permission missing")
            return
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: carbonHotKeyEventTapCallback,
            userInfo: nil
        ) else {
            logger.error("event tap fallback creation failed")
            return
        }

        eventTap = tap
        eventTapRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let eventTapRunLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.notice("event tap fallback started")
    }

    private static func stopEventTapIfUnused() {
        guard tapRegistrations.isEmpty else { return }

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
        }
        eventTap = nil
        eventTapRunLoopSource = nil
    }

    static func handleTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let modifiers = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])

        for (id, registration) in tapRegistrations
        where registration.keyCode == keyCode && registration.modifiers == modifiers {
            fire(id: id, source: "tap", name: registration.name, handler: registration.handler)
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private static func fire(id: UInt32, source: String, name: String? = nil, handler: @escaping () -> Void) {
        let now = Date()
        if let last = lastHandledAt[id], now.timeIntervalSince(last) < 0.5 {
            return
        }
        lastHandledAt[id] = now
        let registrationName = name ?? tapRegistrations[id]?.name ?? "unknown"
        logger.notice("fired name=\(registrationName, privacy: .public) source=\(source, privacy: .public) id=\(id)")
        if source == "carbon", let registration = tapRegistrations[id] {
            runAfterModifierRelease(
                modifiers: registration.modifiers,
                name: registrationName,
                handler: handler
            )
        } else {
            DispatchQueue.main.async(execute: handler)
        }
    }

    private static func runAfterModifierRelease(
        modifiers: CGEventFlags,
        name: String,
        attemptsRemaining: Int = 12,
        handler: @escaping () -> Void
    ) {
        let trackedModifiers = modifiers.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        let activeModifiers = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])

        guard !trackedModifiers.isEmpty,
              !activeModifiers.intersection(trackedModifiers).isEmpty,
              attemptsRemaining > 0 else {
            logger.notice("dispatching name=\(name, privacy: .public) after modifier release")
            DispatchQueue.main.async(execute: handler)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            runAfterModifierRelease(
                modifiers: modifiers,
                name: name,
                attemptsRemaining: attemptsRemaining - 1,
                handler: handler
            )
        }
    }

    private static func cgEventFlags(from modifiers: NSEvent.ModifierFlags) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        return flags
    }
}

private func carbonHotKeyEventHandler(
    eventHandlerCall: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    CarbonHotKeyRegistration.handle(event)
}

private func carbonHotKeyEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    CarbonHotKeyRegistration.handleTap(type: type, event: event)
}

private extension HotKeyConfiguration {
    var displayString: String {
        modifiers.displayString + key.displayString
    }
}
