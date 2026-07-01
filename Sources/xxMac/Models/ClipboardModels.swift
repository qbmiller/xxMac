import Foundation

enum ClipboardContentType: String, Codable {
    case text
    case image
}

enum ClipboardOCRStatus: String, Codable {
    case pending
    case ready
    case failed
    case skipped
}

struct ClipboardItem: Codable, Identifiable {
    var id = UUID()
    let type: ClipboardContentType
    let content: String // Text content or Image filename (relative to storage dir)
    let timestamp: Date
    var size: Int = 0 // Approximate size in bytes
    var imageWidth: Int?
    var imageHeight: Int?
    var thumbnailFilename: String?
    var imageOCRText: String?
    var imageOCRStatus: ClipboardOCRStatus?
    var imageOCRUpdatedAt: Date?

    func searchableContent(imageDescription: String? = nil) -> String {
        switch type {
        case .text:
            return content
        case .image:
            return [
                "image images img photo photos picture pictures 图片 照片",
                imageDescription,
                imageOCRText,
                content
            ]
            .compactMap { $0 }
            .joined(separator: " ")
        }
    }
}

struct ClipboardListItem: Identifiable, Equatable {
    let id: UUID
    let type: ClipboardContentType
    let previewContent: String
    let fullContentLength: Int
    let timestamp: Date
    let size: Int
    let imageFilename: String?
    let imageWidth: Int?
    let imageHeight: Int?
    let thumbnailFilename: String?
    let imageOCRStatus: ClipboardOCRStatus?
    let hasImageOCRText: Bool
    let imageOCRTextPreview: String?
}
