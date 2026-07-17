import Foundation
import AppKit

class ClipboardStorageManager {
    static let shared = ClipboardStorageManager()
    
    private var dbManager: DatabaseManager
    private var imagesDir: URL
    private var thumbnailsDir: URL
    private var storageDir: URL
    
    private var maxItemsCount = AppDefaultSettings.Clipboard.maxHistoryItems
    private var maxImageStorageSizeMB = AppDefaultSettings.Clipboard.maxImageStorageSizeMB
    
    var storageDirectory: URL { storageDir }
    var imagesDirectory: URL { imagesDir }
    var thumbnailsDirectory: URL { thumbnailsDir }
    var databasePath: String { storageDir.appendingPathComponent("clipboard.db").path }

    convenience init() {
        self.init(storageDirectory: ConfigDirectoryManager.shared.currentDirectory)
    }

    init(storageDirectory: URL) {
        self.storageDir = storageDirectory.standardizedFileURL
        self.imagesDir = storageDir.appendingPathComponent("clipboard_images")
        self.thumbnailsDir = storageDir.appendingPathComponent("clipboard_thumbnails")
        
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true, attributes: nil)
        try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true, attributes: nil)
        
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
        thumbnailsDir = storageDir.appendingPathComponent("clipboard_thumbnails")
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true, attributes: nil)
        try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true, attributes: nil)
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

    @discardableResult
    func saveImageItem(
        content: String,
        size: Int,
        width: Int?,
        height: Int?,
        thumbnailFilename: String?,
        ocrStatus: ClipboardOCRStatus? = nil
    ) -> UUID {
        let itemID = UUID()
        let id = itemID.uuidString
        dbManager.insertItem(
            id: id,
            type: ClipboardContentType.image.rawValue,
            content: content,
            size: size,
            imageWidth: width,
            imageHeight: height,
            thumbnailFilename: thumbnailFilename,
            imageOCRStatus: ocrStatus,
            imageOCRUpdatedAt: ocrStatus == nil ? nil : Date()
        )

        DispatchQueue.global(qos: .background).async {
            self.performLRU()
        }

        return itemID
    }
    
    func getAllItems(limit: Int = 100) -> [ClipboardItem] {
        return dbManager.getAllItems(limit: limit)
    }

    func getListItems(limit: Int = 100) -> [ClipboardListItem] {
        return dbManager.getListItems(limit: limit)
    }

    func getItem(id: UUID) -> ClipboardItem? {
        return dbManager.getItem(id: id.uuidString)
    }

    func updateImageOCR(id: UUID, text: String?, status: ClipboardOCRStatus) {
        dbManager.updateImageOCR(id: id.uuidString, text: text, status: status)
    }
    
    func search(query: String) -> [ClipboardItem] {
        if query.isEmpty {
            return getAllItems()
        }
        return dbManager.search(query: query)
    }

    func searchListItems(query: String, limit: Int = 50) -> [ClipboardListItem] {
        if query.isEmpty {
            return getListItems(limit: limit)
        }

        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if Self.imageSearchTerms.contains(normalized) {
            return dbManager.getImageListItems(limit: limit)
        }

        return dbManager.searchListItems(query: normalized, limit: limit)
    }
    
    func deleteItem(_ item: ClipboardItem) {
        dbManager.deleteItem(id: item.id.uuidString)
        if item.type == .image {
            let fileURL = imagesDir.appendingPathComponent(item.content)
            try? FileManager.default.removeItem(at: fileURL)
            if let thumbnailFilename = item.thumbnailFilename {
                let thumbnailURL = thumbnailsDir.appendingPathComponent(thumbnailFilename)
                try? FileManager.default.removeItem(at: thumbnailURL)
            }
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

    func getThumbnailPath(filename: String) -> URL {
        return thumbnailsDir.appendingPathComponent(filename)
    }

    private static let imageSearchTerms: Set<String> = [
        "image", "images", "img", "photo", "photos", "picture", "pictures", "图片", "照片"
    ]
}
