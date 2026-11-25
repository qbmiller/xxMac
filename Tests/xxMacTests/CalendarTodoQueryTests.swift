import XCTest
@testable import xxMac

final class CalendarTodoQueryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func date(_ day: Int, hour: Int = 12, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func task(_ title: String, due: Date?, done: Bool = false) -> TodoTask {
        var task = TodoTask.makeNew(title: title, now: date(25))
        task.dueAt = due
        task.status = done ? .completed : .todo
        return task
    }

    func testSelectedLocalDayExcludesOtherDaysUndatedAndArchivedTasks() {
        let midnight = task("midnight", due: date(25, hour: 0))
        let late = task("late", due: date(25, hour: 23))
        var archived = task("archived", due: date(25))
        archived.archivedAt = date(25)
        let tasks = [late, task("undated", due: nil), task("tomorrow", due: date(26, hour: 0)),
                     archived, midnight, task("yesterday", due: date(24, hour: 23))]
        XCTAssertEqual(CalendarTodoQuery.tasks(tasks, on: date(25), calendar: calendar).map(\.id),
                       [midnight.id, late.id])
    }

    func testCompletedTasksAreOptionalAndFollowOpenTasks() {
        let done = task("done", due: date(25, hour: 8), done: true)
        let open = task("open", due: date(25, hour: 18))
        XCTAssertEqual(CalendarTodoQuery.tasks([done, open], on: date(25), calendar: calendar).map(\.id), [open.id])
        XCTAssertEqual(CalendarTodoQuery.tasks([done, open], on: date(25), includeCompleted: true,
                                              calendar: calendar).map(\.id), [open.id, done.id])
    }

    func testOnlyOpenDatedNonArchivedTasksProduceDots() {
        var archived = task("archived", due: date(27))
        archived.archivedAt = date(25)
        let tasks = [task("open", due: date(25)), task("same day", due: date(25, hour: 23)),
                     task("done", due: date(26), done: true), archived, task("undated", due: nil)]
        XCTAssertEqual(CalendarTodoQuery.daysWithOpenTasks(tasks, calendar: calendar), [calendar.startOfDay(for: date(25))])
    }

    func testTomorrowPreservesWallClockAcrossDaylightSavingAndUsesNowRatherThanOriginalDay() {
        let original = date(25, hour: 10)
        let now = date(31, hour: 22, month: 10)
        let result = CalendarTodoQuery.deferredDeadline(original, now: now, calendar: calendar)!
        let components = calendar.dateComponents([.month, .day, .hour], from: result)
        XCTAssertEqual(components.month, 11)
        XCTAssertEqual(components.day, 1)
        XCTAssertEqual(components.hour, 10)
        XCTAssertNil(CalendarTodoQuery.deferredDeadline(nil, now: now, calendar: calendar))
    }

    func testAddingAcrossSpringDSTUsesLocalDayAndValidTime() {
        let original = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 2, minute: 30))!
        let result = CalendarTodoQuery.deferredDeadline(original, now: original, calendar: calendar)!
        XCTAssertEqual(calendar.component(.day, from: result), 8)
        XCTAssertEqual(calendar.component(.hour, from: result), 3)
    }
}
