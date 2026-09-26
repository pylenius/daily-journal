using JournalCore;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Journal.Views;

/// <summary>Quick capture: writes one file into `inbox/` for the next journal run.</summary>
public static class CaptureDialog
{
    public static async Task ShowAsync(XamlRoot root)
    {
        var kind = new RadioButtons { MaxColumns = 2, SelectedIndex = 0, Items = { "Action", "Note" } };
        var text = new TextBox { AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, MinHeight = 140, MaxHeight = 320, PlaceholderText = "What should the journal know?" };
        var hint = Ui.Secondary("");
        void UpdateHint() => hint.Text = kind.SelectedIndex == 0
            ? "Becomes an open action in the next journal entry."
            : "Folded into the next entry's Done or Details.";
        UpdateHint();
        kind.SelectionChanged += (_, _) => UpdateHint();

        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Title = "Quick capture",
            Content = new StackPanel { Spacing = 12, MinWidth = 440, Children = { kind, text, hint } },
            PrimaryButtonText = "Save",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
            IsPrimaryButtonEnabled = false,
        };
        text.TextChanged += (_, _) => dialog.IsPrimaryButtonEnabled = text.Text.Trim().Length > 0;
        dialog.Opened += (_, _) => text.Focus(FocusState.Programmatic);

        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            await App.Store.CaptureAsync(kind.SelectedIndex == 0 ? CaptureKind.Action : CaptureKind.Note, text.Text);
        }
    }
}
