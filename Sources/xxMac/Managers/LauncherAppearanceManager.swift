import AppKit
import Combine
import SwiftUI

final class LauncherAppearanceManager: ObservableObject {
    static let shared = LauncherAppearanceManager()
    static let sizeScaleRange: ClosedRange<Double> = 0.50...1.05
    static let textScaleRange: ClosedRange<Double> = 0.50...1.20

    @Published var backgroundHex: String {
        didSet { save() }
    }

    @Published var opacity: Double {
        didSet { save() }
    }

    @Published var sizeScale: Double {
        didSet {
            let clampedValue = Self.clampedSizeScale(sizeScale)
            if clampedValue != sizeScale {
                sizeScale = clampedValue
                return
            }
            save()
        }
    }

    @Published var textScale: Double {
        didSet {
            let clampedValue = Self.clampedTextScale(textScale)
            if clampedValue != textScale {
                textScale = clampedValue
                return
            }
            save()
        }
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
    private let textScaleKey = "LauncherAppearanceTextScale"
    private let launcherWidthKey = "LauncherAppearanceWidth"
    private let launcherHeightKey = "LauncherAppearanceHeight"

    private init() {
        let store = PreferencesStore.shared
        backgroundHex = store.string(forKey: backgroundKey) ?? AppDefaultSettings.LauncherAppearance.backgroundHex
        opacity = store.doubleObject(forKey: opacityKey) ?? AppDefaultSettings.LauncherAppearance.opacity
        sizeScale = Self.clampedSizeScale(store.doubleObject(forKey: sizeScaleKey) ?? AppDefaultSettings.LauncherAppearance.sizeScale)
        textScale = Self.clampedTextScale(store.doubleObject(forKey: textScaleKey) ?? AppDefaultSettings.LauncherAppearance.textScale)
        launcherWidth = store.doubleObject(forKey: launcherWidthKey) ?? AppDefaultSettings.LauncherAppearance.width
        launcherHeight = store.doubleObject(forKey: launcherHeightKey) ?? AppDefaultSettings.LauncherAppearance.height
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
        backgroundHex = AppDefaultSettings.LauncherAppearance.backgroundHex
        opacity = AppDefaultSettings.LauncherAppearance.opacity
        sizeScale = AppDefaultSettings.LauncherAppearance.sizeScale
        textScale = AppDefaultSettings.LauncherAppearance.textScale
        launcherWidth = AppDefaultSettings.LauncherAppearance.width
        launcherHeight = AppDefaultSettings.LauncherAppearance.height
    }

    private func save() {
        let store = PreferencesStore.shared
        store.set(backgroundHex, forKey: backgroundKey)
        store.set(opacity, forKey: opacityKey)
        store.set(sizeScale, forKey: sizeScaleKey)
        store.set(textScale, forKey: textScaleKey)
        store.set(launcherWidth, forKey: launcherWidthKey)
        store.set(launcherHeight, forKey: launcherHeightKey)
    }

    private static func clampedSizeScale(_ value: Double) -> Double {
        min(max(value, sizeScaleRange.lowerBound), sizeScaleRange.upperBound)
    }

    private static func clampedTextScale(_ value: Double) -> Double {
        min(max(value, textScaleRange.lowerBound), textScaleRange.upperBound)
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
