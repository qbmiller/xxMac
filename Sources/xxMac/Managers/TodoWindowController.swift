import AppKit
import Combine
import SwiftUI

enum TodoWindowMode: String, Codable {
    case compact
    case board
}

struct TodoWindowFrameState: Codable, Equatable {
    private(set) var compactFrame: CGRect?
    private(set) var boardFrame: CGRect?

    mutating func setFrame(_ frame: CGRect, for mode: TodoWindowMode) {
        switch mode {
        case .compact:
            compactFrame = frame
        case .board:
            boardFrame = frame
        }
    }

    func frame(for mode: TodoWindowMode) -> CGRect? {
        switch mode {
        case .compact:
            return compactFrame
        case .board:
            return boardFrame
        }
    }
}

enum TodoWindowFramePolicy {
    static let minimumSize = NSSize(width: 720, height: 520)
    static let compactSize = NSSize(width: 820, height: 720)
    static let boardSize = NSSize(width: 1_240, height: 720)

    static func defaultFrame(for mode: TodoWindowMode, in visibleFrame: NSRect) -> NSRect {
        let requestedSize = mode == .compact ? compactSize : boardSize
        let size = NSSize(
            width: min(requestedSize.width, visibleFrame.width),
            height: min(requestedSize.height, visibleFrame.height)
        )
        return NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    static func clamped(_ frame: NSRect, to visibleFrame: NSRect) -> NSRect {
        let width = min(max(frame.width, minimumSize.width), visibleFrame.width)
        let height = min(max(frame.height, minimumSize.height), visibleFrame.height)
        var result = NSRect(origin: frame.origin, size: NSSize(width: width, height: height))

        if width >= visibleFrame.width {
            result.origin.x = visibleFrame.minX
        } else {
            result.origin.x = min(max(result.origin.x, visibleFrame.minX), visibleFrame.maxX - width)
        }

        if height >= visibleFrame.height {
            result.origin.y = visibleFrame.minY
        } else {
            result.origin.y = min(max(result.origin.y, visibleFrame.minY), visibleFrame.maxY - height)
        }
        return result
    }
}

extension Notification.Name {
    static let toggleTodoWindow = Notification.Name("ToggleTodoWindow")
}

@MainActor
final class TodoWindowController: NSWindowController, NSWindowDelegate, ObservableObject {
    static let shared = TodoWindowController(store: TodoStore.shared)
    private static let frameStateKey = "TodoWindowFrameState"

    @Published private(set) var mode: TodoWindowMode = .compact

    private let store: TodoStore
    private let preferences: PreferencesStore
    private var frameState: TodoWindowFrameState
    private var isApplyingFrame = false
    private var toggleObserver: NSObjectProtocol?

    init(store: TodoStore, preferences: PreferencesStore = .shared) {
        self.store = store
        self.preferences = preferences
        if let data = preferences.data(forKey: Self.frameStateKey),
           let decoded = try? JSONDecoder().decode(TodoWindowFrameState.self, from: data) {
            frameState = decoded
        } else {
            frameState = TodoWindowFrameState()
        }
        super.init(window: nil)

        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let initialFrame = frameState.frame(for: .compact)
            .map { TodoWindowFramePolicy.clamped($0, to: visibleFrame) }
            ?? TodoWindowFramePolicy.defaultFrame(for: .compact, in: visibleFrame)
        let panel = NSPanel(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Todo"
        panel.minSize = TodoWindowFramePolicy.minimumSize
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: TodoWindowPlaceholderView(store: store))
        window = panel

        toggleObserver = NotificationCenter.default.addObserver(
            forName: .toggleTodoWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.toggle()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let toggleObserver {
            NotificationCenter.default.removeObserver(toggleObserver)
        }
    }

    func toggle() {
        if window?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        applyClampedCurrentFrame()
        if NSApp.isHidden {
            NSApp.unhide(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func hide() {
        saveCurrentFrame()
        window?.orderOut(nil)
    }

    func setMode(_ newMode: TodoWindowMode) {
        guard newMode != mode, let window else { return }
        saveCurrentFrame()
        mode = newMode

        let visibleFrame = visibleFrame(for: window.frame)
        let target = frameState.frame(for: newMode)
            ?? TodoWindowFramePolicy.defaultFrame(for: newMode, in: visibleFrame)
        isApplyingFrame = true
        window.setFrame(TodoWindowFramePolicy.clamped(target, to: visibleFrame), display: true, animate: true)
        isApplyingFrame = false
        saveCurrentFrame()
    }

    func windowDidMove(_ notification: Notification) {
        saveCurrentFrameUnlessApplying(notification)
    }

    func windowDidResize(_ notification: Notification) {
        saveCurrentFrameUnlessApplying(notification)
    }

    func windowWillClose(_ notification: Notification) {
        saveCurrentFrameUnlessApplying(notification)
    }

    private func saveCurrentFrameUnlessApplying(_ notification: Notification) {
        guard !isApplyingFrame,
              let changedWindow = notification.object as? NSWindow,
              changedWindow === window else {
            return
        }
        saveCurrentFrame()
    }

    private func saveCurrentFrame() {
        guard let window else { return }
        frameState.setFrame(window.frame, for: mode)
        if let data = try? JSONEncoder().encode(frameState) {
            preferences.set(data, forKey: Self.frameStateKey)
        }
    }

    private func applyClampedCurrentFrame() {
        guard let window else { return }
        let visibleFrame = visibleFrame(for: window.frame)
        let clamped = TodoWindowFramePolicy.clamped(window.frame, to: visibleFrame)
        guard clamped != window.frame else { return }
        isApplyingFrame = true
        window.setFrame(clamped, display: false)
        isApplyingFrame = false
        saveCurrentFrame()
    }

    private func visibleFrame(for frame: NSRect) -> NSRect {
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
    }
}

private struct TodoWindowPlaceholderView: View {
    @ObservedObject var store: TodoStore

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Todo")
                .font(.title2)
            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
