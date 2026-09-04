import Foundation

public enum JournalParser {
    /// `^\d{4}-\d{2}-\d{2}\.md$`
    static let fileRegex = try! NSRegularExpression(pattern: #"^(\d{4}-\d{2}-\d{2})\.md$"#)
    static let checkboxRegex = try! NSRegularExpression(pattern: #"^(\s*)- \[( |x|X)\] (.*)$"#)
    static let markerRegex = try! NSRegularExpression(pattern: #"\s+[—–-]{1,2}\s+(source|done):\s*"#)
    static let urlDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Returns the date if `fileName` is an entry file, else nil.
    public static func date(fromFileName fileName: String) -> String? {
        guard let m = fileRegex.firstMatch(in: fileName, range: NSRange(fileName.startIndex..., in: fileName)),
              let r = Range(m.range(at: 1), in: fileName) else { return nil }
        return String(fileName[r])
    }

    public static func parse(_ text: String, fileName: String) -> JournalEntry {
        let date = date(fromFileName: fileName) ?? fileName
        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        let lines = text.components(separatedBy: newline)

        var title = ""
        var sections: [Section] = []
        var current: (kind: SectionKind, heading: String, headingLine: Int, start: Int)? = nil
        var preambleStart = 0

        func close(at end: Int) {
            if let c = current {
                sections.append(Section(kind: c.kind, heading: c.heading, headingLine: c.headingLine, bodyLines: c.start..<end))
            } else if end > preambleStart,
                      lines[preambleStart..<end].contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                sections.append(Section(kind: .preamble, heading: "", headingLine: -1, bodyLines: preambleStart..<end))
            }
        }

        for (i, line) in lines.enumerated() {
            if line.hasPrefix("# ") && title.isEmpty && current == nil {
                title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                preambleStart = i + 1
            } else if line.hasPrefix("## ") {
                close(at: i)
                let heading = String(line.dropFirst(3))
                current = (SectionKind.recognise(heading), heading.trimmingCharacters(in: .whitespaces), i, i + 1)
            }
        }
        close(at: lines.count)

        var checkboxes: [CheckboxLine] = []
        var doneItems: [String] = []
        for section in sections {
            var i = section.bodyLines.lowerBound
            while i < section.bodyLines.upperBound {
                let line = lines[i]
                if let cb = parseCheckbox(line) {
                    var continuation: [String] = []
                    var j = i + 1
                    while j < section.bodyLines.upperBound, isContinuation(lines[j], indent: cb.indent) {
                        continuation.append(lines[j]); j += 1
                    }
                    checkboxes.append(makeCheckbox(cb, line: i, date: date, section: section.kind, raw: line, continuation: continuation))
                    i = j
                    continue
                }
                if section.kind == .done, line.hasPrefix("- ") {
                    doneItems.append(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                }
                i += 1
            }
        }

        return JournalEntry(date: date, fileName: fileName, title: title, lines: lines, newline: newline,
                            sections: sections, checkboxes: checkboxes, doneItems: doneItems)
    }

    struct RawCheckbox { let indent: Int; let checked: Bool; let body: String }

    static func parseCheckbox(_ line: String) -> RawCheckbox? {
        guard let m = checkboxRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let indentR = Range(m.range(at: 1), in: line), let markR = Range(m.range(at: 2), in: line),
              let bodyR = Range(m.range(at: 3), in: line) else { return nil }
        return RawCheckbox(indent: line[indentR].count, checked: line[markR] != " ", body: String(line[bodyR]))
    }

    static func isContinuation(_ line: String, indent: Int) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return false }
        let leading = line.prefix { $0 == " " || $0 == "\t" }.count
        if leading <= indent { return false }
        return parseCheckbox(line) == nil
    }

    static func makeCheckbox(_ cb: RawCheckbox, line: Int, date: String, section: SectionKind, raw: String, continuation: [String]) -> CheckboxLine {
        let body = cb.body
        var text = body
        var refKind: ReferenceKind? = nil
        var reference: String? = nil
        if let m = markerRegex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let whole = Range(m.range, in: body), let kindR = Range(m.range(at: 1), in: body) {
            text = String(body[..<whole.lowerBound])
            refKind = body[kindR] == "source" ? .source : .done
            reference = String(body[whole.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        text = text.trimmingCharacters(in: .whitespaces)
        let urls = urlDetector.matches(in: body, range: NSRange(body.startIndex..., in: body)).compactMap { $0.url }
        return CheckboxLine(id: "\(date)#\(line)", date: date, line: line, isChecked: cb.checked, text: text,
                            referenceKind: refKind, reference: reference, urls: urls, section: section, raw: raw,
                            continuation: continuation, identityKey: CheckboxLine.identityKey(for: text))
    }
}
