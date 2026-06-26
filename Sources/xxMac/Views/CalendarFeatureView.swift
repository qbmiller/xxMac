import AppKit
import Combine
import SwiftUI

enum CalendarMenuBarIconStyle: String, CaseIterable, Identifiable {
    case weekdayDay
    case monthDay
    case lunarMonthDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekdayDay:
            return L10n.t("calendar.icon_style.weekday_day")
        case .monthDay:
            return L10n.t("calendar.icon_style.month_day")
        case .lunarMonthDay:
            return L10n.t("calendar.icon_style.lunar_month_day")
        }
    }
}

enum CalendarPreferencesKey {
    static let showLunar = "CalendarShowLunar"
    static let showWeekNumbers = "CalendarShowWeekNumbers"
    static let firstWeekday = "CalendarFirstWeekday"
    static let menuBarIconStyle = "CalendarMenuBarIconStyle"
}

@MainActor
final class CalendarPreferencesStore: ObservableObject {
    static let shared = CalendarPreferencesStore()

    @Published var showLunar: Bool {
        didSet { UserDefaults.standard.set(showLunar, forKey: CalendarPreferencesKey.showLunar) }
    }

    @Published var showWeekNumbers: Bool {
        didSet { UserDefaults.standard.set(showWeekNumbers, forKey: CalendarPreferencesKey.showWeekNumbers) }
    }

    @Published var firstWeekday: Int {
        didSet { UserDefaults.standard.set(firstWeekday, forKey: CalendarPreferencesKey.firstWeekday) }
    }

    @Published var menuBarIconStyle: CalendarMenuBarIconStyle {
        didSet { UserDefaults.standard.set(menuBarIconStyle.rawValue, forKey: CalendarPreferencesKey.menuBarIconStyle) }
    }

    private init() {
        let defaults = UserDefaults.standard
        showLunar = defaults.object(forKey: CalendarPreferencesKey.showLunar) as? Bool ?? true
        showWeekNumbers = defaults.object(forKey: CalendarPreferencesKey.showWeekNumbers) as? Bool ?? true
        let storedWeekday = defaults.integer(forKey: CalendarPreferencesKey.firstWeekday)
        firstWeekday = storedWeekday == 0 ? 2 : storedWeekday
        let rawStyle = defaults.string(forKey: CalendarPreferencesKey.menuBarIconStyle)
        menuBarIconStyle = rawStyle.flatMap(CalendarMenuBarIconStyle.init(rawValue:)) ?? .weekdayDay
    }
}

struct CalendarFeatureView: View {
    let showsSettings: Bool

    @State private var displayedMonth = Date()
    @State private var selectedDate = Date()
    @ObservedObject private var localization = LocalizationManager.shared
    @ObservedObject private var preferences = CalendarPreferencesStore.shared

    init(showsSettings: Bool = false) {
        self.showsSettings = showsSettings
    }

    private var locale: Locale {
        Locale(identifier: localization.language.localeIdentifier)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.firstWeekday = preferences.firstWeekday
        return calendar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CalendarMonthView(
                displayedMonth: $displayedMonth,
                selectedDate: $selectedDate,
                locale: locale,
                calendar: calendar,
                monthDays: monthDays,
                showsWeekNumbers: preferences.showWeekNumbers,
                showsLunar: preferences.showLunar,
                onToday: showToday
            )

            if showsSettings {
                Divider()
                CalendarSettingsControls()
            } else {
                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedDate, format: selectedDateFormat)
                        .font(.headline)
                    if preferences.showLunar {
                        Text(lunarHint(for: selectedDate))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 390, idealWidth: 430, maxWidth: .infinity, minHeight: showsSettings ? 560 : 420, alignment: .top)
    }

