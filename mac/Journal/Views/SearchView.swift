import JournalKit
import SwiftUI

/// Results for the window's search field. Selecting a hit shows its day.
struct SearchView: View {
    @Environment(JournalStore.self) private var store
    @Environment(Navigation.self) private var nav
    let query: String
    @State private var hits: [SearchHit] = []
    @State private var selection: String?

    var body: some View {
        List(selection: $selection) {
            ForEach(hits) { hit in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(hit.date).font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                        Text(hit.section.title).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(MarkdownRenderer.highlighted(hit.lineText, query: query)).lineLimit(4)
                }
                .padding(.vertical, 2)
                .tag(hit.id)
            }
        }
        .listStyle(.inset)
        .overlay {
            if hits.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .navigationTitle("Search")
        .onChange(of: selection) { _, id in
            if let hit = hits.first(where: { $0.id == id }) { nav.show(hit.date) }
        }
        .task(id: query + "\(store.index.lineCount)") {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            hits = store.index.search(query)
        }
    }
}
