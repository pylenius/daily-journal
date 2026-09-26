namespace JournalCore;

/// <summary>One action as seen across days: the newest copy decides its state.</summary>
public sealed record AggregatedAction(string Key, CheckboxLine Latest, IReadOnlyList<string> SeenOn)
{
    public bool IsOpen => !Latest.IsChecked;
    public string FirstSeen => SeenOn.Count > 0 ? SeenOn[0] : Latest.Date;
}

public static class OpenActionsAggregator
{
    /// <summary>All actions from `## Actions` / `## Carried over`, one per identity key, newest copy wins.</summary>
    public static IReadOnlyList<AggregatedAction> Aggregate(IEnumerable<JournalEntry> entries)
    {
        var byKey = new Dictionary<string, (CheckboxLine Latest, SortedSet<string> Dates)>();
        foreach (var entry in entries)
        {
            foreach (var cb in entry.Actions)
            {
                if (byKey.TryGetValue(cb.IdentityKey, out var existing))
                {
                    existing.Dates.Add(cb.Date);
                    var cmp = string.CompareOrdinal(cb.Date, existing.Latest.Date);
                    if (cmp > 0 || (cmp == 0 && cb.Line > existing.Latest.Line)) existing.Latest = cb;
                    byKey[cb.IdentityKey] = existing;
                }
                else
                {
                    byKey[cb.IdentityKey] = (cb, new SortedSet<string>(StringComparer.Ordinal) { cb.Date });
                }
            }
        }
        return byKey.Select(kv => new AggregatedAction(kv.Key, kv.Value.Latest, kv.Value.Dates.ToList()))
            .OrderByDescending(a => a.Latest.Date, StringComparer.Ordinal)
            .ThenBy(a => a.Latest.Line)
            .ToList();
    }

    /// <summary>Only the open ones, newest day first, file order within a day.</summary>
    public static IReadOnlyList<AggregatedAction> OpenActions(IEnumerable<JournalEntry> entries) =>
        Aggregate(entries).Where(a => a.IsOpen).ToList();
}
