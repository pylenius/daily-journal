using JournalCore;
using Xunit;

namespace JournalCore.Tests;

static class Fixtures
{
    public static string Load(string name) =>
        File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", name + ".md"));
}

public class ParserTests
{
    [Fact]
    public void FileNameRecognition()
    {
        Assert.Equal("2026-09-03", JournalParser.DateFromFileName("2026-09-03.md"));
        Assert.Null(JournalParser.DateFromFileName("notes.md"));
        Assert.Null(JournalParser.DateFromFileName("2026-09-03.md.icloud"));
        Assert.Null(JournalParser.DateFromFileName("2026-09-03-DESKTOP.md"));
    }

    [Fact]
    public void ParsesRealEntry()
    {
        var e = JournalParser.Parse(Fixtures.Load("2026-09-03"), "2026-09-03.md");
        Assert.Equal("2026-09-03", e.Date);
        Assert.Equal("Journal — 2026-09-03 (Thursday)", e.Title);
        Assert.Equal([SectionKind.Done, SectionKind.Actions, SectionKind.CarriedOver, SectionKind.Details], e.Sections.Select(s => s.Kind));
        Assert.Equal(3, e.DoneItems.Count);
        Assert.StartsWith("Re-authentication now uses", e.DoneItems[1].Text);
        Assert.Equal(4, e.DoneItems[1].Line);
        Assert.False(e.DoneItems[1].IsHighlighted);
        Assert.Equal(6, e.Actions.Count);
        Assert.Equal(7, e.Checkboxes.Count); // the stray checkbox in Details is parsed but is not an action
        Assert.Equal(6, e.OpenActionCount);
        var first = e.Actions[0];
        Assert.Equal("Reply to Alex in #sales-team with the outcome of the partner tech call", first.Text);
        Assert.Equal(ReferenceKind.Source, first.ReferenceKind);
        Assert.Single(first.Urls);
        Assert.Equal("example.slack.com", first.Urls[0].Host);
        Assert.Equal(SectionKind.Actions, first.Section);
        Assert.Equal(e.Lines[first.Line], first.Raw);
        var ecom = e.Actions[3];
        Assert.Equal("`git log @{u}..HEAD` in ECom", ecom.Reference);
        Assert.Empty(ecom.Urls);
    }

    [Fact]
    public void ContinuationLinesAndCarriedFrom()
    {
        var e = JournalParser.Parse(Fixtures.Load("2026-09-04"), "2026-09-04.md");
        var carried = e.Actions.Where(a => a.Section == SectionKind.CarriedOver).ToList();
        Assert.Equal(5, carried.Count);
        Assert.True(carried[0].IsChecked);
        Assert.Equal(ReferenceKind.Done, carried[0].ReferenceKind);
        Assert.Equal("2026-09-03", carried[0].CarriedFrom);
        Assert.Equal(["    still waiting for the build to pass"], carried[2].Continuation);
        Assert.Equal("ecom: 1 unpushed commit on dev", carried[2].IdentityKey);
    }

    [Fact]
    public void IdentityKeyNormalisation()
    {
        Assert.Equal("reply to alex", CheckboxLine.IdentityKeyFor("  Reply to  Alex.  (from 2026-09-03) "));
        Assert.Equal(CheckboxLine.IdentityKeyFor("reply to alex;"), CheckboxLine.IdentityKeyFor("Reply to Alex"));
    }

    [Fact]
    public void ToleratesOddContent()
    {
        var e = JournalParser.Parse("just a line\n## Weird\n- [X] Upper case box\n\n## Actions\n", "2026-01-01.md");
        Assert.Equal("", e.Title);
        Assert.Equal([SectionKind.Preamble, SectionKind.Other("Weird"), SectionKind.Actions], e.Sections.Select(s => s.Kind));
        Assert.Single(e.Checkboxes);
        Assert.True(e.Checkboxes[0].IsChecked);
        Assert.Empty(e.Actions);
    }

