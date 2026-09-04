import JournalKit
import SwiftUI

struct EntryView: View {
    @Environment(JournalStore.self) private var store
    let date: String
    @State private var showEditor = false
    @State private var detailsExpanded = false

    private var entry: JournalEntry? { store.entry(for: date) }

    var body: some View {
        Group {
            if let entry {
                List {
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
                .listStyle(.insetGrouped)
                .navigationTitle(entry.displayDate)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit", systemImage: "square.and.pencil") { showEditor = true }
                    }
                }
                .sheet(isPresented: $showEditor) { EditView(date: date) }
            } else {
                ContentUnavailableView("Entry not loaded", systemImage: "icloud.and.arrow.down",
                                       description: Text("This day is still downloading or was removed."))
            }
        }
    }

    @ViewBuilder
    private func checkboxSection(_ entry: JournalEntry, kind: SectionKind) -> some View {
        let items = entry.checkboxes.filter { $0.section == kind }
        if !items.isEmpty {
            Section(kind.title) {
                ForEach(items) { item in ActionRow(item: item) }
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
