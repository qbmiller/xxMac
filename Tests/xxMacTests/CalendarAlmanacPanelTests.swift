import AppKit
import SwiftUI
import XCTest
@testable import xxMac

final class CalendarAlmanacPanelTests: XCTestCase {
    @MainActor
    func testAttachedPanelOpensBesideCalendarAndClosesWithPresentation() async throws {
        _ = NSApplication.shared
        let state = CalendarAlmanacPresentation()
        let window = NSWindow(contentRect: NSRect(x: 600, y: 100, width: 430, height: 620),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 12))!
        let attachment = CalendarAlmanacAttachment(date: date, locale: Locale(identifier: "zh-Hans"),
            calendar: calendar, presentation: state, onMoveDays: { _ in }, onMoveMonths: { _ in }, onTogglePin: nil)
        window.contentView = NSHostingView(rootView: attachment.frame(width: 430, height: 620))
        window.orderFront(nil)
        state.isPresented = true
        for _ in 0..<25 {
            if window.childWindows?.contains(where: { $0.isVisible }) == true { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let panel = try XCTUnwrap(window.childWindows?.first)
        XCTAssertEqual(panel.identifier?.rawValue, "xxmac.calendar.almanac")
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.frame.maxX + 6, window.frame.minX, accuracy: 1)
        state.isPresented = false
        for _ in 0..<25 {
            if !panel.isVisible { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(panel.isVisible)
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)

        state.isPresented = true
        for _ in 0..<25 {
            if window.childWindows?.contains(where: { $0.isVisible }) == true { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let reopened = try XCTUnwrap(window.childWindows?.first)
        XCTAssertTrue(reopened.isVisible)
        window.close()
        XCTAssertFalse(state.isPresented)
        XCTAssertFalse(reopened.isVisible)
    }
}
