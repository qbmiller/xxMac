import AppKit
import Combine
import CoreGraphics
import LocalAuthentication
import SwiftUI

final class LockAIManager: ObservableObject {
    static let shared = LockAIManager()

    @Published var isLocked = false
    @Published var statusText: String {
        didSet { PreferencesStore.shared.set(statusText, forKey: Self.statusTextKey) }
    }
    @Published var unlockMessage: String?

    private static let statusTextKey = "LockAIStatusText"
    private var windows: [NSWindow] = []
    private var activityToken: NSObjectProtocol?
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?

    private init() {
        statusText = PreferencesStore.shared.string(forKey: Self.statusTextKey) ?? AppDefaultSettings.LockAI.statusText
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func lock() {
        guard !isLocked else { return }

        beginActivity()
        createCoverWindows()
        startInputBlocking()
        isLocked = true
        unlockMessage = nil
        NSApp.activate(ignoringOtherApps: true)
    }

    func unlock() {
        guard isLocked else { return }

        stopInputBlocking()
        let context = LAContext()
        context.localizedCancelTitle = L10n.t("lock_ai.unlock_cancel")
        let reason = L10n.t("lock_ai.unlock_reason")

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if success {
                    self.finishUnlock()
                } else if let error {
                    self.unlockMessage = error.localizedDescription
                    self.startInputBlocking()
                }
            }
        }
    }

    private func finishUnlock() {
        windows.forEach { $0.close() }
        windows.removeAll()
        stopInputBlocking()
        endActivity()
        isLocked = false
        unlockMessage = nil
    }

    private func beginActivity() {
        guard activityToken == nil else { return }
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled, .idleDisplaySleepDisabled],
            reason: "LockJob keeps AI agents, builds, and downloads running while the screen is covered."
        )
    }

    private func endActivity() {
        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
        }
        activityToken = nil
    }

    private func createCoverWindows() {
        windows.forEach { $0.close() }
        windows = NSScreen.screens.map { screen in
            let window = LockAIWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.backgroundColor = .black
            window.isOpaque = true
            window.hidesOnDeactivate = false
            window.contentView = NSHostingView(rootView: LockAICoverView(manager: self))
            window.setFrame(screen.frame, display: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return window
        }
    }

    @objc private func screenParametersDidChange() {
        guard isLocked else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.isLocked else { return }
            self.createCoverWindows()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func startInputBlocking() {
        guard eventTap == nil else { return }

        let mask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, _ in
                if type == .keyDown {
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    if keyCode == 36 || keyCode == 76 {
                        DispatchQueue.main.async {
                            LockAIManager.shared.unlock()
                        }
                    }
                } else if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
                    DispatchQueue.main.async {
                        LockAIManager.shared.unlock()
                    }
                }
                return nil
            },
            userInfo: nil
        ) else {
            return
        }

        eventTap = tap
        eventTapRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = eventTapRunLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopInputBlocking() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTapRunLoopSource = nil
        eventTap = nil
    }
}

private final class LockAIWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            if event.keyCode == 36 || event.keyCode == 76 {
                LockAIManager.shared.unlock()
            }
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            LockAIManager.shared.unlock()
        default:
            break
        }
        super.sendEvent(event)
    }
}

private struct LockAICoverView: View {
    @ObservedObject var manager: LockAIManager
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var timeText: String {
        now.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.05, blue: 0.06),
                    Color(red: 0.07, green: 0.10, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 26) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 78, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text(timeText)
                        .font(.system(size: 74, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                    Text(manager.statusText)
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.78))
                }

                VStack(spacing: 8) {
                    Text(L10n.t("lock_ai.cover_hint"))
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.62))
                    if let message = manager.unlockMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.8))
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onReceive(timer) { now = $0 }
    }
}
