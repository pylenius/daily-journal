import Foundation
import Markdown
import SwiftUI

/// A block of rendered Markdown. Built once per entry from swift-markdown's AST.
indirect enum RenderBlock: Identifiable {
    case heading(level: Int, text: AttributedString, id: Int)
    case paragraph(AttributedString, id: Int)
    case list(items: [RenderListItem], ordered: Bool, id: Int)
    case code(String, id: Int)
    case quote([RenderBlock], id: Int)
    case rule(id: Int)
    case table(rows: [[AttributedString]], id: Int)
    case raw(String, id: Int)

    var id: Int {
        switch self {
        case .heading(_, _, let id), .paragraph(_, let id), .list(_, _, let id), .code(_, let id),
             .quote(_, let id), .rule(let id), .table(_, let id), .raw(_, let id):
            return id
        }
    }
}

struct RenderListItem: Identifiable {
    let id: Int
    /// nil = plain bullet; otherwise the checkbox state.
    let checked: Bool?
    /// 0-based line index into the source text handed to the renderer.
    let sourceLine: Int?
    let blocks: [RenderBlock]
}

enum MarkdownRenderer {
    static let urlDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func blocks(from text: String) -> [RenderBlock] {
        let doc = Document(parsing: text, options: [])
        var counter = 0
        return convert(doc.blockChildren, &counter)
    }

    /// Inline-only rendering for a single line (action text, done items).
    static func inline(_ text: String) -> AttributedString {
        let doc = Document(parsing: text, options: [])
        var out = AttributedString()
        for block in doc.blockChildren {
            if let p = block as? Paragraph { out.append(inlines(p.inlineChildren)) }
            else { out.append(AttributedString(block.format())) }
        }
        return out
    }

    private static func convert(_ children: some Sequence<BlockMarkup>, _ counter: inout Int) -> [RenderBlock] {
        var out: [RenderBlock] = []
        for child in children {
            counter += 1
            let id = counter
            switch child {
            case let h as Heading:
                out.append(.heading(level: h.level, text: inlines(h.inlineChildren), id: id))
            case let p as Paragraph:
                out.append(.paragraph(inlines(p.inlineChildren), id: id))
            case let l as UnorderedList:
                out.append(.list(items: items(l.listItems, &counter), ordered: false, id: id))
            case let l as OrderedList:
                out.append(.list(items: items(l.listItems, &counter), ordered: true, id: id))
            case let c as CodeBlock:
                out.append(.code(c.code.trimmingCharacters(in: .newlines), id: id))
            case let q as BlockQuote:
                out.append(.quote(convert(q.blockChildren, &counter), id: id))
            case is ThematicBreak:
                out.append(.rule(id: id))
            case let t as Markdown.Table:
                var rows: [[AttributedString]] = []
                rows.append(t.head.cells.map { inlines($0.inlineChildren) })
                for row in t.body.rows { rows.append(row.cells.map { inlines($0.inlineChildren) }) }
                out.append(.table(rows: rows, id: id))
            case let h as HTMLBlock:
                out.append(.raw(h.rawHTML, id: id))
            default:
                out.append(.raw(child.format(), id: id))
            }
        }
        return out
    }

    private static func items(_ listItems: some Sequence<ListItem>, _ counter: inout Int) -> [RenderListItem] {
        listItems.map { item in
            counter += 1
            let id = counter
            let checked: Bool? = item.checkbox.map { $0 == .checked }
            let line = item.range.map { $0.lowerBound.line - 1 }
            return RenderListItem(id: id, checked: checked, sourceLine: line, blocks: convert(item.blockChildren, &counter))
        }
    }

    static func inlines(_ children: some Sequence<InlineMarkup>) -> AttributedString {
        var out = AttributedString()
        for child in children { out.append(inline(child)) }
        return out
    }

