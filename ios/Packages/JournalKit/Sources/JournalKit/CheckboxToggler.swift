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
        guard let flipped = flip(expectedRaw) else { throw .notACheckbox }
        return try LineEditor.replace(in: text, line: line, expectedRaw: expectedRaw, with: flipped)
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
