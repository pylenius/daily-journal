using System.Text.Json;
using JournalCore;
using Microsoft.UI.Dispatching;

namespace Journal.Store;

public enum FolderState { NotChosen, Ready, Unreachable }

/// <summary>
/// The app's single source of truth, mirroring ios/Journal/Store/JournalStore.swift. File work runs on the thread
/// pool; state changes land on the UI thread and raise <see cref="Changed"/>, which pages use to rebuild.
/// </summary>
public sealed class JournalStore(DispatcherQueue dispatcher)
{
    public FolderState FolderState { get; private set; } = FolderState.NotChosen;
    public string? FolderPath { get; private set; }
    public string? UnreachableMessage { get; private set; }
    /// <summary>Newest first.</summary>
    public IReadOnlyList<JournalEntry> Entries { get; private set; } = [];
    /// <summary>Entry files that could not be read yet (still downloading from the sync provider).</summary>
    public IReadOnlyList<string> Placeholders { get; private set; } = [];
    public IReadOnlyList<InboxCapture> Inbox { get; private set; } = [];
    public IReadOnlyList<AggregatedAction> OpenActions { get; private set; } = [];
    public SearchIndex Index { get; private set; } = new([]);
    public DateTime? LastRefresh { get; private set; }
    public bool IsLoading { get; private set; }

    /// <summary>Raised on the UI thread after anything above changed.</summary>
    public event Action? Changed;
    /// <summary>Raised on the UI thread with a message to show.</summary>
    public event Action<string>? Error;

    readonly Dictionary<string, string> hashes = [];
    readonly Dictionary<string, string> paths = [];
    JournalFileIO? io;
    FolderWatcher? watcher;
    DispatcherQueueTimer? reloadTimer;

    public const string DeviceName = "Windows";

    public string? HashOf(string date) => hashes.GetValueOrDefault(date);
    public JournalEntry? Entry(string date) => Entries.FirstOrDefault(e => e.Date == date);
    public string FolderName => FolderPath is null ? "—" : Path.GetFileName(Path.TrimEndingDirectorySeparator(FolderPath));

    // MARK: Folder

    public void Restore()
    {
        if (AppSettings.Load().JournalFolder is { } path) Activate(path);
        else SetState(FolderState.NotChosen);
    }

    public void ChooseFolder(string path)
    {
        var settings = AppSettings.Load();
        settings.JournalFolder = path;
        settings.Save();
        Activate(path);
    }

    public void ForgetFolder()
    {
        var settings = AppSettings.Load();
        settings.JournalFolder = null;
        settings.Save();
        watcher?.Dispose(); watcher = null; io = null;
        FolderPath = null;
        Entries = []; Placeholders = []; Inbox = []; OpenActions = []; Index = new([]);
        hashes.Clear(); paths.Clear();
        SetState(FolderState.NotChosen);
    }

    void Activate(string path)
    {
        watcher?.Dispose(); watcher = null;
        FolderPath = path;
        if (!Directory.Exists(path))
        {
            UnreachableMessage = $"The journal folder is not reachable right now.\n{path}";
            SetState(FolderState.Unreachable);
            return;
        }
        io = new JournalFileIO(path);
        SetState(FolderState.Ready);
        try { watcher = new FolderWatcher(path, () => dispatcher.TryEnqueue(ScheduleReload)); }
        catch (Exception) { /* network or unusual file systems may not support watching; F5 and activation still reload */ }
        _ = ReloadAsync();
    }

    void SetState(FolderState state)
    {
        FolderState = state;
        Changed?.Invoke();
    }

    // MARK: Loading

    /// <summary>Debounced reload for watcher bursts and window activation.</summary>
    public void ScheduleReload()
    {
        reloadTimer ??= CreateReloadTimer();
        reloadTimer.Stop();
        reloadTimer.Start();
    }

    DispatcherQueueTimer CreateReloadTimer()
    {
        var t = dispatcher.CreateTimer();
        t.Interval = TimeSpan.FromMilliseconds(600);
        t.IsRepeating = false;
        t.Tick += (_, _) => _ = ReloadAsync();
        return t;
    }

