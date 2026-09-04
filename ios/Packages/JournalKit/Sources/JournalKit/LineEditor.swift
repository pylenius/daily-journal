import Foundation

/// Single-line edits that keep every other byte of the file intact.
public enum LineEditor {
    public typealias Failure = CheckboxToggler.Failure

    /// Locates the line (at `line` if it still reads `expectedRaw`, else by unique text match) and replaces it
    /// with `replacement`; `nil` deletes the line. Returns the whole new file text.
    public static func replace(in text: String, line: Int, expectedRaw: String, with replacement: String?) throws(Failure) -> String {
        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        var lines = text.components(separatedBy: newline)
        var index = line
        if !(lines.indices.contains(index) && lines[index] == expectedRaw) {
            let matches = lines.indices.filter { lines[$0] == expectedRaw }
            guard matches.count == 1 else { throw .lineNotFound }
            index = matches[0]
        }
        if let replacement { lines[index] = replacement } else { lines.remove(at: index) }
        return lines.joined(separator: newline)
    }

    /// `- text` ↔ `- **text**` (a highlighted Done item). Nil if the line is not a plain bullet.
    public static func highlightToggled(_ line: String) -> String? {
        guard let item = DoneItem.parse(line) else { return nil }
        let prefix = line.prefix(item.bulletPrefixLength)
        return item.isHighlighted ? "\(prefix)\(item.text)" : "\(prefix)**\(item.text)**"
    }
}

/// A plain bullet under `## Done`.
public struct DoneItem: Sendable, Hashable, Identifiable {
    public var id: String { "\(date)#\(line)" }
    public let date: String
    /// 0-based line index into the file.
    public let line: Int
    public let raw: String
    /// Text without the bullet and without a `**…**` highlight wrapper.
    public let text: String
    public let isHighlighted: Bool
    let bulletPrefixLength: Int

    static func parse(_ line: String, date: String = "", lineNumber: Int = 0) -> DoneItem? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        let rest = line.dropFirst(indent.count)
        guard rest.hasPrefix("- ") || rest.hasPrefix("* ") else { return nil }
        if JournalParser.parseCheckbox(line) != nil { return nil }
        var body = String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        var highlighted = false
        if body.hasPrefix("**"), body.hasSuffix("**"), body.count > 4 {
            let inner = String(body.dropFirst(2).dropLast(2))
            if !inner.contains("**") { body = inner; highlighted = true }
        }
        return DoneItem(date: date, line: lineNumber, raw: line, text: body, isHighlighted: highlighted, bulletPrefixLength: indent.count + 2)
    }
}
