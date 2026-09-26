import SwiftUI

@main
struct JournalMacApp: App {
    @State private var store = JournalStore()
    @State private var nav = Navigation()

    var body: some Scene {
        Window("Journal", id: "main") {
            ContentView()
                .environment(store)
                .environment(nav)
                .frame(minWidth: 820, minHeight: 480)
        }
        .commands { JournalCommands(store: store, nav: nav) }

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}
