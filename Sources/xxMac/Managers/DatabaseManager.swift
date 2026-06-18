import Foundation
import SQLite3

class DatabaseManager {
    private var db: OpaquePointer?
    private let dbPath: String
    private let queue = DispatchQueue(label: "com.macefficiency.db", qos: .userInitiated)

    init(path: String) {
        self.dbPath = path
        openDatabase()
        setupTables()
    }

    deinit {
        _ = queue.sync {
            sqlite3_close(db)
        }
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

    private func setupTables() {
        // Main items table
        let createTable = """
        CREATE TABLE IF NOT EXISTS clipboard_items (
            id TEXT PRIMARY KEY,
            type TEXT,
            content TEXT,
            timestamp REAL,
            size INTEGER
        );
        CREATE INDEX IF NOT EXISTS idx_timestamp ON clipboard_items(timestamp);
        """
        execute(sql: createTable)

        // FTS5 virtual table for full-text search
        // We only index text content. For images, we might index their metadata or just leave them out of FTS.
        let createFtsTable = "CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_fts USING fts5(id UNINDEXED, content);"
        execute(sql: createFtsTable)
        
        // Triggers to keep FTS in sync
        let createTriggers = """
        CREATE TRIGGER IF NOT EXISTS after_insert_clipboard_items AFTER INSERT ON clipboard_items
        WHEN new.type = 'text'
        BEGIN
            INSERT INTO clipboard_fts(id, content) VALUES (new.id, new.content);
        END;

        CREATE TRIGGER IF NOT EXISTS after_delete_clipboard_items AFTER DELETE ON clipboard_items
        WHEN old.type = 'text'
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

    @discardableResult
    func execute(sql: String) -> Bool {
        return withDatabase {
            var error: UnsafeMutablePointer<Int8>?
            if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
                let msg = String(cString: error!)
                print("SQL Error: \(msg) | SQL: \(sql)")
                sqlite3_free(error)
                return false
            }
            return true
        }
    }

    func insertItem(id: String, type: String, content: String, size: Int) {
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

            let sql = "INSERT OR REPLACE INTO clipboard_items (id, type, content, timestamp, size) VALUES (?, ?, ?, ?, ?);"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 2, (type as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 3, (content as NSString).utf8String, -1, nil)
                sqlite3_bind_double(statement, 4, Date().timeIntervalSince1970)
                sqlite3_bind_int64(statement, 5, Int64(size))
                
                if sqlite3_step(statement) != SQLITE_DONE {
                    print("Error inserting item")
                }
            }
            sqlite3_finalize(statement)
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

    func getAllItems(limit: Int = 100) -> [ClipboardItem] {
        return withDatabase {
            let sql = "SELECT id, type, content, timestamp, size FROM clipboard_items ORDER BY timestamp DESC LIMIT ?;"
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
                            size: Int(size)
                        ))
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
            SELECT i.id, i.type, i.content, i.timestamp, i.size 
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
                            size: Int(size)
                        ))
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
    
    func getOldItems(maxCount: Int) -> [ClipboardItem] {
        return withDatabase {
            // We want items beyond the first N items.
            let sqlCorrect = "SELECT id, type, content, timestamp, size FROM clipboard_items ORDER BY timestamp DESC LIMIT -1 OFFSET ?;"
            
            var statement: OpaquePointer?
            var items: [ClipboardItem] = []
            
            if sqlite3_prepare_v2(db, sqlCorrect, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(maxCount))
                
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
                            size: Int(size)
                        ))
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
            let selectSql = "SELECT id, type, content, timestamp, size FROM clipboard_items WHERE timestamp < ?;"
            var selectStatement: OpaquePointer?
            var items: [ClipboardItem] = []
            
            if sqlite3_prepare_v2(db, selectSql, -1, &selectStatement, nil) == SQLITE_OK {
                sqlite3_bind_double(selectStatement, 1, date.timeIntervalSince1970)
                while sqlite3_step(selectStatement) == SQLITE_ROW {
                    let id = String(cString: sqlite3_column_text(selectStatement, 0))
                    let typeStr = String(cString: sqlite3_column_text(selectStatement, 1))
                    let content = String(cString: sqlite3_column_text(selectStatement, 2))
                    let timestamp = sqlite3_column_double(selectStatement, 3)
                    let size = sqlite3_column_int64(selectStatement, 4)
                    
                    if let type = ClipboardContentType(rawValue: typeStr), let uuid = UUID(uuidString: id) {
                        items.append(ClipboardItem(
                            id: uuid,
                            type: type,
                            content: content,
                            timestamp: Date(timeIntervalSince1970: timestamp),
                            size: Int(size)
                        ))
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
}
