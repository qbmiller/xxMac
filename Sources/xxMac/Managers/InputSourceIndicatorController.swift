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
        let fontSize = CGFloat(min(32, max(12, settings.indicatorFontSize)))
        label.font = .systemFont(ofSize: fontSize, weight: .medium)
        label.textColor = NSColor(srgbRed: 0.035, green: 0.035, blue: 0.078, alpha: 1)
        label.alignment = .left
        label.lineBreakMode = .byTruncatingTail
        label.sizeToFit()
        let iconSize = fontSize + 6
        let horizontalPadding: CGFloat = 18
        let spacing: CGFloat = 12
        let size = NSSize(width: min(420, max(100, label.frame.width + iconSize + spacing + horizontalPadding * 2)),
                          height: max(label.frame.height, iconSize) + 28)
        let background = NSView(frame: NSRect(origin: .zero, size: size))
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.backgroundColor = NSColor.white.cgColor
        background.layer?.borderWidth = 0.5
        background.layer?.borderColor = NSColor(white: 0.92, alpha: 1).cgColor
        let icon = NSImageView(frame: NSRect(x: horizontalPadding, y: (size.height - iconSize) / 2,
                                            width: iconSize, height: iconSize))
        icon.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .regular)
        icon.contentTintColor = color(settings.indicatorColor)
        icon.imageScaling = .scaleProportionallyUpOrDown
        background.addSubview(icon)
        let labelX = horizontalPadding + iconSize + spacing
        label.frame = NSRect(x: labelX, y: (size.height - label.frame.height) / 2,
                             width: size.width - labelX - horizontalPadding, height: label.frame.height)
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
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x00C553
        return NSColor(srgbRed: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255,
                       blue: Double(value & 255) / 255, alpha: 1)
    }
}
