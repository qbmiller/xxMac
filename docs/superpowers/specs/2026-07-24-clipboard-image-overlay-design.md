# Clipboard Image Overlay Preview

## Goal

Let users inspect a selected clipboard image at a large size without closing the
clipboard launcher or opening the system Quick Look panel.

## Interaction

- When Clipboard History or Favorites has an image selected, pressing Space
  opens an app-managed, screen-level borderless preview panel above the launcher.
- The preview displays the original cached image scaled to fit the current
  screen. At 1x, dragging moves the preview panel anywhere on screen. After
  magnification, dragging or two-finger scrolling pans the image.
- Pressing Space or Escape closes the image preview.
- Opening and closing the overlay does not change the selected item, search
  query, clipboard contents, or launcher visibility.
- Text and Snippets keep their existing Space behavior.

## Implementation

- Keep preview visibility and the selected original image filename in the
  launcher view model.
- Use a custom, borderless `NSPanel` owned by xxMac rather than the system
  `QLPreviewPanel` or a SwiftUI child overlay. This keeps the preview visually
  integrated while allowing it to extend beyond the launcher window.
- Rebuild an `NSImageView` inside a magnifiable `NSScrollView` on each open.
  This avoids stale `QLPreviewView` lifecycle state and supports pinch-to-zoom,
  scrolling, and drag-to-pan.
- Route Space and Escape through the existing launcher-level keyboard handler
  so the field editor cannot bypass the interaction. While the preview is key,
  launcher resign-key handling must not close the clipboard panel.
- Load the original image from `clipboard_images/`; do not use the thumbnail
  cache for the overlay.

## Verification

- Unit-test that only image clipboard results can enter the preview state.
- Run the clipboard launcher tests and the complete Swift test suite.
- Manually verify Space opens the original image above the launcher, the preview
  can move across the screen, pinch and pan work, and Space/Escape close only
  the preview.