    private var monthDays: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end.addingTimeInterval(-1))
        else {
            return []
        }

        var days: [Date] = []
        var date = firstWeek.start
        while date < lastWeek.end {
            days.append(date)
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? lastWeek.end
        }
        return days
    }

    private var selectedDateFormat: Date.FormatStyle {
        .dateTime.locale(locale).year().month(.wide).day().weekday(.wide)
    }

    private func showToday() {
        let today = Date()
        displayedMonth = today
        selectedDate = today
    }

    private func lunarHint(for date: Date) -> String {
        L10n.f("calendar.lunar_format", CalendarFestivalStore.detailText(for: date, calendar: calendar))
    }
}

private struct CalendarMonthView: View {
    @Binding var displayedMonth: Date
    @Binding var selectedDate: Date

    let locale: Locale
    let calendar: Calendar
    let monthDays: [Date]
    let showsWeekNumbers: Bool
    let showsLunar: Bool
    let onToday: () -> Void

    private var columns: [GridItem] {
        let weekColumn = showsWeekNumbers ? [GridItem(.fixed(26), spacing: 6)] : []
        return weekColumn + Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CalendarHeaderView(
                displayedMonth: $displayedMonth,
                locale: locale,
                onToday: onToday
            )

            LazyVGrid(columns: columns, spacing: 6) {
                if showsWeekNumbers {
                    Text("#")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                }

                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(monthRows, id: \.weekNumber) { row in
                    if showsWeekNumbers {
                        Text(row.weekNumber)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }

                    ForEach(row.dates, id: \.self) { date in
                        CalendarDayCell(
                            date: date,
                            displayedMonth: displayedMonth,
                            selectedDate: selectedDate,
                            calendar: calendar,
                            locale: locale,
                            showsLunar: showsLunar
                        )
                        .onTapGesture {
                            selectedDate = date
                        }
                    }
                }
            }
        }
    }

    private var monthRows: [CalendarWeekRow] {
        stride(from: 0, to: monthDays.count, by: 7).map { index in
            let rowDates = Array(monthDays[index..<min(index + 7, monthDays.count)])
            let weekNumber = rowDates.first.map { calendar.component(.weekOfYear, from: $0) } ?? 0
            return CalendarWeekRow(weekNumber: "\(weekNumber)", dates: rowDates)
        }
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = locale
        var symbols = formatter.shortStandaloneWeekdaySymbols ?? formatter.shortWeekdaySymbols ?? []
        let shift = calendar.firstWeekday - 1
        if shift > 0 {
            symbols = Array(symbols.dropFirst(shift)) + Array(symbols.prefix(shift))
        }
        return symbols
    }
}

private struct CalendarWeekRow {
    let weekNumber: String
    let dates: [Date]
}

private enum CalendarHolidayStatus: Int {
    case ordinary = 0
    case work = 1
    case rest = 2

    var title: String {
        switch self {
        case .ordinary:
            return ""
        case .work:
            return "班"
        case .rest:
            return "休"
        }
    }

    var isOrdinary: Bool {
        self == .ordinary
    }
}

private enum CalendarHolidayStore {
    private static let statuses: [String: [String: CalendarHolidayStatus]] = loadStatuses()

    static func status(for date: Date, calendar: Calendar) -> CalendarHolidayStatus {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return .ordinary
        }

        return statuses["\(year)"]?[String(format: "%02d%02d", month, day)] ?? .ordinary
    }

    private static func loadStatuses() -> [String: [String: CalendarHolidayStatus]] {
        guard let url = Bundle.main.url(forResource: "calendar_holidays", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rawStatuses = try? JSONDecoder().decode([String: [String: Int]].self, from: data)
        else {
            return [:]
        }

        return rawStatuses.mapValues { yearStatuses in
            yearStatuses.reduce(into: [String: CalendarHolidayStatus]()) { result, entry in
                result[entry.key] = CalendarHolidayStatus(rawValue: entry.value) ?? .ordinary
            }
        }
    }
}

