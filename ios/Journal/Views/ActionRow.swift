import JournalKit
import SwiftUI

/// A checkbox line: tap the circle to toggle, links open in the browser, other references are copyable.
struct ActionRow: View {
    @Environment(JournalStore.self) private var store
    let item: CheckboxLine
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                Task { await store.toggle(item) }
            } label: {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isChecked ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isChecked ? "Mark open" : "Mark done")
            VStack(alignment: .leading, spacing: 4) {
                Text(MarkdownRenderer.inline(item.text))
                    .strikethrough(item.isChecked, color: .secondary)
                    .foregroundStyle(item.isChecked ? .secondary : .primary)
                if let reference = item.reference, !reference.isEmpty {
                    Text(MarkdownRenderer.autolinked(reference))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                ForEach(item.continuation, id: \.self) { line in
                    Text(MarkdownRenderer.inline(line.trimmingCharacters(in: .whitespaces)))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let subtitle {
                    Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
