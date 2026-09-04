import JournalKit
import SwiftUI

struct DayListView: View {
    @Environment(JournalStore.self) private var store
    @Binding var path: [String]

    private var months: [(String, [JournalEntry])] {
        let grouped = Dictionary(grouping: store.entries) { String($0.date.prefix(7)) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!) }
    }

    var body: some View {
        List {
            if !store.placeholders.isEmpty {
                Section {
                    Label("\(store.placeholders.count) entries still downloading", systemImage: "icloud.and.arrow.down")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(months, id: \.0) { month, entries in
                Section(monthTitle(month)) {
                    ForEach(entries) { entry in
                        NavigationLink(value: entry.date) {
                            DayRow(entry: entry)
                        }
                    }
                }
            }
            if store.entries.isEmpty && !store.isLoading {
                ContentUnavailableView("No entries yet", systemImage: "doc.text",
                                       description: Text("Run the daily-journal skill on your Mac; entries appear here once they sync."))
            }
        }
        .navigationTitle("Journal")
        .navigationDestination(for: String.self) { date in EntryView(date: date) }
        .onAppear {
            // Debug/simulator convenience: `-openDate YYYY-MM-DD` opens an entry straight away.
            let args = ProcessInfo.processInfo.arguments
            if path.isEmpty, let i = args.firstIndex(of: "-openDate"), i + 1 < args.count { path = [args[i + 1]] }
        }
        .refreshable { await store.reload() }
        .overlay(alignment: .bottom) {
            if store.isLoading { ProgressView().padding(8).background(.thinMaterial, in: Capsule()).padding() }
        }
    }

    private func monthTitle(_ ym: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        guard let d = f.date(from: ym) else { return ym }
        let out = DateFormatter(); out.dateFormat = "LLLL yyyy"
        return out.string(from: d)
    }
}

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
