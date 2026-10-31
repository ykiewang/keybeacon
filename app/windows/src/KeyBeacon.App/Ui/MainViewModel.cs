using System;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Media;
using KeyBeacon.App.Ble;
using KeyBeacon.App.Localization;
using KeyBeacon.App.Settings;
using KeyBeacon.Core;

namespace KeyBeacon.App.Ui;

/// <summary>
/// Observable UI state derived from a <see cref="KeyboardSnapshot"/>.
/// Rendering rules honour Principle IV: unavailable 1.1 sections are hidden
/// (null → Visible=false), stale fields keep their last value but surface an
/// "updated hh:mm:ss" hint, and sentinel batteries show "unavailable", never 0%.
/// </summary>
public sealed class MainViewModel : INotifyPropertyChanged
{
    private readonly LocalizationService _loc;

    public MainViewModel(LocalizationService loc)
    {
        _loc = loc;
        ConnectivityRows = new ObservableCollection<LabeledValue>();
        BatteryRows = new ObservableCollection<LabeledValue>();
        Apply(KeyboardSnapshot.ForState(MonitorState.NoKeyboard));
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private string _title = "KeyBeacon";
    public string Title { get => _title; private set => Set(ref _title, value); }

    private string _stateText = string.Empty;
    public string StateText { get => _stateText; private set => Set(ref _stateText, value); }

    private bool _showStatus;
    public bool ShowStatus { get => _showStatus; private set => Set(ref _showStatus, value); }

    private string _layerName = string.Empty;
    public string LayerName { get => _layerName; private set => Set(ref _layerName, value); }

    private bool _shift, _control, _alt, _gui;
    public bool Shift { get => _shift; private set => Set(ref _shift, value); }
    public bool Control { get => _control; private set => Set(ref _control, value); }
    public bool Alt { get => _alt; private set => Set(ref _alt, value); }
    public bool Gui { get => _gui; private set => Set(ref _gui, value); }

    private bool _statusStale;
    public bool StatusStale { get => _statusStale; private set => Set(ref _statusStale, value); }

    private string _statusUpdatedHint = string.Empty;
    public string StatusUpdatedHint { get => _statusUpdatedHint; private set => Set(ref _statusUpdatedHint, value); }

    public ObservableCollection<LabeledValue> ConnectivityRows { get; }
    public ObservableCollection<LabeledValue> BatteryRows { get; }

    private bool _showConnectivity;
    public bool ShowConnectivity { get => _showConnectivity; private set => Set(ref _showConnectivity, value); }

    private bool _showBattery;
    public bool ShowBattery { get => _showBattery; private set => Set(ref _showBattery, value); }

    // Display-mode (full vs single-row compact), driven from the tray menu and
    // persisted in settings. Mirrors macOS DisplayMode.
    private bool _showFull = true;
    public bool ShowFull { get => _showFull; private set => Set(ref _showFull, value); }

    private bool _showCompact;
    public bool ShowCompact { get => _showCompact; private set => Set(ref _showCompact, value); }

    // ---- Compact single-row state (mirrors macOS FloatingPanel.compactRow) ----
    // Layer label (monospaced); shows the state text when disconnected.
    private string _compactLayer = string.Empty;
    public string CompactLayer { get => _compactLayer; private set => Set(ref _compactLayer, value); }

    // Host segment: "│ ● P1". Dot colour green=connected / grey=offline.
    private bool _showCompactHost;
    public bool ShowCompactHost { get => _showCompactHost; private set => Set(ref _showCompactHost, value); }
    private bool _compactHostDotVisible;
    public bool CompactHostDotVisible { get => _compactHostDotVisible; private set => Set(ref _compactHostDotVisible, value); }
    private Brush _compactHostDot = DotGray;
    public Brush CompactHostDot { get => _compactHostDot; private set => Set(ref _compactHostDot, value); }
    private bool _compactProfileVisible;
    public bool CompactProfileVisible { get => _compactProfileVisible; private set => Set(ref _compactProfileVisible, value); }
    private string _compactProfileText = string.Empty;
    public string CompactProfileText { get => _compactProfileText; private set => Set(ref _compactProfileText, value); }

    // Split / battery segment: "│ ●L85 ●R72". For a non-split board the overall
    // reading occupies the left slot and the right slot is hidden.
    private bool _showCompactSplit;
    public bool ShowCompactSplit { get => _showCompactSplit; private set => Set(ref _showCompactSplit, value); }
    private Brush _compactLeftDot = DotGreen;
    public Brush CompactLeftDot { get => _compactLeftDot; private set => Set(ref _compactLeftDot, value); }
    private string _compactLeftBattery = string.Empty;
    public string CompactLeftBattery { get => _compactLeftBattery; private set => Set(ref _compactLeftBattery, value); }
    private bool _compactLeftCharging;
    public bool CompactLeftCharging { get => _compactLeftCharging; private set => Set(ref _compactLeftCharging, value); }
    private bool _compactRightVisible;
    public bool CompactRightVisible { get => _compactRightVisible; private set => Set(ref _compactRightVisible, value); }
    private Brush _compactRightDot = DotGreen;
    public Brush CompactRightDot { get => _compactRightDot; private set => Set(ref _compactRightDot, value); }
    private string _compactRightBattery = string.Empty;
    public string CompactRightBattery { get => _compactRightBattery; private set => Set(ref _compactRightBattery, value); }
    private bool _compactRightCharging;
    public bool CompactRightCharging { get => _compactRightCharging; private set => Set(ref _compactRightCharging, value); }

    // Output-endpoint segment: "│ USB".
    private bool _showCompactEndpoint;
    public bool ShowCompactEndpoint { get => _showCompactEndpoint; private set => Set(ref _showCompactEndpoint, value); }
    private string _compactEndpointText = string.Empty;
    public string CompactEndpointText { get => _compactEndpointText; private set => Set(ref _compactEndpointText, value); }

    private static readonly Brush DotGreen = FrozenBrush(0x34, 0xC7, 0x59);
    private static readonly Brush DotRed = FrozenBrush(0xFF, 0x3B, 0x30);
    private static readonly Brush DotGray = FrozenBrush(0x8E, 0x8E, 0x93);

    private static Brush FrozenBrush(byte r, byte g, byte b)
    {
        var brush = new SolidColorBrush(Color.FromRgb(r, g, b));
        brush.Freeze();
        return brush;
    }

    public void SetDisplayMode(DisplayMode mode)
    {
        ShowCompact = mode == DisplayMode.Compact;
        ShowFull = mode == DisplayMode.Full;
    }

    public void Apply(KeyboardSnapshot s)
    {
        Title = s.KeyboardDisplayName ?? _loc.Get("AppName");

        switch (s.State)
        {
            case MonitorState.Connected:
                StateText = string.Empty;
                break;
            case MonitorState.Connecting:
                StateText = _loc.Get("State_Connecting");
                break;
            case MonitorState.Disconnected:
                StateText = _loc.Get("State_Disconnected");
                break;
            case MonitorState.BluetoothUnavailable:
                StateText = _loc.Get("State_BluetoothUnavailable");
                break;
            case MonitorState.UnsupportedVersion:
                StateText = _loc.Get("State_UnsupportedVersion");
                break;
            default:
                StateText = _loc.Get("State_NoKeyboard");
                break;
        }

        var connected = s.State == MonitorState.Connected;
        ApplyStatus(connected ? s.Status : null, s.StatusFreshness);
        ApplyConnectivity(connected ? s.Connectivity : null, connected ? s.Capability : null);
        ApplyBattery(connected ? s.Battery : null, connected ? s.Capability : null);
        ApplyCompact(s, connected);
    }

    /// <summary>
    /// Builds the structured compact single-row state, segment-for-segment with
    /// macOS <c>FloatingPanel.renderCompactSegments</c>: layer + modifier glyphs,
    /// then host-dot + profile, per-side (or overall) battery with status dots,
    /// and the output endpoint. 1.1 segments hide themselves when the matching
    /// capability bit is clear or the keyboard is disconnected.
    /// </summary>
    private void ApplyCompact(KeyboardSnapshot s, bool connected)
    {
        if (!connected || s.Status is not { } status)
        {
            CompactLayer = string.IsNullOrEmpty(StateText) ? _loc.Get("State_NoKeyboard") : StateText;
            ShowCompactHost = ShowCompactSplit = ShowCompactEndpoint = false;
            return;
        }

        CompactLayer = _loc.LayerLabel(status.LayerIndex, status.LayerName);

        var conn = s.Connectivity;
        var cap = s.Capability;
        if (conn is null || cap is null)
        {
            // KBP 1.0 — only layer + modifier glyphs, no connectivity segments.
            ShowCompactHost = ShowCompactSplit = ShowCompactEndpoint = false;
            return;
        }

        // Host segment: dot (if host-connection capable) + profile index.
        ShowCompactHost = cap.HasHostConnection || cap.HasProfile;
        CompactHostDotVisible = cap.HasHostConnection;
        if (cap.HasHostConnection)
            CompactHostDot = conn.HostState.Connected ? DotGreen : DotGray;
        CompactProfileVisible = cap.HasProfile;
        if (cap.HasProfile)
        {
            var maxSlot = Math.Max((byte)1, conn.Profile.MaxSlots);
            var idx = conn.Profile.Index == 0 ? 0 : Math.Min(conn.Profile.Index, maxSlot);
            var suffix = conn.Profile.IsOpen ? "\u22EF" : string.Empty;
            CompactProfileText = (idx == 0 ? "P\u2014" : $"P{idx}") + suffix;
        }

        // Split / battery segment.
        if (cap.IsSplit)
        {
            ShowCompactSplit = true;
            var leftOnline = !cap.HasSplitLink || conn.SplitFlags.LeftOnline;
            var rightOnline = !cap.HasSplitLink || conn.SplitFlags.RightOnline;
            CompactLeftDot = leftOnline ? DotGreen : DotRed;
            CompactRightDot = rightOnline ? DotGreen : DotRed;
            var split = s.Battery?.Shape as BatteryStatus.Kind.Split;
            CompactLeftBattery = CompactBattery("L", split?.Left);
            CompactRightBattery = CompactBattery("R", split?.Right);
            CompactRightVisible = true;
            CompactLeftCharging = cap.HasLeftCharging && conn.Charging.LeftCharging;
            CompactRightCharging = cap.HasRightCharging && conn.Charging.RightCharging;
        }
        else if (s.Battery?.Shape is BatteryStatus.Kind.Overall overall)
        {
            ShowCompactSplit = true;
            CompactLeftDot = DotGreen;
            CompactLeftBattery = CompactBattery(string.Empty, overall.Reading);
            CompactRightVisible = false;
            CompactLeftCharging = cap.HasLeftCharging && conn.Charging.LeftCharging;
            CompactRightCharging = false;
        }
        else
        {
            ShowCompactSplit = false;
        }

        // Output-endpoint segment.
        ShowCompactEndpoint = cap.HasOutputEndpoint;
        if (cap.HasOutputEndpoint)
        {
            CompactEndpointText = conn.Output.Kind switch
            {
                ConnectivityStatus.OutputKind.Usb => "USB",
                ConnectivityStatus.OutputKind.Ble => "BLE",
                ConnectivityStatus.OutputKind.Unknown => "\u2014",
                _ => $"0x{conn.Output.RawByte:X2}"
            };
        }
    }

    /// <summary>Narrow battery token for compact mode: "L85" / "R72" / "L-".
    /// Mirrors macOS <c>compactBatteryText</c> - no "%" sign, sentinel -> em dash.</summary>
    private static string CompactBattery(string prefix, BatteryStatus.BatteryReading? reading) =>
        reading?.Percent is int p ? $"{prefix}{p}" : $"{prefix}\u2014";

    private void ApplyStatus(KeyboardStatus? status, FieldFreshness freshness)
    {
        if (status is null)
        {
            ShowStatus = false;
            // Compact mode shows the modifier glyphs even while disconnected, so
            // clear them here to avoid a stale "pressed" look.
            Shift = Control = Alt = Gui = false;
            return;
        }

        ShowStatus = true;
        LayerName = _loc.LayerLabel(status.LayerIndex, status.LayerName);
        Shift = status.ShiftActive;
        Control = status.ControlActive;
        Alt = status.AltActive;
        Gui = status.GuiActive;

        StatusStale = freshness.IsStale;
        StatusUpdatedHint = freshness is { IsStale: true, LastUpdated: { } at }
            ? _loc.Format("State_UpdatedAt", at.ToLocalTime().ToString("HH:mm:ss"))
            : string.Empty;
    }

    private void ApplyConnectivity(ConnectivityStatus? conn, CapabilityMatrix? cap)
    {
        ConnectivityRows.Clear();
        if (conn is null || cap is null)
        {
            ShowConnectivity = false;
            return;
        }

        if (cap.HasHostConnection)
        {
            ConnectivityRows.Add(new LabeledValue(
                _loc.Get("Conn_HostLink"),
                conn.HostState.Connected ? _loc.Get("Conn_Online") : _loc.Get("Conn_Offline")));
        }

        if (cap.HasProfile && conn.Profile.Index != 0)
        {
            ConnectivityRows.Add(new LabeledValue(
                _loc.Get("Conn_Profile"),
                $"{conn.Profile.Index}/{conn.Profile.MaxSlots}"));
        }

        if (cap is { IsSplit: true, HasSplitLink: true })
        {
            ConnectivityRows.Add(new LabeledValue(_loc.Get("Conn_SplitLeft"),
                conn.SplitFlags.LeftOnline ? _loc.Get("Conn_Online") : _loc.Get("Conn_Offline")));
            ConnectivityRows.Add(new LabeledValue(_loc.Get("Conn_SplitRight"),
                conn.SplitFlags.RightOnline ? _loc.Get("Conn_Online") : _loc.Get("Conn_Offline")));
        }

        if (cap.HasOutputEndpoint)
        {
            ConnectivityRows.Add(new LabeledValue(_loc.Get("Conn_Output"), OutputLabel(conn.Output.Kind)));
        }

        ShowConnectivity = ConnectivityRows.Count > 0;
    }

    private void ApplyBattery(BatteryStatus? battery, CapabilityMatrix? cap)
    {
        BatteryRows.Clear();
        if (battery is null || cap is null)
        {
            ShowBattery = false;
            return;
        }

        // Battery presence is decided by the AA3 characteristic existing (battery
        // != null), not by the charging capability bits. has_left/right_charging
        // only gate the (optional) charging icon — never the percentage readout.
        // Mirrors macOS renderBatteryRow (FloatingPanel.swift).
        switch (battery.Shape)
        {
            case BatteryStatus.Kind.Overall o:
                BatteryRows.Add(new LabeledValue(string.Empty, _loc.BatteryLabel(o.Reading.Percent)));
                break;
            case BatteryStatus.Kind.Split sp:
                BatteryRows.Add(new LabeledValue(_loc.Get("Battery_Left"), _loc.BatteryLabel(sp.Left.Percent)));
                BatteryRows.Add(new LabeledValue(_loc.Get("Battery_Right"), _loc.BatteryLabel(sp.Right.Percent)));
                break;
        }

        ShowBattery = BatteryRows.Count > 0;
    }

    private string OutputLabel(ConnectivityStatus.OutputKind kind) => kind switch
    {
        ConnectivityStatus.OutputKind.Usb => _loc.Get("Output_Usb"),
        ConnectivityStatus.OutputKind.Ble => _loc.Get("Output_Ble"),
        _ => _loc.Get("Output_Unknown")
    };

    private void Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (Equals(field, value)) return;
        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
}

public sealed record LabeledValue(string Label, string Value);