    private static func inline(_ node: InlineMarkup) -> AttributedString {
        switch node {
        case let t as Markdown.Text:
            return autolinked(t.string)
        case let e as Emphasis:
            var s = inlines(e.inlineChildren); s.inlinePresentationIntent = .emphasized; return s
        case let s as Strong:
            var a = inlines(s.inlineChildren); a.inlinePresentationIntent = .stronglyEmphasized; return a
        case let s as Strikethrough:
            var a = inlines(s.inlineChildren); a.strikethroughStyle = .single; return a
        case let c as InlineCode:
            var a = AttributedString(c.code); a.inlinePresentationIntent = .code; return a
        case let l as Markdown.Link:
            var a = inlines(l.inlineChildren)
            if let d = l.destination, let url = URL(string: d) { a.link = url; a.foregroundColor = .accentColor }
            return a
        case is SoftBreak:
            return AttributedString(" ")
        case is LineBreak:
            return AttributedString("\n")
        case let i as Markdown.Image:
            return AttributedString(i.plainText.isEmpty ? "[image]" : i.plainText)
        case let h as InlineHTML:
            return AttributedString(h.rawHTML)
        case let container as InlineContainer:
            return inlines(container.inlineChildren)
        default:
            return AttributedString(node.plainText)
        }
    }

    /// Plain text with bare URLs turned into links.
    static func autolinked(_ text: String) -> AttributedString {
        var out = AttributedString()
        var cursor = text.startIndex
        let ns = text as NSString
        for m in urlDetector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let r = Range(m.range, in: text), let url = m.url else { continue }
            if r.lowerBound > cursor { out.append(AttributedString(text[cursor..<r.lowerBound])) }
            var link = AttributedString(text[r]); link.link = url; link.foregroundColor = .accentColor
            out.append(link)
            cursor = r.upperBound
        }
        if cursor < text.endIndex { out.append(AttributedString(text[cursor...])) }
        return out
    }
}

/// Renders `RenderBlock`s. `onToggle` gets the 0-based source line of a tapped checkbox.
struct MarkdownBlocksView: View {
    let blocks: [RenderBlock]
    var onToggle: ((Int) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                BlockView(block: block, onToggle: onToggle)
            }
        }
    }
}

private struct BlockView: View {
    let block: RenderBlock
    let onToggle: ((Int) -> Void)?

    var body: some View {
        switch block {
        case .heading(let level, let text, _):
            SwiftUI.Text(text)
                .font(level <= 2 ? .title3.weight(.semibold) : level == 3 ? .headline : .subheadline.weight(.semibold))
                .padding(.top, level <= 3 ? 6 : 2)
        case .paragraph(let text, _):
            SwiftUI.Text(text).textSelection(.enabled)
        case .list(let items, let ordered, _):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let checked = item.checked {
                            Button {
                                if let line = item.sourceLine { onToggle?(line) }
                            } label: {
                                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(checked ? Color.accentColor : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(onToggle == nil || item.sourceLine == nil)
                        } else {
                            SwiftUI.Text(ordered ? "\(i + 1)." : "•").foregroundStyle(.secondary).frame(minWidth: 14, alignment: .trailing)
                        }
                        MarkdownBlocksView(blocks: item.blocks, onToggle: onToggle)
                    }
                }
            }
        case .code(let code, _):
            ScrollView(.horizontal) {
                SwiftUI.Text(code).font(.system(.footnote, design: .monospaced)).textSelection(.enabled).padding(8)
            }
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        case .quote(let inner, _):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.4)).frame(width: 3)
                MarkdownBlocksView(blocks: inner, onToggle: onToggle)
            }
        case .rule:
            Divider()
        case .table(let rows, _):
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                SwiftUI.Text(cell).font(i == 0 ? .footnote.weight(.semibold) : .footnote)
                            }
                        }
                        if i == 0 { Divider() }
                    }
                }
            }
        case .raw(let text, _):
            SwiftUI.Text(text).font(.footnote).foregroundStyle(.secondary)
        }
    }
}
