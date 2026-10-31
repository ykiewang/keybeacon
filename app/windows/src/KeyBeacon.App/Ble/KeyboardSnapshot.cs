using System;
using System.Collections.Generic;
using KeyBeacon.Core;

namespace KeyBeacon.App.Ble;

/// <summary>High-level app state, independent of BLE/WinRT types, for UI binding.</summary>
public enum MonitorState
{
    NoKeyboard,
    BluetoothUnavailable,
    UnsupportedVersion,
    Connecting,
    Connected,
    Disconnected
}

/// <summary>A per-field staleness flag paired with the last-known value timestamp.</summary>
public readonly record struct FieldFreshness(bool IsStale, DateTimeOffset? LastUpdated);

/// <summary>
/// Immutable snapshot the UI renders. Produced by <see cref="KeyboardMonitor"/>
/// on the UI thread. Null sections mean "not available / hidden" — the UI MUST
/// NOT render a placeholder for them (FR-016, Principle IV).
/// </summary>
public sealed record KeyboardSnapshot
{
    public MonitorState State { get; init; } = MonitorState.NoKeyboard;
    public string? KeyboardDisplayName { get; init; }

    // KBP 1.0 — layer + modifiers
    public KeyboardStatus? Status { get; init; }
    public FieldFreshness StatusFreshness { get; init; } = new(true, null);

    // KBP 1.1 — connectivity + battery (null when unsupported/absent)
    public CapabilityMatrix? Capability { get; init; }
    public ConnectivityStatus? Connectivity { get; init; }
    public FieldFreshness ConnectivityFreshness { get; init; } = new(true, null);
    public BatteryStatus? Battery { get; init; }
    public FieldFreshness BatteryFreshness { get; init; } = new(true, null);

    public static KeyboardSnapshot ForState(MonitorState state, string? name = null) =>
        new() { State = state, KeyboardDisplayName = name };
}

/// <summary>Field keys used by the staleness tracker and diagnostics.</summary>
public static class FieldKeys
{
    public const string Status = "status";
    public const string Connectivity = "connectivity";
    public const string Battery = "battery";

    public static IReadOnlyList<string> All { get; } = new[] { Status, Connectivity, Battery };
}
