import AppKit
import Combine
import SwiftUI

final class LauncherAppearanceManager: ObservableObject {
    static let shared = LauncherAppearanceManager()

    @Published var backgroundHex: String {
        didSet { save() }
    }

    @Published var opacity: Double {
        didSet { save() }
    }

    @Published var sizeScale: Double {
        didSet { save() }
    }

    @Published var launcherWidth: Double {
        didSet { save() }
    }

    @Published var launcherHeight: Double {
        didSet { save() }
    }

    private let backgroundKey = "LauncherAppearanceBackgroundHex"
    private let opacityKey = "LauncherAppearanceOpacity"
    private let sizeScaleKey = "LauncherAppearanceSizeScale"
    private let launcherWidthKey = "LauncherAppearanceWidth"
    private let launcherHeightKey = "LauncherAppearanceHeight"

    private init() {
        let store = PreferencesStore.shared
        backgroundHex = store.string(forKey: backgroundKey) ?? "#5C9AAF"
        opacity = store.doubleObject(forKey: opacityKey) ?? 0.78
        sizeScale = store.doubleObject(forKey: sizeScaleKey) ?? 0.82
        launcherWidth = store.doubleObject(forKey: launcherWidthKey) ?? 760
        launcherHeight = store.doubleObject(forKey: launcherHeightKey) ?? 328
    }

    var backgroundColor: Color {
        Color(nsColor: nsColor)
    }

    var nsColor: NSColor {
        NSColor(hexString: backgroundHex) ?? NSColor(calibratedRed: 0.36, green: 0.60, blue: 0.69, alpha: 1)
    }

    func setBackgroundColor(_ color: NSColor) {
        backgroundHex = color.hexString
    }

    func reset() {
        backgroundHex = "#5C9AAF"
        opacity = 0.78
        sizeScale = 0.82
        launcherWidth = 760
        launcherHeight = 328
    }

    private func save() {
        let store = PreferencesStore.shared
        store.set(backgroundHex, forKey: backgroundKey)
        store.set(opacity, forKey: opacityKey)
        store.set(sizeScale, forKey: sizeScaleKey)
        store.set(launcherWidth, forKey: launcherWidthKey)
        store.set(launcherHeight, forKey: launcherHeightKey)
    }
}

private extension NSColor {
    convenience init?(hexString: String) {
        let value = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let number = Int(value, radix: 16) else { return nil }

        let red = CGFloat((number >> 16) & 0xFF) / 255
        let green = CGFloat((number >> 8) & 0xFF) / 255
        let blue = CGFloat(number & 0xFF) / 255
        self.init(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }

    var hexString: String {
        let color = usingColorSpace(.sRGB) ?? self
        let red = Int(round(color.redComponent * 255))
        let green = Int(round(color.greenComponent * 255))
        let blue = Int(round(color.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
