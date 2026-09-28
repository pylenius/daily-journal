import JournalKit
import SwiftUI

/// A checkbox line: tap the circle to toggle, links open in the browser, other references are copyable.
struct ActionRow: View {
    @Environment(JournalStore.self) private var store
    let item: CheckboxLine
    var subtitle: String? = nil
    #if os(macOS)
    @State private var hovering = false
    @State private var copied = false
    #endif

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                Task { await store.toggle(item) }
            } label: {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isChecked ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isChecked ? "Mark open" : "Mark done")
            VStack(alignment: .leading, spacing: 4) {
                Text(MarkdownRenderer.inline(item.text))
                    .strikethrough(item.isChecked, color: .secondary)
                    .foregroundStyle(item.isChecked ? .secondary : .primary)
                if let reference = item.reference, !reference.isEmpty {
                    Text(MarkdownRenderer.autolinked(reference))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                ForEach(item.continuation, id: \.self) { line in
                    Text(MarkdownRenderer.inline(line.trimmingCharacters(in: .whitespaces)))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let subtitle {
                    Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            #if os(macOS)
            Spacer(minLength: 0)
            copyButton
            #endif
        }
        .padding(.vertical, 2)
        #if os(macOS)
        .onHover { hovering = $0 }
        #endif
    }

    #if os(macOS)
    /// Copies the task as plain text to paste into a chat. Shown while the pointer is over the row.
    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(store.plainText(item), forType: .string)
            copied = true
            Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help("Copy as task")
        .accessibilityLabel("Copy as task")
        .opacity(hovering || copied ? 1 : 0)
    }
    #endif
}
