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
        guard let store = TodoWidgetFileStore.appGroup() else {
            throw CompleteTodoIntentError.sharedContainerUnavailable
        }

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

enum CompleteTodoIntentError: Error {
    case invalidTaskID
    case sharedContainerUnavailable
}
