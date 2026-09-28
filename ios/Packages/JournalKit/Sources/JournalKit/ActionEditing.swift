import Foundation

/// Removes an action for good. See spec "Removing an action".
public enum ActionRemover {
    /// Deletes every `## Actions` / `## Carried over` checkbox line whose identity key is `identityKey`,
    /// together with its continuation lines. Returns nil when the text holds no such line. Every other byte is kept.
    public static func removing(identityKey: String, from text: String, fileName: String) -> String? {
        let entry = JournalParser.parse(text, fileName: fileName)
        let hits = entry.checkboxes.filter { $0.section.holdsActions && $0.identityKey == identityKey }
        guard !hits.isEmpty else { return nil }
        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        var lines = text.components(separatedBy: newline)
        for cb in hits.sorted(by: { $0.line > $1.line }) {
            lines.removeSubrange(cb.line ..< min(lines.count, cb.line + 1 + cb.continuation.count))
        }
        return lines.joined(separator: newline)
    }
}

/// Plain text for one action, to paste into a chat (e.g. Claude Code) and keep working on it.
public enum ActionExport {
    /// - Parameters:
    ///   - seenOn: dates the action appears on, oldest first (from the aggregator); empty falls back to its `(from …)` note.
    ///   - filePath: path of the entry file holding `item`, shown with the line number.
    public static func plainText(_ item: CheckboxLine, seenOn: [String] = [], filePath: String? = nil) -> String {
        let first = seenOn.first ?? item.carriedFrom ?? item.date
        var header = "Journal task (\(item.isChecked ? "done" : "open")"
        if first != item.date {
            header += ", since \(first)"
            if seenOn.count > 1 { header += ", carried \(seenOn.count) days" }
        }
        header += "; latest entry \(item.date))"
        var out = [header, item.raw.trimmingCharacters(in: .whitespaces)]
        out += item.continuation
        if let filePath { out.append("File: \(filePath):\(item.line + 1)") }
        return out.joined(separator: "\n")
    }
}
