import Foundation
import JournalKit
import Testing
@testable import Journal

@Suite struct RendererTests {
    @Test func inlineKeepsCodeAndLinks() {
        let a = MarkdownRenderer.inline("Fix `Foo.swift` see https://example.com/x")
        let s = String(a.characters)
        #expect(s == "Fix Foo.swift see https://example.com/x")
        #expect(a.runs.contains { $0.link != nil })
    }

    @Test func checkboxLineMapping() {
        let blocks = MarkdownRenderer.blocks(from: "### Meetings\n- first\n- [ ] second\n- [x] third\n")
        guard case .list(let items, _, _) = blocks[1] else { Issue.record("expected a list"); return }
        #expect(items[0].checked == nil)
        #expect(items[1].checked == false)
        #expect(items[1].sourceLine == 2)
        #expect(items[2].checked == true)
        #expect(items[2].sourceLine == 3)
    }
}

@Suite struct SampleJournalTests {
    @Test func sampleIsAValidJournalWithCarryOver() throws {
        let folder = try SampleJournal.create()
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { JournalParser.date(fromFileName: $0) != nil }.sorted()
        #expect(files.count == 3)
        let entries = try files.map { name in
            JournalParser.parse(try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8), fileName: name)
        }
        #expect(entries.allSatisfy { !$0.doneItems.isEmpty && !$0.actions.isEmpty })
        // Newest copy wins: the price list was sent on the last day, the UK reply is still open.
        let open = OpenActionsAggregator.openActions(entries)
        #expect(open.contains { $0.key.hasPrefix("reply to chris") })
        #expect(!open.contains { $0.key.hasPrefix("send dana") })
        #expect(!open.contains { $0.key.hasPrefix("review robin") })
        #expect(open.count == 4)
        let inbox = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("inbox").path)
        #expect(inbox.count == 1)
    }
}
