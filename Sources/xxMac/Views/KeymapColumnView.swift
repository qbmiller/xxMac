import SwiftUI

struct KeymapColumnView: View {
    let column: KeymapColumn

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(column.title)
                .font(.title3)
                .fontWeight(.medium)
                .lineLimit(1)
                .padding(.bottom, 8)
            Divider()
            ForEach(column.items) { item in
                HStack(spacing: 8) {
                    Text(item.shortcut)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundColor(item.enabled ? .primary : .secondary)
                        .frame(minWidth: 74, alignment: .trailing)
                    Text(item.title)
                        .font(.callout)
                        .foregroundColor(item.enabled ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .padding(.leading, CGFloat(item.depth * 14))
                .padding(.vertical, 4)
            }
        }
    }
}
