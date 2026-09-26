import SwiftUI

struct SettingsView: View {
    @Environment(JournalStore.self) private var store
    @State private var showPicker = false

    var body: some View {
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
                HStack {
                    Button("Choose Another Folder…") { showPicker = true }
                    Button("Reload Now") { Task { await store.reload() } }
                    Spacer()
                    Button("Forget Folder", role: .destructive) { store.forgetFolder() }
                }
            }
            Section("About") {
                Text("Journal reads the Markdown files written by the daily-journal Claude Code plugin. Ticking a box edits the file in place; captures land in the inbox folder for the next run.")
                    .foregroundStyle(.secondary)
                Link("Source code and format spec", destination: URL(string: "https://github.com/pylenius/daily-journal")!)
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { store.chooseFolder(url) }
        }
    }
}
