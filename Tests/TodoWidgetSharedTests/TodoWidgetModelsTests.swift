import Foundation
import XCTest
@testable import TodoWidgetShared

final class TodoWidgetModelsTests: XCTestCase {
    func testSnapshotRoundTripsRenderFieldsAndCount() throws {
        let item = TodoWidgetItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "Ship widget",
            category: .today,
            dueAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let snapshot = TodoWidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_799_000_000),
            nextRefreshAt: Date(timeIntervalSince1970: 1_800_086_400),
            totalIncompleteCount: 12,
            items: [item]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let decoded = try decoder.decode(
            TodoWidgetSnapshot.self,
            from: encoder.encode(snapshot)
        )

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(TodoWidgetEnvironment.maximumItemCount, 10)
        XCTAssertEqual(TodoWidgetEnvironment.appGroupIdentifier, "group.com.xiaomi318.xxMac")
        XCTAssertEqual(TodoWidgetEnvironment.widgetKind, "com.xiaomi318.xxMac.TodoWidget")
    }

    func testCompletionActionRoundTripsStableIdentifiers() throws {
        let action = TodoWidgetAction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            taskID: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            kind: .complete,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )

        let decoded = try JSONDecoder().decode(
            TodoWidgetAction.self,
            from: JSONEncoder().encode(action)
        )

        XCTAssertEqual(decoded, action)
    }
}
