import Foundation
import AppKit

enum SearchResultType {
    case app
    case windowAction
    case clipboard
    case snippet
    case quickShortcut
    case quickShortcutOutput
    case calculator
    case bookmark
    case browserHistory
    case launcherHistory
}

enum LauncherHistoryKind: String, Codable, Hashable {
    case app
    case windowAction
    case quickShortcut
    case calculator
}

struct LauncherHistorySnapshot: Codable, Hashable {
    let kind: LauncherHistoryKind
    let sourceID: String
    let title: String
    let subtitle: String
    let iconName: String
    let query: String
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

struct SnippetPreviewData: Hashable {
    let content: String
}

struct SearchItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let iconName: String
    let iconFileURL: URL?
    let type: SearchResultType
    let clipboardPreview: ClipboardPreviewData?
    let snippetPreview: SnippetPreviewData?
    let launcherHistorySnapshot: LauncherHistorySnapshot?
    let launcherInputText: String?
    let action: () -> Void
    
    init(
        id: String? = nil,
        title: String,
        subtitle: String,
        iconName: String,
        iconFileURL: URL? = nil,
        type: SearchResultType,
        clipboardPreview: ClipboardPreviewData? = nil,
        snippetPreview: SnippetPreviewData? = nil,
        launcherHistorySnapshot: LauncherHistorySnapshot? = nil,
        launcherInputText: String? = nil,
        action: @escaping () -> Void
    ) {
        self.id = id ?? "\(type)_\(title)"
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.iconFileURL = iconFileURL
        self.type = type
        self.clipboardPreview = clipboardPreview
        self.snippetPreview = snippetPreview
        self.launcherHistorySnapshot = launcherHistorySnapshot
        self.launcherInputText = launcherInputText
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
