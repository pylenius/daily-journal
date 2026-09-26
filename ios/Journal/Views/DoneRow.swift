import JournalKit
import SwiftUI

/// A Done bullet. Swipe left (or right-click) to highlight (bold in the file) or remove the line.
struct DoneRow: View {
    @Environment(JournalStore.self) private var store
    let item: DoneItem

    var body: some View {
        Text(MarkdownRenderer.inline(item.text))
            .fontWeight(item.isHighlighted ? .bold : .regular)
            // On macOS a selectable Text takes over right-click with the text menu; the context menu has Copy instead.
            #if os(iOS)
            .textSelection(.enabled)
            #endif
            .padding(.vertical, 2)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                removeButton
                highlightButton.tint(.orange)
            }
            .contextMenu {
                highlightButton
                #if os(macOS)
                Button("Copy", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.text, forType: .string)
                }
                #endif
                removeButton
            }
    }

    private var removeButton: some View {
        Button(role: .destructive) {
            Task { await store.remove(item) }
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }

    private var highlightButton: some View {
        Button {
            Task { await store.toggleHighlight(item) }
        } label: {
            Label(item.isHighlighted ? "Unhighlight" : "Highlight", systemImage: item.isHighlighted ? "bold.slash" : "bold")
        }
    }
}
