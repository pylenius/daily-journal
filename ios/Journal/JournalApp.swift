import SwiftUI

@main
struct JournalApp: App {
    @State private var store = JournalStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
