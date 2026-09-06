import Foundation
import XCTest
@testable import TodoWidgetShared

final class TodoWidgetFileStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoWidgetFileStoreTests-")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testMissingFilesReturnEmptyState() throws {
        let store = TodoWidgetFileStore(directoryURL: temporaryDirectory)

        XCTAssertNil(try store.readSnapshot())
        XCTAssertEqual(try store.readActions(), [])
    }

    func testSharedDirectoryUsesDedicatedApplicationSupportFolder() {
        let homeDirectory = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

        XCTAssertEqual(
            TodoWidgetFileStore.sharedDirectoryURL(homeDirectory: homeDirectory).path,
            "/Users/tester/Library/Application Support/xxMac/Widget"
        )
    }

    func testSnapshotRoundTripAndOptimisticRemoval() throws {
        let firstID = UUID()
        let secondID = UUID()
        let store = TodoWidgetFileStore(directoryURL: temporaryDirectory)
        let snapshot = TodoWidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 100),
            nextRefreshAt: Date(timeIntervalSince1970: 200),
            totalIncompleteCount: 2,
            items: [
                TodoWidgetItem(id: firstID, title: "First", category: .today, dueAt: nil),
                TodoWidgetItem(id: secondID, title: "Second", category: .todo, dueAt: nil)
            ]
        )

        try store.writeSnapshot(snapshot)
        try store.removeItemFromSnapshot(taskID: firstID)

        let updated = try XCTUnwrap(store.readSnapshot())
        XCTAssertEqual(updated.items.map(\.id), [secondID])
        XCTAssertEqual(updated.totalIncompleteCount, 1)
    }

    func testPageIndexPersistsAndMovementClampsToAvailablePages() throws {
        let store = TodoWidgetFileStore(directoryURL: temporaryDirectory)
        let items = (0..<23).map { index in
            TodoWidgetItem(id: UUID(), title: "Task \(index)", category: .todo, dueAt: nil)
        }
        try store.writeSnapshot(
            TodoWidgetSnapshot(
                generatedAt: Date(timeIntervalSince1970: 100),
                nextRefreshAt: Date(timeIntervalSince1970: 200),
                totalIncompleteCount: items.count,
                items: items
            )
        )

        XCTAssertEqual(try store.readPageIndex(), 0)
        XCTAssertEqual(try store.movePage(by: 1), 1)
        XCTAssertEqual(try store.movePage(by: 10), 2)
        XCTAssertEqual(try store.movePage(by: -10), 0)
        XCTAssertEqual(try store.readPageIndex(), 0)
    }

    func testFontSizePersistsAndPageMovementPreservesIt() throws {
        let store = TodoWidgetFileStore(directoryURL: temporaryDirectory)
        let items = (0..<18).map { index in
            TodoWidgetItem(id: UUID(), title: "Task \(index)", category: .todo, dueAt: nil)
        }
        try store.writeSnapshot(
            TodoWidgetSnapshot(
                generatedAt: Date(timeIntervalSince1970: 100),
                nextRefreshAt: Date(timeIntervalSince1970: 200),
                totalIncompleteCount: items.count,
                items: items
            )
        )

        XCTAssertEqual(try store.readFontSize(), TodoWidgetLayout.defaultFontSize)
        XCTAssertEqual(try store.setFontSize(13), 13)
        XCTAssertEqual(try store.movePage(by: 1), 1)
        XCTAssertEqual(try store.readFontSize(), 13)
        XCTAssertEqual(try store.readPageIndex(), 1)
    }

    func testAppendPreservesActionsAndCreatesUniqueOperationIDs() throws {
        let store = TodoWidgetFileStore(directoryURL: temporaryDirectory)
        let first = try store.appendCompletion(taskID: UUID(), now: Date(timeIntervalSince1970: 100))
        let second = try store.appendCompletion(taskID: UUID(), now: Date(timeIntervalSince1970: 200))

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(try store.readActions(), [first, second])

        try store.removeAction(id: first.id)
        XCTAssertEqual(try store.readActions(), [second])
    }

    func testDamagedJSONIsReportedInsteadOfSilentlyDiscarded() throws {
        let store = TodoWidgetFileStore(directoryURL: temporaryDirectory)
        let snapshotURL = temporaryDirectory.appendingPathComponent("todo-widget-snapshot.json")
        try Data("not-json".utf8).write(to: snapshotURL)

        XCTAssertThrowsError(try store.readSnapshot())
    }

    func testConcurrentAppendsDoNotLoseActions() async throws {
        let store = TodoWidgetFileStore(directoryURL: temporaryDirectory)
        let taskIDs = [UUID(), UUID()]

        try await withThrowingTaskGroup(of: Void.self) { group in
            for taskID in taskIDs {
                group.addTask {
                    _ = try store.appendCompletion(taskID: taskID, now: Date())
                }
            }
            try await group.waitForAll()
        }

        XCTAssertEqual(Set(try store.readActions().map(\.taskID)), Set(taskIDs))
    }
}
