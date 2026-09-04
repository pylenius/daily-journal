import Foundation

public struct SearchHit: Sendable, Hashable, Identifiable {
    public var id: String { "\(date)#\(line)" }
    public let date: String
    public let line: Int
    public let lineText: String
    public let section: SectionKind
}

/// Case- and diacritic-insensitive substring search over every line of every entry.
/// Every query term must occur on the same line (AND). Small enough to rebuild on each folder change.
public struct SearchIndex: Sendable {
    struct Row: Sendable { let date: String; let line: Int; let text: String; let folded: String; let section: SectionKind }
    let rows: [Row]

    public init(entries: [JournalEntry]) {
        var rows: [Row] = []
        for e in entries {
            for s in e.sections {
                for i in s.bodyLines {
                    let t = e.lines[i]
                    if t.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                    rows.append(Row(date: e.date, line: i, text: t, folded: SearchIndex.fold(t), section: s.kind))
                }
            }
        }
        self.rows = rows
    }

    public var lineCount: Int { rows.count }

    public static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    public static func terms(_ query: String) -> [String] {
        query.split(whereSeparator: { $0.isWhitespace }).map { fold(String($0)) }.filter { !$0.isEmpty }
    }

    /// Hits newest day first, file order within a day.
    public func search(_ query: String, limit: Int = 200) -> [SearchHit] {
        let terms = SearchIndex.terms(query)
        guard !terms.isEmpty else { return [] }
        var hits: [SearchHit] = []
        for row in rows where terms.allSatisfy({ row.folded.contains($0) }) {
            hits.append(SearchHit(date: row.date, line: row.line, lineText: row.text, section: row.section))
        }
        hits.sort { a, b in a.date != b.date ? a.date > b.date : a.line < b.line }
        return Array(hits.prefix(limit))
    }
}
