using System;
using System.Collections.Generic;
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
/// System-tray presence and menu (FR-008), mirroring the macOS status-item menu:
/// keyboard chooser (US3), show/hide panel toggle, reconnect, pin-to-corner and
/// display-mode radio groups, the verbose-logging toggle (FR-024) and the
/// diagnostics export action (US6). Never takes a taskbar slot or steals focus.
/// </summary>
public sealed class TrayController : IDisposable
{
    private readonly TaskbarIcon _icon;
    private LocalizationService _loc;
    private readonly AppSettings _settings;
    private MenuItem _keyboardsRoot = null!;
    private MenuItem _verboseItem = null!;
    private MenuItem _showPanelItem = null!;

    // Radio groups. Pins use a list because a Dictionary cannot key on a null
    // (nullable-enum) value — null is the "off / remember position" entry.
    private readonly List<(PinnedCorner? Corner, MenuItem Item)> _pinItems = new();
    private readonly Dictionary<DisplayMode, MenuItem> _modeItems = new();
    private readonly Dictionary<UiCulturePreference, MenuItem> _languageItems = new();

    private IReadOnlyList<CompatibleKeyboard> _keyboards = Array.Empty<CompatibleKeyboard>();

    public TrayController(LocalizationService loc, AppSettings settings)
    {
        _loc = loc;
        _settings = settings;

        _icon = new TaskbarIcon
        {
            ToolTipText = loc.Get("AppName"),
            ContextMenu = BuildMenu(),
            Visibility = Visibility.Visible
        };

        // A failure here (icon rendering / native HICON conversion) must never
        // take down the whole app — the tray menu still works without a glyph.
        // Primary: the pre-rendered, pixel-centred .ico resource (URI-backed, so
        // H.NotifyIcon's ImageSource→HICON path works). Fallback: the runtime
        // GDI+ glyph, which is less precisely centred but never throws.
        try { _icon.IconSource = LoadTrayIcon(); }
        catch
        {
            try { _icon.IconSource = BuildTrayIcon(); }
            catch { /* fall back to the default/empty glyph */ }
        }

        // Left-click toggles the panel (Windows-conventional primary action);
        // right-click opens the menu automatically.
        _icon.TrayLeftMouseUp += (_, _) => TogglePanelRequested?.Invoke(this, EventArgs.Empty);

        // The icon is created in code (no XAML host), so the shell never gets a
        // Loaded event to materialise it — ForceCreate registers it explicitly.
        // Efficiency mode stays off so background BLE monitoring isn't throttled.
        _icon.ForceCreate(enablesEfficiencyMode: false);

        SetPinnedCorner(settings.PinnedCorner);
        SetDisplayMode(settings.DisplayMode);
        UpdateKeyboardsMenu();
    }

