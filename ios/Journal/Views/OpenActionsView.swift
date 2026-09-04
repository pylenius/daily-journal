import JournalKit
import SwiftUI

struct OpenActionsView: View {
    @Environment(JournalStore.self) private var store

    private var byDay: [(String, [AggregatedAction])] {
        let grouped = Dictionary(grouping: store.openActions) { $0.latest.date }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!.sorted { $0.latest.line < $1.latest.line }) }
    }

    var body: some View {
        List {
            ForEach(byDay, id: \.0) { date, actions in
                Section {
                    ForEach(actions) { action in
                        ActionRow(item: action.latest, subtitle: action.seenOn.count > 1 ? "since \(action.firstSeen) · \(action.seenOn.count) days" : nil)
                            .contextMenu {
                                NavigationLink("Open \(date)", value: date)
                            }
                    }
                } header: {
                    NavigationLink(value: date) {
                        HStack { Text(store.entry(for: date)?.displayDate ?? date); Spacer(); Image(systemName: "chevron.right").font(.caption) }
                    }
                }
            }
            if store.openActions.isEmpty {
                ContentUnavailableView("Nothing open", systemImage: "checkmark.circle", description: Text("Every action in the journal is ticked."))
            }
        }
        .navigationTitle("Open actions")
        .navigationDestination(for: String.self) { date in EntryView(date: date) }
        .refreshable { await store.reload() }
    }
}
