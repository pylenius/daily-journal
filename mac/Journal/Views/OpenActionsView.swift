import JournalKit
import SwiftUI

struct OpenActionsView: View {
    @Environment(JournalStore.self) private var store
    @Environment(Navigation.self) private var nav
    @State private var selection: String?

    private var byDay: [(String, [AggregatedAction])] {
        let grouped = Dictionary(grouping: store.openActions) { $0.latest.date }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!.sorted { $0.latest.line < $1.latest.line }) }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(byDay, id: \.0) { date, actions in
                Section(store.entry(for: date)?.displayDate ?? date) {
                    ForEach(actions) { action in
                        ActionRow(item: action.latest, subtitle: action.seenOn.count > 1 ? "since \(action.firstSeen) · \(action.seenOn.count) days" : nil)
                            .tag(action.id)
                            .contextMenu {
                                ActionMenu(item: action.latest)
                                Divider()
                                Button("Show \(date)") { nav.show(date) }
                            }
                    }
                }
            }
        }
        .listStyle(.inset)
        .id(byDay.map(\.0)) // see DayListView: rows in a newly inserted Section keep a stale height
        .overlay {
            if store.openActions.isEmpty {
                ContentUnavailableView("Nothing open", systemImage: "checkmark.circle", description: Text("Every action in the journal is ticked."))
            }
        }
        .onChange(of: selection) { _, id in
            if let action = store.openActions.first(where: { $0.id == id }) { nav.show(action.latest.date) }
        }
        .navigationTitle("Open Actions")
    }
}
