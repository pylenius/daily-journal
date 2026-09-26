using Markdig;
using Markdig.Extensions.Tables;
using Markdig.Extensions.TaskLists;
using Markdig.Syntax;
using Markdig.Syntax.Inlines;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Documents;
using Microsoft.UI.Xaml.Media;
using Windows.System;
using Block = Markdig.Syntax.Block;
using MdInline = Markdig.Syntax.Inlines.Inline;
using XamlInline = Microsoft.UI.Xaml.Documents.Inline;

namespace Journal.Rendering;

/// <summary>
/// Renders Markdown (Details and other free-form sections) to WinUI elements, like ios/Journal/Rendering/MarkdownRenderer.swift.
/// Task-list items become real checkboxes; their 0-based source line (relative to the rendered text) is passed to
/// <c>onToggle</c> so the store can flip exactly that line in the file.
/// </summary>
public static class MarkdownRenderer
{
    static readonly MarkdownPipeline Pipeline = new MarkdownPipelineBuilder()
        .UsePipeTables()
        .UseTaskLists()
        .UseAutoLinks()
        .UseEmphasisExtras()
        .Build();

    static readonly FontFamily Mono = new("Cascadia Mono, Consolas");

    public static UIElement Render(string markdown, Action<int>? onToggle = null)
    {
        var doc = Markdown.Parse(markdown, Pipeline);
        var panel = new StackPanel { Spacing = 8 };
        foreach (var block in doc) AddBlock(panel.Children, block, onToggle);
        return panel;
    }

    /// <summary>Inline-only rendering of one line (action text, Done items) into a text block's inlines.</summary>
    public static void RenderInline(string text, InlineCollection target)
    {
        var doc = Markdown.Parse(text, Pipeline);
        foreach (var block in doc)
        {
            if (block is ParagraphBlock p && p.Inline is not null) AddInlines(target, p.Inline);
            else target.Add(new Run { Text = text });
        }
    }

    public static TextBlock InlineTextBlock(string text)
    {
        var tb = new TextBlock { TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true };
        RenderInline(text, tb.Inlines);
        return tb;
    }

    /// <summary>Plain text with bare URLs turned into links (references after `— source:`).</summary>
    public static TextBlock AutolinkedTextBlock(string text)
    {
        var tb = new TextBlock { TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true };
        foreach (var (part, url) in JournalCore.JournalParser.SplitUrls(text))
        {
            if (url is null) tb.Inlines.Add(new Run { Text = part });
            else tb.Inlines.Add(MakeLink(url, [new Run { Text = part }]));
        }
        return tb;
    }

    // MARK: Blocks

    static void AddBlock(UIElementCollection into, Block block, Action<int>? onToggle)
    {
        switch (block)
        {
            case HeadingBlock h:
                var heading = Rich(h.Inline);
                heading.FontWeight = FontWeights.SemiBold;
                heading.FontSize = h.Level switch { 1 => 22, 2 => 19, 3 => 16, _ => 14 };
                heading.Margin = new Thickness(0, 6, 0, 0);
                into.Add(heading);
                break;
            case ParagraphBlock p:
                into.Add(Rich(p.Inline));
                break;
            case ListBlock list:
                into.Add(RenderList(list, onToggle));
                break;
            case FencedCodeBlock or CodeBlock:
                var code = string.Join("\n", ((LeafBlock)block).Lines.Lines.Take(((LeafBlock)block).Lines.Count).Select(l => l.ToString()));
                into.Add(new Border
                {
                    Background = (Brush)Application.Current.Resources["CardBackgroundFillColorSecondaryBrush"],
                    CornerRadius = new CornerRadius(4),
                    Padding = new Thickness(8),
                    Child = new TextBlock { Text = code, FontFamily = Mono, IsTextSelectionEnabled = true, TextWrapping = TextWrapping.Wrap },
                });
                break;
            case QuoteBlock quote:
                var inner = new StackPanel { Spacing = 6 };
                foreach (var child in quote) AddBlock(inner.Children, child, onToggle);
                into.Add(new Border
                {
                    BorderBrush = (Brush)Application.Current.Resources["SystemControlForegroundBaseLowBrush"],
                    BorderThickness = new Thickness(3, 0, 0, 0),
                    Padding = new Thickness(10, 0, 0, 0),
                    Opacity = 0.85,
                    Child = inner,
                });
                break;
            case ThematicBreakBlock:
                into.Add(new Border { Height = 1, Background = (Brush)Application.Current.Resources["DividerStrokeColorDefaultBrush"], Margin = new Thickness(0, 4, 0, 4) });
                break;
            case Table table:
                into.Add(RenderTable(table));
                break;
            case HtmlBlock html:
                into.Add(new TextBlock { Text = string.Join("\n", html.Lines.Lines.Take(html.Lines.Count)), FontFamily = Mono, Opacity = 0.7, TextWrapping = TextWrapping.Wrap });
                break;
            case ContainerBlock container:
                foreach (var child in container) AddBlock(into, child, onToggle);
                break;
            case LeafBlock leaf when leaf.Inline is not null:
                into.Add(Rich(leaf.Inline));
                break;
        }
    }