    [Fact]
    public void CrlfPreserved()
    {
        var e = JournalParser.Parse("# T\r\n\r\n## Actions\r\n- [ ] one — source: x\r\n", "2026-01-02.md");
        Assert.Equal("\r\n", e.Newline);
        Assert.Single(e.Actions);
        Assert.Equal("one", e.Actions[0].Text);
    }
}

public class TogglerTests
{
    [Fact]
    public void MixedLineEndingsParseAndKeepEveryByte()
    {
        // An LF file with one CRLF line appended on Windows must not collapse into one line.
        var text = "# T\n\n## Done\n- a\n\n## Actions\n- [ ] one\n- [ ] two\r\n";
        var e = JournalParser.Parse(text, "2026-01-04.md");
        Assert.Equal("\n", e.Newline);
        Assert.Equal(2, e.Actions.Count);
        Assert.Equal("two", e.Actions[1].Text);
        Assert.Equal("# T\n\n## Done\n- a\n\n## Actions\n- [ ] one\n- [x] two\r\n", CheckboxToggler.Toggle(text, e.Actions[1].Line, e.Actions[1].Raw));
        Assert.Equal("# T\n\n## Done\n- a\n\n## Actions\n- [x] one\n- [ ] two\r\n", CheckboxToggler.Toggle(text, e.Actions[0].Line, e.Actions[0].Raw));
    }

    [Fact]
    public void TogglesExactlyOneLine()
    {
        var text = Fixtures.Load("2026-09-03");
        var e = JournalParser.Parse(text, "2026-09-03.md");
        var target = e.Actions[2];
        var output = CheckboxToggler.Toggle(text, target.Line, target.Raw);
        var a = text.Split('\n'); var b = output.Split('\n');
        Assert.Equal(a.Length, b.Length);
        var diffs = a.Zip(b).Select((p, i) => (p, i)).Where(x => x.p.First != x.p.Second).ToList();
        Assert.Single(diffs);
        Assert.Equal(target.Line, diffs[0].i);
        Assert.StartsWith("- [x] Verify the discounts layout", b[target.Line]);
        // toggling back restores the original bytes
        Assert.Equal(text, CheckboxToggler.Toggle(output, target.Line, b[target.Line]));
    }

    [Fact]
    public void RelocatesWhenLinesInsertedAbove()
    {
        var text = Fixtures.Load("2026-09-03");
        var target = JournalParser.Parse(text, "2026-09-03.md").Actions[4];
        var shifted = text.Replace("## Actions\n", "## Actions\n- [ ] new item from the Mac — source: y\n");
        var output = CheckboxToggler.Toggle(shifted, target.Line, target.Raw);
        Assert.Contains("- [x] Redo the return tracking-number check", output);
        Assert.Contains("- [ ] new item from the Mac", output);
    }

    [Fact]
    public void FailsWhenLineGone()
    {
        var ex = Assert.Throws<LineEditException>(() => CheckboxToggler.Toggle(Fixtures.Load("2026-09-03"), 5, "- [ ] does not exist"));
        Assert.Equal(EditFailure.LineNotFound, ex.Failure);
    }

    [Fact]
    public void Crlf()
    {
        var output = CheckboxToggler.Toggle("## Actions\r\n- [ ] one\r\n- [ ] two\r\n", 2, "- [ ] two");
        Assert.Equal("## Actions\r\n- [ ] one\r\n- [x] two\r\n", output);
    }
}

public class AggregatorTests
{
    [Fact]
    public void NewestCopyWins()
    {
        var d3 = JournalParser.Parse(Fixtures.Load("2026-09-03"), "2026-09-03.md");
        var d4 = JournalParser.Parse(Fixtures.Load("2026-09-04"), "2026-09-04.md");
        var all = OpenActionsAggregator.Aggregate([d3, d4]);
        // 6 actions on day 3, day 4 adds 1 new and repeats 5 → 7 distinct keys
        Assert.Equal(7, all.Count);
        var alex = all.First(a => a.Key.StartsWith("reply to alex"));
        Assert.False(alex.IsOpen);
        Assert.Equal("2026-09-04", alex.Latest.Date);
        Assert.Equal(["2026-09-03", "2026-09-04"], alex.SeenOn);
        var open = OpenActionsAggregator.OpenActions([d3, d4]);
        Assert.Equal(6, open.Count);
        Assert.All(open, a => Assert.True(a.Latest.Date == "2026-09-04" || a.Key.StartsWith("verify the discounts")));
        Assert.Equal("2026-09-04", open[0].Latest.Date);
        Assert.True(open[0].Latest.Line < open[1].Latest.Line);
    }
}

