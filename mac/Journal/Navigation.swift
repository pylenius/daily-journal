import Foundation
import JournalKit
import Observation

enum SidebarItem: Hashable {
    case days, actions, inbox
}

/// Window state shared by the views and the menu commands.
@MainActor
@Observable
final class Navigation {
    var section: SidebarItem = .days
    /// The day shown in the detail column.
    var selectedDate: String?
    var searchText = ""
    var showCapture = false
    var showEditor = false
    var showPicker = false

    init() {
        // Debug convenience: `-openDate YYYY-MM-DD` selects an entry straight away.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-openDate"), i + 1 < args.count { selectedDate = args[i + 1] }
    }

    /// Today's entry, or the newest one when today has none yet.
    func goToToday(_ store: JournalStore) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: Date())
        searchText = ""
        section = .days
        selectedDate = store.entry(for: today) != nil ? today : store.entries.first?.date
    }

    func show(_ date: String) { selectedDate = date }
}
