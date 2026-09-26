using Journal.Rendering;
using JournalCore;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Journal.Views;

/// <summary>One day: Done, Actions, Carried over as native rows; other sections and Details rendered as Markdown.</summary>
public static class EntryView
{
    public static UIElement Build(JournalEntry entry, bool detailsExpanded, Action<bool> onDetailsExpanded)
    {
        var panel = new StackPanel { Spacing = 4 };

        var header = new Grid();
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var title = Ui.PageTitle(entry.DisplayDate);
        var edit = new Button
        {
            Content = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Children = { new FontIcon { Glyph = "", FontSize = 14 }, new TextBlock { Text = "Edit" } } },
            VerticalAlignment = VerticalAlignment.Top,
        };
        ToolTipService.SetToolTip(edit, "Edit the Markdown of this entry");
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(edit, "Edit");
        edit.Click += (_, _) => EditWindow.Open(entry.Date);
        Grid.SetColumn(edit, 1);
        header.Children.Add(title);
        header.Children.Add(edit);
        panel.Children.Add(header);

        if (entry.DoneItems.Count > 0)
        {
            panel.Children.Add(Ui.SectionHeader("Done"));
            panel.Children.Add(Ui.RowsCard(entry.DoneItems.Select(Ui.DoneRow)));
        }

        AddCheckboxSection(panel, entry, SectionKind.Actions);
        AddCheckboxSection(panel, entry, SectionKind.CarriedOver);

        foreach (var s in entry.Sections.Where(s => s.Kind.Type == SectionType.Other))
        {
            panel.Children.Add(Ui.SectionHeader(s.Heading));
            panel.Children.Add(Ui.Card(MarkdownRenderer.Render(entry.BodyText(s), line => Toggle(entry, s.BodyStart + line))));
        }

        if (entry.SectionOf(SectionKind.Details) is { } details)
        {
            var expander = new Expander
            {
                Header = "Details",
                IsExpanded = detailsExpanded,
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Stretch,
                Margin = new Thickness(0, 12, 0, 0),
                Content = MarkdownRenderer.Render(entry.BodyText(details), line => Toggle(entry, details.BodyStart + line)),
            };
            expander.Expanding += (_, _) => onDetailsExpanded(true);
            expander.Collapsed += (_, _) => onDetailsExpanded(false);
            panel.Children.Add(expander);
        }
        return panel;
    }

    static void AddCheckboxSection(StackPanel panel, JournalEntry entry, SectionKind kind)
    {
        var items = entry.Checkboxes.Where(c => c.Section == kind).ToList();
        if (items.Count > 0)
        {
            panel.Children.Add(Ui.SectionHeader(kind.Title));
            panel.Children.Add(Ui.RowsCard(items.Select(i => Ui.ActionRow(i))));
        }
        else if (entry.TextOf(kind)?.Trim() is { Length: > 0 } body)
        {
            panel.Children.Add(Ui.SectionHeader(kind.Title));
            var text = MarkdownRenderer.InlineTextBlock(body);
            text.Foreground = Ui.Res("TextFillColorSecondaryBrush");
            panel.Children.Add(Ui.Card(text));
        }
    }

    static async void Toggle(JournalEntry entry, int line)
    {
        if (entry.Checkboxes.FirstOrDefault(c => c.Line == line) is { } cb) await App.Store.ToggleAsync(cb);
    }
}
