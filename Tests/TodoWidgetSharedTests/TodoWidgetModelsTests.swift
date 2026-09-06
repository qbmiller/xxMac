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
        XCTAssertEqual(TodoWidgetEnvironment.widgetKind, "com.xiaomi318.xxMac.TodoWidget")
    }

    func testPaginationShowsTenItemsPerPageAndClampsInvalidPage() {
        let items = (0..<23).map { index in
            TodoWidgetItem(
                id: UUID(),
                title: "Task \(index)",
                category: .todo,
                dueAt: nil
            )
        }

        XCTAssertEqual(TodoWidgetPagination.pageCount(itemCount: items.count), 3)
        XCTAssertEqual(TodoWidgetPagination.clampedPageIndex(8, itemCount: items.count), 2)
        XCTAssertEqual(
            TodoWidgetPagination.items(items, pageIndex: 1).map(\.title),
            (10..<20).map { "Task \($0)" }
        )
        XCTAssertEqual(
            TodoWidgetPagination.items(items, pageIndex: 8).map(\.title),
            (20..<23).map { "Task \($0)" }
        )
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

    func testWidgetLayoutClampsFontSizeAndReducesPageCapacity() {
        XCTAssertEqual(TodoWidgetLayout.clampedFontSize(2), 9)
        XCTAssertEqual(TodoWidgetLayout.clampedFontSize(80), 13)
        XCTAssertEqual(TodoWidgetLayout.pageSize(fontSize: 9), 10)
        XCTAssertEqual(TodoWidgetLayout.pageSize(fontSize: 11), 8)
        XCTAssertEqual(TodoWidgetLayout.pageSize(fontSize: 13), 7)
    }

    func testPresentationStateDecodesMissingFontSizeUsingDefault() throws {
        let state = try JSONDecoder().decode(
            TodoWidgetPresentationState.self,
            from: Data(#"{"pageIndex":2}"#.utf8)
        )

        XCTAssertEqual(state.pageIndex, 2)
        XCTAssertEqual(state.fontSize, TodoWidgetLayout.defaultFontSize)
    }
}
