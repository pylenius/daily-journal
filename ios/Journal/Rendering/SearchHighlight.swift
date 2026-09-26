import JournalKit
import SwiftUI

extension MarkdownRenderer {
    /// A search hit's line with every query term marked.
    static func highlighted(_ line: String, query: String) -> AttributedString {
        var text = AttributedString(line.trimmingCharacters(in: .whitespaces))
        for term in SearchIndex.terms(query) {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let r = text[searchStart...].range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
                text[r].backgroundColor = .yellow.opacity(0.4)
                text[r].inlinePresentationIntent = .stronglyEmphasized
                searchStart = r.upperBound
            }
        }
        return text
    }
}
