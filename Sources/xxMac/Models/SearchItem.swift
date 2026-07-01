import Foundation
import AppKit

enum SearchResultType {
    case app
    case windowAction
    case clipboard
    case snippet
    case quickShortcut
    case quickShortcutOutput
    case bookmark
}

enum ClipboardPreviewData: Hashable {
    case text(id: UUID, preview: String, fullLength: Int)
    case image(
        filename: String,
        thumbnailFilename: String?,
        byteSize: Int,
        ocrStatus: ClipboardOCRStatus?,
        ocrTextPreview: String?
    )
}

struct SearchItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let iconName: String
    let type: SearchResultType
    let clipboardPreview: ClipboardPreviewData?
    let action: () -> Void
    
    init(
        id: String? = nil,
        title: String,
        subtitle: String,
        iconName: String,
        type: SearchResultType,
        clipboardPreview: ClipboardPreviewData? = nil,
        action: @escaping () -> Void
    ) {
        self.id = id ?? "\(type)_\(title)"
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.type = type
        self.clipboardPreview = clipboardPreview
        self.action = action
    }
    
    // Hashable & Equatable for List selection
    static func == (lhs: SearchItem, rhs: SearchItem) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
