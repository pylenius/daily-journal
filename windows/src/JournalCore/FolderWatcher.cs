namespace JournalCore;

/// <summary>
/// Fires <c>onChange</c> (debounced) when a Markdown file in the journal folder or its <c>inbox/</c> changes,
/// whether written locally or by the sync client.
/// </summary>
public sealed class FolderWatcher : IDisposable
{
    readonly FileSystemWatcher watcher;
    readonly Timer timer;
    readonly Action onChange;
    readonly TimeSpan delay;

    public FolderWatcher(string folder, Action onChange, TimeSpan? debounce = null)
    {
        this.onChange = onChange;
        delay = debounce ?? TimeSpan.FromMilliseconds(600);
        timer = new Timer(_ => this.onChange(), null, Timeout.Infinite, Timeout.Infinite);
        watcher = new FileSystemWatcher(folder, "*.md")
        {
            IncludeSubdirectories = true,
            NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.Size | NotifyFilters.DirectoryName,
        };
        watcher.Changed += (_, e) => Poke(e.FullPath);
        watcher.Created += (_, e) => Poke(e.FullPath);
        watcher.Deleted += (_, e) => Poke(e.FullPath);
        watcher.Renamed += (_, e) => Poke(e.FullPath);
        watcher.Error += (_, _) => Poke(null);
        watcher.EnableRaisingEvents = true;
    }

    void Poke(string? path)
    {
        // Our own atomic-write temp files start with a dot; the archive is not shown.
        if (path is not null && (Path.GetFileName(path).StartsWith('.') || path.Contains($"{Path.DirectorySeparatorChar}archive{Path.DirectorySeparatorChar}")))
            return;
        timer.Change(delay, Timeout.InfiniteTimeSpan);
    }

    public void Dispose()
    {
        watcher.Dispose();
        timer.Dispose();
    }
}
