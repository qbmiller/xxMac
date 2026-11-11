import SwiftUI

/// A pair of scrolling wheels, also available on the app's macOS 13 minimum.
struct CalendarMonthPickerView: View {
    let locale: Locale
    let onSelect: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var year: Int
    @State private var month: Int

    init(date: Date, locale: Locale, onSelect: @escaping (Date) -> Void) {
        self.locale = locale
        self.onSelect = onSelect
        let calendar = Calendar(identifier: .gregorian)
        _year = State(initialValue: calendar.component(.year, from: date))
        _month = State(initialValue: calendar.component(.month, from: date))
    }

    private var monthTitles: [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return calendar.monthSymbols
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(L10n.t("calendar.choose_month"))
                .font(.headline)
            HStack(spacing: 12) {
                CalendarSelectionWheel(values: Array(min(1900, year)...max(2100, year)), selection: $year) {
                    String($0)
                }
                .accessibilityLabel(L10n.t("calendar.year"))
                CalendarSelectionWheel(values: Array(1...12), selection: $month) {
                    locale.identifier.hasPrefix("zh") ? "\($0)月" : monthTitles[$0 - 1]
                }
                .accessibilityLabel(L10n.t("calendar.month"))
            }
            HStack {
                Button(L10n.t("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.t("general.done")) {
                    let calendar = Calendar(identifier: .gregorian)
                    if let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) {
                        onSelect(date)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}

private struct CalendarSelectionWheel: View {
    let values: [Int]
    @Binding var selection: Int
    let title: (Int) -> String
    @Namespace private var coordinateSpace
    @State private var ready = false
    @State private var snapTask: Task<Void, Never>?
    private let rowHeight: CGFloat = 32

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(values, id: \.self) { value in
                        Button {
                            withAnimation { proxy.scrollTo(value, anchor: .center) }
                        } label: {
                            Text(title(value))
                                .font(.system(size: value == selection ? 18 : 15, weight: value == selection ? .semibold : .regular))
                                .foregroundStyle(value == selection ? Color.accentColor : .secondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: rowHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(value)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: CalendarWheelPositions.self, value: [
                                value: abs(geometry.frame(in: .named(coordinateSpace)).midY - rowHeight * 2.5)
                            ])
                        })
                    }
                }
                .padding(.vertical, rowHeight * 2)
            }
            .coordinateSpace(name: coordinateSpace)
            .frame(height: rowHeight * 5)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(height: rowHeight)
            }
            .mask {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0), .init(color: .black, location: 0.3),
                    .init(color: .black, location: 0.7), .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
            .onAppear {
                proxy.scrollTo(selection, anchor: .center)
                DispatchQueue.main.async { ready = true }
            }
            .onPreferenceChange(CalendarWheelPositions.self) { positions in
                guard ready, let nearest = positions.min(by: { $0.value < $1.value })?.key else { return }
                selection = nearest
                snapTask?.cancel()
                snapTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation { proxy.scrollTo(nearest, anchor: .center) }
                }
            }
            .onDisappear { snapTask?.cancel() }
            .accessibilityValue(title(selection))
            .accessibilityAdjustableAction { direction in
                guard let index = values.firstIndex(of: selection) else { return }
                let next = direction == .increment ? index + 1 : index - 1
                guard values.indices.contains(next) else { return }
                proxy.scrollTo(values[next], anchor: .center)
            }
        }
    }
}

private struct CalendarWheelPositions: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
