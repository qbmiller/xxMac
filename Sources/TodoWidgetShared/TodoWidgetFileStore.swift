import Darwin
import Foundation

public protocol TodoWidgetFileStoring: AnyObject {
    func readSnapshot() throws -> TodoWidgetSnapshot?
    func writeSnapshot(_ snapshot: TodoWidgetSnapshot) throws
    func readActions() throws -> [TodoWidgetAction]
    func appendCompletion(taskID: UUID, now: Date) throws -> TodoWidgetAction
    func removeAction(id: UUID) throws
    func removeItemFromSnapshot(taskID: UUID) throws
}

public enum TodoWidgetFileStoreError: LocalizedError {
    case invalidFileURL(URL)
    case openLock(path: String, code: Int32)
    case lock(path: String, code: Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidFileURL(let url):
            return "Invalid widget shared file URL: \(url.path)"
        case .openLock(let path, let code):
            return "Unable to open widget lock at \(path): errno \(code)"
        case .lock(let path, let code):
            return "Unable to lock widget files at \(path): errno \(code)"
        }
    }
}

public final class TodoWidgetFileStore: TodoWidgetFileStoring, @unchecked Sendable {
    private let directoryURL: URL
    private let fileManager: FileManager
    private let snapshotURL: URL
    private let actionsURL: URL
    private let lockURL: URL

    public init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        snapshotURL = directoryURL.appendingPathComponent("todo-widget-snapshot.json")
        actionsURL = directoryURL.appendingPathComponent("todo-widget-actions.json")
        lockURL = directoryURL.appendingPathComponent("todo-widget.lock")
    }

    public static func appGroup(fileManager: FileManager = .default) -> TodoWidgetFileStore? {
        guard let directoryURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: TodoWidgetEnvironment.appGroupIdentifier
        ) else {
            return nil
        }
        return TodoWidgetFileStore(directoryURL: directoryURL, fileManager: fileManager)
    }

    public func readSnapshot() throws -> TodoWidgetSnapshot? {
        try withLock { try read(TodoWidgetSnapshot.self, from: snapshotURL) }
    }

    public func writeSnapshot(_ snapshot: TodoWidgetSnapshot) throws {
        try withLock { try write(snapshot, to: snapshotURL) }
    }

    public func readActions() throws -> [TodoWidgetAction] {
        try withLock { try read([TodoWidgetAction].self, from: actionsURL) ?? [] }
    }

    public func appendCompletion(taskID: UUID, now: Date) throws -> TodoWidgetAction {
        try withLock {
            var actions = try read([TodoWidgetAction].self, from: actionsURL) ?? []
            let action = TodoWidgetAction(id: UUID(), taskID: taskID, kind: .complete, createdAt: now)
            actions.append(action)
            try write(actions, to: actionsURL)
            return action
        }
    }

    public func removeAction(id: UUID) throws {
        try withLock {
            var actions = try read([TodoWidgetAction].self, from: actionsURL) ?? []
            actions.removeAll { $0.id == id }
            try write(actions, to: actionsURL)
        }
    }

    public func removeItemFromSnapshot(taskID: UUID) throws {
        try withLock {
            guard let snapshot = try read(TodoWidgetSnapshot.self, from: snapshotURL) else { return }
            let updated = snapshot.removingItem(id: taskID)
            guard updated != snapshot else { return }
            try write(updated, to: snapshotURL)
        }
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        guard let lockPath = lockURL.withUnsafeFileSystemRepresentation({ $0.map(String.init(cString:)) }) else {
            throw TodoWidgetFileStoreError.invalidFileURL(lockURL)
        }

        let descriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw TodoWidgetFileStoreError.openLock(path: lockPath, code: errno)
        }
        defer { close(descriptor) }

        guard flock(descriptor, LOCK_EX) == 0 else {
            throw TodoWidgetFileStoreError.lock(path: lockPath, code: errno)
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }

    private func read<Value: Decodable>(_ type: Value.Type, from url: URL) throws -> Value? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: Data(contentsOf: url))
    }

    private func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
