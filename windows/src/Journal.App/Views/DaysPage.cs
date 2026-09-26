using System.Globalization;
using JournalCore;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Journal.Views;

/// <summary>Every entry grouped by month on the left, the selected day on the right.</summary>
public sealed class DaysPage : StorePage
{
    readonly ListView list = new() { SelectionMode = ListViewSelectionMode.Single, Padding = new Thickness(0, 0, 0, 16) };
    readonly InfoBar downloading = new() { Severity = InfoBarSeverity.Informational, IsClosable = false, Margin = new Thickness(12, 0, 12, 8) };
    readonly ScrollViewer detail = new() { VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    readonly Grid detailHost = new() { MaxWidth = 900, Padding = new Thickness(24, 16, 24, 32) };
    string? selectedDate;
    string listSignature = "";
    JournalEntry? shownEntry;
    bool detailsExpanded;
    bool suppressSelection;

    public DaysPage()
    {
        var root = new Grid();
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(300) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var left = new Grid();
        left.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        left.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        left.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        var title = Ui.PageTitle("Journal");
        title.Margin = new Thickness(24, 16, 12, 8);
        left.Children.Add(title);
        Grid.SetRow(downloading, 1);
        left.Children.Add(downloading);
        Grid.SetRow(list, 2);
        left.Children.Add(list);
        list.SelectionChanged += (_, _) =>
        {
            if (suppressSelection) return;
            if (list.SelectedItem is ListViewItem { Tag: string date }) { selectedDate = date; ShowDetail(); }
        };

        detail.Content = detailHost;
        var divider = new Border { Width = 1, Background = Ui.Res("DividerStrokeColorDefaultBrush"), HorizontalAlignment = HorizontalAlignment.Left };
        Grid.SetColumn(divider, 1);
        Grid.SetColumn(detail, 1);
        root.Children.Add(left);
        root.Children.Add(divider);
        root.Children.Add(detail);
        Content = root;
    }

    public void Select(string date)
    {
        selectedDate = date;
        if (IsLoaded) Refresh();
    }

    protected override void Refresh()
    {
        var store = App.Store;
        downloading.IsOpen = store.Placeholders.Count > 0;
        downloading.Title = $"{store.Placeholders.Count} entries still downloading";

        if (store.Entries.Count > 0 && (selectedDate is null || store.Entry(selectedDate) is null)) selectedDate = store.Entries[0].Date;
        RebuildList();
        ShowDetail();
    }

    void RebuildList()
    {
        var entries = App.Store.Entries;
        var signature = string.Join("|", entries.Select(e => $"{e.Date}:{e.DoneItems.Count}:{e.OpenActionCount}"));
        suppressSelection = true;
        try
        {
            if (signature != listSignature)
            {
                listSignature = signature;
                list.Items.Clear();
                foreach (var month in entries.GroupBy(e => e.Date[..7]))
                {
                    list.Items.Add(new ListViewItem
                    {
                        Content = new TextBlock { Text = MonthTitle(month.Key), Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"], Margin = new Thickness(0, 12, 0, 2) },
                        IsHitTestVisible = false,
                        IsTabStop = false,
                        MinHeight = 0,
                    });
                    foreach (var entry in month) list.Items.Add(DayRow(entry));
                }
            }
            list.SelectedItem = list.Items.OfType<ListViewItem>().FirstOrDefault(i => i.Tag as string == selectedDate);
            if (list.SelectedItem is not null) list.ScrollIntoView(list.SelectedItem);
        }
        finally { suppressSelection = false; }
    }

    static ListViewItem DayRow(JournalEntry entry)
    {
        var date = DateOnly.ParseExact(entry.Date, "yyyy-MM-dd", CultureInfo.InvariantCulture);
        var info = new List<string>();
        if (entry.DoneItems.Count > 0) info.Add($"{entry.DoneItems.Count} done");
        if (entry.OpenActionCount > 0) info.Add($"{entry.OpenActionCount} open");
        var panel = new StackPanel { Padding = new Thickness(0, 6, 0, 6) };
        panel.Children.Add(new TextBlock { Text = date.ToString("dddd d.M.", CultureInfo.CurrentCulture) });
        panel.Children.Add(new TextBlock { Text = info.Count > 0 ? string.Join(" · ", info) : entry.Date, FontSize = 12, Foreground = Ui.Res("TextFillColorSecondaryBrush") });
        return new ListViewItem { Content = panel, Tag = entry.Date };
    }

    static string MonthTitle(string ym) =>
        DateOnly.TryParseExact(ym + "-01", "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var d)
            ? d.ToString("MMMM yyyy", CultureInfo.CurrentCulture)
            : ym;

    void ShowDetail()
    {
        var store = App.Store;
        if (selectedDate is null || store.Entry(selectedDate) is not { } entry)
        {
            shownEntry = null;
            detailHost.Children.Clear();
            detailHost.Children.Add(store.IsLoading && store.Entries.Count == 0
                ? new ProgressRing { IsActive = true, Margin = new Thickness(0, 48, 0, 0) }
                : Ui.Empty("", "No entries yet", "Run the daily-journal skill on your Mac; entries appear here once they sync."));
            return;
        }
        // Rebuild only when the entry itself changed, and keep the scroll position when it is the same day.
        // The store keeps the same instance for an unchanged file, so a reference check is enough.
        if (ReferenceEquals(shownEntry, entry)) return;
        var sameDay = shownEntry?.Date == entry.Date;
        var offset = detail.VerticalOffset;
        shownEntry = entry;
        detailHost.Children.Clear();
        detailHost.Children.Add(EntryView.Build(entry, detailsExpanded, expanded => detailsExpanded = expanded));
        if (sameDay)
        {
            detail.UpdateLayout();
            detail.ChangeView(null, offset, null, disableAnimation: true);
        }
        else
        {
            detail.ChangeView(null, 0, null, disableAnimation: true);
        }
    }
}
