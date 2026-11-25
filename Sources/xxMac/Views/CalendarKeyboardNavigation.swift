import AppKit
import SwiftUI

/// A window-scoped monitor allows macOS 13 navigation without stealing focus
/// from the quick-add field, month picker, or unrelated xxMac windows.
struct CalendarKeyboardNavigation: NSViewRepresentable {
    let onMoveDays: (Int) -> Void
    let onMoveMonths: (Int) -> Void
    let onTogglePin: (() -> Void)?

    func makeNSView(context: Context) -> KeyboardView { KeyboardView() }

    func updateNSView(_ view: KeyboardView, context: Context) {
        view.onMoveDays = onMoveDays
        view.onMoveMonths = onMoveMonths
        view.onTogglePin = onTogglePin
    }

    final class KeyboardView: NSView {
        var onMoveDays: ((Int) -> Void)?
        var onMoveMonths: ((Int) -> Void)?
        var onTogglePin: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, window.isKeyWindow,
                      event.window === window, window.attachedSheet == nil,
                      !(window.firstResponder is NSTextView),
                      !(window.firstResponder is NSTextField) else { return event }
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    .subtracting([.capsLock, .numericPad, .function])
                if modifiers == .command {
                    switch event.keyCode {
                    case 123: self.onMoveMonths?(-1)
                    case 124: self.onMoveMonths?(1)
                    case 35:
                        guard let toggle = self.onTogglePin else { return event }
                        toggle()
                    default: return event
                    }
                } else if modifiers.isEmpty {
                    switch event.keyCode {
                    case 123: self.onMoveDays?(-1)
                    case 124: self.onMoveDays?(1)
                    case 125: self.onMoveDays?(7)
                    case 126: self.onMoveDays?(-7)
                    default: return event
                    }
                } else { return event }
                return nil
            }
        }

        private func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { removeMonitor() }
    }
}
