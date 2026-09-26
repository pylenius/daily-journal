using System.Text.RegularExpressions;

namespace JournalCore;

public static class JournalParser
{
    static readonly Regex FileRegex = new(@"^(\d{4}-\d{2}-\d{2})\.md$", RegexOptions.Compiled);
    static readonly Regex CheckboxRegex = new(@"^(\s*)- \[( |x|X)\] (.*)$", RegexOptions.Compiled);
    static readonly Regex MarkerRegex = new(@"\s+[—–-]{1,2}\s+(source|done):\s*", RegexOptions.Compiled);
    static readonly Regex UrlRegex = new(@"https?://[^\s<>""'`()\[\]]+", RegexOptions.Compiled | RegexOptions.IgnoreCase);

    /// <summary>Returns the date if <paramref name="fileName"/> is an entry file, else null.</summary>
    public static string? DateFromFileName(string fileName)
    {
        var m = FileRegex.Match(fileName);
        return m.Success ? m.Groups[1].Value : null;
    }

    public static JournalEntry Parse(string text, string fileName)
    {
        var date = DateFromFileName(fileName) ?? fileName;
        var (lines, newline) = SplitLines(text);

        var title = "";
        var sections = new List<Section>();
        (SectionKind Kind, string Heading, int HeadingLine, int Start)? current = null;
        var preambleStart = 0;

        void Close(int end)
        {
            if (current is { } c)
            {
                sections.Add(new Section(c.Kind, c.Heading, c.HeadingLine, c.Start, end));
            }
            else if (end > preambleStart && lines[preambleStart..end].Any(l => l.Trim().Length > 0))
            {
                sections.Add(new Section(SectionKind.Preamble, "", -1, preambleStart, end));
            }
        }

        for (var i = 0; i < lines.Length; i++)
        {
            var line = lines[i];
            if (line.StartsWith("# ") && title.Length == 0 && current is null)
            {
                title = line[2..].Trim();
                preambleStart = i + 1;
            }
            else if (line.StartsWith("## "))
            {
                Close(i);
                var heading = line[3..];
                current = (SectionKind.Recognise(heading), heading.Trim(), i, i + 1);
            }
        }
        Close(lines.Length);

        var checkboxes = new List<CheckboxLine>();
        var doneItems = new List<DoneItem>();
        foreach (var section in sections)
        {
            var i = section.BodyStart;
            while (i < section.BodyEnd)
            {
                var line = lines[i];
                if (ParseCheckbox(line) is { } cb)
                {
                    var continuation = new List<string>();
                    var j = i + 1;
                    while (j < section.BodyEnd && IsContinuation(lines[j], cb.Indent))
                    {
                        continuation.Add(lines[j]); j++;
                    }
                    checkboxes.Add(MakeCheckbox(cb, i, date, section.Kind, line, continuation));
                    i = j;
                    continue;
                }
                if (section.Kind == SectionKind.Done && DoneItem.Parse(line, date, i) is { } item)
                {
                    doneItems.Add(item);
                }
                i++;
            }
        }

        return new JournalEntry(date, fileName, title, lines, newline, sections, checkboxes, doneItems);
    }

    /// <summary>
    /// Splits on LF and drops a CR before it, so CRLF, LF and files mixing both (a line appended on Windows) all parse.
    /// The reported newline is the first line's ending.
    /// </summary>
    public static (string[] Lines, string Newline) SplitLines(string text)
    {
        var lines = text.Split('\n');
        var newline = lines.Length > 1 && lines[0].EndsWith('\r') ? "\r\n" : "\n";
        for (var i = 0; i < lines.Length; i++)
            if (lines[i].EndsWith('\r')) lines[i] = lines[i][..^1];
        return (lines, newline);
    }

    internal readonly record struct RawCheckbox(int Indent, bool Checked, string Body);

    internal static RawCheckbox? ParseCheckbox(string line)
    {
        var m = CheckboxRegex.Match(line);
        if (!m.Success) return null;
        return new RawCheckbox(m.Groups[1].Length, m.Groups[2].Value != " ", m.Groups[3].Value);
    }

    static bool IsContinuation(string line, int indent)
    {
        if (line.Trim().Length == 0) return false;
        var leading = line.TakeWhile(c => c is ' ' or '\t').Count();
        if (leading <= indent) return false;
        return ParseCheckbox(line) is null;
    }

    /// <summary>URLs found anywhere in <paramref name="text"/>, trailing punctuation trimmed.</summary>
    public static IReadOnlyList<Uri> FindUrls(string text)
    {
        var urls = new List<Uri>();
        foreach (Match m in UrlRegex.Matches(text))
        {
            var s = m.Value.TrimEnd('.', ',', ';', ':', '!', '?');
            if (Uri.TryCreate(s, UriKind.Absolute, out var u)) urls.Add(u);
        }
        return urls;
    }

    /// <summary>Splits text into plain and URL runs, for rendering links.</summary>
    public static IEnumerable<(string Text, Uri? Url)> SplitUrls(string text)
    {
        var pos = 0;
        foreach (Match m in UrlRegex.Matches(text))
        {
            var s = m.Value.TrimEnd('.', ',', ';', ':', '!', '?');
            if (!Uri.TryCreate(s, UriKind.Absolute, out var u)) continue;
            if (m.Index > pos) yield return (text[pos..m.Index], null);
            yield return (s, u);
            pos = m.Index + s.Length;
        }
        if (pos < text.Length) yield return (text[pos..], null);
    }

    static CheckboxLine MakeCheckbox(RawCheckbox cb, int line, string date, SectionKind section, string raw, List<string> continuation)
    {
        var body = cb.Body;
        var text = body;
        ReferenceKind? refKind = null;
        string? reference = null;
        var m = MarkerRegex.Match(body);
        if (m.Success)
        {
            text = body[..m.Index];
            refKind = m.Groups[1].Value == "source" ? ReferenceKind.Source : ReferenceKind.Done;
            reference = body[(m.Index + m.Length)..].Trim();
        }
        text = text.Trim();
        return new CheckboxLine($"{date}#{line}", date, line, cb.Checked, text, refKind, reference, FindUrls(body),
                                section, raw, continuation, CheckboxLine.IdentityKeyFor(text));
    }
}
