using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
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

    private string _compactSummary = string.Empty;
    public string CompactSummary { get => _compactSummary; private set => Set(ref _compactSummary, value); }

    private DisplayMode _displayMode = DisplayMode.Full;

    public void SetDisplayMode(DisplayMode mode)
    {
        _displayMode = mode;
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
        CompactSummary = BuildCompactSummary(s, connected);
    }

    /// <summary>
    /// One-line condensed status for compact mode: layer · active modifiers ·
    /// battery. Falls back to the state text when not connected. Battery shows
    /// whenever data is present (charging bits never gate the percentage).
    /// </summary>
    private string BuildCompactSummary(KeyboardSnapshot s, bool connected)
    {
        if (!connected || s.Status is not { } status)
        {
            return string.IsNullOrEmpty(StateText) ? _loc.Get("State_NoKeyboard") : StateText;
        }

        var parts = new List<string> { _loc.LayerLabel(status.LayerIndex, status.LayerName) };

        var mods = new List<string>(4);
        if (status.ShiftActive) mods.Add(_loc.Get("Mod_Shift"));
        if (status.ControlActive) mods.Add(_loc.Get("Mod_Control"));
        if (status.AltActive) mods.Add(_loc.Get("Mod_Alt"));
        if (status.GuiActive) mods.Add(_loc.Get("Mod_Gui"));
        if (mods.Count > 0) parts.Add(string.Join(" ", mods));

        switch (s.Battery?.Shape)
        {
            case BatteryStatus.Kind.Overall o:
                parts.Add(_loc.BatteryLabel(o.Reading.Percent));
                break;
            case BatteryStatus.Kind.Split sp:
                parts.Add($"{_loc.Get("Battery_Left")} {_loc.BatteryLabel(sp.Left.Percent)}  " +
                          $"{_loc.Get("Battery_Right")} {_loc.BatteryLabel(sp.Right.Percent)}");
                break;
        }

        return string.Join("   ", parts);
    }

    private void ApplyStatus(KeyboardStatus? status, FieldFreshness freshness)
    {
        if (status is null)
        {
            ShowStatus = false;
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
