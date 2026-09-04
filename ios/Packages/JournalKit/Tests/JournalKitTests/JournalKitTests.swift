import Foundation
import Testing
@testable import JournalKit

func fixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "md", subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
}

@Suite struct ParserTests {
    @Test func fileNameRecognition() {
        #expect(JournalParser.date(fromFileName: "2026-09-03.md") == "2026-09-03")
        #expect(JournalParser.date(fromFileName: "notes.md") == nil)
        #expect(JournalParser.date(fromFileName: "2026-09-03.md.icloud") == nil)
    }

    @Test func parsesRealEntry() throws {
        let e = JournalParser.parse(try fixture("2026-09-03"), fileName: "2026-09-03.md")
        #expect(e.date == "2026-09-03")
        #expect(e.title == "Journal — 2026-09-03 (Thursday)")
        #expect(e.sections.map(\.kind) == [.done, .actions, .carriedOver, .details])
        #expect(e.doneItems.count == 3)
        #expect(e.actions.count == 6)
        #expect(e.checkboxes.count == 7, "the stray checkbox in Details is parsed but is not an action")
        #expect(e.openActionCount == 6)
        let first = e.actions[0]
        #expect(first.text == "Reply to Anton in #commercial-team with the outcome of the partner tech call")
        #expect(first.referenceKind == .source)
        #expect(first.urls.count == 1)
        #expect(first.urls[0].host == "example.slack.com")
        #expect(first.section == .actions)
        #expect(first.raw == e.lines[first.line])
        let ecom = e.actions[3]
        #expect(ecom.reference == "`git log @{u}..HEAD` in ECom")
        #expect(ecom.urls.isEmpty)
    }

    @Test func continuationLinesAndCarriedFrom() throws {
        let e = JournalParser.parse(try fixture("2026-09-04"), fileName: "2026-09-04.md")
        let carried = e.actions.filter { $0.section == .carriedOver }
        #expect(carried.count == 5)
        #expect(carried[0].isChecked)
        #expect(carried[0].referenceKind == .done)
        #expect(carried[0].carriedFrom == "2026-09-03")
        #expect(carried[2].continuation == ["    still waiting for the build to pass"])
        #expect(carried[2].identityKey == "ecom: 1 unpushed commit on dev")
    }

    @Test func identityKeyNormalisation() {
        #expect(CheckboxLine.identityKey(for: "  Reply to  Anton.  (from 2026-09-03) ") == "reply to anton")
        #expect(CheckboxLine.identityKey(for: "Reply to Anton") == CheckboxLine.identityKey(for: "reply to anton;"))
    }

    @Test func toleratesOddContent() {
        let e = JournalParser.parse("just a line\n## Weird\n- [X] Upper case box\n\n## Actions\n", fileName: "2026-01-01.md")
        #expect(e.title == "")
        #expect(e.sections.map(\.kind) == [.preamble, .other("Weird"), .actions])
        #expect(e.checkboxes.count == 1)
        #expect(e.checkboxes[0].isChecked)
        #expect(e.actions.isEmpty)
    }

    @Test func crlfPreserved() {
        let text = "# T\r\n\r\n## Actions\r\n- [ ] one — source: x\r\n"
        let e = JournalParser.parse(text, fileName: "2026-01-02.md")
        #expect(e.newline == "\r\n")
        #expect(e.actions.count == 1)
        #expect(e.actions[0].text == "one")
    }
}

@Suite struct TogglerTests {
    @Test func togglesExactlyOneLine() throws {
        let text = try fixture("2026-09-03")
        let e = JournalParser.parse(text, fileName: "2026-09-03.md")
        let target = e.actions[2]
        let out = try CheckboxToggler.toggle(in: text, line: target.line, expectedRaw: target.raw)
        let a = text.components(separatedBy: "\n"), b = out.components(separatedBy: "\n")
        #expect(a.count == b.count)
        let diffs = zip(a, b).enumerated().filter { $0.element.0 != $0.element.1 }
        #expect(diffs.count == 1)
        #expect(diffs[0].offset == target.line)
        #expect(b[target.line].hasPrefix("- [x] Verify the discounts layout"))
        #expect(out.hasSuffix("\n") == text.hasSuffix("\n"))
        // toggling back restores the original bytes
        let back = try CheckboxToggler.toggle(in: out, line: target.line, expectedRaw: b[target.line])
        #expect(back == text)
    }

    @Test func relocatesWhenLinesInsertedAbove() throws {
        let text = try fixture("2026-09-03")
        let e = JournalParser.parse(text, fileName: "2026-09-03.md")
        let target = e.actions[4]
        let shifted = text.replacingOccurrences(of: "## Actions\n", with: "## Actions\n- [ ] new item from the Mac — source: y\n")
        let out = try CheckboxToggler.toggle(in: shifted, line: target.line, expectedRaw: target.raw)
        #expect(out.contains("- [x] Redo the return tracking-number check"))
        #expect(out.contains("- [ ] new item from the Mac"))
    }

