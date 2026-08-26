import Foundation

struct DailyPasteCounter: Codable, Equatable {
    var dateKey: String
    var nextValue: Int

    init(dateKey: String = "", nextValue: Int = 1) {
        self.dateKey = dateKey
        self.nextValue = max(nextValue, 1)
    }

    func nextNumber(on date: Date, calendar: Calendar) -> Int {
        guard dateKey == Self.dateKey(for: date, calendar: calendar) else {
            return 1
        }
        return max(nextValue, 1)
    }

    mutating func recordSuccess(on date: Date, calendar: Calendar) {
        let currentDateKey = Self.dateKey(for: date, calendar: calendar)
        if dateKey == currentDateKey {
            nextValue = max(nextValue, 1) + 1
        } else {
            dateKey = currentDateKey
            nextValue = 2
        }
    }

    mutating func reset(on date: Date, calendar: Calendar) {
        dateKey = Self.dateKey(for: date, calendar: calendar)
        nextValue = 1
    }

    private static func dateKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

struct FinderPasteOperationSettings: Codable, Equatable {
    var imageEnabled: Bool
    var textEnabled: Bool
    var imageCounter: DailyPasteCounter
    var textCounter: DailyPasteCounter

    init(
        imageEnabled: Bool = AppDefaultSettings.Clipboard.imagePasteToFileEnabled,
        textEnabled: Bool = AppDefaultSettings.Clipboard.textPasteToFileEnabled,
        imageCounter: DailyPasteCounter = DailyPasteCounter(),
        textCounter: DailyPasteCounter = DailyPasteCounter()
    ) {
        self.imageEnabled = imageEnabled
        self.textEnabled = textEnabled
        self.imageCounter = imageCounter
        self.textCounter = textCounter
    }
}

enum FinderPastePayload: Equatable {
    case fileURLs([URL])
    case image(Data)
    case text(String)
    case unsupported
}

enum FinderPasteRoute: Equatable {
    case pastePaths([URL])
    case saveImage(Data)
    case saveText(String)
    case none
}

enum FinderPasteRoutingPolicy {
    static func route(
        payload: FinderPastePayload,
        isFinderFrontmost: Bool,
        settings: FinderPasteOperationSettings
    ) -> FinderPasteRoute {
        switch payload {
        case .fileURLs(let urls):
            guard !isFinderFrontmost, !urls.isEmpty else { return .none }
            return .pastePaths(urls)
        case .image(let data):
            guard isFinderFrontmost, settings.imageEnabled else { return .none }
            return .saveImage(data)
        case .text(let text):
            guard isFinderFrontmost, settings.textEnabled else { return .none }
            return .saveText(text)
        case .unsupported:
            return .none
        }
    }
}
