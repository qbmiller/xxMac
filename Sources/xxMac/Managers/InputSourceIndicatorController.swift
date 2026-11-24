import AppKit

protocol InputSourceIndicatorPresenting {
    func show(source: InputSourceDescriptor, settings: InputSourceSettings)
    func hide()
}

final class InputSourceIndicatorController: InputSourceIndicatorPresenting {
    private var panel: NSPanel?
    private var dismissal: DispatchWorkItem?

    func show(source: InputSourceDescriptor, settings: InputSourceSettings) {
        hide()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let label = NSTextField(labelWithString: settings.indicatorAbbreviated ? String(source.name.prefix(3)) : source.name)
        label.font = .systemFont(ofSize: CGFloat(min(32, max(12, settings.indicatorFontSize))), weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.sizeToFit()
        let size = NSSize(width: min(420, max(64, label.frame.width + 32)), height: label.frame.height + 22)
        let background = NSView(frame: NSRect(origin: .zero, size: size))
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.backgroundColor = color(settings.indicatorColor).cgColor
        label.frame = NSRect(x: 16, y: 11, width: size.width - 32, height: size.height - 22)
        background.addSubview(label)
        panel.contentView = background
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main
        guard let bounds = screen?.visibleFrame else { return }
        let desired = settings.indicatorPosition == .pointer
            ? NSPoint(x: pointer.x + 16, y: pointer.y - size.height - 12)
            : NSPoint(x: bounds.midX - size.width / 2, y: bounds.minY + 80)
        let origin = NSPoint(x: min(max(desired.x, bounds.minX + 6), bounds.maxX - size.width - 6),
                             y: min(max(desired.y, bounds.minY + 6), bounds.maxY - size.height - 6))
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        let work = DispatchWorkItem { [weak self] in self?.panel?.orderOut(nil) }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + min(5, max(0.3, settings.indicatorDuration)), execute: work)
    }

    func hide() {
        dismissal?.cancel()
        dismissal = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        return panel
    }

    private func color(_ hex: String) -> NSColor {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x2563EB
        return NSColor(srgbRed: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255,
                       blue: Double(value & 255) / 255, alpha: 0.94)
    }
}
