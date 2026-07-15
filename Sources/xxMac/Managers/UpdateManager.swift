import Combine
import Foundation

enum UpdatePreferencesKey {
    static let frequency = "UpdateCheckFrequency"
    static let lastSuccessfulCheck = "UpdateLastSuccessfulCheck"
    static let availableVersion = "UpdateAvailableVersion"
}

enum UpdateCheckFrequency: String, CaseIterable, Identifiable {
    case off
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var localizationKey: String {
        "about.update_frequency.\(rawValue)"
    }

    func nextCheckDate(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .off:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        }
    }

    func isDue(lastCheckedAt: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard self != .off else { return false }
        guard let lastCheckedAt else { return true }
        guard let nextCheckDate = nextCheckDate(after: lastCheckedAt, calendar: calendar) else { return false }
        return now >= nextCheckDate
    }
}

enum UpdateVersion {
    static func isNewer(_ remoteVersion: String, than localVersion: String) -> Bool {
        let remoteParts = parts(remoteVersion)
        let localParts = parts(localVersion)
        let count = max(remoteParts.count, localParts.count)

        for index in 0..<count {
            let remotePart = index < remoteParts.count ? remoteParts[index] : 0
            let localPart = index < localParts.count ? localParts[index] : 0
            if remotePart != localPart {
                return remotePart > localPart
            }
        }

        return false
    }

    private static func parts(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }
}

enum UpdateCheckOutcome: Equatable {
    case upToDate
    case updateAvailable(version: String)
}

protocol UpdatePreferenceStoring: AnyObject {
    func string(forKey key: String) -> String?
    func doubleObject(forKey key: String) -> Double?
    func set(_ value: String, forKey key: String)
    func set(_ value: Double, forKey key: String)
    func removeObject(forKey key: String)
}

extension PreferencesStore: UpdatePreferenceStoring {}

protocol UpdateReleaseProviding {
    func latestVersion() async throws -> String
}

struct GitHubUpdateReleaseProvider: UpdateReleaseProviding {
    func latestVersion() async throws -> String {
        let url = URL(string: "https://github.com/qbmiller/xxMac/releases/latest")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "HEAD"

        let delegate = UpdateReleaseRedirectDelegate()
        let (_, response) = try await URLSession.shared.data(for: request, delegate: delegate)
        let tagURL = delegate.redirectURL ?? response.url
        guard let tagName = tagURL?.lastPathComponent,
              tagURL?.path.contains("/releases/tag/") == true else {
            throw URLError(.badURL)
        }

        return tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }
}

private final class UpdateReleaseRedirectDelegate: NSObject, URLSessionTaskDelegate {
    private(set) var redirectURL: URL?

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard 300..<400 ~= response.statusCode, let url = request.url else {
            return request
        }

        redirectURL = url
        return nil
    }
}

@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()
    static let releasesURL = URL(string: "https://github.com/qbmiller/xxMac/releases")!

    @Published var frequency: UpdateCheckFrequency {
        didSet {
            store.set(frequency.rawValue, forKey: UpdatePreferencesKey.frequency)
            if frequency == .off {
                clearAvailableVersion()
            }
            guard hasStarted else { return }
            scheduleNextCheck()
            Task { await checkIfNeeded() }
        }
    }

    @Published private(set) var availableVersion: String?
    @Published private(set) var isChecking = false

    private let store: UpdatePreferenceStoring
    private let releaseProvider: UpdateReleaseProviding
    private let currentVersion: String
    private let now: () -> Date
    private let calendar: Calendar
    private var timer: Timer?
    private var retryAfter: Date?
    private var hasStarted = false

    init(
        store: UpdatePreferenceStoring = PreferencesStore.shared,
        releaseProvider: UpdateReleaseProviding = GitHubUpdateReleaseProvider(),
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0",
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.store = store
        self.releaseProvider = releaseProvider
        self.currentVersion = currentVersion
        self.now = now
        self.calendar = calendar
        frequency = store.string(forKey: UpdatePreferencesKey.frequency)
            .flatMap(UpdateCheckFrequency.init(rawValue:))
            ?? AppDefaultSettings.Updates.frequency

        let storedVersion = store.string(forKey: UpdatePreferencesKey.availableVersion)
        if frequency != .off,
           let storedVersion,
           UpdateVersion.isNewer(storedVersion, than: currentVersion) {
            availableVersion = storedVersion
        } else {
            availableVersion = nil
            store.removeObject(forKey: UpdatePreferencesKey.availableVersion)
        }
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        scheduleNextCheck()
        Task { await checkIfNeeded() }
    }

    func checkIfNeeded() async {
        let checkDate = now()
        guard frequency.isDue(lastCheckedAt: lastSuccessfulCheck, now: checkDate, calendar: calendar),
              retryAfter.map({ checkDate >= $0 }) ?? true,
              !isChecking else {
            scheduleNextCheck()
            return
        }

        do {
            _ = try await checkForUpdates()
        } catch {
            retryAfter = checkDate.addingTimeInterval(60 * 60)
            scheduleNextCheck()
        }
    }

    @discardableResult
    func checkForUpdates() async throws -> UpdateCheckOutcome {
        guard !isChecking else {
            return availableVersion.map(UpdateCheckOutcome.updateAvailable) ?? .upToDate
        }

        isChecking = true
        defer { isChecking = false }

        let remoteVersion = try await releaseProvider.latestVersion()
        let checkedAt = now()
        store.set(checkedAt.timeIntervalSince1970, forKey: UpdatePreferencesKey.lastSuccessfulCheck)
        retryAfter = nil

        let outcome: UpdateCheckOutcome
        if UpdateVersion.isNewer(remoteVersion, than: currentVersion) {
            outcome = .updateAvailable(version: remoteVersion)
            if frequency != .off {
                availableVersion = remoteVersion
                store.set(remoteVersion, forKey: UpdatePreferencesKey.availableVersion)
            }
        } else {
            outcome = .upToDate
            clearAvailableVersion()
        }

        scheduleNextCheck()
        return outcome
    }

    private var lastSuccessfulCheck: Date? {
        store.doubleObject(forKey: UpdatePreferencesKey.lastSuccessfulCheck).map(Date.init(timeIntervalSince1970:))
    }

    private func clearAvailableVersion() {
        availableVersion = nil
        store.removeObject(forKey: UpdatePreferencesKey.availableVersion)
    }

    private func scheduleNextCheck() {
        timer?.invalidate()
        timer = nil

        guard hasStarted, frequency != .off else { return }
        let currentDate = now()
        let dueDate = lastSuccessfulCheck
            .flatMap { frequency.nextCheckDate(after: $0, calendar: calendar) }
            ?? currentDate
        let targetDate = max(dueDate, retryAfter ?? .distantPast)
        let interval = max(1, targetDate.timeIntervalSince(currentDate))

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.checkIfNeeded()
            }
        }
    }
}
