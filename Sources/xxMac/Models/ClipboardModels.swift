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

    func searchableContent(imageDescription: String? = nil) -> String {
        switch type {
        case .text:
            return content
        case .image:
            return [
                "image images img photo photos picture pictures 图片 照片",
                imageDescription,
                content
            ]
            .compactMap { $0 }
            .joined(separator: " ")
        }
    }
}
