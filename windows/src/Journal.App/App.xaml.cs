using Journal.Store;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;

namespace Journal;

public partial class App : Application
{
    public static JournalStore Store { get; private set; } = null!;
    public static MainWindow MainWindow { get; private set; } = null!;

    /// <summary>`--journalFolder <path>` skips the picker; `--openDate YYYY-MM-DD` opens that day (as on iOS).</summary>
    public static string? Arg(string name)
    {
        var args = Environment.GetCommandLineArgs();
        var i = Array.FindIndex(args, a => a.Equals(name, StringComparison.OrdinalIgnoreCase));
        return i >= 0 && i + 1 < args.Length ? args[i + 1] : null;
    }

    public App()
    {
        InitializeComponent();
        UnhandledException += (_, e) =>
        {
            e.Handled = true;
            Store?.ReportError(e.Exception.Message);
        };
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        Store = new JournalStore(DispatcherQueue.GetForCurrentThread());
        MainWindow = new MainWindow();
        MainWindow.Activate();
        if (Arg("--journalFolder") is { } folder) Store.ChooseFolder(folder); else Store.Restore();
    }
}