public class SearchTests
{
    [Fact]
    public void AndOfTermsCaseAndDiacriticInsensitive()
    {
        var d3 = JournalParser.Parse(Fixtures.Load("2026-09-03"), "2026-09-03.md");
        var d4 = JournalParser.Parse(Fixtures.Load("2026-09-04"), "2026-09-04.md");
        var idx = new SearchIndex([d3, d4]);
        Assert.Empty(idx.Search(""));
        var alex = idx.Search("ALEX");
        Assert.Equal(5, alex.Count);
        Assert.Equal("2026-09-04", alex[0].Date);
        Assert.Equal(3, idx.Search("alex outcome").Count);
        Assert.Empty(idx.Search("alex nothing-here"));
        Assert.All(idx.Search("pickup"), h => Assert.Contains("pickup", h.LineText));
        Assert.Single(idx.Search("dana"));
        Assert.Single(idx.Search("Dána"));
    }
}

public class InboxTests
{
    [Fact]
    public void WriteThenParseRoundTrip()
    {
        var tz = TimeZoneInfo.FindSystemTimeZoneById("Europe/Helsinki");
        var now = new DateTimeOffset(2026, 9, 4, 9, 12, 33, TimeSpan.FromHours(3));
        var (name, contents) = InboxWriter.MakeCapture(CaptureKind.Action, "  Call Noor about the release\n", "Windows", now, tz, () => 0xbeef);
        Assert.Equal("2026-09-04-091233-beef.md", name);
        Assert.Equal("kind: action\ncreated: 2026-09-04T09:12:33+03:00\ndevice: Windows\n\nCall Noor about the release\n", contents);
        var parsed = InboxParser.Parse(name, contents);
        Assert.Equal(CaptureKind.Action, parsed.Kind);
        Assert.Equal("Windows", parsed.Device);
        Assert.Equal("Call Noor about the release", parsed.Body);
        Assert.Equal(now, parsed.Created);
    }

    [Fact]
    public void HeaderlessFileIsANote()
    {
        var p = InboxParser.Parse("x.md", "Just a thought: buy milk\n\nand bread");
        Assert.Equal(CaptureKind.Note, p.Kind);
        Assert.Equal("Just a thought: buy milk\n\nand bread", p.Body);
        Assert.Null(p.Created);
    }
}

public class LineEditorTests
{
    [Fact]
    public void DeleteAndHighlight()
    {
        var text = "## Done\n- one\n- **two**\n- three\n";
        var e = JournalParser.Parse(text, "2026-01-03.md");
        Assert.Equal(["one", "two", "three"], e.DoneItems.Select(d => d.Text));
        Assert.True(e.DoneItems[1].IsHighlighted);
        Assert.Equal("## Done\n- **two**\n- three\n", LineEditor.Replace(text, e.DoneItems[0].Line, e.DoneItems[0].Raw, null));
        var hi = LineEditor.HighlightToggled("- three");
        Assert.Equal("- **three**", hi);
        Assert.Equal("  - two", LineEditor.HighlightToggled("  - **two**"));
        Assert.Null(LineEditor.HighlightToggled("- [ ] not a done item"));
        Assert.Equal("## Done\n- one\n- **two**\n- **three**\n", LineEditor.Replace(text, 3, "- three", hi));
        Assert.Throws<LineEditException>(() => LineEditor.Replace(text, 9, "- gone", null));
    }
}
