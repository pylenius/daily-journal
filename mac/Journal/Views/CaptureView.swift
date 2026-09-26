import JournalKit
import SwiftUI

struct CaptureView: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var kind: CaptureKind = .action
    @State private var text = ""
    @FocusState private var focused: Bool

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Capture").font(.headline)
            Picker("Kind", selection: $kind) {
                Text("Action").tag(CaptureKind.action)
                Text("Note").tag(CaptureKind.note)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 120)
                .focused($focused)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            Text(kind == .action
                 ? "Becomes an open action in the next journal entry."
                 : "Folded into the next entry's Done or Details.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let body = text
                    Task { await store.capture(kind: kind, body: body); dismiss() }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { focused = true }
    }
}