    @Test func failsWhenLineGone() throws {
        let text = try fixture("2026-09-03")
        #expect(throws: CheckboxToggler.Failure.lineNotFound) {
            try CheckboxToggler.toggle(in: text, line: 5, expectedRaw: "- [ ] does not exist")
        }
    }

    @Test func crlf() throws {
        let text = "## Actions\r\n- [ ] one\r\n- [ ] two\r\n"
        let out = try CheckboxToggler.toggle(in: text, line: 2, expectedRaw: "- [ ] two")
        #expect(out == "## Actions\r\n- [ ] one\r\n- [x] two\r\n")
    }
}

@Suite struct AggregatorTests {
    @Test func newestCopyWins() throws {
        let d3 = JournalParser.parse(try fixture("2026-09-03"), fileName: "2026-09-03.md")
        let d4 = JournalParser.parse(try fixture("2026-09-04"), fileName: "2026-09-04.md")
        let all = OpenActionsAggregator.aggregate([d3, d4])
        // 6 actions on day 3, day 4 adds 1 new and repeats 5 → 7 distinct keys
        #expect(all.count == 7)
        let anton = try #require(all.first { $0.key.hasPrefix("reply to anton") })
        #expect(anton.isOpen == false)
        #expect(anton.latest.date == "2026-09-04")
        #expect(anton.seenOn == ["2026-09-03", "2026-09-04"])
        let open = OpenActionsAggregator.openActions([d3, d4])
        #expect(open.count == 6)
        #expect(open.allSatisfy { $0.latest.date == "2026-09-04" || $0.key.hasPrefix("verify the discounts") })
        #expect(open[0].latest.date == "2026-09-04")
        #expect(open[0].latest.line < open[1].latest.line)
    }
}

@Suite struct SearchTests {
    @Test func andOfTermsCaseAndDiacriticInsensitive() throws {
        let d3 = JournalParser.parse(try fixture("2026-09-03"), fileName: "2026-09-03.md")
        let d4 = JournalParser.parse(try fixture("2026-09-04"), fileName: "2026-09-04.md")
        let idx = SearchIndex(entries: [d3, d4])
        #expect(idx.search("").isEmpty)
        let anton = idx.search("ANTON")
        #expect(anton.count == 5)
        #expect(anton[0].date == "2026-09-04")
        #expect(idx.search("anton outcome").count == 3)
        #expect(idx.search("anton nothing-here").isEmpty)
        #expect(idx.search("pickup").allSatisfy { $0.lineText.contains("pickup") })
        #expect(idx.search("elay").count == 1)
        #expect(idx.search("Élay").count == 1)
    }
}

@Suite struct InboxTests {
    @Test func writeThenParseRoundTrip() {
        let tz = TimeZone(identifier: "Europe/Helsinki")!
        var comps = DateComponents(); comps.year = 2026; comps.month = 9; comps.day = 4; comps.hour = 9; comps.minute = 12; comps.second = 33
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let now = cal.date(from: comps)!
        let (name, contents) = InboxWriter.makeCapture(kind: .action, body: "  Call Stian about the release\n", device: "iPhone", now: now, timeZone: tz, random: { 0xbeef })
        #expect(name == "2026-09-04-091233-beef.md")
        #expect(contents == "kind: action\ncreated: 2026-09-04T09:12:33+03:00\ndevice: iPhone\n\nCall Stian about the release\n")
        let parsed = InboxParser.parse(fileName: name, contents: contents)
        #expect(parsed.kind == .action)
        #expect(parsed.device == "iPhone")
        #expect(parsed.body == "Call Stian about the release")
        #expect(parsed.created == now)
    }

    @Test func headerlessFileIsANote() {
        let p = InboxParser.parse(fileName: "x.md", contents: "Just a thought: buy milk\n\nand bread")
        #expect(p.kind == .note)
        #expect(p.body == "Just a thought: buy milk\n\nand bread")
        #expect(p.created == nil)
    }
}

@Suite struct ConflictTests {
    @Test func newestWinsButChecksStick() {
        let old = ConflictResolver.Version(modified: Date(timeIntervalSince1970: 100), text: "## Actions\n- [x] a\n- [ ] b\n")
        let new = ConflictResolver.Version(modified: Date(timeIntervalSince1970: 200), text: "## Actions\n- [ ] a\n- [ ] b\n- [ ] c\n")
        #expect(ConflictResolver.merge([old, new]) == "## Actions\n- [x] a\n- [ ] b\n- [ ] c\n")
        #expect(ConflictResolver.merge([new]) == new.text)
    }
}
