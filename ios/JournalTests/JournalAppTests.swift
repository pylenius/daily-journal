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