    static UIElement RenderList(ListBlock list, Action<int>? onToggle)
    {
        var panel = new StackPanel { Spacing = 4 };
        var number = int.TryParse(list.OrderedStart, out var start) ? start : 1;
        foreach (var item in list.OfType<ListItemBlock>())
        {
            var task = (item.FirstOrDefault() as ParagraphBlock)?.Inline?.FirstChild as TaskList;
            FrameworkElement marker;
            if (task is not null)
            {
                var line = item.Line;
                var box = new CheckBox { IsChecked = task.Checked, MinWidth = 0, MinHeight = 0, Padding = new Thickness(0), Margin = new Thickness(0, -4, 0, 0) };
                Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(box, PlainText((item.FirstOrDefault() as ParagraphBlock)?.Inline).Trim());
                if (onToggle is null) box.IsEnabled = false;
                else box.Click += (_, _) => onToggle(line);
                marker = box;
            }
            else
            {
                marker = new TextBlock { Text = list.IsOrdered ? $"{number}." : "•", Opacity = 0.7 };
            }
            number++;
            var content = new StackPanel { Spacing = 4 };
            foreach (var child in item) AddBlock(content.Children, child, onToggle);
            var row = new Grid { ColumnSpacing = 6 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(task is not null ? 28 : 18) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            Grid.SetColumn(content, 1);
            row.Children.Add(marker);
            row.Children.Add(content);
            panel.Children.Add(row);
        }
        return panel;
    }

    static UIElement RenderTable(Table table)
    {
        var grid = new Grid { ColumnSpacing = 16, RowSpacing = 4 };
        var rows = table.OfType<TableRow>().ToList();
        var columns = rows.Count == 0 ? 0 : rows.Max(r => r.Count);
        for (var c = 0; c < columns; c++) grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        for (var r = 0; r < rows.Count; r++)
        {
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            for (var c = 0; c < rows[r].Count; c++)
            {
                var cell = (TableCell)rows[r][c];
                var cellPanel = new StackPanel();
                foreach (var child in cell) AddBlock(cellPanel.Children, child, null);
                if (rows[r].IsHeader) foreach (var tb in cellPanel.Children.OfType<RichTextBlock>()) tb.FontWeight = FontWeights.SemiBold;
                Grid.SetRow(cellPanel, r);
                Grid.SetColumn(cellPanel, c);
                grid.Children.Add(cellPanel);
            }
        }
        return new ScrollViewer { Content = grid, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled, HorizontalScrollMode = ScrollMode.Auto, VerticalScrollMode = ScrollMode.Disabled };
    }

    // MARK: Inlines

    /// <summary>The text of an inline tree without markup, for accessible names.</summary>
    static string PlainText(ContainerInline? container)
    {
        if (container is null) return "";
        var sb = new System.Text.StringBuilder();
        foreach (var inline in container)
        {
            switch (inline)
            {
                case LiteralInline lit: sb.Append(lit.Content.ToString()); break;
                case CodeInline code: sb.Append(code.Content); break;
                case AutolinkInline auto: sb.Append(auto.Url); break;
                case LineBreakInline: sb.Append(' '); break;
                case ContainerInline c: sb.Append(PlainText(c)); break;
            }
        }
        return sb.ToString();
    }

    static RichTextBlock Rich(ContainerInline? inline)
    {
        var rtb = new RichTextBlock { TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true };
        var paragraph = new Paragraph();
        if (inline is not null) AddInlines(paragraph.Inlines, inline);
        rtb.Blocks.Add(paragraph);
        return rtb;
    }

    static void AddInlines(InlineCollection target, ContainerInline container)
    {
        foreach (var inline in container) Add(target, inline);
    }

    static void Add(InlineCollection target, MdInline inline)
    {
        switch (inline)
        {
            case TaskList:
                break; // rendered as a CheckBox by the list
            case LiteralInline lit:
                target.Add(new Run { Text = lit.Content.ToString() });
                break;
            case CodeInline code:
                target.Add(new Run { Text = code.Content, FontFamily = Mono });
                break;
            case LineBreakInline br:
                if (br.IsHard) target.Add(new LineBreak()); else target.Add(new Run { Text = " " });
                break;
            case AutolinkInline auto when Uri.TryCreate(auto.Url, UriKind.Absolute, out var autoUri):
                target.Add(MakeLink(autoUri, [new Run { Text = auto.Url }]));
                break;
            case LinkInline { IsImage: false } link when Uri.TryCreate(link.GetDynamicUrl?.Invoke() ?? link.Url, UriKind.Absolute, out var uri):
                var children = new List<XamlInline>();
                var tmp = new Span();
                AddInlines(tmp.Inlines, link);
                foreach (var c in tmp.Inlines.ToList()) { tmp.Inlines.Remove(c); children.Add(c); }
                if (children.Count == 0) children.Add(new Run { Text = uri.ToString() });
                target.Add(MakeLink(uri, children));
                break;
            case EmphasisInline em:
                Span span = em.DelimiterChar == '~' ? new Span { TextDecorations = Windows.UI.Text.TextDecorations.Strikethrough }
                    : em.DelimiterCount >= 2 ? new Bold() : new Italic();
                AddInlines(span.Inlines, em);
                target.Add(span);
                break;
            case HtmlInline html:
                target.Add(new Run { Text = html.Tag });
                break;
            case HtmlEntityInline entity:
                target.Add(new Run { Text = entity.Transcoded.ToString() });
                break;
            case ContainerInline c:
                AddInlines(target, c);
                break;
            default:
                target.Add(new Run { Text = inline.ToString() });
                break;
        }
    }

    static Hyperlink MakeLink(Uri uri, IEnumerable<XamlInline> content)
    {
        var link = new Hyperlink();
        foreach (var c in content) link.Inlines.Add(c);
        link.Click += async (_, _) => await Launcher.LaunchUriAsync(uri);
        ToolTipService.SetToolTip(link, uri.ToString());
        return link;
    }
}
