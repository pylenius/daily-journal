import SwiftUI

struct JournalCommands: Commands {
    let store: JournalStore
    let nav: Navigation

    private var ready: Bool {
        if case .ready = store.folderState { return true }
        return false
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Capture…") { nav.showCapture = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!ready)
            Button("Choose Journal Folder…") { nav.showPicker = true }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }
        CommandMenu("Journal") {
            Button("Go to Today") { nav.goToToday(store) }
                .keyboardShortcut("t")
                .disabled(!ready)
            Button("Edit Entry…") { nav.showEditor = true }
                .keyboardShortcut("e")
                .disabled(nav.selectedDate.flatMap { store.entry(for: $0) } == nil)
            Divider()
            Button("Reload") { Task { await store.reload() } }
                .keyboardShortcut("r")
                .disabled(!ready)
        }
    }
}
