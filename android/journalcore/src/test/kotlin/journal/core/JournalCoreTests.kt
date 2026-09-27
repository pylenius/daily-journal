package journal.core

import java.io.File
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** One copy of the fixtures, shared with the Swift and C# tests (see build.gradle.kts). */
object Fixtures {
    fun load(name: String): String = File(System.getProperty("journal.fixtures"), "$name.md").readText()
}

class ParserTests {
    @Test fun fileNameRecognition() {
        assertEquals("2026-09-03", JournalParser.dateFromFileName("2026-09-03.md"))
        assertNull(JournalParser.dateFromFileName("notes.md"))
        assertNull(JournalParser.dateFromFileName("2026-09-03.md.icloud"))
        assertNull(JournalParser.dateFromFileName("2026-09-03-DESKTOP.md"))
    }

    @Test fun parsesRealEntry() {
        val e = JournalParser.parse(Fixtures.load("2026-09-03"), "2026-09-03.md")
        assertEquals("2026-09-03", e.date)
        assertEquals("Journal — 2026-09-03 (Thursday)", e.title)
        assertEquals(
            listOf(SectionKind.Done, SectionKind.Actions, SectionKind.CarriedOver, SectionKind.Details),
            e.sections.map { it.kind },
        )
        assertEquals(3, e.doneItems.size)
        assertTrue(e.doneItems[1].text.startsWith("Re-authentication now uses"))
        assertEquals(4, e.doneItems[1].line)
        assertFalse(e.doneItems[1].isHighlighted)
        assertEquals(6, e.actions.size)
        assertEquals(7, e.checkboxes.size) // the stray checkbox in Details is parsed but is not an action
        assertEquals(6, e.openActionCount)
        val first = e.actions[0]
        assertEquals("Reply to Alex in #sales-team with the outcome of the partner tech call", first.text)
        assertEquals(ReferenceKind.Source, first.referenceKind)
        assertEquals(1, first.urls.size)
        assertEquals("example.slack.com", first.urls[0].host)
        assertEquals(SectionKind.Actions, first.section)
        assertEquals(e.lines[first.line], first.raw)
        val ecom = e.actions[3]
        assertEquals("`git log @{u}..HEAD` in ECom", ecom.reference)
        assertTrue(ecom.urls.isEmpty())
    }

    @Test fun continuationLinesAndCarriedFrom() {
        val e = JournalParser.parse(Fixtures.load("2026-09-04"), "2026-09-04.md")
        val carried = e.actions.filter { it.section == SectionKind.CarriedOver }
        assertEquals(5, carried.size)
        assertTrue(carried[0].isChecked)
        assertEquals(ReferenceKind.Done, carried[0].referenceKind)
        assertEquals("2026-09-03", carried[0].carriedFrom)
        assertEquals(listOf("    still waiting for the build to pass"), carried[2].continuation)
        assertEquals("ecom: 1 unpushed commit on dev", carried[2].identityKey)
    }

    @Test fun identityKeyNormalisation() {
        assertEquals("reply to alex", CheckboxLine.identityKeyFor("  Reply to  Alex.  (from 2026-09-03) "))
        assertEquals(CheckboxLine.identityKeyFor("reply to alex;"), CheckboxLine.identityKeyFor("Reply to Alex"))
    }

    @Test fun toleratesOddContent() {
        val e = JournalParser.parse("just a line\n## Weird\n- [X] Upper case box\n\n## Actions\n", "2026-01-01.md")
        assertEquals("", e.title)
        assertEquals(listOf(SectionKind.Preamble, SectionKind.other("Weird"), SectionKind.Actions), e.sections.map { it.kind })
        assertEquals(1, e.checkboxes.size)
        assertTrue(e.checkboxes[0].isChecked)
        assertTrue(e.actions.isEmpty())
    }

    @Test fun crlfPreserved() {
        val e = JournalParser.parse("# T\r\n\r\n## Actions\r\n- [ ] one — source: x\r\n", "2026-01-02.md")
        assertEquals("\r\n", e.newline)
        assertEquals(1, e.actions.size)
        assertEquals("one", e.actions[0].text)
    }

