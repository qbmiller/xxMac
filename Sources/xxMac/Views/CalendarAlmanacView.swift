import SwiftUI

struct CalendarAlmanacSummary: View {
    let entry: CalendarAlmanacEntry?
    let isExpanded: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(L10n.t("calendar.almanac.title")).fontWeight(.medium)
                    Image(systemName: isExpanded ? "chevron.left" : "chevron.left.square")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                if let entry {
                    summaryLine("calendar.almanac.good", items: entry.good, color: .green)
                    summaryLine("calendar.almanac.bad", items: entry.bad, color: .red)
                } else {
                    Text(L10n.t("calendar.almanac.unavailable")).foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(width: 144, alignment: .leading)
            .background(Color.red.opacity(hovered || isExpanded ? 0.07 : 0),
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(L10n.t("calendar.almanac.toggle"))
        .accessibilityLabel(L10n.t("calendar.almanac.toggle"))
    }

    private func summaryLine(_ key: String, items: [String], color: Color) -> some View {
        HStack(spacing: 5) {
            Text(L10n.t(key)).foregroundStyle(color)
            Text(items.isEmpty ? "—" : items.prefix(2).joined(separator: " ") + (items.count > 2 ? " …" : ""))
                .foregroundStyle(.primary)
        }
    }
}

struct CalendarAlmanacDetailView: View {
    let date: Date
    let locale: Locale
    let entry: CalendarAlmanacEntry?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t("calendar.almanac.title")).font(.headline)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L10n.t("calendar.almanac.close"))
            }
            .padding(16)
            Divider().padding(.horizontal, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    dateHeading
                    if let entry {
                        Divider()
                        activities("calendar.almanac.good", items: entry.good, color: .green)
                        activities("calendar.almanac.bad", items: entry.bad, color: .red)
                        Divider()
                        HStack(alignment: .top, spacing: 12) {
                            fact("calendar.almanac.god", text: "\(entry.god) · \(entry.quality)")
                            Spacer(minLength: 0)
                            fact("calendar.almanac.officer", text: entry.officer)
                        }
                        fact("calendar.almanac.clash", text: entry.clash)
                        fact("calendar.almanac.good_gods", text: entry.goodGods.joined(separator: " "))
                        fact("calendar.almanac.bad_gods", text: entry.badGods.joined(separator: " "))
                        fact("calendar.almanac.level", text: entry.level)
                        fact("calendar.almanac.peng", text: entry.peng)
                        fact("calendar.almanac.nayin", text: entry.nayin)
                    } else {
                        Text(L10n.t("calendar.almanac.unavailable")).foregroundStyle(.secondary)
                        Text(L10n.t("calendar.almanac.range")).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(L10n.t("calendar.almanac.source"))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
        }
    }

    private var dateHeading: some View {
        VStack(spacing: 5) {
            Text(String(Calendar(identifier: .gregorian).component(.day, from: date)))
                .font(.system(size: 54, weight: .medium, design: .rounded))
                .foregroundStyle(.red)
            if let entry {
                Text(entry.lunar).font(.title2.weight(.semibold))
                Text(entry.pillars).font(.caption).foregroundStyle(.secondary)
                if entry.solarTerm != "无" && !entry.solarTerm.isEmpty {
                    Text(entry.solarTerm).font(.caption).foregroundStyle(.red)
                }
            }
            Text(date, format: .dateTime.locale(locale).year().month().day().weekday())
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func activities(_ key: String, items: [String], color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(L10n.t(key))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .padding(5)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            CalendarAlmanacActivityLayout {
                ForEach(Array((items.isEmpty ? ["—"] : items).enumerated()), id: \.offset) { _, item in
                    Text(item).font(.subheadline).fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private func fact(_ key: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t(key)).font(.caption).foregroundStyle(.secondary)
            Text(text.isEmpty ? "—" : text).font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

/// Keep each traditional activity together instead of splitting a two-character word.
private struct CalendarAlmanacActivityLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? 240).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(subviews, width: bounds.width)
        for (index, point) in layout.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                                 proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + 6
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + 8
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), positions)
    }
}
