import Foundation

public enum CheckboxToggler {
    public enum Failure: Error, Equatable, Sendable {
        /// The expected line is no longer in the file (or is ambiguous).
        case lineNotFound
        case notACheckbox
    }

    /// Flip `[ ]`↔`[x]` on one line, preserving every other byte and the newline style.
    ///
    /// The line is located at `line` if its content still equals `expectedRaw`; otherwise the first line
    /// equal to `expectedRaw` is used, provided it is unique. Returns the whole new file text.
    public static func toggle(in text: String, line: Int, expectedRaw: String) throws(Failure) -> String {
        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        var lines = text.components(separatedBy: newline)
        var index = line
        if !(lines.indices.contains(index) && lines[index] == expectedRaw) {
            let matches = lines.indices.filter { lines[$0] == expectedRaw }
            guard matches.count == 1 else { throw .lineNotFound }
            index = matches[0]
        }
        guard let flipped = flip(lines[index]) else { throw .notACheckbox }
        lines[index] = flipped
        return lines.joined(separator: newline)
    }

    /// The single line with its box flipped, or nil if it is not a checkbox line.
    public static func flip(_ line: String) -> String? {
        guard JournalParser.parseCheckbox(line) != nil else { return nil }
        if let r = line.range(of: "- [ ] ") { return line.replacingCharacters(in: r, with: "- [x] ") }
        if let r = line.range(of: "- [x] ") { return line.replacingCharacters(in: r, with: "- [ ] ") }
        if let r = line.range(of: "- [X] ") { return line.replacingCharacters(in: r, with: "- [ ] ") }
        return nil
    }
}