    public async Task ReloadAsync()
    {
        if (io is null)
        {
            if (FolderPath is not null) Activate(FolderPath);
            return;
        }
        var fileIO = io;
        IsLoading = true;
        Changed?.Invoke();
        var previous = Entries.ToDictionary(e => e.Date);
        var previousHashes = new Dictionary<string, string>(hashes);
        try
        {
            var result = await Task.Run(() =>
            {
                var entries = new List<JournalEntry>();
                var newHashes = new Dictionary<string, string>();
                var newPaths = new Dictionary<string, string>();
                var placeholders = new List<string>();
                foreach (var f in fileIO.ListEntryFiles())
                {
                    newPaths[f.Date] = f.Path;
                    try
                    {
                        var loaded = fileIO.Read(f.Path);
                        entries.Add(previousHashes.GetValueOrDefault(f.Date) == loaded.Hash && previous.TryGetValue(f.Date, out var existing)
                            ? existing
                            : JournalParser.Parse(loaded.Text, f.Name));
                        newHashes[f.Date] = loaded.Hash;
                    }
                    catch (Exception)
                    {
                        placeholders.Add(f.Date);
                    }
                }
                IReadOnlyList<InboxCapture> inbox;
                try { inbox = fileIO.ListInbox(); } catch (Exception) { inbox = []; }
                return (entries, newHashes, newPaths, placeholders, inbox);
            });
            if (io != fileIO) return; // folder changed meanwhile
            Entries = result.entries.OrderByDescending(e => e.Date, StringComparer.Ordinal).ToList();
            hashes.Clear(); foreach (var kv in result.newHashes) hashes[kv.Key] = kv.Value;
            paths.Clear(); foreach (var kv in result.newPaths) paths[kv.Key] = kv.Value;
            Placeholders = result.placeholders;
            Inbox = result.inbox;
            RebuildDerived();
            LastRefresh = DateTime.Now;
            if (FolderState != FolderState.Ready) FolderState = FolderState.Ready;
        }
        catch (Exception e)
        {
            UnreachableMessage = e.Message;
            FolderState = FolderState.Unreachable;
        }
        finally
        {
            IsLoading = false;
            Changed?.Invoke();
        }
    }

    void RebuildDerived()
    {
        OpenActions = OpenActionsAggregator.OpenActions(Entries);
        Index = new SearchIndex(Entries);
    }

    // MARK: Mutations

    public Task ToggleAsync(CheckboxLine cb) =>
        MutateAsync(cb.Date, (fileIO, path) => fileIO.Toggle(path, cb.Line, cb.Raw));

    public Task RemoveAsync(DoneItem item) =>
        MutateAsync(item.Date, (fileIO, path) => fileIO.EditLine(path, item.Line, item.Raw, null));

    public Task ToggleHighlightAsync(DoneItem item)
    {
        if (LineEditor.HighlightToggled(item.Raw) is not { } replacement) return Task.CompletedTask;
        return MutateAsync(item.Date, (fileIO, path) => fileIO.EditLine(path, item.Line, item.Raw, replacement));
    }

    async Task MutateAsync(string date, Func<JournalFileIO, string, JournalFileIO.Loaded> edit)
    {
        if (io is not { } fileIO || !paths.TryGetValue(date, out var path)) return;
        try
        {
            var loaded = await Task.Run(() => edit(fileIO, path));
            Apply(loaded, date, Path.GetFileName(path));
        }
        catch (Exception e)
        {
            ReportError(e.Message);
            await ReloadAsync();
        }
    }

    /// <summary>Full-text save. Throws <see cref="ChangedSinceLoadException"/> when the file moved on.</summary>
    public async Task SaveAsync(string date, string text, string? expectedHash)
    {
        if (io is not { } fileIO || !paths.TryGetValue(date, out var path)) return;
        var loaded = await Task.Run(() => fileIO.Write(path, text, expectedHash));
        Apply(loaded, date, Path.GetFileName(path));
    }

    public async Task CaptureAsync(CaptureKind kind, string body)
    {
        if (io is not { } fileIO) return;
        try
        {
            Inbox = await Task.Run(() =>
            {
                fileIO.WriteCapture(kind, body, DeviceName);
                return fileIO.ListInbox();
            });
            Changed?.Invoke();
        }
        catch (Exception e)
        {
            ReportError(e.Message);
        }
    }

    void Apply(JournalFileIO.Loaded loaded, string date, string fileName)
    {
        var entry = JournalParser.Parse(loaded.Text, fileName);
        hashes[date] = loaded.Hash;
        Entries = Entries.Where(e => e.Date != date).Append(entry).OrderByDescending(e => e.Date, StringComparer.Ordinal).ToList();
        RebuildDerived();
        Changed?.Invoke();
    }

    public void ReportError(string message)
    {
        if (dispatcher.HasThreadAccess) Error?.Invoke(message);
        else dispatcher.TryEnqueue(() => Error?.Invoke(message));
    }
}

/// <summary>Per-user settings in %LOCALAPPDATA%\DailyJournal\settings.json.</summary>
public sealed class AppSettings
{
    public string? JournalFolder { get; set; }

    static string FilePath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DailyJournal", "settings.json");

    public static AppSettings Load()
    {
        try { return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath)) ?? new(); }
        catch (Exception) { return new(); }
    }

    public void Save()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
        File.WriteAllText(FilePath, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
    }
}
