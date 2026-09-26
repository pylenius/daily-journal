import JournalKit
import SwiftUI

struct DayListView: View {
    @Environment(JournalStore.self) private var store
    @Environment(Navigation.self) private var nav

    private var months: [(String, [JournalEntry])] {
        let grouped = Dictionary(grouping: store.entries) { String($0.date.prefix(7)) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!) }
    }

    var body: some View {
        List(selection: Binding(get: { nav.selectedDate }, set: { nav.selectedDate = $0 })) {
            if !store.placeholders.isEmpty {
                Label("\(store.placeholders.count) entries still downloading", systemImage: "icloud.and.arrow.down")
                    .foregroundStyle(.secondary)
            }
            ForEach(months, id: \.0) { month, entries in
                Section(monthTitle(month)) {
                    ForEach(entries) { entry in
                        DayRow(entry: entry).tag(entry.date)
                    }
                }
            }
        }
        .listStyle(.inset)
        // macOS List keeps a one-line height for rows that arrive inside a newly inserted Section; rebuild when the months change.
        .id(months.map(\.0))
        .overlay {
            if store.entries.isEmpty && !store.isLoading {
                ContentUnavailableView("No entries yet", systemImage: "doc.text",
                                       description: Text("Run the daily-journal skill; entries appear here once they are written."))
            }
        }
        .navigationTitle("Days")
    }

    private func monthTitle(_ ym: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        guard let d = f.date(from: ym) else { return ym }
        let out = DateFormatter(); out.dateFormat = "LLLL yyyy"
        return out.string(from: d)
    }
}
