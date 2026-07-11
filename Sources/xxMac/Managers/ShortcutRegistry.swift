import Foundation
import AppKit

enum ShortcutAction: Hashable {
    case window(WindowAction)
    case appLauncher(UUID)
    case clipboard
    case snippets
    case quickShortcut(UUID)
    case browserBookmarks
    case browserHistory
}

enum ShortcutTrigger {
    case keyboard(HotKeyConfiguration)
    case launcherKeyword(String)
}

struct ShortcutRegistration {
    let action: ShortcutAction
    let trigger: ShortcutTrigger
}

struct ShortcutConflict: Equatable {
    let action: ShortcutAction
}

enum ShortcutRegistry {
    static func normalizedKeyword(_ keyword: String) -> String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func conflict(
        for trigger: ShortcutTrigger,
        action: ShortcutAction,
        in registrations: [ShortcutRegistration]
    ) -> ShortcutConflict? {
        registrations.lazy
            .filter { $0.action != action }
            .first { existing in triggersConflict(trigger, existing.trigger) }
            .map { ShortcutConflict(action: $0.action) }
    }

    private static func triggersConflict(_ lhs: ShortcutTrigger, _ rhs: ShortcutTrigger) -> Bool {
        switch (lhs, rhs) {
        case let (.keyboard(left), .keyboard(right)):
            return left.key.carbonKeyCode == right.key.carbonKeyCode &&
                normalizedModifiers(left.modifiers) == normalizedModifiers(right.modifiers)
        case let (.launcherKeyword(left), .launcherKeyword(right)):
            let normalizedLeft = normalizedKeyword(left)
            return !normalizedLeft.isEmpty && normalizedLeft == normalizedKeyword(right)
        default:
            return false
        }
    }

    private static func normalizedModifiers(_ modifiers: NSEvent.ModifierFlags) -> UInt {
        modifiers.intersection([.command, .option, .control, .shift]).rawValue
    }
}

final class ShortcutRegistryStore {
    static let shared = ShortcutRegistryStore()

    private let lock = NSLock()
    private var registrations: [ShortcutAction: ShortcutTrigger] = [:]

    private init() {}

    func register(action: ShortcutAction, trigger: ShortcutTrigger) -> ShortcutConflict? {
        lock.lock()
        defer { lock.unlock() }

        let existing = registrations.map { ShortcutRegistration(action: $0.key, trigger: $0.value) }
        if let conflict = ShortcutRegistry.conflict(for: trigger, action: action, in: existing) {
            return conflict
        }
        registrations[action] = trigger
        return nil
    }

    func unregister(action: ShortcutAction) {
        lock.lock()
        registrations.removeValue(forKey: action)
        lock.unlock()
    }

    func conflict(for action: ShortcutAction, trigger: ShortcutTrigger) -> ShortcutConflict? {
        lock.lock()
        let existing = registrations.map { ShortcutRegistration(action: $0.key, trigger: $0.value) }
        lock.unlock()
        return ShortcutRegistry.conflict(for: trigger, action: action, in: existing)
    }
}