    @Test fun splitUrlsTrimsPunctuation() {
        val parts = JournalParser.splitUrls("see https://example.com/a, then (https://x.org/b).")
        assertEquals(listOf("see ", "https://example.com/a", ", then (", "https://x.org/b", ")."), parts.map { it.first })
        assertEquals(listOf(false, true, false, true, false), parts.map { it.second != null })
    }
}

class TogglerTests {
    @Test fun mixedLineEndingsParseAndKeepEveryByte() {
        // An LF file with one CRLF line appended on Windows must not collapse into one line.
        val text = "# T\n\n## Done\n- a\n\n## Actions\n- [ ] one\n- [ ] two\r\n"
        val e = JournalParser.parse(text, "2026-01-04.md")
        assertEquals("\n", e.newline)
        assertEquals(2, e.actions.size)
        assertEquals("two", e.actions[1].text)
        assertEquals("# T\n\n## Done\n- a\n\n## Actions\n- [ ] one\n- [x] two\r\n", CheckboxToggler.toggle(text, e.actions[1].line, e.actions[1].raw))
        assertEquals("# T\n\n## Done\n- a\n\n## Actions\n- [x] one\n- [ ] two\r\n", CheckboxToggler.toggle(text, e.actions[0].line, e.actions[0].raw))
    }

    @Test fun togglesExactlyOneLine() {
        val text = Fixtures.load("2026-09-03")
        val e = JournalParser.parse(text, "2026-09-03.md")
        val target = e.actions[2]
        val output = CheckboxToggler.toggle(text, target.line, target.raw)
        val a = text.split('\n')
        val b = output.split('\n')
        assertEquals(a.size, b.size)
        val diffs = a.indices.filter { a[it] != b[it] }
        assertEquals(listOf(target.line), diffs)
        assertTrue(b[target.line].startsWith("- [x] Verify the discounts layout"))
        // toggling back restores the original bytes
        assertEquals(text, CheckboxToggler.toggle(output, target.line, b[target.line]))
    }

    @Test fun relocatesWhenLinesInsertedAbove() {
        val text = Fixtures.load("2026-09-03")
        val target = JournalParser.parse(text, "2026-09-03.md").actions[4]
        val shifted = text.replace("## Actions\n", "## Actions\n- [ ] new item from the Mac — source: y\n")
        val output = CheckboxToggler.toggle(shifted, target.line, target.raw)
        assertTrue(output.contains("- [x] Redo the return tracking-number check"))
        assertTrue(output.contains("- [ ] new item from the Mac"))
    }

    @Test fun failsWhenLineGone() {
        val ex = assertFailsWith<LineEditException> { CheckboxToggler.toggle(Fixtures.load("2026-09-03"), 5, "- [ ] does not exist") }
        assertEquals(EditFailure.LineNotFound, ex.failure)
    }

    @Test fun crlf() {
        assertEquals("## Actions\r\n- [ ] one\r\n- [x] two\r\n", CheckboxToggler.toggle("## Actions\r\n- [ ] one\r\n- [ ] two\r\n", 2, "- [ ] two"))
    }
}

class AggregatorTests {
    @Test fun newestCopyWins() {
        val d3 = JournalParser.parse(Fixtures.load("2026-09-03"), "2026-09-03.md")
        val d4 = JournalParser.parse(Fixtures.load("2026-09-04"), "2026-09-04.md")
        val all = OpenActionsAggregator.aggregate(listOf(d3, d4))
        // 6 actions on day 3, day 4 adds 1 new and repeats 5 → 7 distinct keys
        assertEquals(7, all.size)
        val alex = all.first { it.key.startsWith("reply to alex") }
        assertFalse(alex.isOpen)
        assertEquals("2026-09-04", alex.latest.date)
        assertEquals(listOf("2026-09-03", "2026-09-04"), alex.seenOn)
        val open = OpenActionsAggregator.openActions(listOf(d3, d4))
        assertEquals(6, open.size)
        assertTrue(open.all { it.latest.date == "2026-09-04" || it.key.startsWith("verify the discounts") })
        assertEquals("2026-09-04", open[0].latest.date)
        assertTrue(open[0].latest.line < open[1].latest.line)
    }
}

