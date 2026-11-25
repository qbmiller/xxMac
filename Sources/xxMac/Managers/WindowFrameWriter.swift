import Foundation

enum WindowFrameWriter {
    static func apply(
        _ frame: CGRect,
        setSize: (CGSize) -> Void,
        setPosition: (CGPoint) -> Void
    ) {
        // Resizing can reposition a tiled window, and moving a large window
        // first can be clamped at a screen edge. Apply the final origin last.
        setSize(frame.size)
        setPosition(frame.origin)
    }
}
