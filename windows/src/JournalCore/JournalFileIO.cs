using System.Security.Cryptography;
using System.Text;

namespace JournalCore;

public sealed class ChangedSinceLoadException() : Exception("The entry changed on another device since you opened it.");

/// <summary>
/// All reads and writes to the journal folder. Windows has no file coordination, so every edit re-reads the file
/// right before writing and replaces it atomically; sync clients (OneDrive, iCloud, Google Drive) that briefly lock
/// a file are retried.
/// </summary>
public sealed class JournalFileIO(string root)
{
    public sealed record EntryFile(string Path, string Name, string Date, DateTime? Modified);
    public sealed record Loaded(string Text, DateTime? Modified, string Hash);

    static readonly UTF8Encoding Utf8NoBom = new(false);

    public string Root { get; } = root;
    public string InboxPath => Path.Combine(Root, "inbox");

    // MARK: Listing

    public IReadOnlyList<EntryFile> ListEntryFiles()
    {
        if (!Directory.Exists(Root)) throw new DirectoryNotFoundException("The journal folder is not reachable right now.");
        var files = new List<EntryFile>();
        foreach (var path in Directory.EnumerateFiles(Root, "*.md"))
        {
            var name = Path.GetFileName(path);
            if (JournalParser.DateFromFileName(name) is not { } date) continue;
            DateTime? modified = null;
            try { modified = File.GetLastWriteTimeUtc(path); } catch (IOException) { }
            files.Add(new EntryFile(path, name, date, modified));
        }
        return files.OrderByDescending(f => f.Date, StringComparer.Ordinal).ToList();
    }

    // MARK: Reading

    /// <summary>Reads an entry. A cloud-only placeholder is downloaded by the sync client on first read.</summary>
    public Loaded Read(string path) => Retry(() =>
    {
        var data = File.ReadAllBytes(path);
        return new Loaded(Decode(data), File.GetLastWriteTimeUtc(path), Hash(data));
    });

    // MARK: Writing

    /// <summary>Flips one checkbox. Re-reads first so a concurrent Mac write is never clobbered.</summary>
    public Loaded Toggle(string path, int line, string expectedRaw)
    {
        var flipped = CheckboxToggler.Flip(expectedRaw) ?? throw new LineEditException(EditFailure.LineNotFound);
        return EditLine(path, line, expectedRaw, flipped);
    }

    /// <summary>Replaces (or, with null, deletes) one line, located by position or unique text. Every other byte is kept.</summary>
    public Loaded EditLine(string path, int line, string expectedRaw, string? replacement) => Retry(() =>
    {
        var text = Decode(File.ReadAllBytes(path));
        var newText = LineEditor.Replace(text, line, expectedRaw, replacement);
        return WriteAtomic(path, newText);
    });

    /// <summary>Replaces the whole file. When <paramref name="expectedHash"/> is given and the file no longer matches it, nothing is written.</summary>
    public Loaded Write(string path, string text, string? expectedHash) => Retry(() =>
    {
        if (expectedHash is not null && File.Exists(path) && Hash(File.ReadAllBytes(path)) != expectedHash)
            throw new ChangedSinceLoadException();
        return WriteAtomic(path, text);
    });

    // MARK: Inbox

    public IReadOnlyList<InboxCapture> ListInbox()
    {
        if (!Directory.Exists(InboxPath)) return [];
        var captures = new List<InboxCapture>();
        foreach (var path in Directory.EnumerateFiles(InboxPath, "*.md"))
        {
            var name = Path.GetFileName(path);
            if (name.StartsWith('.')) continue;
            try { captures.Add(InboxParser.Parse(name, Decode(File.ReadAllBytes(path)))); }
            catch (IOException) { }
        }
        return captures.OrderByDescending(c => c.FileName, StringComparer.Ordinal).ToList();
    }

    /// <summary>Writes a new capture into `inbox/`. Never overwrites an existing file.</summary>
    public string WriteCapture(CaptureKind kind, string body, string? device, DateTimeOffset? now = null)
    {
        var (name, contents) = InboxWriter.MakeCapture(kind, body, device, now);
        Directory.CreateDirectory(InboxPath);
        using (var fs = new FileStream(Path.Combine(InboxPath, name), FileMode.CreateNew, FileAccess.Write))
        {
            var bytes = Utf8NoBom.GetBytes(contents);
            fs.Write(bytes);
        }
        return name;
    }

    // MARK: Helpers

    public static string Hash(byte[] data) => Convert.ToHexString(SHA256.HashData(data)).ToLowerInvariant();

    /// <summary>UTF-8, tolerating a BOM (which is kept out of the text; entries are written without one).</summary>
    static string Decode(byte[] data)
    {
        var span = data.AsSpan();
        if (span.StartsWith(Encoding.UTF8.Preamble)) span = span[3..];
        return Utf8NoBom.GetString(span);
    }

    static Loaded WriteAtomic(string path, string text)
    {
        var bytes = Utf8NoBom.GetBytes(text);
        var dir = Path.GetDirectoryName(path)!;
        var temp = Path.Combine(dir, $".{Path.GetFileName(path)}.{Guid.NewGuid():N}.tmp");
        try
        {
            File.WriteAllBytes(temp, bytes);
            File.Move(temp, path, overwrite: true);
        }
        finally
        {
            if (File.Exists(temp)) File.Delete(temp);
        }
        return new Loaded(text, File.GetLastWriteTimeUtc(path), Hash(bytes));
    }

    /// <summary>Retries briefly on sharing violations: sync clients hold files open while uploading or downloading.</summary>
    static T Retry<T>(Func<T> body)
    {
        for (var attempt = 0; ; attempt++)
        {
            try { return body(); }
            catch (IOException e) when (attempt < 5 && e is not FileNotFoundException and not DirectoryNotFoundException)
            {
                Thread.Sleep(150 * (attempt + 1));
            }
        }
    }
}