private enum CalendarFestivalStore {
    private static let solarTermTitles = [
        "立春", "雨水", "惊蛰", "春分", "清明", "谷雨",
        "立夏", "小满", "芒种", "夏至", "小暑", "大暑",
        "立秋", "处暑", "白露", "秋分", "寒露", "霜降",
        "立冬", "小雪", "大雪", "冬至", "小寒", "大寒"
    ]
    private static let lunarFestivals = loadDictionary(resource: "calendar_lunar_festivals")
    private static let solarFestivals = loadDictionary(resource: "calendar_solar_festivals")
    private static let solarAllFestivals = loadArrayDictionary(resource: "calendar_solar_all_festivals")
    private static let weekPrimaryFestivals = loadDictionary(resource: "calendar_week_primary_festivals")
    private static let weekAllFestivals = loadArrayDictionary(resource: "calendar_week_all_festivals")
    private static let weekSpecialFestivals = loadDictionary(resource: "calendar_week_special_festivals")
    private static let chuxiDates = loadDictionary(resource: "calendar_chuxi")
    private static let solarTerms = loadSolarTerms()

    static func displayText(for date: Date, calendar: Calendar) -> String {
        lunarFestival(for: date, calendar: calendar)
            ?? solarTerm(for: date, calendar: calendar)
            ?? weekPrimaryFestival(for: date, calendar: calendar)
            ?? solarPrimaryFestival(for: date, calendar: calendar)
            ?? LunarCalendarText.day(for: date)
    }

    static func detailText(for date: Date, calendar: Calendar) -> String {
        let festivals = allFestivals(for: date, calendar: calendar)
        guard !festivals.isEmpty else {
            return LunarCalendarText.monthDay(for: date)
        }

        return ([LunarCalendarText.monthDay(for: date)] + festivals).joined(separator: " · ")
    }

    private static func allFestivals(for date: Date, calendar: Calendar) -> [String] {
        let values = [
            lunarFestival(for: date, calendar: calendar),
            solarTerm(for: date, calendar: calendar)
        ] + weekAllFestival(for: date, calendar: calendar)
            + [weekSpecialFestival(for: date, calendar: calendar)]
            + solarAllFestival(for: date, calendar: calendar)

        return unique(values.compactMap(\.self))
    }

    private static func lunarFestival(for date: Date, calendar: Calendar) -> String? {
        guard let solarYear = solarYear(for: date, calendar: calendar),
              let solarMonthDay = solarMonthDay(for: date, calendar: calendar)
        else {
            return nil
        }

        let lunarKey = chuxiDates["\(solarYear)"] == solarMonthDay ? "0100" : lunarMonthDayKey(for: date)
        return lunarKey.flatMap { lunarFestivals[$0] }
    }

    private static func solarTerm(for date: Date, calendar: Calendar) -> String? {
        guard let solarYear = solarYear(for: date, calendar: calendar),
              let solarMonthDay = solarMonthDay(for: date, calendar: calendar),
              let termDates = solarTerms["\(solarYear)"],
              let index = termDates.firstIndex(of: solarMonthDay),
              solarTermTitles.indices.contains(index)
        else {
            return nil
        }

        return solarTermTitles[index]
    }

    private static func solarPrimaryFestival(for date: Date, calendar: Calendar) -> String? {
        guard let solarMonthDay = solarMonthDay(for: date, calendar: calendar) else { return nil }
        return solarFestivals[solarMonthDay]
    }

    private static func solarAllFestival(for date: Date, calendar: Calendar) -> [String] {
        guard let solarMonthDay = solarMonthDay(for: date, calendar: calendar) else { return [] }
        return solarAllFestivals[solarMonthDay] ?? []
    }

    private static func weekPrimaryFestival(for date: Date, calendar: Calendar) -> String? {
        guard let key = solarMonthWeekdayKey(for: date, calendar: calendar) else { return nil }
        return weekPrimaryFestivals[key]
    }

    private static func weekAllFestival(for date: Date, calendar: Calendar) -> [String] {
        guard let key = solarMonthWeekdayKey(for: date, calendar: calendar) else { return [] }
        return weekAllFestivals[key] ?? []
    }

