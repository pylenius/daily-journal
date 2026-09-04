import JournalKit
import SwiftUI

struct ContentView: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var showCapture = false
    @State private var showSettings = false
    @State private var showPicker = false
    @State private var dayPath: [String] = []

    var body: some View {
        Group {
            switch store.folderState {
            case .notChosen:
                WelcomeView(showPicker: $showPicker)
            case .unreachable(let message):
                ContentUnavailableView {
                    Label("Journal folder unavailable", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { Task { await store.reload() } }
                    Button("Choose another folder") { showPicker = true }
                }
            case .ready:
                mainTabs
            }
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { store.chooseFolder(url) }
        }
        .sheet(isPresented: $showCapture) { CaptureSheet() }
        .sheet(isPresented: $showSettings) { SettingsView(showPicker: $showPicker) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.scheduleReload() }
        }
        .alert("Something went wrong", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var mainTabs: some View {
        TabView {
            Tab("Days", systemImage: "calendar") {
                NavigationStack(path: $dayPath) { DayListView(path: $dayPath).toolbar { toolbar } }
            }
            Tab("Actions", systemImage: "checklist") {
                NavigationStack { OpenActionsView().toolbar { toolbar } }
            }
            .badge(store.openActions.count)
            Tab("Search", systemImage: "magnifyingglass", role: .search) {
                NavigationStack { SearchView().toolbar { toolbar } }
            }
            Tab("Inbox", systemImage: "tray") {
                NavigationStack { InboxView().toolbar { toolbar } }
            }
            .badge(store.inbox.count)
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showCapture = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("Quick capture")
        }
    }
}

struct WelcomeView: View {
    @Binding var showPicker: Bool

    var body: some View {
        ContentUnavailableView {
            Label("Choose your journal folder", systemImage: "folder.badge.plus")
        } description: {
            Text("Pick the folder where your daily journal files (YYYY-MM-DD.md) are written — for example the Journal folder in iCloud Drive. The app reads and updates those files in place.")
        } actions: {
            Button("Choose folder…") { showPicker = true }.buttonStyle(.borderedProminent)
        }
    }
}
