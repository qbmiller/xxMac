import XCTest
@testable import xxMac

final class TodoModelsTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testNewTaskUsesTodoAndFourthQuadrantDefaults() {
        let now = date(2026, 9, 5, 10, 30)
        let task = TodoTask.makeNew(title: "  Write release notes  ", now: now)

        XCTAssertEqual(task.title, "Write release notes")
        XCTAssertEqual(task.status, .todo)
        XCTAssertEqual(task.quadrant, .notImportantNotUrgent)
        XCTAssertNil(task.dueAt)
        XCTAssertNil(task.completedAt)
        XCTAssertNil(task.archivedAt)
        XCTAssertEqual(task.createdAt, now)
        XCTAssertEqual(task.updatedAt, now)
    }

    func testStatusRollbackUsesFixedWorkflowOrder() {
        XCTAssertNil(TodoStatus.todo.previous)
        XCTAssertEqual(TodoStatus.inProgress.previous, .todo)
        XCTAssertEqual(TodoStatus.completed.previous, .inProgress)
    }

    func testTransitionIntoAndOutOfCompletedUpdatesCompletionDate() {
        let created = date(2026, 9, 5, 9, 0)
        let completed = date(2026, 9, 5, 11, 0)
        let reopened = date(2026, 9, 5, 12, 0)
        let task = TodoTask.makeNew(title: "Task", now: created)

        let done = task.transitioned(to: .completed, at: completed)
        let active = done.transitioned(to: .inProgress, at: reopened)

        XCTAssertEqual(done.status, .completed)
        XCTAssertEqual(done.completedAt, completed)
        XCTAssertEqual(done.updatedAt, completed)
        XCTAssertEqual(active.status, .inProgress)
        XCTAssertNil(active.completedAt)
        XCTAssertEqual(active.updatedAt, reopened)
    }

    func testSearchMatchesTitleAndNotesCaseInsensitively() {
        let now = date(2026, 9, 5, 9, 0)
        let titleMatch = TodoTask.makeNew(title: "Release Notes", now: now)
        let notesMatch = TodoTask.makeNew(title: "Build", notes: "Upload DMG to GitHub", now: now)
        let miss = TodoTask.makeNew(title: "Lunch", notes: "Noodles", now: now)

        XCTAssertEqual(TodoTaskQuery.search([titleMatch, notesMatch, miss], text: "gitHUB").map(\.id), [notesMatch.id])
        XCTAssertEqual(TodoTaskQuery.search([titleMatch, notesMatch, miss], text: "release").map(\.id), [titleMatch.id])
        XCTAssertEqual(TodoTaskQuery.search([titleMatch, notesMatch, miss], text: "  ").count, 3)
    }

    func testActiveTasksExcludeArchivedItems() {
        let now = date(2026, 9, 5, 9, 0)
        let active = TodoTask.makeNew(title: "Active", now: now)
        var archived = TodoTask.makeNew(title: "Archived", now: now)
        archived.archivedAt = now

        XCTAssertEqual(TodoTaskQuery.active([active, archived]).map(\.id), [active.id])
        XCTAssertEqual(TodoTaskQuery.archived([active, archived]).map(\.id), [archived.id])
    }

    func testTodayGroupsOverdueOpenTodayOpenAndTodayCompleted() {
        let now = date(2026, 9, 5, 12, 0)
        let overdue = task("Overdue", due: date(2026, 9, 4, 18, 0), now: now)
        let todayOpen = task("Today open", due: date(2026, 9, 5, 15, 0), now: now)
        let todayDone = task("Today done", due: date(2026, 9, 5, 10, 0), status: .completed, now: now)
        let oldDone = task("Old done", due: date(2026, 9, 4, 10, 0), status: .completed, now: now)
        let future = task("Future", due: date(2026, 9, 6, 10, 0), now: now)
        let noDue = TodoTask.makeNew(title: "No due", now: now)

        let groups = TodoTaskQuery.todayGroups(
            [future, todayDone, noDue, oldDone, todayOpen, overdue],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(groups.map(\.section), [.overdue, .todayOpen, .todayCompleted])
        XCTAssertEqual(groups[0].tasks.map(\.id), [overdue.id])
        XCTAssertEqual(groups[1].tasks.map(\.id), [todayOpen.id])
        XCTAssertEqual(groups[2].tasks.map(\.id), [todayDone.id])
    }

    func testRankPolicyCalculatesEdgesAndMiddle() {
        XCTAssertEqual(TodoRankPolicy.rank(before: nil, after: nil), 1_024)
        XCTAssertEqual(TodoRankPolicy.rank(before: nil, after: 1_024), 0)
        XCTAssertEqual(TodoRankPolicy.rank(before: 1_024, after: nil), 2_048)
        XCTAssertEqual(TodoRankPolicy.rank(before: 1_024, after: 2_048), 1_536)
        XCTAssertEqual(TodoRankPolicy.normalizedRanks(count: 3), [1_024, 2_048, 3_072])
    }

    func testQuadrantAndStatusRanksCanChangeIndependently() {
        let now = date(2026, 9, 5, 12, 0)
        let task = TodoTask.makeNew(title: "Task", now: now)

        let movedQuadrant = task.moving(to: .importantUrgent, quadrantRank: 9_999, at: now)
        let movedStatus = movedQuadrant.moving(to: .inProgress, statusRank: 7_777, at: now)

        XCTAssertEqual(movedQuadrant.quadrantRank, 9_999)
        XCTAssertEqual(movedQuadrant.statusRank, task.statusRank)
        XCTAssertEqual(movedStatus.quadrantRank, 9_999)
        XCTAssertEqual(movedStatus.statusRank, 7_777)
        XCTAssertEqual(movedStatus.status, .inProgress)
    }

    func testTaskDraftUsesNewTaskDefaultsAndValidatesTrimmedTitle() {
        var draft = TodoTaskDraft()

        XCTAssertEqual(draft.status, .todo)
        XCTAssertEqual(draft.quadrant, .notImportantNotUrgent)
        XCTAssertNil(draft.dueAt)
        XCTAssertFalse(draft.canSave)

        draft.title = "  Prepare demo  "

        XCTAssertTrue(draft.canSave)
        XCTAssertEqual(draft.normalizedTitle, "Prepare demo")
    }

    func testTaskDraftAppliesEditableFieldsAndNormalizesDeadlineToMinute() {
        let createdAt = date(2026, 9, 5, 8, 0)
        var original = TodoTask.makeNew(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            title: "Original",
            notes: "Old note",
            now: createdAt,
            quadrantRank: 4_096,
            statusRank: 8_192
        )
        original.archivedAt = date(2026, 9, 5, 9, 0)

        var deadlineComponents = DateComponents()
        deadlineComponents.calendar = calendar
        deadlineComponents.timeZone = calendar.timeZone
        deadlineComponents.year = 2026
        deadlineComponents.month = 9
        deadlineComponents.day = 6
        deadlineComponents.hour = 14
        deadlineComponents.minute = 35
        deadlineComponents.second = 42

        var draft = TodoTaskDraft(task: original)
        draft.title = "  Updated  "
        draft.notes = "New note"
        draft.status = .inProgress
        draft.quadrant = .importantUrgent
        draft.dueAt = deadlineComponents.date

        let updated = draft.applying(to: original, calendar: calendar)

        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.title, "Updated")
        XCTAssertEqual(updated.notes, "New note")
        XCTAssertEqual(updated.status, .inProgress)
        XCTAssertEqual(updated.quadrant, .importantUrgent)
        XCTAssertEqual(calendar.component(.second, from: updated.dueAt!), 0)
        XCTAssertEqual(updated.createdAt, original.createdAt)
        XCTAssertEqual(updated.updatedAt, original.updatedAt)
        XCTAssertEqual(updated.archivedAt, original.archivedAt)
        XCTAssertEqual(updated.quadrantRank, original.quadrantRank)
        XCTAssertEqual(updated.statusRank, original.statusRank)
    }

    private func task(_ title: String, due: Date, status: TodoStatus = .todo, now: Date) -> TodoTask {
        var value = TodoTask.makeNew(title: title, now: now)
        value.dueAt = due
        return value.transitioned(to: status, at: now)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }
}
