using System.Windows;
using System.Windows.Input;
using KeyBeacon.App.Settings;

namespace KeyBeacon.App.Ui;

/// <summary>
/// Borderless, always-on-top, taskbar-free status panel (FR-020), mirroring the
/// macOS floating panel. Draggable by its background with the position remembered
/// across launches. When a corner is pinned it anchors there and a drag snaps
/// back — matching macOS <c>isMovableByWindowBackground</c> + <c>pinnedCorner</c>.
/// </summary>
public partial class FloatingPanel : Window
{
    private const double EdgeMargin = 12;
    private readonly AppSettings _settings;

    public FloatingPanel(MainViewModel viewModel, AppSettings settings)
    {
        InitializeComponent();
        DataContext = viewModel;
        _settings = settings;
        Loaded += (_, _) => ApplyPlacement();
    }

    /// <summary>
    /// Anchors the panel to the pinned corner when one is configured; otherwise
    /// restores the last dragged position (clamped to the work area), falling
    /// back to the top-right default on first launch.
    /// </summary>
    public void ApplyPlacement()
    {
        if (_settings.PinnedCorner is { } corner)
        {
            SnapToCorner(corner);
            return;
        }

        var area = SystemParameters.WorkArea;
        if (_settings.PanelLeft is { } savedLeft && _settings.PanelTop is { } savedTop)
        {
            Left = Clamp(savedLeft, area.Left, area.Right - ActualWidth);
            Top = Clamp(savedTop, area.Top, area.Bottom - ActualHeight);
        }
        else
        {
            Left = area.Right - ActualWidth - EdgeMargin;
            Top = area.Top + EdgeMargin;
        }
    }

    private void SnapToCorner(PinnedCorner corner)
    {
        var area = SystemParameters.WorkArea;
        Left = corner is PinnedCorner.TopLeft or PinnedCorner.BottomLeft
            ? area.Left + EdgeMargin
            : area.Right - ActualWidth - EdgeMargin;
        Top = corner is PinnedCorner.TopLeft or PinnedCorner.TopRight
            ? area.Top + EdgeMargin
            : area.Bottom - ActualHeight - EdgeMargin;
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        if (e.ButtonState != MouseButtonState.Pressed) return;

        DragMove(); // blocks until the mouse button is released

        if (_settings.PinnedCorner is { } corner)
        {
            // Pinned: the drag is visual only — snap back to the corner.
            SnapToCorner(corner);
            return;
        }

        _settings.PanelLeft = Left;
        _settings.PanelTop = Top;
        _settings.Save();
    }

    private static double Clamp(double value, double min, double max)
    {
        if (max < min) return min;
        if (value < min) return min;
        return value > max ? max : value;
    }
}