    private static func weekSpecialFestival(for date: Date, calendar: Calendar) -> String? {
        guard isInvalidNextWeekday(for: date, calendar: calendar),
              let key = solarMonthWeekdayKey(for: date, calendar: calendar)
        else {
            return nil
        }

        return weekSpecialFestivals[key]
    }

    private static func lunarMonthDayKey(for date: Date) -> String? {
        let components = Calendar(identifier: .chinese).dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else { return nil }
        return String(format: "%02d%02d", month, day)
    }

    private static func solarYear(for date: Date, calendar: Calendar) -> Int? {
        calendar.dateComponents([.year], from: date).year
    }

    private static func solarMonthDay(for date: Date, calendar: Calendar) -> String? {
        let components = calendar.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else { return nil }
        return String(format: "%02d%02d", month, day)
    }

    private static func solarMonthWeekdayKey(for date: Date, calendar: Calendar) -> String? {
        let components = calendar.dateComponents([.month, .weekdayOrdinal, .weekday], from: date)
        guard let month = components.month,
              let weekdayOrdinal = components.weekdayOrdinal,
              let weekday = components.weekday
        else {
            return nil
        }

        return String(format: "%02d%d%d", month, weekdayOrdinal, weekday)
    }

    private static func isInvalidNextWeekday(for date: Date, calendar: Calendar) -> Bool {
        let components = calendar.dateComponents([.year, .month, .weekday, .weekdayOrdinal], from: date)
        guard let year = components.year,
              let month = components.month,
              let weekday = components.weekday,
              let weekdayOrdinal = components.weekdayOrdinal
        else {
            return false
        }

        let nextComponents = DateComponents(
            calendar: calendar,
            year: year,
            month: month,
            weekday: weekday,
            weekdayOrdinal: weekdayOrdinal + 1
        )
        return !nextComponents.isValidDate
    }

    private static func loadDictionary(resource: String) -> [String: String] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dictionary = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }

        return dictionary
    }

    private static func loadArrayDictionary(resource: String) -> [String: [String]] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dictionary = try? JSONDecoder().decode([String: [String]].self, from: data)
        else {
            return [:]
        }

        return dictionary
    }

    private static func loadSolarTerms() -> [String: [String]] {
        guard let url = Bundle.main.url(forResource: "calendar_solar_terms", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let terms = try? JSONDecoder().decode([String: [String]].self, from: data)
        else {
            return [:]
        }

        return terms
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

private struct CalendarHeaderView: View {
    @Binding var displayedMonth: Date

    let locale: Locale
    let onToday: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(displayedMonth, format: .dateTime.locale(locale).year().month(.wide))
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.red)

            Spacer()

            Button(action: previousMonth) {
                Label(L10n.t("calendar.previous_month"), systemImage: "chevron.left")
            }
            .labelStyle(.iconOnly)
            .help(L10n.t("calendar.previous_month"))

            Button(action: onToday) {
                Text(L10n.t("calendar.today"))
            }

            Button(action: nextMonth) {
                Label(L10n.t("calendar.next_month"), systemImage: "chevron.right")
            }
            .labelStyle(.iconOnly)
            .help(L10n.t("calendar.next_month"))
        }
    }

    private func previousMonth() {
        displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
    }

    private func nextMonth() {
        displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
    }
}

private struct CalendarDayCell: View {
    let date: Date
    let displayedMonth: Date
    let selectedDate: Date
    let calendar: Calendar
    let locale: Locale
    let showsLunar: Bool

