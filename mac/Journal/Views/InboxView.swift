import JournalKit
import SwiftUI

/// Captures waiting in `inbox/` for the next journal run.
struct InboxView: View {
    @Environment(JournalStore.self) private var store
    @Environment(Navigation.self) private var nav

    var body: some View {
        List {
            if !store.inbox.isEmpty {
                Section {
                    ForEach(store.inbox) { capture in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: capture.kind == .action ? "circle" : "note.text").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(MarkdownRenderer.inline(capture.body)).textSelection(.enabled)
                                HStack(spacing: 6) {
                                    if let created = capture.created { Text(created, format: .dateTime.day().month().hour().minute()) }
                                    if let device = capture.device { Text("· \(device)") }
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } footer: {
                    Text("Waiting for the next journal run.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.inset)
        .id(store.inbox.isEmpty) // see DayListView: rows in a newly inserted Section keep a stale height
        .overlay {
            if store.inbox.isEmpty {
                ContentUnavailableView {
                    Label("Inbox is empty", systemImage: "tray")
                } description: {
                    Text("Captures wait here until the next journal run folds them into an entry.")
                } actions: {
                    Button("New Capture…") { nav.showCapture = true }
                }
            }
        }
        .navigationTitle("Inbox")
    }
}
