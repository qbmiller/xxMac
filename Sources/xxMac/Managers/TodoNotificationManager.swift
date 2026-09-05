import AppKit
import Foundation
import UserNotifications

protocol TodoNotificationScheduling: AnyObject {
    func reconcile(old: TodoTask?, new: TodoTask?)
    func authorizationStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void)
    func openSystemSettings()
}

enum TodoNotificationDecision: Equatable {
    case schedule(TodoTask)
    case cancel(UUID)
    case none
}

enum TodoNotificationPolicy {
    static func decision(old: TodoTask?, new: TodoTask?, now: Date = Date()) -> TodoNotificationDecision {
        guard let new else {
            return old.map { .cancel($0.id) } ?? .none
        }

        let newCanSchedule = canSchedule(new, now: now)
        let oldCanSchedule = old.map { canSchedule($0, now: now) } ?? false

        if newCanSchedule {
            guard let old else { return .schedule(new) }
            if !oldCanSchedule || old.title != new.title || old.dueAt != new.dueAt {
                return .schedule(new)
            }
            return .none
        }

        if oldCanSchedule {
            return .cancel(new.id)
        }
        return .none
    }

    private static func canSchedule(_ task: TodoTask, now: Date) -> Bool {
        guard task.archivedAt == nil,
              task.status != .completed,
              let dueAt = task.dueAt else {
            return false
        }
        return dueAt > now
    }
}

final class TodoNotificationManager: TodoNotificationScheduling {
    static let shared = TodoNotificationManager()

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func reconcile(old: TodoTask?, new: TodoTask?) {
        switch TodoNotificationPolicy.decision(old: old, new: new) {
        case .schedule(let task):
            schedule(task)
        case .cancel(let id):
            center.removePendingNotificationRequests(withIdentifiers: [identifier(for: id)])
        case .none:
            break
        }
    }

    func authorizationStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus)
            }
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func schedule(_ task: TodoTask) {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.addRequest(for: task)
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { return }
                    self.addRequest(for: task)
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    private func addRequest(for task: TodoTask) {
        guard let dueAt = task.dueAt, dueAt > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = L10n.t("todo.notification.due")
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
            from: dueAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier(for: task.id),
            content: content,
            trigger: trigger
        )
        center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
        center.add(request)
    }

    private func identifier(for id: UUID) -> String {
        "todo.\(id.uuidString)"
    }
}
