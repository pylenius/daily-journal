namespace JournalCore;

public enum EditFailure { LineNotFound, NotACheckbox }

public sealed class LineEditException(EditFailure failure) : Exception(failure == EditFailure.LineNotFound
    ? "That line is no longer in the entry. It was reloaded."
    : "That line is not a checkbox.")
{
    public EditFailure Failure { get; } = failure;
}

/// <summary>Single-line edits that keep every other byte of the file intact.</summary>
public static class LineEditor
{
    /// <summary>
    /// Locates the line (at <paramref name="line"/> if it still reads <paramref name="expectedRaw"/>, else by unique
    /// text match) and replaces it with <paramref name="replacement"/>; null deletes the line. Returns the whole new file text.
    /// </summary>
    public static string Replace(string text, int line, string expectedRaw, string? replacement)
    {
        // Each line keeps its own ending, so CRLF, LF and mixed files come back byte for byte.
        var parts = text.Split('\n').ToList();
        string Content(int i) => parts[i].EndsWith('\r') ? parts[i][..^1] : parts[i];
        var index = line;
        if (!(index >= 0 && index < parts.Count && Content(index) == expectedRaw))
        {
            var matches = Enumerable.Range(0, parts.Count).Where(i => Content(i) == expectedRaw).ToList();
            if (matches.Count != 1) throw new LineEditException(EditFailure.LineNotFound);
            index = matches[0];
        }
        if (replacement is not null) parts[index] = replacement + (parts[index].EndsWith('\r') ? "\r" : "");
        else parts.RemoveAt(index);
        return string.Join("\n", parts);
    }

    /// <summary>`- text` ↔ `- **text**` (a highlighted Done item). Null if the line is not a plain bullet.</summary>
    public static string? HighlightToggled(string line)
    {
        if (DoneItem.Parse(line) is not { } item) return null;
        var prefix = line[..item.BulletPrefixLength];
        return item.IsHighlighted ? $"{prefix}{item.Text}" : $"{prefix}**{item.Text}**";
    }
}

/// <summary>A plain bullet under `## Done`.</summary>
public sealed record DoneItem(string Date, int Line, string Raw, string Text, bool IsHighlighted, int BulletPrefixLength)
{
    public string Id => $"{Date}#{Line}";

    public static DoneItem? Parse(string line, string date = "", int lineNumber = 0)
    {
        var indent = line.TakeWhile(c => c is ' ' or '\t').Count();
        var rest = line[indent..];
        if (!(rest.StartsWith("- ") || rest.StartsWith("* "))) return null;
        if (JournalParser.ParseCheckbox(line) is not null) return null;
        var body = rest[2..].Trim();
        var highlighted = false;
        if (body.StartsWith("**") && body.EndsWith("**") && body.Length > 4)
        {
            var inner = body[2..^2];
            if (!inner.Contains("**")) { body = inner; highlighted = true; }
        }
        return new DoneItem(date, lineNumber, line, body, highlighted, indent + 2);
    }
}

public static class CheckboxToggler
{
    /// <summary>Flip `[ ]`↔`[x]` on one line, preserving every other byte and the newline style.</summary>
    public static string Toggle(string text, int line, string expectedRaw)
    {
        var flipped = Flip(expectedRaw) ?? throw new LineEditException(EditFailure.NotACheckbox);
        return LineEditor.Replace(text, line, expectedRaw, flipped);
    }

    /// <summary>The single line with its box flipped, or null if it is not a checkbox line.</summary>
    public static string? Flip(string line)
    {
        if (JournalParser.ParseCheckbox(line) is null) return null;
        foreach (var (from, to) in new[] { ("- [ ] ", "- [x] "), ("- [x] ", "- [ ] "), ("- [X] ", "- [ ] ") })
        {
            var i = line.IndexOf(from, StringComparison.Ordinal);
            if (i >= 0) return line[..i] + to + line[(i + from.Length)..];
        }
        return null;
    }
}
