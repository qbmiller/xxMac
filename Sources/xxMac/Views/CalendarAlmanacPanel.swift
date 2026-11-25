import AppKit
import SwiftUI

@MainActor
final class CalendarAlmanacPresentation: ObservableObject {
    @Published var isPresented = false
}

/// Keep the two surfaces on one screen, with the almanac immediately to the left.
enum CalendarAlmanacPlacement {
    static func frames(parent: CGRect, screen: CGRect) -> (parent: CGRect, detail: CGRect) {
        let gap: CGFloat = 6
        let width = min(300, screen.width)
        var parent = parent
        let height = min(max(parent.height - 12, 360), screen.height)
        if parent.width + width + gap <= screen.width {
            parent.origin.x = min(max(parent.minX, screen.minX + width + gap), screen.maxX - parent.width)
        }
        var x = parent.minX - width - gap
        if x < screen.minX { x = parent.maxX + gap }
        x = max(screen.minX, min(x, screen.maxX - width))
        let y = max(screen.minY, min(parent.maxY - height - 12, screen.maxY - height))
        return (parent, CGRect(x: x, y: y, width: width, height: height))
    }
}

/// SwiftUI owns date and presentation; this bridge owns only the attached panel.
struct CalendarAlmanacAttachment: NSViewRepresentable {
    let date: Date
    let locale: Locale
    let calendar: Calendar
    @ObservedObject var presentation: CalendarAlmanacPresentation
    let onMoveDays: (Int) -> Void
    let onMoveMonths: (Int) -> Void
    let onTogglePin: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        let coordinator = context.coordinator
        view.windowChanged = { [weak coordinator] in coordinator?.refresh() }
        return view
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        context.coordinator.anchor = view
        context.coordinator.attachment = self
        context.coordinator.refresh()
    }

    static func dismantleNSView(_ view: AnchorView, coordinator: Coordinator) {
        coordinator.close()
    }

    final class AnchorView: NSView {
        var windowChanged: (() -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            windowChanged?()
        }
    }

    @MainActor
    final class Coordinator {
        weak var anchor: NSView?
        var attachment: CalendarAlmanacAttachment?
        private var panel: NSPanel?
        private weak var parent: NSWindow?
        private var observations: [NSObjectProtocol] = []
        private var keyMonitor: Any?
        private var positioning = false

        func refresh() {
            guard let attachment, attachment.presentation.isPresented, let window = anchor?.window,
                  window.isVisible else { close(); return }
            if panel == nil {
                let panel = AlmanacPanel(contentRect: .zero,
                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = true
                panel.hidesOnDeactivate = false
                panel.identifier = NSUserInterfaceItemIdentifier("xxmac.calendar.almanac")
                panel.setAccessibilityLabel(L10n.t("calendar.almanac.title"))
                self.panel = panel
                parent = window
                window.addChildWindow(panel, ordered: .above)
                for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                             NSWindow.didChangeScreenNotification] {
                    observations.append(NotificationCenter.default.addObserver(forName: name, object: window,
                        queue: .main) { [weak self] _ in
                            MainActor.assumeIsolated { self?.position() }
                        })
                }
                observations.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                    object: window, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated {
                            self?.attachment?.presentation.isPresented = false
                            self?.close()
                        }
                    })
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, event.keyCode == 53,
                          event.window === self.parent || event.window === self.panel else { return event }
                    self.attachment?.presentation.isPresented = false
                    self.close()
                    return nil
                }
            }
            panel?.contentView = NSHostingView(rootView:
                CalendarAlmanacDetailView(date: attachment.date, locale: attachment.locale,
                    entry: CalendarAlmanacStore.shared.entry(for: attachment.date, calendar: attachment.calendar),
                    onClose: { attachment.presentation.isPresented = false })
                .background(CalendarKeyboardNavigation(onMoveDays: attachment.onMoveDays,
                    onMoveMonths: attachment.onMoveMonths, onTogglePin: attachment.onTogglePin))
            )
            position()
            panel?.orderFront(nil)
        }

        private func position() {
            guard !positioning, let parent, let panel, let screen = parent.screen else { return }
            positioning = true
            defer { positioning = false }
            let frames = CalendarAlmanacPlacement.frames(parent: parent.frame, screen: screen.visibleFrame)
            if parent.frame != frames.parent { parent.setFrame(frames.parent, display: true) }
            panel.level = parent.level
            panel.setFrame(frames.detail, display: true)
        }

        func close() {
            for observation in observations { NotificationCenter.default.removeObserver(observation) }
            observations.removeAll()
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
            if let panel {
                parent?.removeChildWindow(panel)
                panel.orderOut(nil)
            }
            panel = nil
            parent = nil
        }

        deinit {
            for observation in observations { NotificationCenter.default.removeObserver(observation) }
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        }
    }
}

private final class AlmanacPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