    var body: some View {
        let isCurrentMonth = calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let holidayStatus = CalendarHolidayStore.status(for: date, calendar: calendar)
        let textColor = primaryTextColor(isCurrentMonth: isCurrentMonth, holidayStatus: holidayStatus)
        let secondaryColor = secondaryTextColor(isCurrentMonth: isCurrentMonth, holidayStatus: holidayStatus)

        ZStack(alignment: .topLeading) {
            holidayBackground(holidayStatus: holidayStatus, isSelected: isSelected)

            if !holidayStatus.isOrdinary {
                Text(holidayStatus.title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(holidayStatus == .rest ? Color.red : Color.secondary)
                    .padding(.leading, 4)
                    .padding(.top, 3)
            }

            VStack(spacing: 3) {
                Text(date, format: .dateTime.locale(locale).day())
                    .font(.title3.monospacedDigit())
                    .fontWeight(isToday ? .semibold : .regular)
                    .foregroundStyle(textColor)

                if showsLunar {
                    Text(CalendarFestivalStore.displayText(for: date, calendar: calendar))
                        .font(.caption2)
                        .foregroundStyle(secondaryColor)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(isToday || isSelected ? Color.red : Color.clear, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
    }

    private var isWeekend: Bool {
        calendar.isDateInWeekend(date)
    }

    private func holidayBackground(holidayStatus: CalendarHolidayStatus, isSelected: Bool) -> some View {
        let color: Color
        switch holidayStatus {
        case .rest:
            color = Color.red.opacity(0.12)
        case .work:
            color = Color.secondary.opacity(0.11)
        case .ordinary:
            color = isSelected ? Color.red.opacity(0.14) : Color.clear
        }

        return RoundedRectangle(cornerRadius: 6)
            .fill(isSelected ? Color.red.opacity(0.14) : color)
    }

    private func primaryTextColor(isCurrentMonth: Bool, holidayStatus: CalendarHolidayStatus) -> Color {
        if !isCurrentMonth {
            return Color.secondary.opacity(0.55)
        }

        if holidayStatus == .work {
            return .primary
        }

        if holidayStatus == .rest || isWeekend {
            return .red
        }

        return .primary
    }

    private func secondaryTextColor(isCurrentMonth: Bool, holidayStatus: CalendarHolidayStatus) -> Color {
        if !isCurrentMonth {
            return Color.secondary.opacity(0.45)
        }

        if holidayStatus == .work {
            return .secondary
        }

        if holidayStatus == .rest || isWeekend {
            return Color.red.opacity(0.85)
        }

        return .secondary
    }

    private var accessibilityLabel: String {
        DateFormatter.localizedString(from: date, dateStyle: .full, timeStyle: .none)
    }
}

private struct CalendarSettingsControls: View {
    @ObservedObject private var preferences = CalendarPreferencesStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker(L10n.t("calendar.first_weekday"), selection: $preferences.firstWeekday) {
                Text(L10n.t("calendar.weekday_sunday")).tag(1)
                Text(L10n.t("calendar.weekday_monday")).tag(2)
            }
            .pickerStyle(.menu)

            Toggle(L10n.t("calendar.show_lunar"), isOn: $preferences.showLunar)
            Toggle(L10n.t("calendar.show_week_numbers"), isOn: $preferences.showWeekNumbers)

            Picker(L10n.t("calendar.menu_bar_style"), selection: $preferences.menuBarIconStyle) {
                ForEach(CalendarMenuBarIconStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

enum LunarCalendarText {
    private static let months = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
    private static let days = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
    ]

    static func month(for date: Date) -> String {
        let components = Calendar(identifier: .chinese).dateComponents([.month], from: date)
        guard let month = components.month, months.indices.contains(month - 1) else { return "" }
        return months[month - 1]
    }

    static func day(for date: Date) -> String {
        let components = Calendar(identifier: .chinese).dateComponents([.day], from: date)
        guard let day = components.day, days.indices.contains(day - 1) else { return "" }
        return days[day - 1]
    }

    static func monthDay(for date: Date) -> String {
        "\(month(for: date))\(day(for: date))"
    }
}

@MainActor
final class CalendarMenuBarController {
    private let statusItem: NSStatusItem
    private let contextMenu: NSMenu
    private let popover = NSPopover()
    private let preferences = CalendarPreferencesStore.shared
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?

    init(statusItem: NSStatusItem, contextMenu: NSMenu) {
        self.statusItem = statusItem
        self.contextMenu = contextMenu
        configureStatusItem()
        configurePopover()
        observeChanges()
        refreshStatusItem()
        scheduleTimer()
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        timer?.invalidate()
    }

    func showCalendarWindow() {
        CalendarWindowController.shared.show()
    }

    func refreshStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = CalendarMenuBarIconRenderer.image(
            style: preferences.menuBarIconStyle,
            locale: Locale(identifier: LocalizationManager.shared.language.localeIdentifier)
        )
        button.imagePosition = .imageOnly
        button.attributedTitle = NSAttributedString()
        button.toolTip = L10n.t("calendar.menu_bar_tooltip")
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        statusItem.menu = nil
        button.target = self
        button.action = #selector(handleStatusItemClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = L10n.t("calendar.menu_bar_tooltip")
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 430, height: 460)
        popover.contentViewController = NSHostingController(rootView: CalendarFeatureView())
    }

    private func observeChanges() {
        LocalizationManager.shared.$language
            .sink { [weak self] _ in
                self?.refreshStatusItem()
            }
            .store(in: &cancellables)

        preferences.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshStatusItem()
                }
            }
            .store(in: &cancellables)
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatusItem()
            }
        }
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu(sender)
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: Any?) {
        popover.isShown ? closePopover() : showPopover(sender)
    }

    private func showPopover(_ sender: Any?) {
        guard let button = sender as? NSStatusBarButton else { return }
        popover.contentViewController = NSHostingController(rootView: CalendarFeatureView())
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.becomeKey()
        startEventMonitor()
    }

    private func showContextMenu(_ sender: Any?) {
        closePopover()
        guard let button = sender as? NSStatusBarButton else { return }
        contextMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
    }

    private func closePopover() {
        popover.close()
        stopEventMonitor()
    }

    private func startEventMonitor() {
        stopEventMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover()
            }
        }
    }

    private func stopEventMonitor() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }
}

