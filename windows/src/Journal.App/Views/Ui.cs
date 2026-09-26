using Journal.Rendering;
using JournalCore;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Journal.Views;

/// <summary>A page that rebuilds itself whenever the store changes.</summary>
public abstract class StorePage : Page
{
    protected StorePage()
    {
        Loaded += (_, _) => { App.Store.Changed += Refresh; Refresh(); };
        Unloaded += (_, _) => App.Store.Changed -= Refresh;
    }

    protected abstract void Refresh();
}

/// <summary>Small builders shared by the code-built pages, in the Windows 11 Settings card style.</summary>
public static class Ui
{
    public static Brush Res(string key) => (Brush)Application.Current.Resources[key];

    public static TextBlock PageTitle(string text) => new()
    {
        Text = text,
        Style = (Style)Application.Current.Resources["TitleTextBlockStyle"],
        Margin = new Thickness(0, 0, 0, 12),
        TextWrapping = TextWrapping.Wrap,
    };

    public static TextBlock SectionHeader(string text) => new()
    {
        Text = text,
        Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"],
        Margin = new Thickness(4, 12, 0, 6),
    };

    public static TextBlock Secondary(string text, double size = 12) => new()
    {
        Text = text,
        FontSize = size,
        Foreground = Res("TextFillColorSecondaryBrush"),
        TextWrapping = TextWrapping.Wrap,
        IsTextSelectionEnabled = true,
    };

    public static Border Card(UIElement child, Thickness? padding = null) => new()
    {
        Background = Res("CardBackgroundFillColorDefaultBrush"),
        BorderBrush = Res("CardStrokeColorDefaultBrush"),
        BorderThickness = new Thickness(1),
        CornerRadius = new CornerRadius(8),
        Padding = padding ?? new Thickness(16, 12, 16, 12),
        Child = child,
    };

    /// <summary>A card holding rows separated by thin dividers.</summary>
    public static Border RowsCard(IEnumerable<UIElement> rows)
    {
        var panel = new StackPanel();
        var first = true;
        foreach (var row in rows)
        {
            if (!first) panel.Children.Add(new Border { Height = 1, Background = Res("DividerStrokeColorDefaultBrush"), Margin = new Thickness(0, 8, 0, 8) });
            panel.Children.Add(row);
            first = false;
        }
        return Card(panel);
    }

    public static ScrollViewer Scroll(UIElement content, double maxWidth = 900) => new()
    {
        Content = new Grid
        {
            MaxWidth = maxWidth,
            Padding = new Thickness(24, 16, 24, 32),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            Children = { content },
        },
        VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
    };

    public static UIElement Empty(string glyph, string title, string text)
    {
        var panel = new StackPanel { Spacing = 8, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 48, 0, 0), MaxWidth = 420 };
        panel.Children.Add(new FontIcon { Glyph = glyph, FontSize = 36, Foreground = Res("TextFillColorSecondaryBrush") });
        panel.Children.Add(new TextBlock { Text = title, Style = (Style)Application.Current.Resources["SubtitleTextBlockStyle"], HorizontalAlignment = HorizontalAlignment.Center });
        panel.Children.Add(new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center, Foreground = Res("TextFillColorSecondaryBrush") });
        return panel;
    }

    /// <summary>A checkbox line: tick to toggle, links open in the browser, references are selectable.</summary>
    public static UIElement ActionRow(CheckboxLine item, string? subtitle = null)
    {
        var box = new CheckBox { IsChecked = item.IsChecked, MinWidth = 0, Padding = new Thickness(0), VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, -4, 0, 0) };
        ToolTipService.SetToolTip(box, item.IsChecked ? "Mark open" : "Mark done");
        AutomationProperties.SetName(box, item.Text);
        box.Click += async (_, _) => await App.Store.ToggleAsync(item);

        var content = new StackPanel { Spacing = 2 };
        var text = MarkdownRenderer.InlineTextBlock(item.Text);
        if (item.IsChecked)
        {
            text.TextDecorations = Windows.UI.Text.TextDecorations.Strikethrough;
            text.Foreground = Res("TextFillColorSecondaryBrush");
        }
        content.Children.Add(text);
        if (!string.IsNullOrEmpty(item.Reference))
        {
            var reference = MarkdownRenderer.AutolinkedTextBlock(item.Reference);
            reference.FontSize = 12;
            reference.Foreground = Res("TextFillColorSecondaryBrush");
            content.Children.Add(reference);
        }
        foreach (var line in item.Continuation)
        {
            var c = MarkdownRenderer.InlineTextBlock(line.Trim());
            c.FontSize = 12;
            c.Foreground = Res("TextFillColorSecondaryBrush");
            content.Children.Add(c);
        }
        if (subtitle is not null)
        {
            content.Children.Add(new TextBlock { Text = subtitle, FontSize = 11, Foreground = Res("TextFillColorTertiaryBrush") });
        }

        var grid = new Grid { ColumnSpacing = 4 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(32) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        Grid.SetColumn(content, 1);
        grid.Children.Add(box);
        grid.Children.Add(content);
        return grid;
    }

    /// <summary>A Done bullet. Right-click (or the … button) to highlight (bold in the file) or remove the line.</summary>
    public static UIElement DoneRow(DoneItem item)
    {
        var text = MarkdownRenderer.InlineTextBlock(item.Text);
        if (item.IsHighlighted) text.FontWeight = FontWeights.Bold;

        var menu = new MenuFlyout();
        var highlight = new MenuFlyoutItem { Text = item.IsHighlighted ? "Unhighlight" : "Highlight", Icon = new FontIcon { Glyph = "" } };
        highlight.Click += async (_, _) => await App.Store.ToggleHighlightAsync(item);
        var remove = new MenuFlyoutItem { Text = "Remove", Icon = new FontIcon { Glyph = "" } };
        remove.Click += async (_, _) => await App.Store.RemoveAsync(item);
        menu.Items.Add(highlight);
        menu.Items.Add(remove);

        var more = new Button
        {
            Content = new FontIcon { Glyph = "", FontSize = 14 },
            Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
            BorderThickness = new Thickness(0),
            Padding = new Thickness(6, 2, 6, 2),
            VerticalAlignment = VerticalAlignment.Top,
            Flyout = menu,
            Opacity = 0,
        };
        ToolTipService.SetToolTip(more, "Highlight or remove");
        AutomationProperties.SetName(more, $"More options for {item.Text}");

        var grid = new Grid { ColumnSpacing = 4, Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(20) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var bullet = new TextBlock { Text = "•", Foreground = Res("TextFillColorSecondaryBrush") };
        Grid.SetColumn(text, 1);
        Grid.SetColumn(more, 2);
        grid.Children.Add(bullet);
        grid.Children.Add(text);
        grid.Children.Add(more);
        grid.ContextFlyout = menu;
        grid.PointerEntered += (_, _) => more.Opacity = 1;
        grid.PointerExited += (_, _) => more.Opacity = 0;
        more.GotFocus += (_, _) => more.Opacity = 1;
        more.LostFocus += (_, _) => more.Opacity = 0;
        return grid;
    }
}
