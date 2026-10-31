using System.Windows;
using System.Windows.Controls;
using KeyBeacon.App.Localization;

namespace KeyBeacon.App.Ui;

/// <summary>
/// Pre-export review (FR-025, US6 scenario 3): tells the user what the bundle
/// will contain and lets them opt into including full device names before the
/// archive is written.
/// </summary>
public sealed class ExportReviewWindow : Window
{
    private readonly CheckBox _includeNames;

    public ExportReviewWindow(LocalizationService loc)
    {
        Title = loc.Get("Dialog_ExportTitle");
        SizeToContent = SizeToContent.WidthAndHeight;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Width = 420;

        _includeNames = new CheckBox
        {
            Content = loc.Get("Dialog_ExportIncludeNames"),
            Margin = new Thickness(0, 12, 0, 12)
        };

        var message = new TextBlock
        {
            Text = loc.Get("Dialog_ExportReview"),
            TextWrapping = TextWrapping.Wrap
        };

        var ok = new Button { Content = "OK", Width = 88, IsDefault = true, Margin = new Thickness(0, 0, 8, 0) };
        ok.Click += (_, _) => { DialogResult = true; };
        var cancel = new Button { Content = "Cancel", Width = 88, IsCancel = true };

        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right
        };
        buttons.Children.Add(ok);
        buttons.Children.Add(cancel);

        var root = new StackPanel { Margin = new Thickness(16) };
        root.Children.Add(message);
        root.Children.Add(_includeNames);
        root.Children.Add(buttons);

        Content = root;
    }

    public bool IncludeFullNames => _includeNames.IsChecked == true;
}
