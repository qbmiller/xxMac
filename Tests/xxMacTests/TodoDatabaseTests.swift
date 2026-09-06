import Foundation
import SQLite3
import XCTest
@testable import xxMac

final class TodoDatabaseTests: XCTestCase {
    private var rootURL: URL!
    private var databaseURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoDatabaseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        databaseURL = rootURL.appendingPathComponent("todo.db")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL)
        rootURL = nil
        databaseURL = nil
        try super.tearDownWithError()
    }

    func testOpeningDatabaseCreatesSchemaVersionTwo() throws {
        let database = try TodoDatabase(url: databaseURL)
        defer { database.checkpointAndClose() }

        XCTAssertEqual(try userVersion(at: databaseURL), 2)
    }

    func testOpeningVersionOneDatabaseMigratesExistingTasks() throws {
        try createVersionOneDatabase()

        let database = try TodoDatabase(url: databaseURL)
        defer { database.checkpointAndClose() }

        let task = try XCTUnwrap(database.fetchTasks(includeArchived: true).first)
        XCTAssertEqual(task.title, "Legacy task")
        XCTAssertEqual(task.status, .completed)
        XCTAssertNil(task.statusBeforeCompletion)
        XCTAssertEqual(try userVersion(at: databaseURL), 2)
    }

    func testInsertAndFetchRoundTripsEveryTaskField() throws {
        let database = try TodoDatabase(url: databaseURL)
        defer { database.checkpointAndClose() }
        let task = makeTask(
            title: "Ship todo",
            notes: "Verify SQLite bindings",
            status: .completed,
            quadrant: .importantUrgent,
            dueAt: date(2026, 9, 6, 14, 35),
            completedAt: date(2026, 9, 5, 16, 0),
            statusBeforeCompletion: .todo,
            archivedAt: date(2026, 9, 5, 17, 0),
            quadrantRank: 2_048,
            statusRank: 3_072
        )

        try database.insert(task)

        XCTAssertEqual(try database.fetchTasks(includeArchived: true), [task])
    }

    func testInsertAndFetchPreservesNullableValues() throws {
        let database = try TodoDatabase(url: databaseURL)
        defer { database.checkpointAndClose() }
        let task = makeTask(title: "No optional values")

        try database.insert(task)

        let fetched = try XCTUnwrap(database.fetchTasks(includeArchived: false).first)
        XCTAssertEqual(fetched, task)
        XCTAssertNil(fetched.dueAt)
        XCTAssertNil(fetched.completedAt)
        XCTAssertNil(fetched.archivedAt)
    }

    func testUpdateReplacesPersistedTaskValues() throws {
        let database = try TodoDatabase(url: databaseURL)
        defer { database.checkpointAndClose() }
        var task = makeTask(title: "Before")
        try database.insert(task)

        task.title = "After"
        task.notes = "Edited"
        task.status = .inProgress
        task.quadrant = .notImportantUrgent
        task.dueAt = date(2026, 9, 7, 9, 5)
        task.updatedAt = date(2026, 9, 5, 18, 0)
        task.quadrantRank = 4_096
        task.statusRank = 5_120
        try database.update(task)

        XCTAssertEqual(try database.fetchTasks(includeArchived: false), [task])
    }

    func testUpdateRanksPersistsAllTasksInBatch() throws {
        let database = try TodoDatabase(url: databaseURL)
        defer { database.checkpointAndClose() }
        var first = makeTask(title: "First", quadrantRank: 1_024, statusRank: 1_024)
        var second = makeTask(title: "Second", quadrantRank: 2_048, statusRank: 2_048)
        try database.insert(first)
        try database.insert(second)

        first.quadrantRank = 9_000
        first.statusRank = 8_000
        second.quadrantRank = 7_000
        second.statusRank = 6_000
        try database.updateRanks([first, second])

        let fetched = try database.fetchTasks(includeArchived: true)
        let byID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        XCTAssertEqual(byID[first.id]?.quadrantRank, 9_000)
        XCTAssertEqual(byID[first.id]?.statusRank, 8_000)
        XCTAssertEqual(byID[second.id]?.quadrantRank, 7_000)
        XCTAssertEqual(byID[second.id]?.statusRank, 6_000)
    }

    func testFetchExcludesArchivedTasksByDefaultQuery() throws {
        let database = try TodoDatabase(url: databaseURL)
        defer { database.checkpointAndClose() }
        let active = makeTask(title: "Active")
        let archived = makeTask(title: "Archived", archivedAt: date(2026, 9, 5, 17, 0))
        try database.insert(active)
        try database.insert(archived)

        XCTAssertEqual(try database.fetchTasks(includeArchived: false).map(\.id), [active.id])
        XCTAssertEqual(Set(try database.fetchTasks(includeArchived: true).map(\.id)), Set([active.id, archived.id]))
    }

    func testDeletePermanentlyRemovesTask() throws {
        let database = try TodoDatabase(url: databaseURL)
        defer { database.checkpointAndClose() }
        let task = makeTask(title: "Delete me")
        try database.insert(task)

        try database.delete(id: task.id)

        XCTAssertTrue(try database.fetchTasks(includeArchived: true).isEmpty)
    }

    func testReopenSwitchesDatabaseFiles() throws {
        let database = try TodoDatabase(url: databaseURL)
        let first = makeTask(title: "First database")
        try database.insert(first)
        let otherURL = rootURL.appendingPathComponent("other.db")

        try database.reopen(at: otherURL)
        let second = makeTask(title: "Second database")
        try database.insert(second)
        XCTAssertEqual(try database.fetchTasks(includeArchived: true).map(\.id), [second.id])

        try database.reopen(at: databaseURL)
        XCTAssertEqual(try database.fetchTasks(includeArchived: true).map(\.id), [first.id])
        database.checkpointAndClose()
    }

    private func makeTask(
        title: String,
        notes: String = "",
        status: TodoStatus = .todo,
        quadrant: TodoQuadrant = .notImportantNotUrgent,
        dueAt: Date? = nil,
        completedAt: Date? = nil,
        statusBeforeCompletion: TodoStatus? = nil,
        archivedAt: Date? = nil,
        quadrantRank: Double = 1_024,
        statusRank: Double = 1_024
    ) -> TodoTask {
        let createdAt = date(2026, 9, 5, 10, 0)
        return TodoTask(
            id: UUID(), title: title, notes: notes, status: status, quadrant: quadrant,
            dueAt: dueAt, createdAt: createdAt, updatedAt: createdAt,
            completedAt: completedAt, statusBeforeCompletion: statusBeforeCompletion, archivedAt: archivedAt,
            quadrantRank: quadrantRank, statusRank: statusRank
        )
    }

    private func createVersionOneDatabase() throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
            nil
        ) == SQLITE_OK, let database else {
            throw NSError(domain: "TodoDatabaseTests", code: 10)
        }
        defer { sqlite3_close(database) }

        let taskID = UUID().uuidString
        let createdAt = date(2026, 9, 5, 10, 0).timeIntervalSince1970
        let sql = """
        CREATE TABLE todo_tasks (
            id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL, quadrant TEXT NOT NULL, due_at REAL, created_at REAL NOT NULL,
            updated_at REAL NOT NULL, completed_at REAL, archived_at REAL,
            quadrant_rank REAL NOT NULL, status_rank REAL NOT NULL
        );
        INSERT INTO todo_tasks VALUES ('\(taskID)', 'Legacy task', '', 'completed',
            'notImportantNotUrgent', NULL, \(createdAt), \(createdAt), \(createdAt), NULL, 1024, 1024);
        PRAGMA user_version = 1;
        """
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "TodoDatabaseTests", code: 11)
        }
    }

    private func userVersion(at url: URL) throws -> Int32 {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw NSError(domain: "TodoDatabaseTests", code: 1)
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK else {
            throw NSError(domain: "TodoDatabaseTests", code: 2)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw NSError(domain: "TodoDatabaseTests", code: 3)
        }
        return sqlite3_column_int(statement, 0)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }
}
