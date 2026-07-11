import AppKit
import Foundation

struct LauncherHistoryRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let kind: LauncherHistoryKind
    let sourceID: String
    let title: String
    let subtitle: String
    let iconName: String
    let query: String
    let executedAt: Date
}

final class LauncherHistoryManager: ObservableObject {
    static let shared = LauncherHistoryManager()

    static let defaultMaxItems = AppDefaultSettings.LauncherHistory.maxItems
    static let maxItemsRange = 0...500

    @Published private(set) var records: [LauncherHistoryRecord] = []

    @Published var maxItems: Int {
        didSet {
            let clamped = Self.clampedMaxItems(maxItems)
            if clamped != maxItems {
                maxItems = clamped
                return
            }
            saveMaxItems()
            trimRecords()
        }
    }

    private let recordsKey = "LauncherHistoryRecords"
    private let maxItemsKey = "LauncherHistoryMaxItems"

    private init() {
        let store = PreferencesStore.shared
        maxItems = Self.clampedMaxItems(store.intObject(forKey: maxItemsKey) ?? Self.defaultMaxItems)
        loadRecords()
        trimRecords()
    }

    func record(item: SearchItem, query: String) {
        guard let snapshot = snapshot(for: item, query: query) else { return }

        let record = LauncherHistoryRecord(
            id: UUID(),
            kind: snapshot.kind,
            sourceID: snapshot.sourceID,
            title: snapshot.title,
            subtitle: snapshot.subtitle,
            iconName: snapshot.iconName,
            query: snapshot.query,
            executedAt: Date()
        )

        records.removeAll {
            $0.kind == record.kind &&
            $0.sourceID == record.sourceID &&
            $0.query == record.query
        }
        records.insert(record, at: 0)
        trimRecords()
    }

    func search(query: String) -> [SearchItem] {
        let normalizedQuery = AppSearchKeyBuilder.normalize(query)
        let compactQuery = AppSearchKeyBuilder.normalizeCompact(query)
        guard !normalizedQuery.isEmpty || !compactQuery.isEmpty else {
            return records.map(makeSearchItem)
        }

        return records
            .filter { record in
                let values = [record.title, record.subtitle, record.query]
                return values.contains { value in
                    let normalized = AppSearchKeyBuilder.normalize(value)
                    let compact = AppSearchKeyBuilder.normalizeCompact(value)
                    return (!normalizedQuery.isEmpty && normalized.contains(normalizedQuery)) ||
                        (!compactQuery.isEmpty && compact.contains(compactQuery))
                }
            }
            .map(makeSearchItem)
    }

    func clear() {
        records = []
        saveRecords()
    }

    private func snapshot(for item: SearchItem, query: String) -> LauncherHistorySnapshot? {
        if let snapshot = item.launcherHistorySnapshot {
            return snapshot
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        switch item.type {
        case .app:
            return LauncherHistorySnapshot(
                kind: .app,
                sourceID: item.subtitle,
                title: item.title,
                subtitle: item.subtitle,
                iconName: item.iconName,
                query: trimmedQuery
            )
        case .windowAction:
            return LauncherHistorySnapshot(
                kind: .windowAction,
                sourceID: item.id,
                title: item.title,
                subtitle: item.subtitle,
                iconName: item.iconName,
                query: trimmedQuery
            )
        case .quickShortcut:
            return nil
        case .calculator:
            return LauncherHistorySnapshot(
                kind: .calculator,
                sourceID: item.id,
                title: item.title,
                subtitle: item.subtitle,
                iconName: item.iconName,
                query: trimmedQuery
            )
        case .launcherHistory, .clipboard, .snippet, .quickShortcutOutput, .bookmark, .browserHistory:
            return nil
        }
    }

    private func makeSearchItem(from record: LauncherHistoryRecord) -> SearchItem {
        SearchItem(
            id: "launcher_history.\(record.id.uuidString)",
            title: record.title,
            subtitle: historySubtitle(for: record),
            iconName: record.iconName,
            type: .launcherHistory,
            launcherHistorySnapshot: LauncherHistorySnapshot(
                kind: record.kind,
                sourceID: record.sourceID,
                title: record.title,
                subtitle: record.subtitle,
                iconName: record.iconName,
                query: record.query
            ),
            action: { [weak self] in
                self?.replay(record)
            }
        )
    }

    private func historySubtitle(for record: LauncherHistoryRecord) -> String {
        if record.query.isEmpty {
            return L10n.f("launcher_history.subtitle_format", record.subtitle)
        }
        return L10n.f("launcher_history.subtitle_with_query_format", record.subtitle, record.query)
    }

    private func replay(_ record: LauncherHistoryRecord) {
        switch record.kind {
        case .app:
            NSWorkspace.shared.open(URL(fileURLWithPath: record.sourceID))
        case .windowAction:
            executeWindowAction(id: record.sourceID)
        case .quickShortcut:
            QuickShortcutManager.shared.execute(id: record.sourceID, query: record.query)
        case .calculator:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(record.title, forType: .string)
        }
    }

    private func executeWindowAction(id: String) {
        switch id {
        case "window.left": AccessibilityManager.shared.leftHalf()
        case "window.right": AccessibilityManager.shared.rightHalf()
        case "window.top": AccessibilityManager.shared.topHalf()
        case "window.bottom": AccessibilityManager.shared.bottomHalf()
        case "window.top_left": AccessibilityManager.shared.topLeft()
        case "window.top_right": AccessibilityManager.shared.topRight()
        case "window.bottom_left": AccessibilityManager.shared.bottomLeft()
        case "window.bottom_right": AccessibilityManager.shared.bottomRight()
        case "window.maximize": AccessibilityManager.shared.maximize()
        case "window.center": AccessibilityManager.shared.center()
        case "window.next_screen": AccessibilityManager.shared.nextScreen()
        case "window.previous_screen": AccessibilityManager.shared.previousScreen()
        default: break
        }
    }

    private func trimRecords() {
        let limit = Self.clampedMaxItems(maxItems)
        if limit == 0 {
            records = []
        } else if records.count > limit {
            records = Array(records.prefix(limit))
        }
        saveRecords()
    }

    private func loadRecords() {
        guard let data = PreferencesStore.shared.data(forKey: recordsKey),
              let decoded = try? JSONDecoder().decode([LauncherHistoryRecord].self, from: data) else {
            records = []
            return
        }
        records = decoded.sorted { $0.executedAt > $1.executedAt }
    }

    private func saveRecords() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        PreferencesStore.shared.set(data, forKey: recordsKey)
    }

    private func saveMaxItems() {
        PreferencesStore.shared.set(maxItems, forKey: maxItemsKey)
    }

    private static func clampedMaxItems(_ value: Int) -> Int {
        min(max(value, maxItemsRange.lowerBound), maxItemsRange.upperBound)
    }
}
