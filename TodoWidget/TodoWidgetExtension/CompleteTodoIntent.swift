import AppIntents
import Foundation
import WidgetKit

struct CompleteTodoIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Todo"
    static var description = IntentDescription("Mark a Todo task as completed.")
    static var openAppWhenRun = false

    @Parameter(title: "Task ID")
    var taskID: String

    init() {
        taskID = ""
    }

    init(taskID: String) {
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID) else {
            throw CompleteTodoIntentError.invalidTaskID
        }
        let store = TodoWidgetFileStore.shared()

        _ = try store.appendCompletion(taskID: id, now: Date())
        try? store.removeItemFromSnapshot(taskID: id)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(TodoWidgetEnvironment.actionsChangedNotification as CFString),
            nil,
            nil,
            true
        )
        WidgetCenter.shared.reloadTimelines(ofKind: TodoWidgetEnvironment.widgetKind)
        return .result()
    }
}


struct ChangeTodoPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Change Todo Page"
    static var description = IntentDescription("Show another page of Todo tasks.")
    static var openAppWhenRun = false

    @Parameter(title: "Page Delta")
    var delta: Int

    @Parameter(title: "Large Widget")
    var isLarge: Bool

    init() {
        delta = 0
        isLarge = false
    }

    init(delta: Int, isLarge: Bool) {
        self.delta = delta
        self.isLarge = isLarge
    }

    func perform() async throws -> some IntentResult {
        let store = TodoWidgetFileStore.shared()
        _ = try store.movePage(by: delta, isLarge: isLarge)
        WidgetCenter.shared.reloadTimelines(ofKind: TodoWidgetEnvironment.widgetKind)
        return .result()
    }
}

enum CompleteTodoIntentError: Error {
    case invalidTaskID
    case sharedContainerUnavailable
}
