import AppKit

@MainActor
final class ClipboardImagePreviewPanelController {
    private var panel: ClipboardImagePreviewPanel?
    private let onCloseRequested: () -> Void

    var isVisible: Bool {
        panel?.isVisible == true
    }

    init(onCloseRequested: @escaping () -> Void) {
        self.onCloseRequested = onCloseRequested
    }

    @discardableResult
    func showImage(at imageURL: URL, relativeTo launcherWindow: NSWindow?) -> Bool {
        guard let image = NSImage(contentsOf: imageURL), image.isValid else {
            return false
        }

        dismiss()

        let screen = launcherWindow?.screen ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            return false
        }

        let frame = Self.previewFrame(imageSize: image.size, visibleFrame: visibleFrame)
        let previewView = ClipboardImagePreviewScrollView(
            image: image,
            viewportSize: frame.size
        )
        let panel = ClipboardImagePreviewPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = previewView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]
        panel.animationBehavior = .utilityWindow
        panel.keyDownHandler = { [weak self] event in
            guard event.keyCode == 49 || event.keyCode == 53 else {
                return false
            }
            self?.onCloseRequested()
            return true
        }
        panel.closeHandler = { [weak self] in
            self?.onCloseRequested()
        }

        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        return true
    }

    func dismiss() {
        guard let panel else { return }
        panel.keyDownHandler = nil
        panel.closeHandler = nil
        panel.orderOut(nil)
        panel.contentView = nil
        self.panel = nil
    }

    nonisolated static func previewFrame(imageSize: NSSize, visibleFrame: NSRect) -> NSRect {
        let maximumSize = NSSize(
            width: visibleFrame.width * 0.86,
            height: visibleFrame.height * 0.84
        )
        let safeImageSize = NSSize(
            width: max(imageSize.width, 1),
            height: max(imageSize.height, 1)
        )
        let fitScale = min(
            1,
            maximumSize.width / safeImageSize.width,
            maximumSize.height / safeImageSize.height
        )
        let fittedSize = NSSize(
            width: safeImageSize.width * fitScale,
            height: safeImageSize.height * fitScale
        )
        let windowSize = NSSize(
            width: min(maximumSize.width, max(520, fittedSize.width)),
            height: min(maximumSize.height, max(360, fittedSize.height))
        )

        return NSRect(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.midY - windowSize.height / 2,
            width: windowSize.width,
            height: windowSize.height
        )
    }
}

private final class ClipboardImagePreviewPanel: NSPanel {
    var keyDownHandler: ((NSEvent) -> Bool)?
    var closeHandler: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        closeHandler?()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyDownHandler?(event) == true {
            return
        }
        super.sendEvent(event)
    }
}

private final class ClipboardImagePreviewScrollView: NSScrollView {
    private let previewImageView: ClipboardPreviewImageView
    private var dragStartPoint: NSPoint?
    private var dragStartOrigin: NSPoint?

    init(image: NSImage, viewportSize: NSSize) {
        previewImageView = ClipboardPreviewImageView(
            frame: NSRect(origin: .zero, size: viewportSize)
        )
        super.init(frame: NSRect(origin: .zero, size: viewportSize))

        drawsBackground = true
        backgroundColor = .black
        borderType = .noBorder
        hasHorizontalScroller = false
        hasVerticalScroller = false
        usesPredominantAxisScrolling = false
        allowsMagnification = true
        minMagnification = 1
        maxMagnification = 6

        previewImageView.image = image
        previewImageView.imageAlignment = .alignCenter
        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.isEditable = false
        documentView = previewImageView
        magnification = 1

        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        guard magnification > minMagnification + 0.001 else {
            window?.performDrag(with: event)
            return
        }

        dragStartPoint = convert(event.locationInWindow, from: nil)
        dragStartOrigin = contentView.bounds.origin
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartPoint, let dragStartOrigin else {
            super.mouseDragged(with: event)
            return
        }

        let currentPoint = convert(event.locationInWindow, from: nil)
        let proposedOrigin = NSPoint(
            x: dragStartOrigin.x - (currentPoint.x - dragStartPoint.x),
            y: dragStartOrigin.y - (currentPoint.y - dragStartPoint.y)
        )
        let constrainedBounds = contentView.constrainBoundsRect(
            NSRect(origin: proposedOrigin, size: contentView.bounds.size)
        )
        contentView.scroll(to: constrainedBounds.origin)
        reflectScrolledClipView(contentView)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStartPoint != nil else {
            super.mouseUp(with: event)
            return
        }

        dragStartPoint = nil
        dragStartOrigin = nil
        NSCursor.pop()
    }
}

private final class ClipboardPreviewImageView: NSImageView {
    override func mouseDown(with event: NSEvent) {
        enclosingScrollView?.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        enclosingScrollView?.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        enclosingScrollView?.mouseUp(with: event)
    }
}
