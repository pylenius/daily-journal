import JournalKit
import SwiftUI

struct SearchView: View {
    @Environment(JournalStore.self) private var store
    @State private var query = ""
    @State private var hits: [SearchHit] = []

    var body: some View {
        List {
            if query.isEmpty {
                Text("Search every line of every entry. All words must appear on the same line.")
                    .foregroundStyle(.secondary)
            } else if hits.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ForEach(hits) { hit in
                    NavigationLink(value: hit.date) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(hit.date).font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                                Text(hit.section.title).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(highlighted(hit.lineText)).font(.subheadline).lineLimit(4)
                        }
                    }
                }
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Find in journal")
        .navigationDestination(for: String.self) { date in EntryView(date: date) }
        .task(id: query + "\(store.index.lineCount)") {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            hits = store.index.search(query)
        }
    }

    private func highlighted(_ line: String) -> AttributedString {
        var text = AttributedString(line.trimmingCharacters(in: .whitespaces))
        for term in SearchIndex.terms(query) {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let r = text[searchStart...].range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
                text[r].backgroundColor = .yellow.opacity(0.4)
                text[r].inlinePresentationIntent = .stronglyEmphasized
                searchStart = r.upperBound
            }
        }
        return text
    }
}
