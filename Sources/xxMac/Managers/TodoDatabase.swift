import Foundation
import SQLite3

protocol TodoPersisting: AnyObject {
    func fetchTasks(includeArchived: Bool) throws -> [TodoTask]
    func insert(_ task: TodoTask) throws
    func update(_ task: TodoTask) throws
    func update(_ task: TodoTask, normalizingRanks tasks: [TodoTask]) throws
    func updateRanks(_ tasks: [TodoTask]) throws
    func delete(id: UUID) throws
    func checkpointAndClose()
    func reopen(at url: URL) throws
}

enum TodoDatabaseError: LocalizedError, Equatable {
    case open(path: String, message: String)
    case sqlite(operation: String, message: String)
    case invalidRow(column: String)

    var errorDescription: String? {
        switch self {
        case let .open(path, message):
            return "Unable to open todo database at \(path): \(message)"
        case let .sqlite(operation, message):
            return "Todo database \(operation) failed: \(message)"
        case let .invalidRow(column):
            return "Todo database row contains an invalid \(column) value"
        }
    }
}

final class TodoDatabase: TodoPersisting {
    private static let schemaVersion: Int32 = 1
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let queue = DispatchQueue(label: "com.macefficiency.todo.database", qos: .userInitiated)
    private var database: OpaquePointer?
    private var databaseURL: URL

    init(url: URL) throws {
        databaseURL = url
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try openAndPrepare()
    }

    deinit {
        checkpointAndClose()
    }

