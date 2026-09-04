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

    private var changedOnMac: Bool { loadedHash != nil && store.hashes[date] != loadedHash }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if changedOnMac {
                    Label("This entry changed on another device while you were editing.", systemImage: "exclamationmark.triangle")
                        .font(.footnote).padding(8).frame(maxWidth: .infinity).background(.yellow.opacity(0.25))
                }
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 4)
            }
            .navigationTitle(date)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save(force: false) } } }
            }
            .onAppear {
                if let entry = store.entry(for: date) {
                    text = entry.lines.joined(separator: entry.newline)
                    loadedHash = store.hashes[date]
                }
            }
            .confirmationDialog("The entry changed on another device.", isPresented: $conflict, titleVisibility: .visible) {
                Button("Overwrite with my version", role: .destructive) { Task { await save(force: true) } }
                Button("Copy my text and discard") { UIPasteboard.general.string = text; dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .alert("Could not save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK") {}
            } message: { Text(saveError ?? "") }
        }
        .interactiveDismissDisabled(text != (store.entry(for: date).map { $0.lines.joined(separator: $0.newline) } ?? text))
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