class SearchTests {
    @Test fun andOfTermsCaseAndDiacriticInsensitive() {
        val d3 = JournalParser.parse(Fixtures.load("2026-09-03"), "2026-09-03.md")
        val d4 = JournalParser.parse(Fixtures.load("2026-09-04"), "2026-09-04.md")
        val idx = SearchIndex(listOf(d3, d4))
        assertTrue(idx.search("").isEmpty())
        val alex = idx.search("ALEX")
        assertEquals(5, alex.size)
        assertEquals("2026-09-04", alex[0].date)
        assertEquals(3, idx.search("alex outcome").size)
        assertTrue(idx.search("alex nothing-here").isEmpty())
        assertTrue(idx.search("pickup").all { it.lineText.contains("pickup") })
        assertEquals(1, idx.search("dana").size)
        assertEquals(1, idx.search("Dána").size)
    }

    @Test fun matchRangesMapBackThroughAccents() {
        assertEquals(listOf(4..7), SearchIndex.matchRanges("Met Dána today", "dana"))
        assertEquals(listOf(0..3, 9..12), SearchIndex.matchRanges("Alex and ALEX", "alex"))
        assertTrue(SearchIndex.matchRanges("anything", " ").isEmpty())
    }
}

class InboxTests {
    @Test fun writeThenParseRoundTrip() {
        val now = ZonedDateTime.of(2026, 9, 4, 9, 12, 33, 0, ZoneId.of("Europe/Helsinki"))
        val (name, contents) = InboxWriter.makeCapture(CaptureKind.Action, "  Call Noor about the release\n", "Android", now) { 0xbeef }
        assertEquals("2026-09-04-091233-beef.md", name)
        assertEquals("kind: action\ncreated: 2026-09-04T09:12:33+03:00\ndevice: Android\n\nCall Noor about the release\n", contents)
        val parsed = InboxParser.parse(name, contents)
        assertEquals(CaptureKind.Action, parsed.kind)
        assertEquals("Android", parsed.device)
        assertEquals("Call Noor about the release", parsed.body)
        assertEquals(now.toOffsetDateTime(), parsed.created)
    }

    @Test fun utcIsWrittenAsZ() {
        val now = ZonedDateTime.of(2026, 9, 4, 6, 0, 0, 0, ZoneId.of("UTC"))
        val (_, contents) = InboxWriter.makeCapture(CaptureKind.Note, "x", null, now) { 1 }
        assertEquals("kind: note\ncreated: 2026-09-04T06:00:00Z\n\nx\n", contents)
    }

    @Test fun headerlessFileIsANote() {
        val p = InboxParser.parse("x.md", "Just a thought: buy milk\n\nand bread")
        assertEquals(CaptureKind.Note, p.kind)
        assertEquals("Just a thought: buy milk\n\nand bread", p.body)
        assertNull(p.created)
    }
}

class LineEditorTests {
    @Test fun deleteAndHighlight() {
        val text = "## Done\n- one\n- **two**\n- three\n"
        val e = JournalParser.parse(text, "2026-01-03.md")
        assertEquals(listOf("one", "two", "three"), e.doneItems.map { it.text })
        assertTrue(e.doneItems[1].isHighlighted)
        assertEquals("## Done\n- **two**\n- three\n", LineEditor.replace(text, e.doneItems[0].line, e.doneItems[0].raw, null))
        val hi = LineEditor.highlightToggled("- three")
        assertEquals("- **three**", hi)
        assertEquals("  - two", LineEditor.highlightToggled("  - **two**"))
        assertNull(LineEditor.highlightToggled("- [ ] not a done item"))
        assertEquals("## Done\n- one\n- **two**\n- **three**\n", LineEditor.replace(text, 3, "- three", hi))
        assertFailsWith<LineEditException> { LineEditor.replace(text, 9, "- gone", null) }
    }
}