    /// <summary>
    /// Builds (or rebuilds) the right-click menu from the current
    /// <see cref="_loc"/>. The checkable-group backing collections are cleared
    /// first so a rebuild after a language change does not accumulate stale
    /// menu items.
    /// </summary>
    private ContextMenu BuildMenu()
    {
        _pinItems.Clear();
        _modeItems.Clear();
        _languageItems.Clear();

        _keyboardsRoot = new MenuItem { Header = _loc.Get("Menu_Keyboard") };

        _showPanelItem = new MenuItem
        {
            Header = _loc.Get("Menu_ShowPanel"),
            IsCheckable = true,
            IsChecked = _settings.PanelVisible
        };
        _showPanelItem.Click += (_, _) => TogglePanelRequested?.Invoke(this, EventArgs.Empty);

        var reconnect = new MenuItem { Header = _loc.Get("Menu_Reconnect") };
        reconnect.Click += (_, _) => ReconnectRequested?.Invoke(this, EventArgs.Empty);

        var pinRoot = BuildPinMenu();
        var modeRoot = BuildModeMenu();
        var languageRoot = BuildLanguageMenu();

        _verboseItem = new MenuItem
        {
            Header = _loc.Get("Menu_VerboseLogging"),
            IsCheckable = true,
            IsChecked = _settings.VerboseLogging
        };
        _verboseItem.Click += (_, _) => VerboseLoggingToggled?.Invoke(this, _verboseItem.IsChecked);

        var export = new MenuItem { Header = _loc.Get("Menu_ExportDiagnostics") };
        export.Click += (_, _) => ExportDiagnosticsRequested?.Invoke(this, EventArgs.Empty);

        var quit = new MenuItem { Header = _loc.Get("Menu_Quit") };
        quit.Click += (_, _) => QuitRequested?.Invoke(this, EventArgs.Empty);

        var menu = new ContextMenu();
        menu.Items.Add(_keyboardsRoot);
        menu.Items.Add(new Separator());
        menu.Items.Add(_showPanelItem);
        menu.Items.Add(reconnect);
        menu.Items.Add(new Separator());
        menu.Items.Add(pinRoot);
        menu.Items.Add(modeRoot);
        menu.Items.Add(languageRoot);
        menu.Items.Add(new Separator());
        menu.Items.Add(_verboseItem);
        menu.Items.Add(export);
        menu.Items.Add(new Separator());
        menu.Items.Add(quit);
        return menu;
    }

    /// <summary>
    /// Re-applies the menu labels after a UI-language change WITHOUT recreating
    /// the <see cref="TaskbarIcon"/>. Rebuilding the icon is unsafe: two
    /// TaskbarIcon instances share one shell notification id, so disposing the
    /// old one issues NIM_DELETE for that id and removes the freshly-created
    /// icon's glyph (the icon vanishes from the tray). Only the ContextMenu is
    /// swapped; the icon registration and tooltip are left untouched.
    /// </summary>
    public void ApplyLocalization(LocalizationService loc)
    {
        _loc = loc;
        _icon.ContextMenu = BuildMenu();
        SetPinnedCorner(_settings.PinnedCorner);
        SetDisplayMode(_settings.DisplayMode);
        SetLanguage(_settings.UICulture);
        UpdateKeyboardsMenu();
    }

    private MenuItem BuildPinMenu()
    {
        var root = new MenuItem { Header = _loc.Get("Menu_PinCorner") };

        var off = NewCheckItem(_loc.Get("Menu_PinOff"));
        off.Click += (_, _) => PinCornerSelected?.Invoke(this, null);
        _pinItems.Add((null, off));
        root.Items.Add(off);
        root.Items.Add(new Separator());

        AddPinCorner(root, PinnedCorner.TopLeft, "Corner_TopLeft");
        AddPinCorner(root, PinnedCorner.TopRight, "Corner_TopRight");
        AddPinCorner(root, PinnedCorner.BottomLeft, "Corner_BottomLeft");
        AddPinCorner(root, PinnedCorner.BottomRight, "Corner_BottomRight");
        return root;
    }

    private void AddPinCorner(MenuItem root, PinnedCorner corner, string labelKey)
    {
        var item = NewCheckItem(_loc.Get(labelKey));
        item.Click += (_, _) => PinCornerSelected?.Invoke(this, corner);
        _pinItems.Add((corner, item));
        root.Items.Add(item);
    }

    private MenuItem BuildModeMenu()
    {
        var root = new MenuItem { Header = _loc.Get("Menu_DisplayMode") };

        var full = NewCheckItem(_loc.Get("Menu_DisplayFull"));
        full.Click += (_, _) => DisplayModeSelected?.Invoke(this, DisplayMode.Full);
        _modeItems[DisplayMode.Full] = full;
        root.Items.Add(full);

        var compact = NewCheckItem(_loc.Get("Menu_DisplayCompact"));
        compact.Click += (_, _) => DisplayModeSelected?.Invoke(this, DisplayMode.Compact);
        _modeItems[DisplayMode.Compact] = compact;
        root.Items.Add(compact);
        return root;
    }

