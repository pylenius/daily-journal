import JournalKit
import SwiftUI

/// A Done bullet. Swipe left to highlight (bold in the file) or remove the line.
struct DoneRow: View {
    @Environment(JournalStore.self) private var store
    let item: DoneItem

    var body: some View {
        Text(MarkdownRenderer.inline(item.text))
            .fontWeight(item.isHighlighted ? .bold : .regular)
            .textSelection(.enabled)
            .padding(.vertical, 2)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    Task { await store.remove(item) }
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                Button {
                    Task { await store.toggleHighlight(item) }
                } label: {
                    Label(item.isHighlighted ? "Unhighlight" : "Highlight", systemImage: item.isHighlighted ? "bold.slash" : "bold")
                }
                .tint(.orange)
            }
    }
}
