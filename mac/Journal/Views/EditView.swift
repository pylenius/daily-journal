import JournalKit
import SwiftUI

/// Raw Markdown editor with a stale-file guard.
struct EditView: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let date: String
    @State private var text = ""
    @State private var loadedHash: String?
    @State private var conflict = false
    @State private var saveError: String?

    private var changedElsewhere: Bool { loadedHash != nil && store.hashes[date] != loadedHash }

    var body: some View {
        VStack(spacing: 0) {
            if changedElsewhere {
                Label("This entry changed on disk while you were editing.", systemImage: "exclamationmark.triangle")
                    .font(.callout).padding(8).frame(maxWidth: .infinity).background(.yellow.opacity(0.25))
            }
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .scrollContentBackground(.hidden)
                .padding(8)
            Divider()
            HStack {
                Text(date).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { Task { await save(force: false) } }
                    .keyboardShortcut("s")
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .frame(minWidth: 700, idealWidth: 820, minHeight: 500, idealHeight: 680)
        .onAppear {
            if let entry = store.entry(for: date) {
                text = entry.lines.joined(separator: entry.newline)
                loadedHash = store.hashes[date]
            }
        }
        .confirmationDialog("The entry changed on disk.", isPresented: $conflict, titleVisibility: .visible) {
            Button("Overwrite with My Version", role: .destructive) { Task { await save(force: true) } }
            Button("Copy My Text and Discard") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                dismiss()
            }
            Button("Keep Editing", role: .cancel) {}
        }
        .alert("Could not save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") {}
        } message: { Text(saveError ?? "") }
    }

    private func save(force: Bool) async {
        do {
            try await store.save(date: date, text: text, expectedHash: force ? nil : loadedHash)
            dismiss()
        } catch JournalFileIO.IOError.changedSinceLoad {
            conflict = true
        } catch {
            saveError = error.localizedDescription
        }
    }
}
