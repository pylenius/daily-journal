using System.Globalization;

namespace JournalCore;

public enum CaptureKind { Note, Action }

/// <summary>A capture file in `inbox/`, written by a phone or PC and consumed by the Mac.</summary>
public sealed record InboxCapture(string FileName, CaptureKind Kind, DateTimeOffset? Created, string? Device, string Body)
{
    public string Id => FileName;
}

public static class InboxWriter
{
    /// <summary>File name and contents for a new capture, per spec "Inbox captures".</summary>
    public static (string FileName, string Contents) MakeCapture(CaptureKind kind, string body, string? device,
        DateTimeOffset? now = null, TimeZoneInfo? timeZone = null, Func<ushort>? random = null)
    {
        var tz = timeZone ?? TimeZoneInfo.Local;
        var local = TimeZoneInfo.ConvertTime(now ?? DateTimeOffset.UtcNow, tz);
        var stamp = local.ToString("yyyy-MM-dd-HHmmss", CultureInfo.InvariantCulture);
        var suffix = (random ?? (() => (ushort)Random.Shared.Next(0, 0x10000)))().ToString("x4");
        var iso = local.ToString("yyyy-MM-dd'T'HH:mm:ss", CultureInfo.InvariantCulture)
                  + (local.Offset == TimeSpan.Zero ? "Z" : local.ToString("zzz", CultureInfo.InvariantCulture));
        var header = $"kind: {(kind == CaptureKind.Action ? "action" : "note")}\ncreated: {iso}\n";
        if (!string.IsNullOrEmpty(device)) header += $"device: {device}\n";
        return ($"{stamp}-{suffix}.md", header + "\n" + body.Trim() + "\n");
    }
}

public static class InboxParser
{
    /// <summary>Parses a capture file. Unknown header keys are ignored; missing `kind` means `note`.</summary>
    public static InboxCapture Parse(string fileName, string contents)
    {
        var normalised = contents.Replace("\r\n", "\n");
        var parts = normalised.Split("\n\n");
        var headers = new Dictionary<string, string>();
        var body = normalised;
        var headerLines = parts[0].Split('\n');
        var looksLikeHeader = headerLines.Length > 0 && headerLines.All(line =>
        {
            var colon = line.IndexOf(':');
            if (colon <= 0) return false;
            return line[..colon].All(c => char.IsLetter(c) || c is '_' or '-');
        });
        if (looksLikeHeader)
        {
            foreach (var line in headerLines)
            {
                var colon = line.IndexOf(':');
                headers[line[..colon].ToLowerInvariant()] = line[(colon + 1)..].Trim();
            }
            body = string.Join("\n\n", parts.Skip(1));
        }
        var kind = headers.GetValueOrDefault("kind") == "action" ? CaptureKind.Action : CaptureKind.Note;
        DateTimeOffset? created = headers.TryGetValue("created", out var c)
            && DateTimeOffset.TryParse(c, CultureInfo.InvariantCulture, DateTimeStyles.None, out var d) ? d : null;
        return new InboxCapture(fileName, kind, created, headers.GetValueOrDefault("device"), body.Trim());
    }
}
