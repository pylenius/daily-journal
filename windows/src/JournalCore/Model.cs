using System.Globalization;
using System.Text.RegularExpressions;

namespace JournalCore;

public enum SectionType { Done, Actions, CarriedOver, Details, Other, Preamble }

/// <summary>Which recognised section a line belongs to. See spec/JOURNAL_FORMAT.md.</summary>
public readonly record struct SectionKind(SectionType Type, string Name = "")
{
    public static readonly SectionKind Done = new(SectionType.Done);
    public static readonly SectionKind Actions = new(SectionType.Actions);
    public static readonly SectionKind CarriedOver = new(SectionType.CarriedOver);
    public static readonly SectionKind Details = new(SectionType.Details);
    public static readonly SectionKind Preamble = new(SectionType.Preamble);
    public static SectionKind Other(string name) => new(SectionType.Other, name);

    /// <summary>True for the two sections whose checkboxes count as actions.</summary>
    public bool HoldsActions => Type is SectionType.Actions or SectionType.CarriedOver;

    internal static SectionKind Recognise(string heading) => heading.Trim().ToLowerInvariant() switch
    {
        "done" => Done,
        "actions" => Actions,
        "carried over" => CarriedOver,
        "details" => Details,
        _ => Other(heading.Trim()),
    };

    public string Title => Type switch
    {
        SectionType.Done => "Done",
        SectionType.Actions => "Actions",
        SectionType.CarriedOver => "Carried over",
        SectionType.Details => "Details",
        SectionType.Other => Name,
        _ => "",
    };
}

/// <summary>A level-2 section of an entry. Body lines are 0-based line indexes after the heading, up to the next `##`.</summary>
public sealed record Section(SectionKind Kind, string Heading, int HeadingLine, int BodyStart, int BodyEnd)
{
    public IEnumerable<int> BodyLines => Enumerable.Range(BodyStart, BodyEnd - BodyStart);
}

/// <summary>How the trailing reference on a checkbox line was marked.</summary>
public enum ReferenceKind { Source, Done }

/// <summary>One `- [ ]` / `- [x]` line.</summary>
public sealed record CheckboxLine(
    string Id,
    string Date,
    int Line,
    bool IsChecked,
    string Text,
    ReferenceKind? ReferenceKind,
    string? Reference,
    IReadOnlyList<Uri> Urls,
    SectionKind Section,
    string Raw,
    IReadOnlyList<string> Continuation,
    string IdentityKey)
{
    internal static readonly Regex FromRegex = new(@"\(from (\d{4}-\d{2}-\d{2})\)\s*$", RegexOptions.Compiled);

    /// <summary>The `(from YYYY-MM-DD)` note, if the text carries one.</summary>
    public string? CarriedFrom
    {
        get
        {
            var m = FromRegex.Match(Text);
            return m.Success ? m.Groups[1].Value : null;
        }
    }

    /// <summary>Normalised identity across days. See spec "Action identity across days".</summary>
    public static string IdentityKeyFor(string text)
    {
        var t = FromRegex.Replace(text, "", 1);
        t = Regex.Replace(t, @"\s+", " ").Trim().ToLowerInvariant();
        while (t.Length > 0 && ".;:".Contains(t[^1])) t = t[..^1];
        return t;
    }
}

/// <summary>A parsed journal entry. Immutable; re-parse after any write.</summary>
public sealed class JournalEntry
{
    public JournalEntry(string date, string fileName, string title, IReadOnlyList<string> lines, string newline,
                        IReadOnlyList<Section> sections, IReadOnlyList<CheckboxLine> checkboxes, IReadOnlyList<DoneItem> doneItems)
    {
        Date = date; FileName = fileName; Title = title; Lines = lines; Newline = newline;
        Sections = sections; Checkboxes = checkboxes; DoneItems = doneItems;
    }

    /// <summary>`YYYY-MM-DD`, from the file name.</summary>
    public string Date { get; }
    public string FileName { get; }
    public string Title { get; }
    public IReadOnlyList<string> Lines { get; }
    /// <summary>"\n" or "\r\n", whatever the file used (defaults to "\n").</summary>
    public string Newline { get; }
    public IReadOnlyList<Section> Sections { get; }
    public IReadOnlyList<CheckboxLine> Checkboxes { get; }
    /// <summary>Plain bullets under `## Done`.</summary>
    public IReadOnlyList<DoneItem> DoneItems { get; }

    /// <summary>Checkboxes in `## Actions` and `## Carried over`.</summary>
    public IReadOnlyList<CheckboxLine> Actions => Checkboxes.Where(c => c.Section.HoldsActions).ToList();
    public int OpenActionCount => Actions.Count(a => !a.IsChecked);

    public Section? SectionOf(SectionKind kind) => Sections.FirstOrDefault(s => s.Kind == kind);

    /// <summary>Raw text of a section body (without the heading).</summary>
    public string? TextOf(SectionKind kind)
    {
        var s = SectionOf(kind);
        return s is null ? null : BodyText(s, Newline);
    }

    public string BodyText(Section s, string separator = "\n") =>
        string.Join(separator, Lines.Skip(s.BodyStart).Take(s.BodyEnd - s.BodyStart));

    /// <summary>The whole file text as parsed.</summary>
    public string FullText => string.Join(Newline, Lines);

    /// <summary>Weekday-aware display title, falling back to the date.</summary>
    public string DisplayDate =>
        DateOnly.TryParseExact(Date, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var d)
            ? d.ToString("D", CultureInfo.CurrentCulture)
            : Date;
}
