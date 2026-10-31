using System.Windows;
using KeyBeacon.App.Settings;

namespace KeyBeacon.App.Ui;

/// <summary>
/// Borderless, always-on-top, taskbar-free status panel (FR-020), mirroring the
/// macOS floating panel. Position is pinned to a screen corner (data-model §8).
/// </summary>
public partial class FloatingPanel : Window
{
    private const double EdgeMargin = 12;

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
            ? area.Left + EdgeMargin
            : area.Right - ActualWidth - EdgeMargin;
        var top = corner is PinnedCorner.TopLeft or PinnedCorner.TopRight
            ? area.Top + EdgeMargin
            : area.Bottom - ActualHeight - EdgeMargin;

        Left = left;
        Top = top;
    }
}
