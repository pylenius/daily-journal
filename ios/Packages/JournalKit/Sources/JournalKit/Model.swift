import Foundation

/// Which recognised section a line belongs to. See spec/JOURNAL_FORMAT.md.
public enum SectionKind: Sendable, Hashable {
    case done
    case actions
    case carriedOver
    case details
    case other(String)
    case preamble

    /// True for the two sections whose checkboxes count as actions.
    public var holdsActions: Bool { self == .actions || self == .carriedOver }

    static func recognise(_ heading: String) -> SectionKind {
        switch heading.trimmingCharacters(in: .whitespaces).lowercased() {
        case "done": return .done
        case "actions": return .actions
        case "carried over": return .carriedOver
        case "details": return .details
        default: return .other(heading.trimmingCharacters(in: .whitespaces))
        }
    }

    public var title: String {
        switch self {
        case .done: return "Done"
        case .actions: return "Actions"
        case .carriedOver: return "Carried over"
        case .details: return "Details"
        case .other(let s): return s
        case .preamble: return ""
        }
    }
}

/// A level-2 section of an entry. `bodyLines` are 0-based line indexes after the heading, up to the next `##`.
public struct Section: Sendable, Hashable {
    public let kind: SectionKind
    public let heading: String
    public let headingLine: Int
    public let bodyLines: Range<Int>

    public init(kind: SectionKind, heading: String, headingLine: Int, bodyLines: Range<Int>) {
        self.kind = kind; self.heading = heading; self.headingLine = headingLine; self.bodyLines = bodyLines
    }
}

/// How the trailing reference on a checkbox line was marked.
public enum ReferenceKind: Sendable, Hashable {
    case source
    case done
}

/// One `- [ ]` / `- [x]` line.
public struct CheckboxLine: Sendable, Hashable, Identifiable {
    /// `"<date>#<line>"` — unique within a folder.
    public let id: String
    public let date: String
    /// 0-based line index into the file.
    public let line: Int
    public let isChecked: Bool
    /// Text between `] ` and the ` — source:` / ` — done:` marker.
    public let text: String
    public let referenceKind: ReferenceKind?
    /// Everything after the marker, trimmed. Nil when there is no marker.
    public let reference: String?
    /// URLs found anywhere on the line (reference first, then text).
    public let urls: [URL]
    public let section: SectionKind
    /// The exact original line, used to relocate it before toggling.
    public let raw: String
    /// Indented lines that follow this item.
    public let continuation: [String]
    /// Normalised identity across days. See spec "Action identity across days".
    public let identityKey: String

    /// The `(from YYYY-MM-DD)` note, if the text carries one.
    public var carriedFrom: String? {
        guard let m = CheckboxLine.fromRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    static let fromRegex = try! NSRegularExpression(pattern: #"\(from (\d{4}-\d{2}-\d{2})\)\s*$"#)

    public static func identityKey(for text: String) -> String {
        var t = text
        if let m = fromRegex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)), let r = Range(m.range, in: t) {
            t.removeSubrange(r)
        }
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        while let last = t.last, ".;:".contains(last) { t.removeLast() }
        return t
    }
}

/// A parsed journal entry. Immutable; re-parse after any write.
public struct JournalEntry: Sendable, Hashable, Identifiable {
    public var id: String { date }
    /// `YYYY-MM-DD`, from the file name.
    public let date: String
    public let fileName: String
    public let title: String
    public let lines: [String]
    /// `"\n"` or `"\r\n"`, whatever the file used (defaults to `"\n"`).
    public let newline: String
    public let sections: [Section]
    public let checkboxes: [CheckboxLine]
    /// Plain bullets under `## Done`.
    public let doneItems: [DoneItem]

    public init(date: String, fileName: String, title: String, lines: [String], newline: String,
                sections: [Section], checkboxes: [CheckboxLine], doneItems: [DoneItem]) {
        self.date = date; self.fileName = fileName; self.title = title; self.lines = lines; self.newline = newline
        self.sections = sections; self.checkboxes = checkboxes; self.doneItems = doneItems
    }

    /// Checkboxes in `## Actions` and `## Carried over`.
    public var actions: [CheckboxLine] { checkboxes.filter { $0.section.holdsActions } }
    public var openActionCount: Int { actions.filter { !$0.isChecked }.count }

    public func section(_ kind: SectionKind) -> Section? { sections.first { $0.kind == kind } }

    /// Raw text of a section body (without the heading).
    public func text(of kind: SectionKind) -> String? {
        guard let s = section(kind) else { return nil }
        return lines[s.bodyLines].joined(separator: newline)
    }

    /// Weekday-aware display title, falling back to the date.
    public var displayDate: String {
        JournalEntry.dateFormatter.date(from: date).map { JournalEntry.displayFormatter.string(from: $0) } ?? date
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .iso8601); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"; return f
    }()
    static let displayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .full; f.timeStyle = .none; return f
    }()
}
