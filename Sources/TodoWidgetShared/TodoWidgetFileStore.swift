import Darwin
import Foundation

public protocol TodoWidgetFileStoring: AnyObject {
    func readSnapshot() throws -> TodoWidgetSnapshot?
    func writeSnapshot(_ snapshot: TodoWidgetSnapshot) throws
    func readActions() throws -> [TodoWidgetAction]
    func readPageIndex() throws -> Int
    func readFontSize() throws -> Int
    func setFontSize(_ fontSize: Int) throws -> Int
    func movePage(by delta: Int) throws -> Int
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
    public static let sharedDirectoryRelativePath = "Library/Application Support/xxMac/Widget"

    private let directoryURL: URL
    private let fileManager: FileManager
    private let snapshotURL: URL
    private let actionsURL: URL
    private let presentationURL: URL
    private let lockURL: URL

    public init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        snapshotURL = directoryURL.appendingPathComponent("todo-widget-snapshot.json")
        actionsURL = directoryURL.appendingPathComponent("todo-widget-actions.json")
        presentationURL = directoryURL.appendingPathComponent("todo-widget-presentation.json")
        lockURL = directoryURL.appendingPathComponent("todo-widget.lock")
    }

    public static func shared(fileManager: FileManager = .default) -> TodoWidgetFileStore {
        TodoWidgetFileStore(
            directoryURL: sharedDirectoryURL(homeDirectory: currentUserHomeDirectory()),
            fileManager: fileManager
        )
    }

    public static func sharedDirectoryURL(homeDirectory: URL) -> URL {
        homeDirectory.appendingPathComponent(sharedDirectoryRelativePath, isDirectory: true)
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

    public func readPageIndex() throws -> Int {
        try withLock {
            try readPresentationState().pageIndex
        }
    }

    public func readFontSize() throws -> Int {
        try withLock {
            try readPresentationState().fontSize
        }
    }

    public func setFontSize(_ fontSize: Int) throws -> Int {
        try withLock {
            let current = try readPresentationState()
            let normalized = TodoWidgetLayout.clampedFontSize(fontSize)
            let snapshot = try read(TodoWidgetSnapshot.self, from: snapshotURL)
            let pageIndex = TodoWidgetPagination.clampedPageIndex(
                current.pageIndex,
                itemCount: snapshot?.items.count ?? 0,
                pageSize: TodoWidgetLayout.pageSize(fontSize: normalized)
            )
            try write(
                TodoWidgetPresentationState(pageIndex: pageIndex, fontSize: normalized),
                to: presentationURL
            )
            return normalized
        }
    }

    public func movePage(by delta: Int) throws -> Int {
        try withLock {
            let snapshot = try read(TodoWidgetSnapshot.self, from: snapshotURL)
            let current = try readPresentationState()
            let target = TodoWidgetPagination.clampedPageIndex(
                current.pageIndex + delta,
                itemCount: snapshot?.items.count ?? 0,
                pageSize: TodoWidgetLayout.pageSize(fontSize: current.fontSize)
            )
            try write(
                TodoWidgetPresentationState(pageIndex: target, fontSize: current.fontSize),
                to: presentationURL
            )
            return target
        }
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

    private func readPresentationState() throws -> TodoWidgetPresentationState {
        try read(TodoWidgetPresentationState.self, from: presentationURL) ?? TodoWidgetPresentationState()
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

    private static func currentUserHomeDirectory() -> URL {
        let userID = getuid()
        let bufferSize = max(1, Int(sysconf(_SC_GETPW_R_SIZE_MAX)))
        var passwordEntry = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: bufferSize)

        let status = getpwuid_r(userID, &passwordEntry, &buffer, buffer.count, &result)
        if status == 0, result != nil, let homePath = passwordEntry.pw_dir {
            return URL(fileURLWithPath: String(cString: homePath), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
