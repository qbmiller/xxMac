import Foundation
import XCTest
@testable import xxMac

final class TodoNotificationPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testCreatingActiveTaskWithFutureDeadlineSchedulesNotification() {
        let task = makeTask(dueAt: now.addingTimeInterval(3_600))

        XCTAssertEqual(
            TodoNotificationPolicy.decision(old: nil, new: task, now: now),
            .schedule(task)
        )
    }

    func testTaskWithoutFutureDeadlineDoesNothing() {
        XCTAssertEqual(
            TodoNotificationPolicy.decision(old: nil, new: makeTask(dueAt: nil), now: now),
            .none
        )
        XCTAssertEqual(
            TodoNotificationPolicy.decision(old: nil, new: makeTask(dueAt: now.addingTimeInterval(-1)), now: now),
            .none
        )
    }

    func testEditingTitleOrDeadlineReschedulesFutureNotification() {
        let old = makeTask(title: "Before", dueAt: now.addingTimeInterval(3_600))
        var renamed = old
        renamed.title = "After"
        var delayed = old
        delayed.dueAt = now.addingTimeInterval(7_200)

        XCTAssertEqual(TodoNotificationPolicy.decision(old: old, new: renamed, now: now), .schedule(renamed))
        XCTAssertEqual(TodoNotificationPolicy.decision(old: old, new: delayed, now: now), .schedule(delayed))
    }

    func testUnrelatedEditKeepsExistingNotification() {
        let old = makeTask(dueAt: now.addingTimeInterval(3_600))
        var edited = old
        edited.notes = "New notes"
        edited.quadrant = .importantUrgent

        XCTAssertEqual(TodoNotificationPolicy.decision(old: old, new: edited, now: now), .none)
    }

    func testCompletingArchivingOrClearingDeadlineCancelsNotification() {
        let old = makeTask(dueAt: now.addingTimeInterval(3_600))
        var completed = old
        completed.status = .completed
        var archived = old
        archived.archivedAt = now
        var cleared = old
        cleared.dueAt = nil

        XCTAssertEqual(TodoNotificationPolicy.decision(old: old, new: completed, now: now), .cancel(old.id))
        XCTAssertEqual(TodoNotificationPolicy.decision(old: old, new: archived, now: now), .cancel(old.id))
        XCTAssertEqual(TodoNotificationPolicy.decision(old: old, new: cleared, now: now), .cancel(old.id))
    }

    func testDeletingTaskCancelsItsNotification() {
        let old = makeTask(dueAt: now.addingTimeInterval(3_600))

        XCTAssertEqual(TodoNotificationPolicy.decision(old: old, new: nil, now: now), .cancel(old.id))
    }

    func testRestoringOrReopeningFutureTaskSchedulesNotification() {
        var archived = makeTask(dueAt: now.addingTimeInterval(3_600))
        archived.archivedAt = now
        var restored = archived
        restored.archivedAt = nil
        var completed = restored
        completed.status = .completed
        var reopened = completed
        reopened.status = .inProgress

        XCTAssertEqual(TodoNotificationPolicy.decision(old: archived, new: restored, now: now), .schedule(restored))
        XCTAssertEqual(TodoNotificationPolicy.decision(old: completed, new: reopened, now: now), .schedule(reopened))
    }

    private func makeTask(
        title: String = "Task",
        dueAt: Date?
    ) -> TodoTask {
        var task = TodoTask.makeNew(title: title, now: now)
        task.dueAt = dueAt
        return task
    }
}
