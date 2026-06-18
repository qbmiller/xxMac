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
        backgroundHex = UserDefaults.standard.string(forKey: backgroundKey) ?? "#5C9AAF"
        let savedOpacity = UserDefaults.standard.double(forKey: opacityKey)
        opacity = savedOpacity == 0 ? 0.78 : savedOpacity
        let savedSizeScale = UserDefaults.standard.double(forKey: sizeScaleKey)
        sizeScale = savedSizeScale == 0 ? 0.82 : savedSizeScale
        let savedLauncherWidth = UserDefaults.standard.double(forKey: launcherWidthKey)
        launcherWidth = savedLauncherWidth == 0 ? 760 : savedLauncherWidth
        let savedLauncherHeight = UserDefaults.standard.double(forKey: launcherHeightKey)
        launcherHeight = savedLauncherHeight == 0 ? 328 : savedLauncherHeight
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
        UserDefaults.standard.set(backgroundHex, forKey: backgroundKey)
        UserDefaults.standard.set(opacity, forKey: opacityKey)
        UserDefaults.standard.set(sizeScale, forKey: sizeScaleKey)
        UserDefaults.standard.set(launcherWidth, forKey: launcherWidthKey)
        UserDefaults.standard.set(launcherHeight, forKey: launcherHeightKey)
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
