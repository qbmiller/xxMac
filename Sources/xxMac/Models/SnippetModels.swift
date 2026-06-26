import Foundation
import HotKey
import AppKit

struct SnippetSettings: Codable {
    var hotKey: HotKeyConfiguration? = HotKeyConfiguration(key: .x, modifiers: [.control, .option, .command])
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
