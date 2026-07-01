import Foundation
import SQLite3

class DatabaseManager {
    private var db: OpaquePointer?
    private var dbPath: String
    private let queue = DispatchQueue(label: "com.macefficiency.db", qos: .userInitiated)

    init(path: String) {
        self.dbPath = path
        openDatabase()
        setupTables()
    }

    deinit {
        checkpointAndClose()
    }

    private func withDatabase<T>(_ block: () -> T) -> T {
        return queue.sync {
            block()
        }
    }

    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            let error = String(cString: sqlite3_errmsg(db))
            print("Error opening database at \(dbPath): \(error)")
        }
        
        // Enable WAL mode for high performance concurrency
        execute(sql: "PRAGMA journal_mode=WAL;")
        execute(sql: "PRAGMA synchronous=NORMAL;")
    }

    func checkpointAndClose() {
        queue.sync {
            guard db != nil else { return }
            sqlite3_exec(db, "PRAGMA wal_checkpoint(FULL);", nil, nil, nil)
            sqlite3_close(db)
            db = nil
        }
    }

    func reopen(path: String) {
        queue.sync {
            if db != nil {
                sqlite3_exec(db, "PRAGMA wal_checkpoint(FULL);", nil, nil, nil)
                sqlite3_close(db)
            }
            dbPath = path
            db = nil
            openDatabaseUnlocked()
            setupTablesUnlocked()
        }
    }

    private func openDatabaseUnlocked() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            let error = String(cString: sqlite3_errmsg(db))
            print("Error opening database at \(dbPath): \(error)")
        }

        _ = executeUnlocked(sql: "PRAGMA journal_mode=WAL;")
        _ = executeUnlocked(sql: "PRAGMA synchronous=NORMAL;")
    }

    private func setupTables() {
        // Main items table
        let createTable = """
        CREATE TABLE IF NOT EXISTS clipboard_items (
            id TEXT PRIMARY KEY,
            type TEXT,
            content TEXT,
            timestamp REAL,
            size INTEGER,
            image_width INTEGER,
            image_height INTEGER,
            thumbnail_filename TEXT,
            image_ocr_text TEXT,
            image_ocr_status TEXT,
            image_ocr_updated_at REAL
        );
        CREATE INDEX IF NOT EXISTS idx_timestamp ON clipboard_items(timestamp);
        """
        execute(sql: createTable)
        ensureClipboardMetadataColumns()

        // FTS5 virtual table for full-text search
        // We only index text content. For images, we might index their metadata or just leave them out of FTS.
        let createFtsTable = "CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_fts USING fts5(id UNINDEXED, content);"
        execute(sql: createFtsTable)
        
        // Triggers to keep FTS in sync
        let createTriggers = """
        DROP TRIGGER IF EXISTS after_delete_clipboard_items;

        CREATE TRIGGER IF NOT EXISTS after_insert_clipboard_items AFTER INSERT ON clipboard_items
        WHEN new.type = 'text'
        BEGIN
            INSERT INTO clipboard_fts(id, content) VALUES (new.id, new.content);
        END;

        CREATE TRIGGER IF NOT EXISTS after_delete_clipboard_items AFTER DELETE ON clipboard_items
        BEGIN
            DELETE FROM clipboard_fts WHERE id = old.id;
        END;

        CREATE TRIGGER IF NOT EXISTS after_update_clipboard_items AFTER UPDATE ON clipboard_items
        WHEN new.type = 'text'
        BEGIN
            UPDATE clipboard_fts SET content = new.content WHERE id = old.id;
        END;
        """
        execute(sql: createTriggers)
    }

    private func setupTablesUnlocked() {
        let createTable = """
        CREATE TABLE IF NOT EXISTS clipboard_items (
            id TEXT PRIMARY KEY,
            type TEXT,
            content TEXT,
            timestamp REAL,
            size INTEGER,
            image_width INTEGER,
            image_height INTEGER,
            thumbnail_filename TEXT,
            image_ocr_text TEXT,
            image_ocr_status TEXT,
            image_ocr_updated_at REAL
        );
        CREATE INDEX IF NOT EXISTS idx_timestamp ON clipboard_items(timestamp);
        """
        _ = executeUnlocked(sql: createTable)
        ensureClipboardMetadataColumnsUnlocked()

        let createFtsTable = "CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_fts USING fts5(id UNINDEXED, content);"
        _ = executeUnlocked(sql: createFtsTable)

        let createTriggers = """
        DROP TRIGGER IF EXISTS after_delete_clipboard_items;

        CREATE TRIGGER IF NOT EXISTS after_insert_clipboard_items AFTER INSERT ON clipboard_items
        WHEN new.type = 'text'
        BEGIN
            INSERT INTO clipboard_fts(id, content) VALUES (new.id, new.content);
        END;

        CREATE TRIGGER IF NOT EXISTS after_delete_clipboard_items AFTER DELETE ON clipboard_items
        BEGIN
            DELETE FROM clipboard_fts WHERE id = old.id;
        END;

        CREATE TRIGGER IF NOT EXISTS after_update_clipboard_items AFTER UPDATE ON clipboard_items
        WHEN new.type = 'text'
        BEGIN
            UPDATE clipboard_fts SET content = new.content WHERE id = old.id;
        END;
        """
        _ = executeUnlocked(sql: createTriggers)
    }

    private func ensureClipboardMetadataColumns() {
        withDatabase {
            ensureClipboardMetadataColumnsUnlocked()
        }
    }

    private func ensureClipboardMetadataColumnsUnlocked() {
        ensureColumnExists(table: "clipboard_items", column: "image_width", definition: "INTEGER")
        ensureColumnExists(table: "clipboard_items", column: "image_height", definition: "INTEGER")
        ensureColumnExists(table: "clipboard_items", column: "thumbnail_filename", definition: "TEXT")
        ensureColumnExists(table: "clipboard_items", column: "image_ocr_text", definition: "TEXT")
        ensureColumnExists(table: "clipboard_items", column: "image_ocr_status", definition: "TEXT")
        ensureColumnExists(table: "clipboard_items", column: "image_ocr_updated_at", definition: "REAL")
    }

    private func ensureColumnExists(table: String, column: String, definition: String) {
        let pragma = "PRAGMA table_info(\(table));"
        var statement: OpaquePointer?
        var exists = false

        if sqlite3_prepare_v2(db, pragma, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let name = sqlite3_column_text(statement, 1) else { continue }
                if String(cString: name) == column {
                    exists = true
                    break
                }
            }
        }
        sqlite3_finalize(statement)

        guard !exists else { return }
        _ = executeUnlocked(sql: "ALTER TABLE \(table) ADD COLUMN \(column) \(definition);")
    }

    @discardableResult
    func execute(sql: String) -> Bool {
        return withDatabase {
            executeUnlocked(sql: sql)
        }
    }

    private func executeUnlocked(sql: String) -> Bool {
        var error: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let msg = error.map { String(cString: $0) } ?? "Unknown SQLite error"
            print("SQL Error: \(msg) | SQL: \(sql)")
            sqlite3_free(error)
            return false
        }
        return true
    }

    func insertItem(
        id: String,
        type: String,
        content: String,
        size: Int,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        thumbnailFilename: String? = nil,
        imageOCRText: String? = nil,
        imageOCRStatus: ClipboardOCRStatus? = nil,
        imageOCRUpdatedAt: Date? = nil
    ) {
        withDatabase {
            // Deduplication: If same content exists, we update its timestamp and move to top
            // For text items, we check content. For images, we usually treat each as unique since they have unique filenames.
            if type == "text" {
                let checkSql = "SELECT id FROM clipboard_items WHERE type = 'text' AND content = ? LIMIT 1;"
                var checkStatement: OpaquePointer?
                var existingId: String?
                
                if sqlite3_prepare_v2(db, checkSql, -1, &checkStatement, nil) == SQLITE_OK {
                    sqlite3_bind_text(checkStatement, 1, (content as NSString).utf8String, -1, nil)
                    if sqlite3_step(checkStatement) == SQLITE_ROW {
                        existingId = String(cString: sqlite3_column_text(checkStatement, 0))
                    }
                }
                sqlite3_finalize(checkStatement)
                
                if let eid = existingId {
                    let updateSql = "UPDATE clipboard_items SET timestamp = ? WHERE id = ?;"
                    var updateStatement: OpaquePointer?
                    if sqlite3_prepare_v2(db, updateSql, -1, &updateStatement, nil) == SQLITE_OK {
                        sqlite3_bind_double(updateStatement, 1, Date().timeIntervalSince1970)
                        sqlite3_bind_text(updateStatement, 2, (eid as NSString).utf8String, -1, nil)
                        sqlite3_step(updateStatement)
                    }
                    sqlite3_finalize(updateStatement)
                    return
                }
            }

            let sql = """
            INSERT OR REPLACE INTO clipboard_items
            (id, type, content, timestamp, size, image_width, image_height, thumbnail_filename,
             image_ocr_text, image_ocr_status, image_ocr_updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 2, (type as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 3, (content as NSString).utf8String, -1, nil)
                sqlite3_bind_double(statement, 4, Date().timeIntervalSince1970)
                sqlite3_bind_int64(statement, 5, Int64(size))
                bindOptionalInt(imageWidth, to: statement, index: 6)
                bindOptionalInt(imageHeight, to: statement, index: 7)
                bindOptionalText(thumbnailFilename, to: statement, index: 8)
                bindOptionalText(imageOCRText, to: statement, index: 9)
                bindOptionalText(imageOCRStatus?.rawValue, to: statement, index: 10)
                bindOptionalDouble(imageOCRUpdatedAt?.timeIntervalSince1970, to: statement, index: 11)
                
                if sqlite3_step(statement) != SQLITE_DONE {
                    print("Error inserting item")
                }
            }
            sqlite3_finalize(statement)
        }
    }

    private func bindOptionalInt(_ value: Int?, to statement: OpaquePointer?, index: Int32) {
        if let value {
            sqlite3_bind_int(statement, index, Int32(value))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindOptionalText(_ value: String?, to statement: OpaquePointer?, index: Int32) {
        if let value {
            sqlite3_bind_text(statement, index, (value as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindOptionalDouble(_ value: Double?, to statement: OpaquePointer?, index: Int32) {
        if let value {
            sqlite3_bind_double(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    func deleteItem(id: String) {
        withDatabase {
            let sql = "DELETE FROM clipboard_items WHERE id = ?;"
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }

    func updateItemTimestamp(id: String) {
        withDatabase {
            let sql = "UPDATE clipboard_items SET timestamp = ? WHERE id = ?;"
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_double(statement, 1, Date().timeIntervalSince1970)
                sqlite3_bind_text(statement, 2, (id as NSString).utf8String, -1, nil)
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }

    func getAllItems(limit: Int = 100) -> [ClipboardItem] {
        return withDatabase {
            let sql = "SELECT id, type, content, timestamp, size, image_width, image_height, thumbnail_filename, image_ocr_text, image_ocr_status, image_ocr_updated_at FROM clipboard_items ORDER BY timestamp DESC LIMIT ?;"
            var statement: OpaquePointer?
            var items: [ClipboardItem] = []
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(limit))
                
                while sqlite3_step(statement) == SQLITE_ROW {
                    let id = String(cString: sqlite3_column_text(statement, 0))
                    let typeStr = String(cString: sqlite3_column_text(statement, 1))
                    let content = String(cString: sqlite3_column_text(statement, 2))
                    let timestamp = sqlite3_column_double(statement, 3)
                    let size = sqlite3_column_int64(statement, 4)
                    
                    if let type = ClipboardContentType(rawValue: typeStr), let uuid = UUID(uuidString: id) {
                        items.append(ClipboardItem(
                            id: uuid,
                            type: type,
                            content: content,
                            timestamp: Date(timeIntervalSince1970: timestamp),
                            size: Int(size),
                            imageWidth: optionalInt(statement, 5),
                            imageHeight: optionalInt(statement, 6),
                            thumbnailFilename: optionalString(statement, 7),
                            imageOCRText: optionalString(statement, 8),
                            imageOCRStatus: optionalOCRStatus(statement, 9),
                            imageOCRUpdatedAt: optionalDate(statement, 10)
                        ))
                    }
                }
            }
            sqlite3_finalize(statement)
            return items
        }
    }

    func getItem(id itemID: String) -> ClipboardItem? {
        return withDatabase {
            let sql = "SELECT id, type, content, timestamp, size, image_width, image_height, thumbnail_filename, image_ocr_text, image_ocr_status, image_ocr_updated_at FROM clipboard_items WHERE id = ? LIMIT 1;"
            var statement: OpaquePointer?
            var item: ClipboardItem?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (itemID as NSString).utf8String, -1, nil)
                if sqlite3_step(statement) == SQLITE_ROW {
                    item = makeClipboardItem(from: statement)
                }
            }
            sqlite3_finalize(statement)
            return item
        }
    }

    func getListItems(limit: Int = 100, previewLimit: Int = 4096) -> [ClipboardListItem] {
        return withDatabase {
            let sql = """
            SELECT id, type,
                   CASE WHEN type = 'text' THEN substr(content, 1, ?) ELSE content END,
                   length(content), timestamp, size, image_width, image_height, thumbnail_filename,
                   image_ocr_status,
                   CASE WHEN image_ocr_text IS NULL OR length(image_ocr_text) = 0 THEN 0 ELSE 1 END,
                   substr(image_ocr_text, 1, 500)
            FROM clipboard_items
            ORDER BY timestamp DESC
            LIMIT ?;
            """
            var statement: OpaquePointer?
            var items: [ClipboardListItem] = []

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(previewLimit))
                sqlite3_bind_int(statement, 2, Int32(limit))
                while sqlite3_step(statement) == SQLITE_ROW {
                    if let item = makeClipboardListItem(from: statement) {
                        items.append(item)
                    }
                }
            }
            sqlite3_finalize(statement)
            return items
        }
    }

    func search(query: String, limit: Int = 50) -> [ClipboardItem] {
        return withDatabase {
            // Search using FTS5 for text items, combined with simple LIKE for filename/meta if needed
            // Here we primarily use FTS5 for content search.
            let sql = """
            SELECT i.id, i.type, i.content, i.timestamp, i.size, i.image_width, i.image_height, i.thumbnail_filename, i.image_ocr_text, i.image_ocr_status, i.image_ocr_updated_at
            FROM clipboard_items i
            JOIN clipboard_fts f ON i.id = f.id
            WHERE f.content MATCH ?
            ORDER BY rank
            LIMIT ?;
            """
            
            var statement: OpaquePointer?
            var items: [ClipboardItem] = []
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                // FTS5 MATCH pattern: we add * for prefix matching
                let searchPattern = "\(query)*"
                sqlite3_bind_text(statement, 1, (searchPattern as NSString).utf8String, -1, nil)
                sqlite3_bind_int(statement, 2, Int32(limit))
                
                while sqlite3_step(statement) == SQLITE_ROW {
                    if let item = makeClipboardItem(from: statement) {
                        items.append(item)
                    }
                }
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                print("Search Prepare Error: \(error)")
            }
            sqlite3_finalize(statement)
            return items
        }
    }

    func searchListItems(query: String, limit: Int = 50, previewLimit: Int = 4096) -> [ClipboardListItem] {
        return withDatabase {
            let sql = """
            SELECT i.id, i.type, substr(i.content, 1, ?), length(i.content),
                   i.timestamp, i.size, i.image_width, i.image_height, i.thumbnail_filename,
                   i.image_ocr_status,
                   CASE WHEN i.image_ocr_text IS NULL OR length(i.image_ocr_text) = 0 THEN 0 ELSE 1 END,
                   substr(i.image_ocr_text, 1, 500)
            FROM clipboard_items i
            JOIN clipboard_fts f ON i.id = f.id
            WHERE f.content MATCH ?
            ORDER BY rank
            LIMIT ?;
            """

            var statement: OpaquePointer?
            var items: [ClipboardListItem] = []

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                let searchPattern = "\(query)*"
                sqlite3_bind_int(statement, 1, Int32(previewLimit))
                sqlite3_bind_text(statement, 2, (searchPattern as NSString).utf8String, -1, nil)
                sqlite3_bind_int(statement, 3, Int32(limit))
                while sqlite3_step(statement) == SQLITE_ROW {
                    if let item = makeClipboardListItem(from: statement) {
                        items.append(item)
                    }
                }
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                print("Search Prepare Error: \(error)")
            }
            sqlite3_finalize(statement)
            return items
        }
    }

    func getImageListItems(limit: Int = 50) -> [ClipboardListItem] {
        return withDatabase {
            let sql = """
            SELECT id, type, content, length(content), timestamp, size,
                   image_width, image_height, thumbnail_filename,
                   image_ocr_status,
                   CASE WHEN image_ocr_text IS NULL OR length(image_ocr_text) = 0 THEN 0 ELSE 1 END,
                   substr(image_ocr_text, 1, 500)
            FROM clipboard_items
            WHERE type = 'image'
            ORDER BY timestamp DESC
            LIMIT ?;
            """
            var statement: OpaquePointer?
            var items: [ClipboardListItem] = []

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(limit))
                while sqlite3_step(statement) == SQLITE_ROW {
                    if let item = makeClipboardListItem(from: statement) {
                        items.append(item)
                    }
                }
            }
            sqlite3_finalize(statement)
            return items
        }
    }
    
    func getOldItems(maxCount: Int) -> [ClipboardItem] {
        return withDatabase {
            // We want items beyond the first N items.
            let sqlCorrect = "SELECT id, type, content, timestamp, size, image_width, image_height, thumbnail_filename, image_ocr_text, image_ocr_status, image_ocr_updated_at FROM clipboard_items ORDER BY timestamp DESC LIMIT -1 OFFSET ?;"
            
            var statement: OpaquePointer?
            var items: [ClipboardItem] = []
            
            if sqlite3_prepare_v2(db, sqlCorrect, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(maxCount))
                
                while sqlite3_step(statement) == SQLITE_ROW {
                    if let item = makeClipboardItem(from: statement) {
                        items.append(item)
                    }
                }
            }
            sqlite3_finalize(statement)
            return items
        }
    }
    
    func deleteItemsOlderThan(date: Date) -> [ClipboardItem] {
        return withDatabase {
            // We return items to be deleted so file cache can be cleaned up
            let selectSql = "SELECT id, type, content, timestamp, size, image_width, image_height, thumbnail_filename, image_ocr_text, image_ocr_status, image_ocr_updated_at FROM clipboard_items WHERE timestamp < ?;"
            var selectStatement: OpaquePointer?
            var items: [ClipboardItem] = []
            
            if sqlite3_prepare_v2(db, selectSql, -1, &selectStatement, nil) == SQLITE_OK {
                sqlite3_bind_double(selectStatement, 1, date.timeIntervalSince1970)
                while sqlite3_step(selectStatement) == SQLITE_ROW {
                    if let item = makeClipboardItem(from: selectStatement) {
                        items.append(item)
                    }
                }
            }
            sqlite3_finalize(selectStatement)
            
            let deleteSql = "DELETE FROM clipboard_items WHERE timestamp < ?;"
            var deleteStatement: OpaquePointer?
            if sqlite3_prepare_v2(db, deleteSql, -1, &deleteStatement, nil) == SQLITE_OK {
                sqlite3_bind_double(deleteStatement, 1, date.timeIntervalSince1970)
                sqlite3_step(deleteStatement)
            }
            sqlite3_finalize(deleteStatement)
            
            return items
        }
    }
    
    func vacuum() {
        _ = execute(sql: "VACUUM;")
    }

    func updateImageOCR(id: String, text: String?, status: ClipboardOCRStatus) {
        withDatabase {
            let sql = """
            UPDATE clipboard_items
            SET image_ocr_text = ?, image_ocr_status = ?, image_ocr_updated_at = ?
            WHERE id = ? AND type = 'image';
            """
            var statement: OpaquePointer?
            let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                bindOptionalText(trimmedText?.isEmpty == true ? nil : trimmedText, to: statement, index: 1)
                sqlite3_bind_text(statement, 2, (status.rawValue as NSString).utf8String, -1, nil)
                sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970)
                sqlite3_bind_text(statement, 4, (id as NSString).utf8String, -1, nil)
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)

            updateImageFTS(id: id, ocrText: trimmedText)
        }
    }

    private func updateImageFTS(id: String, ocrText: String?) {
        let fetchSql = "SELECT content FROM clipboard_items WHERE id = ? AND type = 'image' LIMIT 1;"
        var fetchStatement: OpaquePointer?
        var filename: String?

        if sqlite3_prepare_v2(db, fetchSql, -1, &fetchStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(fetchStatement, 1, (id as NSString).utf8String, -1, nil)
            if sqlite3_step(fetchStatement) == SQLITE_ROW, let content = sqlite3_column_text(fetchStatement, 0) {
                filename = String(cString: content)
            }
        }
        sqlite3_finalize(fetchStatement)

        let deleteSql = "DELETE FROM clipboard_fts WHERE id = ?;"
        var deleteStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteSql, -1, &deleteStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(deleteStatement, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_step(deleteStatement)
        }
        sqlite3_finalize(deleteStatement)

        guard let filename else { return }

        let searchableText = [
            "image images img photo photos picture pictures 图片 照片",
            filename,
            ocrText
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !searchableText.isEmpty else { return }

        let insertSql = "INSERT INTO clipboard_fts(id, content) VALUES (?, ?);"
        var insertStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSql, -1, &insertStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(insertStatement, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 2, (searchableText as NSString).utf8String, -1, nil)
            sqlite3_step(insertStatement)
        }
        sqlite3_finalize(insertStatement)
    }

    private func makeClipboardItem(from statement: OpaquePointer?) -> ClipboardItem? {
        guard
            let idText = sqlite3_column_text(statement, 0),
            let typeText = sqlite3_column_text(statement, 1),
            let contentText = sqlite3_column_text(statement, 2)
        else {
            return nil
        }

        let id = String(cString: idText)
        let typeStr = String(cString: typeText)
        let content = String(cString: contentText)
        let timestamp = sqlite3_column_double(statement, 3)
        let size = sqlite3_column_int64(statement, 4)

        guard let type = ClipboardContentType(rawValue: typeStr), let uuid = UUID(uuidString: id) else {
            return nil
        }

        return ClipboardItem(
            id: uuid,
            type: type,
            content: content,
            timestamp: Date(timeIntervalSince1970: timestamp),
            size: Int(size),
            imageWidth: optionalInt(statement, 5),
            imageHeight: optionalInt(statement, 6),
            thumbnailFilename: optionalString(statement, 7),
            imageOCRText: optionalString(statement, 8),
            imageOCRStatus: optionalOCRStatus(statement, 9),
            imageOCRUpdatedAt: optionalDate(statement, 10)
        )
    }

    private func makeClipboardListItem(from statement: OpaquePointer?) -> ClipboardListItem? {
        guard
            let idText = sqlite3_column_text(statement, 0),
            let typeText = sqlite3_column_text(statement, 1),
            let previewText = sqlite3_column_text(statement, 2)
        else {
            return nil
        }

        let id = String(cString: idText)
        let typeStr = String(cString: typeText)
        let previewContent = String(cString: previewText)
        let fullContentLength = sqlite3_column_int(statement, 3)
        let timestamp = sqlite3_column_double(statement, 4)
        let size = sqlite3_column_int64(statement, 5)

        guard let type = ClipboardContentType(rawValue: typeStr), let uuid = UUID(uuidString: id) else {
            return nil
        }

        return ClipboardListItem(
            id: uuid,
            type: type,
            previewContent: previewContent,
            fullContentLength: Int(fullContentLength),
            timestamp: Date(timeIntervalSince1970: timestamp),
            size: Int(size),
            imageFilename: type == .image ? previewContent : nil,
            imageWidth: optionalInt(statement, 6),
            imageHeight: optionalInt(statement, 7),
            thumbnailFilename: optionalString(statement, 8),
            imageOCRStatus: optionalOCRStatus(statement, 9),
            hasImageOCRText: optionalInt(statement, 10) == 1,
            imageOCRTextPreview: optionalString(statement, 11)
        )
    }

    private func optionalInt(_ statement: OpaquePointer?, _ index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int(statement, index))
    }

    private func optionalString(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }

    private func optionalDate(_ statement: OpaquePointer?, _ index: Int32) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }

    private func optionalOCRStatus(_ statement: OpaquePointer?, _ index: Int32) -> ClipboardOCRStatus? {
        guard let rawValue = optionalString(statement, index) else { return nil }
        return ClipboardOCRStatus(rawValue: rawValue)
    }
}
