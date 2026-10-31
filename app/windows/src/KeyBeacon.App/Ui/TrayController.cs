using System;
using System.Collections.Generic;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using H.NotifyIcon;
using KeyBeacon.App.Ble;
using KeyBeacon.App.Localization;
using KeyBeacon.App.Settings;
using KeyBeacon.Core;

namespace KeyBeacon.App.Ui;

/// <summary>
/// System-tray presence and menu (FR-008). Hosts keyboard selection (US3),
/// the verbose-logging toggle (FR-024) and the diagnostics export action (US6).
/// Never takes a taskbar slot or steals focus.
/// </summary>
public sealed class TrayController : IDisposable
{
    private readonly TaskbarIcon _icon;
    private readonly LocalizationService _loc;
    private readonly AppSettings _settings;
    private readonly MenuItem _keyboardsRoot;
    private readonly MenuItem _verboseItem;

    private IReadOnlyList<CompatibleKeyboard> _keyboards = Array.Empty<CompatibleKeyboard>();

    public TrayController(LocalizationService loc, AppSettings settings)
    {
        _loc = loc;
        _settings = settings;

        _keyboardsRoot = new MenuItem { Header = loc.Get("Menu_Keyboard") };
        _verboseItem = new MenuItem
        {
            Header = loc.Get("Menu_VerboseLogging"),
            IsCheckable = true,
            IsChecked = settings.VerboseLogging
        };
        _verboseItem.Click += (_, _) => VerboseLoggingToggled?.Invoke(this, _verboseItem.IsChecked);

        var showPanel = new MenuItem { Header = loc.Get("Menu_ShowPanel") };
        showPanel.Click += (_, _) => ShowPanelRequested?.Invoke(this, EventArgs.Empty);

        var reconnect = new MenuItem { Header = loc.Get("Menu_Reconnect") };
        reconnect.Click += (_, _) => ReconnectRequested?.Invoke(this, EventArgs.Empty);

        var export = new MenuItem { Header = loc.Get("Menu_ExportDiagnostics") };
        export.Click += (_, _) => ExportDiagnosticsRequested?.Invoke(this, EventArgs.Empty);

        var quit = new MenuItem { Header = loc.Get("Menu_Quit") };
        quit.Click += (_, _) => QuitRequested?.Invoke(this, EventArgs.Empty);

        var menu = new ContextMenu();
        menu.Items.Add(_keyboardsRoot);
        menu.Items.Add(new Separator());
        menu.Items.Add(showPanel);
        menu.Items.Add(reconnect);
        menu.Items.Add(new Separator());
        menu.Items.Add(_verboseItem);
        menu.Items.Add(export);
        menu.Items.Add(new Separator());
        menu.Items.Add(quit);

        _icon = new TaskbarIcon
        {
            ToolTipText = loc.Get("AppName"),
            ContextMenu = menu,
            IconSource = BuildTrayIcon(),
            Visibility = Visibility.Visible
        };
        _icon.TrayLeftMouseUp += (_, _) => ShowPanelRequested?.Invoke(this, EventArgs.Empty);

        UpdateKeyboardsMenu();
    }

    /// <summary>
    /// Renders the tray glyph at runtime (rounded dark tile + white "K"), so the
    /// app needs no packaged .ico. Mirrors the floating panel's dark styling.
    /// </summary>
    private static ImageSource BuildTrayIcon()
    {
        const int size = 32;
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            var bg = new SolidColorBrush(Color.FromRgb(0x20, 0x21, 0x24));
            dc.DrawRoundedRectangle(bg, null, new Rect(0, 0, size, size), 7, 7);
            var text = new FormattedText(
                "K",
                CultureInfo.InvariantCulture,
                FlowDirection.LeftToRight,
                new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.Bold, FontStretches.Normal),
                20,
                Brushes.White,
                1.0);
            dc.DrawText(text, new Point((size - text.Width) / 2, (size - text.Height) / 2));
        }

        var bmp = new RenderTargetBitmap(size, size, 96, 96, PixelFormats.Pbgra32);
        bmp.Render(visual);
        bmp.Freeze();
        return bmp;
    }

    public event EventHandler? ShowPanelRequested;
    public event EventHandler? ReconnectRequested;
    public event EventHandler? QuitRequested;
    public event EventHandler? ExportDiagnosticsRequested;
    public event EventHandler<string>? KeyboardSelected;
    public event EventHandler<bool>? VerboseLoggingToggled;

    public void SetTitle(string title) => _icon.ToolTipText = title;

    public void UpdateKeyboards(IReadOnlyList<CompatibleKeyboard> keyboards)
    {
        _keyboards = keyboards;
        UpdateKeyboardsMenu();
    }

    private void UpdateKeyboardsMenu()
    {
        _keyboardsRoot.Items.Clear();

        if (_keyboards.Count == 0)
        {
            _keyboardsRoot.Items.Add(new MenuItem { Header = _loc.Get("Menu_NoKeyboards"), IsEnabled = false });
            return;
        }

        foreach (var kb in _keyboards)
        {
            var item = new MenuItem
            {
                Header = kb.DisplayName,
                IsCheckable = true,
                IsChecked = kb.Identifier == _settings.SelectedKeyboardId,
                Tag = kb.Identifier
            };
            item.Click += (_, _) => KeyboardSelected?.Invoke(this, kb.Identifier);
            _keyboardsRoot.Items.Add(item);
        }
    }

    public void Dispose() => _icon.Dispose();
}
