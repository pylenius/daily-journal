using System.Globalization;
using System.Text;

namespace JournalCore;

public sealed record SearchHit(string Date, int Line, string LineText, SectionKind Section)
{
    public string Id => $"{Date}#{Line}";
}

/// <summary>
/// Case- and diacritic-insensitive substring search over every line of every entry.
/// Every query term must occur on the same line (AND). Small enough to rebuild on each folder change.
/// </summary>
public sealed class SearchIndex
{
    readonly record struct Row(string Date, int Line, string Text, string Folded, SectionKind Section);
    readonly List<Row> rows = [];

    public SearchIndex(IEnumerable<JournalEntry> entries)
    {
        foreach (var e in entries)
            foreach (var s in e.Sections)
                foreach (var i in s.BodyLines)
                {
                    var t = e.Lines[i];
                    if (t.Trim().Length == 0) continue;
                    rows.Add(new Row(e.Date, i, t, Fold(t), s.Kind));
                }
    }

    public int LineCount => rows.Count;

    public static string Fold(string s)
    {
        var sb = new StringBuilder(s.Length);
        foreach (var c in s.Normalize(NormalizationForm.FormD))
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) sb.Append(c);
        return sb.ToString().Normalize(NormalizationForm.FormC).ToLowerInvariant();
    }

    public static IReadOnlyList<string> Terms(string query) =>
        query.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Select(Fold).Where(t => t.Length > 0).ToList();

    /// <summary>Hits newest day first, file order within a day.</summary>
    public IReadOnlyList<SearchHit> Search(string query, int limit = 200)
    {
        var terms = Terms(query);
        if (terms.Count == 0) return [];
        return rows.Where(r => terms.All(t => r.Folded.Contains(t, StringComparison.Ordinal)))
            .Select(r => new SearchHit(r.Date, r.Line, r.Text, r.Section))
            .OrderByDescending(h => h.Date, StringComparer.Ordinal)
            .ThenBy(h => h.Line)
            .Take(limit)
            .ToList();
    }
}
