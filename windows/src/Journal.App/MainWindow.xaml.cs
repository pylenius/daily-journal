using Journal.Store;
using Journal.Views;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Storage.Pickers;

namespace Journal;

public sealed partial class MainWindow : Window
{
    static string IconPath => Path.Combine(AppContext.BaseDirectory, "Assets", "Journal.ico");
    bool wasDeactivated;

    public MainWindow()
    {
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        AppWindow.SetIcon(IconPath);
        ResizeScaled(this, 1200, 820);
        TitleIcon.Source = new BitmapImage(new Uri(IconPath));

        App.Store.Changed += OnStoreChanged;
        App.Store.Error += ShowError;
        Activated += (_, e) =>
        {
            // Like the iOS scene becoming active: pick up whatever the Mac wrote meanwhile.
            if (e.WindowActivationState == WindowActivationState.Deactivated) { wasDeactivated = true; return; }
            if (wasDeactivated) { wasDeactivated = false; App.Store.ScheduleReload(); }
        };
        Nav.Loaded += (_, _) => { if (Nav.SelectedItem is null || Nav.SelectedItem == Nav.SettingsItem) Nav.SelectedItem = DaysItem; };
        OnStoreChanged();
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    static extern uint GetDpiForWindow(IntPtr hwnd);

    /// <summary>AppWindow sizes are in physical pixels; scale from effective pixels so the window fits at any display scale, centred on screen.</summary>
    public static void ResizeScaled(Window window, int width, int height)
    {
        var scale = GetDpiForWindow(WinRT.Interop.WindowNative.GetWindowHandle(window)) / 96.0;
        var area = DisplayArea.GetFromWindowId(window.AppWindow.Id, DisplayAreaFallback.Nearest).WorkArea;
        var w = Math.Min((int)(width * scale), area.Width);
        var h = Math.Min((int)(height * scale), area.Height);
        window.AppWindow.MoveAndResize(new Windows.Graphics.RectInt32(area.X + (area.Width - w) / 2, area.Y + (area.Height - h) / 2, w, h));
    }

    void OnStoreChanged()
    {
        var store = App.Store;
        var ready = store.FolderState == FolderState.Ready;
        Nav.Visibility = ready ? Visibility.Visible : Visibility.Collapsed;
        WelcomePanel.Visibility = ready ? Visibility.Collapsed : Visibility.Visible;
        TitleFolder.Text = ready ? store.FolderPath ?? "" : "";
        if (store.FolderState == FolderState.Unreachable)
        {
            WelcomeIcon.Glyph = "";
            WelcomeTitle.Text = "Journal folder unavailable";
            WelcomeText.Text = store.UnreachableMessage ?? "";
            RetryButton.Visibility = Visibility.Visible;
        }
        else
        {
            WelcomeIcon.Glyph = "";
            WelcomeTitle.Text = "Choose your journal folder";
            WelcomeText.Text = "Pick the folder where your daily journal files (YYYY-MM-DD.md) are written — for example "
                + @"the Journal folder in iCloud Drive (%USERPROFILE%\iCloudDrive\Journal) or OneDrive. "
                + "The app reads and updates those files in place.";
            RetryButton.Visibility = Visibility.Collapsed;
        }
        SetBadge(ActionsBadge, store.OpenActions.Count);
        SetBadge(InboxBadge, store.Inbox.Count);
        LoadingRing.IsActive = store.IsLoading;
    }

    static void SetBadge(InfoBadge badge, int count)
    {
        badge.Value = count;
        badge.Visibility = count > 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    void ShowError(string message)
    {
        ErrorBar.Message = message;
        ErrorBar.IsOpen = true;
    }

    // MARK: Navigation

    // Pages are built in code, which Frame navigation cannot instantiate, so they are hosted directly and kept alive.
    readonly Dictionary<Type, StorePage> pages = [];

    T Show<T>() where T : StorePage, new()
    {
        if (!pages.TryGetValue(typeof(T), out var page)) pages[typeof(T)] = page = new T();
        if (!ReferenceEquals(ContentHost.Content, page)) ContentHost.Content = page;
        return (T)page;
    }

    void OnNavSelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.IsSettingsSelected) { Show<SettingsPage>(); return; }
        switch ((args.SelectedItem as NavigationViewItem)?.Tag as string)
        {
            case "actions": Show<ActionsPage>(); break;
            case "search": Show<SearchPage>(); break;
            case "inbox": Show<InboxPage>(); break;
            default:
                var days = Show<DaysPage>();
                if (App.Arg("--openDate") is { } date && pages.Count == 1) days.Select(date);
                break;
        }
    }

    /// <summary>Opens a day on the Days page (from Actions, Search or a link).</summary>
    public void ShowDay(string date)
    {
        if (!ReferenceEquals(Nav.SelectedItem, DaysItem)) Nav.SelectedItem = DaysItem;
        Show<DaysPage>().Select(date);
    }

    // MARK: Commands

    async void OnCapture(object sender, RoutedEventArgs e) => await CaptureDialog.ShowAsync(Root.XamlRoot);

    async void OnCaptureAccelerator(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        args.Handled = true;
        if (App.Store.FolderState == FolderState.Ready) await CaptureDialog.ShowAsync(Root.XamlRoot);
    }

    async void OnReloadAccelerator(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        args.Handled = true;
        await App.Store.ReloadAsync();
    }

    void OnSearchAccelerator(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        args.Handled = true;
        Nav.SelectedItem = SearchItem;
    }

    async void OnRetry(object sender, RoutedEventArgs e) => await App.Store.ReloadAsync();

    async void OnChooseFolder(object sender, RoutedEventArgs e) => await PickFolderAsync();

    public async Task PickFolderAsync()
    {
        var picker = new FolderPicker { SuggestedStartLocation = PickerLocationId.DocumentsLibrary };
        picker.FileTypeFilter.Add("*");
        WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(this));
        var folder = await picker.PickSingleFolderAsync();
        if (folder is not null) App.Store.ChooseFolder(folder.Path);
    }
}
