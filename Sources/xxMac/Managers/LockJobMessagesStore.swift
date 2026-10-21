import Foundation

@MainActor
final class LockJobMessagesStore {
    static let sourceURL = URL(string: "https://cf.xiaomi318.com/xxmac/lockjob.json")!
    private static let refreshInterval: TimeInterval = 24 * 60 * 60

    private let configDirectory: ConfigDirectoryManager
    private let session: URLSession
    private(set) var messages: [String] = []
    private var lastRefresh: Date?
    private var refreshTask: Task<Bool, Never>?

    init(configDirectory: ConfigDirectoryManager = .shared, session: URLSession = .shared) {
        self.configDirectory = configDirectory
        self.session = session
        loadCache()
    }

    func loadCache() {
        let url = configDirectory.lockJobMessagesURL
        guard let data = try? Data(contentsOf: url),
              let decoded = try? Self.decodeMessages(data) else {
            messages = []
            lastRefresh = nil
            return
        }
        messages = decoded
        lastRefresh = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    func randomMessage() -> String? {
        messages.randomElement()
    }

    func refreshIfNeeded(now: Date = Date()) async {
        _ = await refresh(now: now)
    }

    func refresh(force: Bool = false, now: Date = Date()) async -> Bool {
        if let refreshTask {
            return await refreshTask.value
        }
        guard force || (lastRefresh.map({ now.timeIntervalSince($0) >= Self.refreshInterval }) ?? true) else {
            return true
        }
        let task = Task { await fetch(now: now) }
        refreshTask = task
        let succeeded = await task.value
        refreshTask = nil
        return succeeded
    }

    private func fetch(now: Date) async -> Bool {
        do {
            var request = URLRequest(url: Self.sourceURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 12
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode), data.count <= 100_000 else {
                throw URLError(.badServerResponse)
            }
            let decoded = try Self.decodeMessages(data)
            try data.write(to: configDirectory.lockJobMessagesURL, options: .atomic)
            messages = decoded
            lastRefresh = now
            return true
        } catch {
            // Keep the last valid cache and retry on a later launch or lock.
            return false
        }
    }

    private static func decodeMessages(_ data: Data) throws -> [String] {
        let messages = try JSONDecoder().decode([String].self, from: data)
        guard !messages.isEmpty,
              messages.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 200 }) else {
            throw URLError(.cannotParseResponse)
        }
        return messages
    }
}
