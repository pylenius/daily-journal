import SwiftUI

struct SettingsView: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var showPicker: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Journal folder") {
                    LabeledContent("Folder", value: store.folderName)
                    if let last = store.lastRefresh {
                        LabeledContent("Last refresh") { Text(last, format: .dateTime.hour().minute().second()) }
                    }
                    LabeledContent("Entries", value: "\(store.entries.count)")
                    if store.bookmarkIsStale {
                        Label("Access to the folder is stale — choose it again.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                    if store.isSampleJournal {
                        Label("This is the made-up sample journal. Choose your own folder to use the app for real.", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Choose another folder…") { dismiss(); showPicker = true }
                    Button("Reload now") { Task { await store.reload() } }
                    Button("Forget folder", role: .destructive) { store.forgetFolder(); dismiss() }
                    if !store.isSampleJournal {
                        Button("Open the sample journal") { store.useSampleJournal(); dismiss() }
                    }
                }
                Section("About") {
                    Text("Journal reads the Markdown files written by the daily-journal Claude Code plugin. Ticking a box edits the file in place; captures land in the inbox folder for the next run.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("Source code and format spec", destination: URL(string: "https://github.com/pylenius/daily-journal")!)
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
