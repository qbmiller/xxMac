import Foundation

enum ClipboardContentType: String, Codable {
    case text
    case image
}

struct ClipboardItem: Codable, Identifiable {
    var id = UUID()
    let type: ClipboardContentType
    let content: String // Text content or Image filename (relative to storage dir)
    let timestamp: Date
    var size: Int = 0 // Approximate size in bytes
}
