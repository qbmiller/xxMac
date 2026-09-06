import Foundation
import TodoWidgetShared
import XCTest
@testable import xxMac

final class TodoWidgetSnapshotBuilderTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 10))!
    }

    func testTodayTakesPriorityWithoutDuplicatingInProgressTask() {
        let dueToday = makeTask(
            title: "Due today",
            status: .inProgress,
            dueAt: calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 12))!,
            statusRank: 2_000
        )
        let ordinaryInProgress = makeTask(
            title: "In progress",
            status: .inProgress,
            dueAt: nil,
            statusRank: 1_000
        )

        let snapshot = TodoWidgetSnapshotBuilder.makeSnapshot(
            tasks: [ordinaryInProgress, dueToday],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.items.map(\.id), [dueToday.id, ordinaryInProgress.id])
        XCTAssertEqual(snapshot.items.map(\.category), [.today, .inProgress])
    }

    func testOrdersTodayThenInProgressThenTodoUsingGroupRules() {
        let overdue = makeTask(
            title: "Overdue",
            status: .todo,
            dueAt: calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 9))!,
            statusRank: 9_000
        )
        let today = makeTask(
            title: "Today",
            status: .todo,
            dueAt: calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 16))!,
            statusRank: 8_000
        )
        let inProgressFirst = makeTask(title: "Doing first", status: .inProgress, statusRank: 1_000)
        let inProgressSecond = makeTask(title: "Doing second", status: .inProgress, statusRank: 2_000)
        let todoFirst = makeTask(title: "Todo first", status: .todo, statusRank: 1_000)
        let todoSecond = makeTask(title: "Todo second", status: .todo, statusRank: 2_000)

        let snapshot = TodoWidgetSnapshotBuilder.makeSnapshot(
            tasks: [todoSecond, inProgressSecond, today, todoFirst, overdue, inProgressFirst],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(
            snapshot.items.map(\.id),
            [overdue.id, today.id, inProgressFirst.id, inProgressSecond.id, todoFirst.id, todoSecond.id]
        )
        XCTAssertEqual(
            snapshot.items.map(\.category),
            [.today, .today, .inProgress, .inProgress, .todo, .todo]
        )
    }

    func testExcludesCompletedAndArchivedFromItemsAndTotal() {
        let visible = makeTask(title: "Visible", status: .todo, statusRank: 1_000)
        let completed = makeTask(title: "Completed", status: .completed, statusRank: 2_000)
        var archived = makeTask(title: "Archived", status: .todo, statusRank: 3_000)
        archived.archivedAt = now

        let snapshot = TodoWidgetSnapshotBuilder.makeSnapshot(
            tasks: [completed, archived, visible],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.items.map(\.id), [visible.id])
        XCTAssertEqual(snapshot.totalIncompleteCount, 1)
    }

    func testLimitsItemsToTenButKeepsFullIncompleteCount() {
        let tasks = (0..<12).map { index in
            makeTask(title: "Task \(index)", status: .todo, statusRank: Double(index))
        }

        let snapshot = TodoWidgetSnapshotBuilder.makeSnapshot(
            tasks: tasks,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.items.count, 10)
        XCTAssertEqual(snapshot.totalIncompleteCount, 12)
        XCTAssertEqual(snapshot.items.map(\.title), (0..<10).map { "Task \($0)" })
    }

    func testSchedulesNextRefreshAtFollowingLocalMidnight() {
        let snapshot = TodoWidgetSnapshotBuilder.makeSnapshot(
            tasks: [],
            now: now,
            calendar: calendar
        )
        let expected = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7))!

        XCTAssertEqual(snapshot.nextRefreshAt, expected)
    }

    private func makeTask(
        title: String,
        status: TodoStatus,
        dueAt: Date? = nil,
        statusRank: Double,
        updatedOffset: TimeInterval = 0
    ) -> TodoTask {
        let updatedAt = now.addingTimeInterval(updatedOffset)
        var task = TodoTask.makeNew(
            title: title,
            now: updatedAt,
            statusRank: statusRank
        )
        task.status = status
        task.dueAt = dueAt
        task.updatedAt = updatedAt
        return task
    }
}
