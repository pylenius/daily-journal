import JournalKit
import SwiftUI

struct EntryView: View {
    @Environment(JournalStore.self) private var store
    @Environment(Navigation.self) private var nav
    let date: String
    @State private var detailsExpanded = true

    private var entry: JournalEntry? { store.entry(for: date) }

    var body: some View {
        if let entry {
            List {
                Text(entry.displayDate)
                    .font(.title2.weight(.semibold))
                    .listRowSeparator(.hidden)
                    .padding(.bottom, 4)
                if !entry.doneItems.isEmpty {
                    Section("Done") {
                        ForEach(entry.doneItems) { item in
                            DoneRow(item: item)
                        }
                    }
                }
                checkboxSection(entry, kind: .actions)
                checkboxSection(entry, kind: .carriedOver)
                ForEach(entry.sections.filter { if case .other = $0.kind { return true } else { return false } }, id: \.headingLine) { s in
                    Section(s.heading) {
                        MarkdownBlocksView(blocks: MarkdownRenderer.blocks(from: entry.lines[s.bodyLines].joined(separator: "\n"))) { line in
                            toggle(entry, sectionStart: s.bodyLines.lowerBound, relativeLine: line)
                        }
                    }
                }
                if let details = entry.section(.details) {
                    Section {
                        DisclosureGroup("Details", isExpanded: $detailsExpanded) {
                            MarkdownBlocksView(blocks: MarkdownRenderer.blocks(from: entry.lines[details.bodyLines].joined(separator: "\n"))) { line in
                                toggle(entry, sectionStart: details.bodyLines.lowerBound, relativeLine: line)
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .navigationTitle(entry.displayDate)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit", systemImage: "square.and.pencil") { nav.showEditor = true }
                        .help("Edit the Markdown (⌘E)")
                }
            }
        } else {
            ContentUnavailableView("Entry not loaded", systemImage: "icloud.and.arrow.down",
                                   description: Text("This day is still downloading or was removed."))
        }
    }

    @ViewBuilder
    private func checkboxSection(_ entry: JournalEntry, kind: SectionKind) -> some View {
        let items = entry.checkboxes.filter { $0.section == kind }
        if !items.isEmpty {
            Section(kind.title) {
                ForEach(items) { item in
                    ActionRow(item: item).contextMenu { ActionMenu(item: item) }
                }
            }
        } else if let s = entry.section(kind) {
            let body = entry.lines[s.bodyLines].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                Section(kind.title) { Text(MarkdownRenderer.inline(body)).foregroundStyle(.secondary) }
            }
        }
    }

    private func toggle(_ entry: JournalEntry, sectionStart: Int, relativeLine: Int) {
        let line = sectionStart + relativeLine
        guard entry.lines.indices.contains(line) else { return }
        if let cb = entry.checkboxes.first(where: { $0.line == line }) {
            Task { await store.toggle(cb) }
        }
    }
}

/// Right-click menu for a checkbox line.
struct ActionMenu: View {
    @Environment(JournalStore.self) private var store
    let item: CheckboxLine

    var body: some View {
        Button(item.isChecked ? "Mark Open" : "Mark Done") { Task { await store.toggle(item) } }
        Button("Copy as Task") { copy(store.plainText(item)) }
        Button("Copy Text") { copy(item.text) }
        if let reference = item.reference, !reference.isEmpty {
            Button("Copy Reference") { copy(reference) }
        }
        ForEach(item.urls, id: \.self) { url in
            Link("Open \(url.host() ?? url.absoluteString)", destination: url)
        }
        if item.section.holdsActions {
            Divider()
            Button("Remove Task…", role: .destructive) { confirmRemove() }
        }
    }

    /// Removal deletes the task from every day, so it asks first.
    private func confirmRemove() {
        let alert = NSAlert()
        alert.messageText = "Remove this task from every day?"
        alert.informativeText = "“\(item.text)” is deleted from Actions and Carried over in all entries. Use Mark Done for a task you finished."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await store.removeAction(item) }
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}