    func fetchTasks(includeArchived: Bool) throws -> [TodoTask] {
        try queue.sync {
            let archivedClause = includeArchived ? "" : "WHERE archived_at IS NULL"
            let sql = """
            SELECT id, title, notes, status, quadrant, due_at, created_at, updated_at,
                   completed_at, archived_at, quadrant_rank, status_rank
            FROM todo_tasks
            \(archivedClause)
            ORDER BY created_at ASC, id ASC;
            """
            let statement = try prepare(sql, operation: "prepare fetch")
            defer { sqlite3_finalize(statement) }

            var tasks: [TodoTask] = []
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    tasks.append(try decodeTask(from: statement))
                case SQLITE_DONE:
                    return tasks
                default:
                    throw sqliteError(operation: "fetch tasks")
                }
            }
        }
    }

    func insert(_ task: TodoTask) throws {
        try queue.sync {
            let sql = """
            INSERT INTO todo_tasks (
                id, title, notes, status, quadrant, due_at, created_at, updated_at,
                completed_at, archived_at, quadrant_rank, status_rank
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            let statement = try prepare(sql, operation: "prepare insert")
            defer { sqlite3_finalize(statement) }
            bind(task, to: statement)
            try finish(statement, operation: "insert task")
        }
    }

    func update(_ task: TodoTask) throws {
        try queue.sync {
            try updateUnlocked(task)
        }
    }

    func update(_ task: TodoTask, normalizingRanks tasks: [TodoTask]) throws {
        try queue.sync {
            try execute("BEGIN IMMEDIATE TRANSACTION;", operation: "begin normalized move")
            do {
                try updateRanksUnlocked(tasks)
                try updateUnlocked(task)
                try execute("COMMIT;", operation: "commit normalized move")
            } catch {
                try? execute("ROLLBACK;", operation: "rollback normalized move")
                throw error
            }
        }
    }

    func updateRanks(_ tasks: [TodoTask]) throws {
        guard !tasks.isEmpty else { return }
        try queue.sync {
            try execute("BEGIN IMMEDIATE TRANSACTION;", operation: "begin rank update")
            do {
                try updateRanksUnlocked(tasks)
                try execute("COMMIT;", operation: "commit rank update")
            } catch {
                try? execute("ROLLBACK;", operation: "rollback rank update")
                throw error
            }
        }
    }

    func delete(id: UUID) throws {
        try queue.sync {
            let statement = try prepare(
                "DELETE FROM todo_tasks WHERE id = ?;",
                operation: "prepare delete"
            )
            defer { sqlite3_finalize(statement) }
            bindText(id.uuidString, to: statement, index: 1)
            try finish(statement, operation: "delete task")
        }
    }

    func checkpointAndClose() {
        queue.sync {
            closeUnlocked()
        }
    }

    func reopen(at url: URL) throws {
        try queue.sync {
            closeUnlocked()
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            databaseURL = url
            try openAndPrepareUnlocked()
        }
    }

    private func updateUnlocked(_ task: TodoTask) throws {
        let sql = """
        UPDATE todo_tasks SET
            title = ?, notes = ?, status = ?, quadrant = ?, due_at = ?,
            created_at = ?, updated_at = ?, completed_at = ?, archived_at = ?,
            quadrant_rank = ?, status_rank = ?
        WHERE id = ?;
        """
        let statement = try prepare(sql, operation: "prepare update")
        defer { sqlite3_finalize(statement) }
        bindText(task.title, to: statement, index: 1)
        bindText(task.notes, to: statement, index: 2)
        bindText(task.status.rawValue, to: statement, index: 3)
        bindText(task.quadrant.rawValue, to: statement, index: 4)
        bindDate(task.dueAt, to: statement, index: 5)
        sqlite3_bind_double(statement, 6, task.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 7, task.updatedAt.timeIntervalSince1970)
        bindDate(task.completedAt, to: statement, index: 8)
        bindDate(task.archivedAt, to: statement, index: 9)
        sqlite3_bind_double(statement, 10, task.quadrantRank)
        sqlite3_bind_double(statement, 11, task.statusRank)
        bindText(task.id.uuidString, to: statement, index: 12)
        try finish(statement, operation: "update task")
    }

    private func updateRanksUnlocked(_ tasks: [TodoTask]) throws {
        guard !tasks.isEmpty else { return }
        let statement = try prepare(
            "UPDATE todo_tasks SET quadrant_rank = ?, status_rank = ? WHERE id = ?;",
            operation: "prepare rank update"
        )
        defer { sqlite3_finalize(statement) }

        for task in tasks {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_double(statement, 1, task.quadrantRank)
            sqlite3_bind_double(statement, 2, task.statusRank)
            bindText(task.id.uuidString, to: statement, index: 3)
            try finish(statement, operation: "update task ranks")
        }
    }

    private func openAndPrepare() throws {
        try queue.sync {
            try openAndPrepareUnlocked()
        }
    }

    private func openAndPrepareUnlocked() throws {
        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(databaseURL.path, &connection, flags, nil)
        guard result == SQLITE_OK, let connection else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
            if connection != nil {
                sqlite3_close(connection)
            }
            throw TodoDatabaseError.open(path: databaseURL.path, message: message)
        }
        database = connection

        do {
            try execute("PRAGMA journal_mode=WAL;", operation: "enable WAL")
            try execute("PRAGMA synchronous=NORMAL;", operation: "set synchronous mode")
            try execute("PRAGMA foreign_keys=ON;", operation: "enable foreign keys")
            try execute(
                """
                CREATE TABLE IF NOT EXISTS todo_tasks (
                    id TEXT PRIMARY KEY NOT NULL,
                    title TEXT NOT NULL,
                    notes TEXT NOT NULL DEFAULT '',
                    status TEXT NOT NULL,
                    quadrant TEXT NOT NULL,
                    due_at REAL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    completed_at REAL,
                    archived_at REAL,
                    quadrant_rank REAL NOT NULL,
                    status_rank REAL NOT NULL
                );
                """,
                operation: "create todo table"
            )
            try execute(
                "CREATE INDEX IF NOT EXISTS idx_todo_status ON todo_tasks(archived_at, status, status_rank);",
                operation: "create status index"
            )
            try execute(
                "CREATE INDEX IF NOT EXISTS idx_todo_quadrant ON todo_tasks(archived_at, quadrant, quadrant_rank);",
                operation: "create quadrant index"
            )
            try execute(
                "CREATE INDEX IF NOT EXISTS idx_todo_due_at ON todo_tasks(due_at);",
                operation: "create due date index"
            )
            try execute("PRAGMA user_version = \(Self.schemaVersion);", operation: "set schema version")
        } catch {
            closeUnlocked()
            throw error
        }
    }

    private func closeUnlocked() {
        guard let database else { return }
        sqlite3_exec(database, "PRAGMA wal_checkpoint(FULL);", nil, nil, nil)
        sqlite3_close(database)
        self.database = nil
    }

    private func prepare(_ sql: String, operation: String) throws -> OpaquePointer {
        guard let database else {
            throw TodoDatabaseError.sqlite(operation: operation, message: "Database is closed")
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw sqliteError(operation: operation)
        }
        return statement
    }

    private func execute(_ sql: String, operation: String) throws {
        guard let database else {
            throw TodoDatabaseError.sqlite(operation: operation, message: "Database is closed")
        }
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw TodoDatabaseError.sqlite(operation: operation, message: message)
        }
    }

    private func finish(_ statement: OpaquePointer, operation: String) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw sqliteError(operation: operation)
        }
    }

    private func bind(_ task: TodoTask, to statement: OpaquePointer) {
        bindText(task.id.uuidString, to: statement, index: 1)
        bindText(task.title, to: statement, index: 2)
        bindText(task.notes, to: statement, index: 3)
        bindText(task.status.rawValue, to: statement, index: 4)
        bindText(task.quadrant.rawValue, to: statement, index: 5)
        bindDate(task.dueAt, to: statement, index: 6)
        sqlite3_bind_double(statement, 7, task.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 8, task.updatedAt.timeIntervalSince1970)
        bindDate(task.completedAt, to: statement, index: 9)
        bindDate(task.archivedAt, to: statement, index: 10)
        sqlite3_bind_double(statement, 11, task.quadrantRank)
        sqlite3_bind_double(statement, 12, task.statusRank)
    }

    private func bindText(_ value: String, to statement: OpaquePointer, index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, Self.transient)
    }

    private func bindDate(_ value: Date?, to statement: OpaquePointer, index: Int32) {
        if let value {
            sqlite3_bind_double(statement, index, value.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func decodeTask(from statement: OpaquePointer) throws -> TodoTask {
        guard let idText = text(at: 0, from: statement), let id = UUID(uuidString: idText) else {
            throw TodoDatabaseError.invalidRow(column: "id")
        }
        guard let title = text(at: 1, from: statement) else {
            throw TodoDatabaseError.invalidRow(column: "title")
        }
        guard let notes = text(at: 2, from: statement) else {
            throw TodoDatabaseError.invalidRow(column: "notes")
        }
        guard let statusText = text(at: 3, from: statement), let status = TodoStatus(rawValue: statusText) else {
            throw TodoDatabaseError.invalidRow(column: "status")
        }
        guard let quadrantText = text(at: 4, from: statement),
              let quadrant = TodoQuadrant(rawValue: quadrantText) else {
            throw TodoDatabaseError.invalidRow(column: "quadrant")
        }

        return TodoTask(
            id: id,
            title: title,
            notes: notes,
            status: status,
            quadrant: quadrant,
            dueAt: date(at: 5, from: statement),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 7)),
            completedAt: date(at: 8, from: statement),
            archivedAt: date(at: 9, from: statement),
            quadrantRank: sqlite3_column_double(statement, 10),
            statusRank: sqlite3_column_double(statement, 11)
        )
    }

    private func text(at index: Int32, from statement: OpaquePointer) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let bytes = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: bytes)
    }

    private func date(at index: Int32, from statement: OpaquePointer) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }

    private func sqliteError(operation: String) -> TodoDatabaseError {
        let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Database is closed"
        return .sqlite(operation: operation, message: message)
    }
}
