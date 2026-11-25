import Foundation

struct CalendarAlmanacEntry: Decodable {
    let lunar: String
    let lunarYear: Int
    let lunarMonth: Int
    let lunarDay: Int
    let isLeap: Bool
    let zodiac: String
    let pillars: String
    let good: [String]
    let bad: [String]
    let goodGods: [String]
    let badGods: [String]
    let level: String
    let officer: String
    let god: String
    let quality: String
    let clash: String
    let peng: String
    let nayin: String
    let solarTerm: String
}

/// Small immutable yearly resources; at most three years are retained in memory.
/// UI reads on the main thread; tests may construct independent stores.
final class CalendarAlmanacStore {
    static let shared = CalendarAlmanacStore(
        directory: Bundle.main.resourceURL?.appendingPathComponent("Almanac")
    )
    private let directory: URL?
    private let lock = NSLock()
    private var cache: [String: [String: CalendarAlmanacEntry]] = [:]
    private var recentYears: [String] = []

    init(directory: URL?) { self.directory = directory }

    func entry(for date: Date, calendar: Calendar) -> CalendarAlmanacEntry? {
        // Resource keys are civil Gregorian dates even when macOS uses another calendar.
        var civilCalendar = Calendar(identifier: .gregorian)
        civilCalendar.timeZone = calendar.timeZone
        let parts = civilCalendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return entry(forKey: String(format: "%04d-%02d-%02d", year, month, day))
    }

    func entry(forKey key: String) -> CalendarAlmanacEntry? {
        guard key.count == 10, key >= "1901-02-19", key <= "2099-12-31" else { return nil }
        let year = String(key.prefix(4))
        guard Int(year) != nil else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if cache[year] == nil {
            let entries: [String: CalendarAlmanacEntry]
            if let url = directory?.appendingPathComponent("\(year).json.deflate"),
               let compressed = try? Data(contentsOf: url),
               let data = try? (compressed as NSData).decompressed(using: .zlib),
               let decoded = try? JSONDecoder().decode([String: CalendarAlmanacEntry].self, from: data as Data) {
                entries = decoded
            } else {
                entries = [:]
            }
            cache[year] = entries
        }
        recentYears.removeAll { $0 == year }
        recentYears.append(year)
        if recentYears.count > 3 { cache.removeValue(forKey: recentYears.removeFirst()) }
        return cache[year]?[key]
    }
}
