import Foundation
import HotKey
import AppKit

struct SnippetSettings: Codable {
    var hotKey: HotKeyConfiguration? = AppDefaultSettings.Snippets.hotKey
}

struct SnippetCollection: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
}

struct SnippetEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var collectionID: UUID
    var name: String
    var keyword: String
    var content: String
}
