using JournalCore;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.ApplicationModel.DataTransfer;

namespace Journal.Views;

/// <summary>Raw Markdown editor with a stale-file guard, one window per day.</summary>
public sealed class EditWindow : Window
{
    static readonly Dictionary<string, EditWindow> OpenWindows = [];

    readonly string date;
    readonly string? loadedHash;
    readonly string original;
    readonly TextBox editor;
    readonly InfoBar staleBar;
    readonly Grid root;
    bool closingConfirmed;

    public static void Open(string date)
    {
        if (OpenWindows.TryGetValue(date, out var existing)) { existing.Activate(); return; }
        if (App.Store.Entry(date) is not { } entry) return;
        var window = new EditWindow(entry);
        OpenWindows[date] = window;
        window.Activate();
    }

    EditWindow(JournalEntry entry)
    {
        date = entry.Date;
        loadedHash = App.Store.HashOf(date);
        original = entry.FullText;
        Title = $"Edit {date}";
        SystemBackdrop = new MicaBackdrop();
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "Journal.ico"));
        MainWindow.ResizeScaled(this, 900, 800);

        staleBar = new InfoBar
        {
            Severity = InfoBarSeverity.Warning,
            Message = "This entry changed on another device while you were editing.",
            IsClosable = false,
            IsOpen = false,
        };
        editor = new TextBox
        {
            Text = original,
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            FontFamily = new FontFamily("Cascadia Mono, Consolas"),
            IsSpellCheckEnabled = false,
        };
        ScrollViewer.SetVerticalScrollBarVisibility(editor, ScrollBarVisibility.Auto);
        var save = new Button { Content = "Save", Style = (Style)Application.Current.Resources["AccentButtonStyle"] };
        save.Click += async (_, _) => await SaveAsync(force: false);
        var cancel = new Button { Content = "Cancel" };
        cancel.Click += async (_, _) => await CloseWithConfirmAsync();
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Right, Children = { cancel, save } };

        root = new Grid { Padding = new Thickness(16), RowSpacing = 12 };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        Grid.SetRow(editor, 1);
        Grid.SetRow(buttons, 2);
        root.Children.Add(staleBar);
        root.Children.Add(editor);
        root.Children.Add(buttons);
        root.KeyboardAccelerators.Add(Accelerator(Windows.System.VirtualKey.S, async () => await SaveAsync(force: false)));
        Content = root;

        App.Store.Changed += OnStoreChanged;
        AppWindow.Closing += OnClosing;
        Closed += (_, _) =>
        {
            App.Store.Changed -= OnStoreChanged;
            OpenWindows.Remove(date);
        };
    }

    static Microsoft.UI.Xaml.Input.KeyboardAccelerator Accelerator(Windows.System.VirtualKey key, Action action)
    {
        var a = new Microsoft.UI.Xaml.Input.KeyboardAccelerator { Key = key, Modifiers = Windows.System.VirtualKeyModifiers.Control };
        a.Invoked += (_, e) => { e.Handled = true; action(); };
        return a;
    }

    bool Dirty => editor.Text.Replace("\r\n", "\n").Replace("\r", "\n") != original.Replace("\r\n", "\n");

    void OnStoreChanged() => staleBar.IsOpen = loadedHash is not null && App.Store.HashOf(date) != loadedHash;

    /// <summary>The TextBox normalises line endings to CR; write back with the newline style the file had.</summary>
    string TextToSave()
    {
        var newline = App.Store.Entry(date)?.Newline ?? "\n";
        return editor.Text.Replace("\r\n", "\n").Replace("\r", "\n").Replace("\n", newline);
    }

    async Task SaveAsync(bool force)
    {
        try
        {
            await App.Store.SaveAsync(date, TextToSave(), force ? null : loadedHash);
            closingConfirmed = true;
            Close();
        }
        catch (ChangedSinceLoadException)
        {
            var dialog = new ContentDialog
            {
                XamlRoot = root.XamlRoot,
                Title = "The entry changed on another device",
                Content = "Overwrite it with your version, or copy your text to the clipboard and discard it?",
                PrimaryButtonText = "Overwrite",
                SecondaryButtonText = "Copy and discard",
                CloseButtonText = "Keep editing",
                DefaultButton = ContentDialogButton.Close,
            };
            switch (await dialog.ShowAsync())
            {
                case ContentDialogResult.Primary:
                    await SaveAsync(force: true);
                    break;
                case ContentDialogResult.Secondary:
                    var package = new DataPackage();
                    package.SetText(editor.Text);
                    Clipboard.SetContent(package);
                    closingConfirmed = true;
                    Close();
                    break;
            }
        }
        catch (Exception e)
        {
            staleBar.Severity = InfoBarSeverity.Error;
            staleBar.Message = $"Could not save: {e.Message}";
            staleBar.IsOpen = true;
        }
    }

    /// <summary>The title-bar close button. Closing from code (Cancel) does not raise this, so both go through <see cref="CloseWithConfirmAsync"/>.</summary>
    async void OnClosing(AppWindow sender, AppWindowClosingEventArgs args)
    {
        if (closingConfirmed || !Dirty) return;
        args.Cancel = true;
        await CloseWithConfirmAsync();
    }

    async Task CloseWithConfirmAsync()
    {
        if (closingConfirmed || !Dirty)
        {
            closingConfirmed = true;
            Close();
            return;
        }
        var dialog = new ContentDialog
        {
            XamlRoot = root.XamlRoot,
            Title = "Save your changes?",
            PrimaryButtonText = "Save",
            SecondaryButtonText = "Discard",
            CloseButtonText = "Keep editing",
            DefaultButton = ContentDialogButton.Primary,
        };
        switch (await dialog.ShowAsync())
        {
            case ContentDialogResult.Primary:
                await SaveAsync(force: false);
                break;
            case ContentDialogResult.Secondary:
                closingConfirmed = true;
                Close();
                break;
        }
    }
}