private enum CalendarMenuBarIconRenderer {
    static func image(style: CalendarMenuBarIconStyle, locale: Locale) -> NSImage {
        let date = Date()
        let title: String
        let subtitle: String

        switch style {
        case .weekdayDay:
            title = weekdayTitle(for: date, locale: locale)
            subtitle = dayTitle(for: date)
        case .monthDay:
            title = monthTitle(for: date, locale: locale)
            subtitle = dayTitle(for: date)
        case .lunarMonthDay:
            title = LunarCalendarText.month(for: date)
            subtitle = LunarCalendarText.day(for: date)
        }

        return drawTwoLineIcon(title: title, subtitle: subtitle)
    }

    private static func weekdayTitle(for date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }

    private static func monthTitle(for date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: date)
    }

    private static func dayTitle(for date: Date) -> String {
        String(Calendar.current.component(.day, from: date))
    }

    private static func drawTwoLineIcon(title: String, subtitle: String) -> NSImage {
        let size = NSSize(width: 24, height: 22)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.labelColor.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 2.5, yRadius: 2.5).fill()

            let titleFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
            let subtitleFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
            let titleAttributes: [NSAttributedString.Key: Any] = [.font: titleFont]
            let subtitleAttributes: [NSAttributedString.Key: Any] = [.font: subtitleFont]
            let titleString = NSAttributedString(string: title, attributes: titleAttributes)
            let subtitleString = NSAttributedString(string: subtitle, attributes: subtitleAttributes)
            let titleSize = titleString.size()
            let subtitleSize = subtitleString.size()

            NSGraphicsContext.current?.compositingOperation = .destinationOut
            titleString.draw(at: CGPoint(x: (rect.width - titleSize.width) / 2, y: 10.5))
            subtitleString.draw(at: CGPoint(x: (rect.width - subtitleSize.width) / 2, y: 1.3))
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            return true
        }
        image.isTemplate = true
        return image
    }
}

@MainActor
final class CalendarWindowController {
    static let shared = CalendarWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = L10n.t("calendar.title")
            window.contentView = NSHostingView(rootView: CalendarFeatureView())
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
