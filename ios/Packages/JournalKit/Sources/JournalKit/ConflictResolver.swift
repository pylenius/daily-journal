import Foundation

public enum ConflictResolver {
    public struct Version: Sendable { public let modified: Date; public let text: String
        public init(modified: Date, text: String) { self.modified = modified; self.text = text } }

    /// Spec "Concurrency": newest body wins, but a checkbox that is `[x]` in any version stays `[x]`.
    /// Checked lines are matched by their unchecked form, so the newest body's line is what gets flipped.
    public static func merge(_ versions: [Version]) -> String {
        guard let newest = versions.max(by: { $0.modified < $1.modified }) else { return "" }
        var checkedElsewhere: Set<String> = []
        for v in versions {
            for line in v.text.components(separatedBy: "\n") {
                let l = line.hasSuffix("\r") ? String(line.dropLast()) : line
                if let cb = JournalParser.parseCheckbox(l), cb.checked, let unchecked = CheckboxToggler.flip(l) {
                    checkedElsewhere.insert(unchecked)
                }
            }
        }
        if checkedElsewhere.isEmpty { return newest.text }
        let newline = newest.text.contains("\r\n") ? "\r\n" : "\n"
        let merged = newest.text.components(separatedBy: newline).map { line -> String in
            if checkedElsewhere.contains(line), let flipped = CheckboxToggler.flip(line) { return flipped }
            return line
        }
        return merged.joined(separator: newline)
    }
}
