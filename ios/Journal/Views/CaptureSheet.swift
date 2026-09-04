import JournalKit
import SwiftUI

struct CaptureSheet: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var kind: CaptureKind = .action
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Picker("Kind", selection: $kind) {
                    Text("Action").tag(CaptureKind.action)
                    Text("Note").tag(CaptureKind.note)
                }
                .pickerStyle(.segmented)
                TextEditor(text: $text)
                    .frame(minHeight: 140)
                    .focused($focused)
                Text(kind == .action
                     ? "Becomes an open action in the next journal entry."
                     : "Folded into the next entry's Done or Details.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Quick capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let body = text
                        Task { await store.capture(kind: kind, body: body); dismiss() }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }
}
