import Carbon
import Foundation

protocol InputSourceControlling {
    func availableSources() -> [InputSourceDescriptor]
    func currentSource() -> InputSourceDescriptor?
    func selectSource(id: String) -> Bool
}

struct SystemInputSourceController: InputSourceControlling {
    func availableSources() -> [InputSourceDescriptor] {
        var seen = Set<String>()
        return sources().compactMap { source in
            guard let descriptor = descriptor(source), seen.insert(descriptor.id).inserted else { return nil }
            return descriptor
        }
    }

    func currentSource() -> InputSourceDescriptor? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return descriptor(source)
    }

    func selectSource(id: String) -> Bool {
        guard let source = sources().first(where: { descriptor($0)?.id == id }) else { return false }
        return TISSelectInputSource(source) == noErr
    }

    private func sources() -> [TISInputSource] {
        let properties = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
                          kTISPropertyInputSourceIsSelectCapable as String: true,
                          kTISPropertyInputSourceIsEnabled as String: true] as CFDictionary
        return TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource] ?? []
    }

    private func property(_ source: TISInputSource, _ key: CFString) -> AnyObject? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
    }

    private func descriptor(_ source: TISInputSource) -> InputSourceDescriptor? {
        guard let id = property(source, kTISPropertyInputSourceID) as? String else { return nil }
        return .init(sourceID: id, modeID: property(source, kTISPropertyInputModeID) as? String,
                     name: property(source, kTISPropertyLocalizedName) as? String ?? id)
    }
}

enum InputSourceManager {
    static func selectEnglishInputSource() {
        InputSourceAutomationManager.shared.selectForLauncher()
    }
}
