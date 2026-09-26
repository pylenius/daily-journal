import JournalKit
import SwiftUI

/// One day in the day list: date, done and open-action counts, and the first Done item.
struct DayRow: View {
    let entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.displayDate).font(.headline)
            HStack(spacing: 12) {
                Label("\(entry.doneItems.count)", systemImage: "checkmark.seal").foregroundStyle(.secondary)
                if entry.openActionCount > 0 {
                    Label("\(entry.openActionCount) open", systemImage: "circle").foregroundStyle(Color.accentColor)
                }
            }
            .font(.caption)
            if let first = entry.doneItems.first {
                Text(MarkdownRenderer.inline(first.text)).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}
