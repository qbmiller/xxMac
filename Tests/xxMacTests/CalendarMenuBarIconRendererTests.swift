import AppKit
import XCTest
@testable import xxMac

final class CalendarMenuBarIconRendererTests: XCTestCase {
    @MainActor
    func testCalendarStylesAreRasterizedBeforeStatusBarRedraw() throws {
        for localeID in ["zh-Hans", "en-US"] {
            for style in CalendarMenuBarIconStyle.allCases {
                let image = CalendarMenuBarIconRenderer.image(style: style, locale: Locale(identifier: localeID))
                XCTAssertTrue(image.isTemplate)
                XCTAssertEqual(image.size, NSSize(width: 24, height: 22))
                let bitmap = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
                XCTAssertEqual(bitmap.pixelsWide, 48)
                XCTAssertEqual(bitmap.pixelsHigh, 44)
                let pixels = try XCTUnwrap(bitmap.bitmapData)
                let alpha = stride(from: 3, to: bitmap.bytesPerRow * bitmap.pixelsHigh, by: 4).map { pixels[$0] }
                XCTAssertTrue(alpha.contains { $0 > 0 }, "Missing icon: \(style), \(localeID)")
                XCTAssertTrue(alpha.contains { $0 == 0 }, "Missing transparency")
                // The central rectangle excludes the transparent outer border.
                // Text must actually punch holes through the opaque template.
                let interiorAlpha = (7..<37).flatMap { y in
                    (8..<40).map { x in pixels[y * bitmap.bytesPerRow + x * 4 + 3] }
                }
                XCTAssertTrue(interiorAlpha.contains { $0 == 0 }, "Missing text cutout: \(style), \(localeID)")
                XCTAssertTrue(interiorAlpha.contains { $0 == 255 }, "Missing icon background")
                for _ in 0..<10 {
                    var rect = CGRect(origin: .zero, size: image.size)
                    XCTAssertNotNil(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
                }
            }
        }
    }
}