    private MenuItem BuildLanguageMenu()
    {
        var root = new MenuItem { Header = _loc.Get("Menu_Language") };

        // Order: follow-system, English, 中文 — concrete languages self-named so
        // a user can always find their own (mirrors macOS), with the current
        // preference shown checked (FR-012).
        AddLanguageItem(root, UiCulturePreference.System, "Menu_LanguageSystem");
        AddLanguageItem(root, UiCulturePreference.English, "Menu_LanguageEnglish");
        AddLanguageItem(root, UiCulturePreference.Chinese, "Menu_LanguageChinese");
        return root;
    }

    private void AddLanguageItem(MenuItem root, UiCulturePreference preference, string labelKey)
    {
        var item = NewCheckItem(_loc.Get(labelKey));
        item.IsChecked = _settings.UICulture == preference;
        item.Click += (_, _) => LanguageSelected?.Invoke(this, preference);
        _languageItems[preference] = item;
        root.Items.Add(item);
    }

    private static MenuItem NewCheckItem(string header) =>
        new() { Header = header, IsCheckable = true };

    /// <summary>
    /// Loads the pre-rendered tray glyph (rounded dark tile + optically-centred
    /// white "K") from the embedded <c>Assets/trayicon.ico</c> resource. A
    /// <see cref="BitmapImage"/> keeps its <c>UriSource</c>, which is the only
    /// shape H.NotifyIcon 2.1.4 can turn into a native HICON (it resolves the
    /// pack URI via <c>Application.GetResourceStream</c>); a runtime in-memory
    /// bitmap would throw, so this path is deliberately URI-backed.
    /// </summary>
    private static ImageSource LoadTrayIcon() => new BitmapImage(
        new Uri("pack://application:,,,/Assets/trayicon.ico", UriKind.Absolute));

    /// <summary>
    /// Fallback tray glyph rendered at runtime as a
    /// <see cref="GeneratedIconSource"/>. H.NotifyIcon's <c>ToIconAsync</c>
    /// special-cases this type and rasterises it with its own GDI+ generator,
    /// so it bypasses the WPF ImageSource→Uri conversion that cannot handle a
    /// runtime-generated <c>RenderTargetBitmap</c>/<c>BitmapFrame</c>. Used only
    /// when the embedded <c>.ico</c> fails to load.
    /// </summary>
    private static ImageSource BuildTrayIcon() => new GeneratedIconSource
    {
        Text = "K",
        Foreground = Brushes.White,
        Background = new SolidColorBrush(Color.FromRgb(0x20, 0x21, 0x24)),
        FontFamily = new FontFamily("Segoe UI"),
        FontWeight = FontWeights.Bold,
        FontSize = 40,
        Size = 64,
        CornerRadius = new CornerRadius(12)
    };

    public event EventHandler? TogglePanelRequested;
    public event EventHandler? ReconnectRequested;
    public event EventHandler? QuitRequested;
    public event EventHandler? ExportDiagnosticsRequested;
    public event EventHandler<string>? KeyboardSelected;
    public event EventHandler<bool>? VerboseLoggingToggled;
    public event EventHandler<PinnedCorner?>? PinCornerSelected;
    public event EventHandler<DisplayMode>? DisplayModeSelected;
    public event EventHandler<UiCulturePreference>? LanguageSelected;

    public void SetTitle(string title) => _icon.ToolTipText = title;

    public void SetPanelVisible(bool visible) => _showPanelItem.IsChecked = visible;

    public void SetPinnedCorner(PinnedCorner? corner)
    {
        foreach (var (c, item) in _pinItems) item.IsChecked = c == corner;
    }

    public void SetDisplayMode(DisplayMode mode)
    {
        foreach (var pair in _modeItems) pair.Value.IsChecked = pair.Key == mode;
    }

    public void SetLanguage(UiCulturePreference preference)
    {
        foreach (var pair in _languageItems) pair.Value.IsChecked = pair.Key == preference;
    }

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
