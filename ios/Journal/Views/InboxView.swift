import JournalKit
import SwiftUI

/// Captures waiting in `inbox/` for the next journal run on the Mac.
struct InboxView: View {
    @Environment(JournalStore.self) private var store

    var body: some View {
        List {
            if store.inbox.isEmpty {
                ContentUnavailableView("Inbox is empty", systemImage: "tray",
                                       description: Text("Captures you add with + wait here until the Mac folds them into a journal entry."))
            } else {
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
                    }
                } footer: {
                    Text("Pending until the next /daily-journal run. Only the Mac archives inbox files.")
                }
            }
        }
        .navigationTitle("Inbox")
        .refreshable { await store.reload() }
    }
}
