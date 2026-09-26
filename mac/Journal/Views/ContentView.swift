import JournalKit
import SwiftUI

struct ContentView: View {
    @Environment(JournalStore.self) private var store
    @Environment(Navigation.self) private var nav
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var nav = nav
        Group {
            switch store.folderState {
            case .notChosen:
                WelcomeView()
            case .unreachable(let message):
                ContentUnavailableView {
                    Label("Journal folder unavailable", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { Task { await store.reload() } }
                    Button("Choose another folder…") { nav.showPicker = true }
                }
            case .ready:
                split
            }
        }
        .fileImporter(isPresented: $nav.showPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { store.chooseFolder(url) }
        }
        .sheet(isPresented: $nav.showCapture) { CaptureView() }
        .sheet(isPresented: $nav.showEditor) {
            if let date = nav.selectedDate { EditView(date: date) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.scheduleReload() }
        }
        .onChange(of: store.entries.first?.date) { _, newest in
            if nav.selectedDate == nil { nav.selectedDate = newest }
        }
        .alert("Something went wrong", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var split: some View {
        @Bindable var nav = nav
        return NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 240)
        } content: {
            Group {
                if !nav.searchText.isEmpty {
                    SearchView(query: nav.searchText)
                } else {
                    switch nav.section {
                    case .days: DayListView()
                    case .actions: OpenActionsView()
                    case .inbox: InboxView()
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 480)
        } detail: {
            if let date = nav.selectedDate {
                EntryView(date: date).id(date)
            } else {
                ContentUnavailableView("No day selected", systemImage: "calendar")
            }
        }
        .searchable(text: $nav.searchText, placement: .sidebar, prompt: "Find in journal")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Quick Capture", systemImage: "plus") { nav.showCapture = true }
                    .help("Add a note or action to the inbox (⇧⌘N)")
            }
        }
    }
}

struct SidebarView: View {
    @Environment(JournalStore.self) private var store
    @Environment(Navigation.self) private var nav

    var body: some View {
        List(selection: Binding(get: { nav.searchText.isEmpty ? nav.section : nil },
                                set: { if let s = $0 { nav.section = s; nav.searchText = "" } })) {
            Label("Days", systemImage: "calendar")
                .tag(SidebarItem.days)
            Label("Actions", systemImage: "checklist")
                .badge(store.openActions.count)
                .tag(SidebarItem.actions)
            Label("Inbox", systemImage: "tray")
                .badge(store.inbox.count)
                .tag(SidebarItem.inbox)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 6) {
                if store.isLoading { ProgressView().controlSize(.small) }
                Text(store.folderName).lineLimit(1).truncationMode(.middle)
            }
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
    }
}

struct WelcomeView: View {
    @Environment(Navigation.self) private var nav

    var body: some View {
        ContentUnavailableView {
            Label("Choose your journal folder", systemImage: "folder.badge.plus")
        } description: {
            Text("Pick the folder where your daily journal files (YYYY-MM-DD.md) are written — for example the Journal folder in iCloud Drive. The app reads and updates those files in place.")
        } actions: {
            Button("Choose Folder…") { nav.showPicker = true }.buttonStyle(.borderedProminent)
        }
    }
}
