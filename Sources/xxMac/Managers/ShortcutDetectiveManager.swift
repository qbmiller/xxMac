import Foundation
import AppKit

struct ShortcutDetection {
    let action: WindowAction
    let hotkeyDisplay: String
    let appName: String
    let bundleIdentifier: String
    let timestamp: Date

    var actionName: String { action.displayName }
}

final class ShortcutDetectiveManager: ObservableObject {
    static let shared = ShortcutDetectiveManager()

    private let enabledKey = "ShortcutDetectiveEnabled"
    private var tipWindowController = ShortcutTipWindowController()

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: enabledKey)
        }
    }

    @Published private(set) var lastDetection: ShortcutDetection?

    private init() {
        if let stored = UserDefaults.standard.object(forKey: enabledKey) as? Bool {
            isEnabled = stored
        } else {
            isEnabled = false
            UserDefaults.standard.set(false, forKey: enabledKey)
        }
    }

    func recordHotkeyReception(for action: WindowAction, hotkeyDisplay: String) {
        guard isEnabled else { return }

        let app = NSWorkspace.shared.frontmostApplication
        let detection = ShortcutDetection(
            action: action,
            hotkeyDisplay: hotkeyDisplay,
            appName: app?.localizedName ?? L10n.t("shortcut.unknown_app"),
            bundleIdentifier: app?.bundleIdentifier ?? L10n.t("shortcut.unknown_bundle"),
            timestamp: Date()
        )

        if Thread.isMainThread {
            lastDetection = detection
            tipWindowController.show(message: L10n.f("shortcut.tip_message", detection.appName, detection.hotkeyDisplay))
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.lastDetection = detection
                self?.tipWindowController.show(message: L10n.f("shortcut.tip_message", detection.appName, detection.hotkeyDisplay))
            }
        }
    }

    func clearLastDetection() {
        lastDetection = nil
    }
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
