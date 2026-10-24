using System.Windows;
using KeyBeacon.App.Settings;

namespace KeyBeacon.App.Ui;

/// <summary>
/// Borderless, always-on-top, taskbar-free status panel (FR-020), mirroring the
/// macOS floating panel. Position is pinned to a screen corner (data-model §8).
/// </summary>
public partial class FloatingPanel : Window
{
    private const double Margin = 12;

    public FloatingPanel(MainViewModel viewModel)
    {
        InitializeComponent();
        DataContext = viewModel;
        Loaded += (_, _) => Reposition(PinnedCorner.TopRight);
    }

    public void Reposition(PinnedCorner corner)
    {
        var area = SystemParameters.WorkArea;
        var left = corner is PinnedCorner.TopLeft or PinnedCorner.BottomLeft
            ? area.Left + Margin
            : area.Right - ActualWidth - Margin;
        var top = corner is PinnedCorner.TopLeft or PinnedCorner.TopRight
            ? area.Top + Margin
            : area.Bottom - ActualHeight - Margin;

        Left = left;
        Top = top;
    }
}
