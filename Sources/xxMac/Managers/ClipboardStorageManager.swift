import Foundation
import AppKit

class ClipboardStorageManager {
    static let shared = ClipboardStorageManager()
    
    private var dbManager: DatabaseManager
    private var imagesDir: URL
    private var storageDir: URL
    
    private var maxItemsCount = 1000
    private var maxImageStorageSizeMB = 500
    
    var storageDirectory: URL { storageDir }
    var imagesDirectory: URL { imagesDir }
    var databasePath: String { storageDir.appendingPathComponent("clipboard.db").path }

    convenience init() {
        self.init(storageDirectory: ConfigDirectoryManager.shared.currentDirectory)
    }

    init(storageDirectory: URL) {
        self.storageDir = storageDirectory.standardizedFileURL
        self.imagesDir = storageDir.appendingPathComponent("clipboard_images")
        
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true, attributes: nil)
        
        let dbPath = storageDir.appendingPathComponent("clipboard.db").path
        self.dbManager = DatabaseManager(path: dbPath)
    }

    func prepareForDirectoryMigration() {
        dbManager.checkpointAndClose()
    }

    func resumeAfterDirectoryMigration() {
        dbManager.reopen(path: databasePath)
    }

    func reloadStorageDirectory(_ directory: URL = ConfigDirectoryManager.shared.currentDirectory) {
        storageDir = directory.standardizedFileURL
        imagesDir = storageDir.appendingPathComponent("clipboard_images")
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true, attributes: nil)
        dbManager.reopen(path: databasePath)
    }

    func configureLimits(maxItemsCount: Int, maxImageStorageSizeMB: Int) {
        self.maxItemsCount = max(1, maxItemsCount)
        self.maxImageStorageSizeMB = max(1, maxImageStorageSizeMB)
    }
    
    func saveItem(type: ClipboardContentType, content: String, size: Int) {
        let id = UUID().uuidString
        dbManager.insertItem(id: id, type: type.rawValue, content: content, size: size)
        
        // After saving, perform LRU cleanup asynchronously
        DispatchQueue.global(qos: .background).async {
            self.performLRU()
        }
    }
    
    func getAllItems(limit: Int = 100) -> [ClipboardItem] {
        return dbManager.getAllItems(limit: limit)
    }
    
    func search(query: String) -> [ClipboardItem] {
        if query.isEmpty {
            return getAllItems()
        }
        return dbManager.search(query: query)
    }
    
    func deleteItem(_ item: ClipboardItem) {
        dbManager.deleteItem(id: item.id.uuidString)
        if item.type == .image {
            let fileURL = imagesDir.appendingPathComponent(item.content)
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    func markItemUsed(_ item: ClipboardItem) {
        dbManager.updateItemTimestamp(id: item.id.uuidString)
    }
    
    func clearHistory(type: ClipboardContentType? = nil) {
        let items = dbManager.getAllItems(limit: 10000)
        for item in items {
            if type == nil || item.type == type {
                deleteItem(item)
            }
        }
        dbManager.vacuum()
    }
    
    // MARK: - LRU Cleanup
    
    private func performLRU() {
        // 1. Cleanup by count
        let oldItems = dbManager.getOldItems(maxCount: maxItemsCount)
        for item in oldItems {
            deleteItem(item)
        }
        
        // 2. Cleanup by age (optional, e.g. 30 days)
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 3600)
        let expiredItems = dbManager.deleteItemsOlderThan(date: thirtyDaysAgo)
        for item in expiredItems {
            if item.type == .image {
                let fileURL = imagesDir.appendingPathComponent(item.content)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        
        // 3. Image storage size limit
        cleanupImageStorage()
    }
    
    private func cleanupImageStorage() {
        let maxImageStorageSize = maxImageStorageSizeMB * 1024 * 1024
        let items = dbManager.getAllItems(limit: max(maxItemsCount, 2000))
        let imageItems = items.filter { $0.type == .image }
        
        var currentSize = imageItems.reduce(0) { $0 + $1.size }
        
        if currentSize > maxImageStorageSize {
            // Remove oldest images until we are under limit
            for item in imageItems.reversed() {
                if currentSize <= maxImageStorageSize { break }
                currentSize -= item.size
                deleteItem(item)
            }
        }
    }
    
    func getImagePath(filename: String) -> URL {
        return imagesDir.appendingPathComponent(filename)
    }
}
