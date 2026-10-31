using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
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
            Visibility = Visibility.Visible
        };

        // A failure here (icon rendering / native HICON conversion) must never
        // take down the whole app — the tray menu still works without a glyph.
        try { _icon.IconSource = BuildTrayIcon(); }
        catch { /* fall back to the default/empty glyph */ }

        _icon.TrayLeftMouseUp += (_, _) => ShowPanelRequested?.Invoke(this, EventArgs.Empty);

        UpdateKeyboardsMenu();
    }

    /// <summary>
    /// Builds the tray glyph (rounded dark tile + white "K") as a
    /// <see cref="GeneratedIconSource"/>. H.NotifyIcon's <c>ToIconAsync</c>
    /// special-cases this type and rasterises it with its own GDI+ generator,
    /// so it bypasses the WPF ImageSource→Uri conversion that cannot handle a
    /// runtime-generated <c>RenderTargetBitmap</c>/<c>BitmapFrame</c>
    /// (the source of the earlier startup crash).
    /// </summary>
    private static ImageSource BuildTrayIcon() => new GeneratedIconSource
    {
        Text = "K",
        Foreground = Brushes.White,
        Background = new SolidColorBrush(Color.FromRgb(0x20, 0x21, 0x24)),
        FontFamily = new FontFamily("Segoe UI"),
        FontWeight = FontWeights.Bold,
        FontSize = 44,
        Size = 64,
        CornerRadius = new CornerRadius(12)
    };

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
