using System.Globalization;
using JournalCore;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Journal.Views;

/// <summary>Every open action across all days, one per action, grouped by the day holding its newest copy.</summary>
public sealed class ActionsPage : StorePage
{
    protected override void Refresh()
    {
        var store = App.Store;
        var panel = new StackPanel { Spacing = 4 };
        panel.Children.Add(Ui.PageTitle("Open actions"));
        if (store.OpenActions.Count == 0)
        {
            panel.Children.Add(Ui.Empty("", "Nothing open", "Every action in the journal is ticked."));
        }
        foreach (var day in store.OpenActions.GroupBy(a => a.Latest.Date).OrderByDescending(g => g.Key, StringComparer.Ordinal))
        {
            var link = new HyperlinkButton
            {
                Content = store.Entry(day.Key)?.DisplayDate ?? day.Key,
                Padding = new Thickness(4, 2, 4, 2),
                Margin = new Thickness(0, 12, 0, 4),
            };
            link.Click += (_, _) => App.MainWindow.ShowDay(day.Key);
            panel.Children.Add(link);
            panel.Children.Add(Ui.RowsCard(day.OrderBy(a => a.Latest.Line).Select(a =>
                Ui.ActionRow(a.Latest, a.SeenOn.Count > 1 ? $"since {a.FirstSeen} · {a.SeenOn.Count} days" : null))));
        }
        Content = Ui.Scroll(panel);
    }
}

/// <summary>Every line of every entry; all words must match on the same line.</summary>
public sealed class SearchPage : StorePage
{
    readonly TextBox query = new() { PlaceholderText = "Search the journal", Margin = new Thickness(0, 0, 0, 12) };
    readonly StackPanel results = new() { Spacing = 4 };

    public SearchPage()
    {
        var panel = new StackPanel();
        panel.Children.Add(Ui.PageTitle("Search"));
        panel.Children.Add(query);
        panel.Children.Add(results);
        Content = Ui.Scroll(panel);
        query.TextChanged += (_, _) => Refresh();
        Loaded += (_, _) => query.Focus(FocusState.Programmatic);
    }

    protected override void Refresh()
    {
        results.Children.Clear();
        var index = App.Store.Index;
        if (string.IsNullOrWhiteSpace(query.Text))
        {
            results.Children.Add(Ui.Secondary($"{index.LineCount} lines in {App.Store.Entries.Count} entries.", 13));
            return;
        }
        var hits = index.Search(query.Text);
        if (hits.Count == 0)
        {
            results.Children.Add(Ui.Empty("", "No results", $"Nothing matches “{query.Text}”."));
            return;
        }
        foreach (var day in hits.GroupBy(h => h.Date))
        {
            results.Children.Add(Ui.SectionHeader(App.Store.Entry(day.Key)?.DisplayDate ?? day.Key));
            var rows = new StackPanel { Spacing = 2 };
            foreach (var hit in day)
            {
                var content = new StackPanel { HorizontalAlignment = HorizontalAlignment.Left };
                content.Children.Add(new TextBlock { Text = hit.LineText.Trim(), TextWrapping = TextWrapping.Wrap });
                content.Children.Add(new TextBlock { Text = hit.Section.Title, FontSize = 11, Foreground = Ui.Res("TextFillColorTertiaryBrush") });
                var button = new Button
                {
                    Content = content,
                    HorizontalAlignment = HorizontalAlignment.Stretch,
                    HorizontalContentAlignment = HorizontalAlignment.Left,
                    Padding = new Thickness(12, 8, 12, 8),
                };
                var date = hit.Date;
                button.Click += (_, _) => App.MainWindow.ShowDay(date);
                rows.Children.Add(button);
            }
            results.Children.Add(rows);
        }
    }
}

/// <summary>Captures waiting for the next journal run. Read-only: only the writer archives them.</summary>
public sealed class InboxPage : StorePage
{
    protected override void Refresh()
    {
        var panel = new StackPanel { Spacing = 4 };
        panel.Children.Add(Ui.PageTitle("Inbox"));
        var inbox = App.Store.Inbox;
        if (inbox.Count == 0)
        {
            panel.Children.Add(Ui.Empty("", "Inbox is empty", "Quick captures (Ctrl+N) wait here until the next journal run folds them in."));
        }
        else
        {
            panel.Children.Add(Ui.Secondary("Waiting for the next journal run on the Mac.", 13));
            panel.Children.Add(Ui.RowsCard(inbox.Select(Row)));
        }
        Content = Ui.Scroll(panel);
    }

    static UIElement Row(InboxCapture capture)
    {
        var panel = new StackPanel { Spacing = 2 };
        var meta = new List<string> { capture.Kind == CaptureKind.Action ? "Action" : "Note" };
        if (capture.Created is { } created) meta.Add(created.ToLocalTime().ToString("g", CultureInfo.CurrentCulture));
        if (!string.IsNullOrEmpty(capture.Device)) meta.Add(capture.Device);
        panel.Children.Add(new TextBlock { Text = string.Join(" · ", meta), FontSize = 12, Foreground = Ui.Res("TextFillColorSecondaryBrush") });
        panel.Children.Add(Rendering.MarkdownRenderer.InlineTextBlock(capture.Body));
        return panel;
    }
}

public sealed class SettingsPage : StorePage
{
    protected override void Refresh()
    {
        var store = App.Store;
        var panel = new StackPanel { Spacing = 4 };
        panel.Children.Add(Ui.PageTitle("Settings"));

        panel.Children.Add(Ui.SectionHeader("Journal folder"));
        var folder = new StackPanel { Spacing = 8 };
        folder.Children.Add(new TextBlock { Text = store.FolderPath ?? "—", TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true });
        var facts = $"{store.Entries.Count} entries";
        if (store.LastRefresh is { } last) facts += $" · last refresh {last.ToString("T", CultureInfo.CurrentCulture)}";
        folder.Children.Add(Ui.Secondary(facts));
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        var choose = new Button { Content = "Choose another folder…" };
        choose.Click += async (_, _) => await App.MainWindow.PickFolderAsync();
        var reload = new Button { Content = "Reload now" };
        reload.Click += async (_, _) => await store.ReloadAsync();
        var forget = new Button { Content = "Forget folder" };
        forget.Click += (_, _) => store.ForgetFolder();
        buttons.Children.Add(choose);
        buttons.Children.Add(reload);
        buttons.Children.Add(forget);
        folder.Children.Add(buttons);
        panel.Children.Add(Ui.Card(folder));

        panel.Children.Add(Ui.SectionHeader("About"));
        var about = new StackPanel { Spacing = 8 };
        about.Children.Add(Ui.Secondary("Journal reads the Markdown files written by the daily-journal Claude Code plugin. "
            + "Ticking a box edits the file in place; captures land in the inbox folder for the next run. "
            + "Sync is whatever keeps the folder in step: iCloud for Windows, OneDrive, Google Drive, …", 13));
        about.Children.Add(new HyperlinkButton { Content = "Source code and format spec", NavigateUri = new Uri("https://github.com/pylenius/daily-journal"), Padding = new Thickness(0) });
        about.Children.Add(Ui.Secondary($"Version {typeof(App).Assembly.GetName().Version?.ToString(3)}"));
        about.Children.Add(Ui.Secondary("Shortcuts: Ctrl+N quick capture · F5 reload · Ctrl+F search"));
        panel.Children.Add(Ui.Card(about));
        Content = Ui.Scroll(panel);
    }
}
