import Foundation
import HotKey
import AppKit

struct AppShortcut: Codable, Identifiable {
    var id: UUID = UUID()
    let appName: String
    let appPath: String
    let key: Key
    let modifiers: NSEvent.ModifierFlags
    let isEnabled: Bool
    
    // Custom coding keys if needed, but default is fine
}
