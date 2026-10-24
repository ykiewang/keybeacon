using System;
using System.Collections.Generic;

namespace KeyBeacon.Core;

public enum BleConnectionState
{
    Disconnected,
    Connecting,
    Connected
}

/// <summary>
/// A connected BLE peripheral exposing the KeyBeacon service.
/// On Windows the identifier is the WinRT <c>DeviceInformation.Id</c>.
/// </summary>
public sealed record CompatibleKeyboard(
    string Identifier,
    string? Name,
    BleConnectionState State,
    bool IsCompatible)
{
    public static bool IsCompatibleServices(IEnumerable<Guid> discoveredServiceIds) =>
        discoveredServiceIds.Any(id => id == KbpUuids.Service);

    /// <summary>BLE device name when usable, otherwise a stable generic fallback (FR-003).</summary>
    public string DisplayName =>
        string.IsNullOrWhiteSpace(Name)
            ? $"Keyboard {IdentifierPrefix(Identifier)}"
            : Name!;

    /// <summary>
    /// Picks the keyboard to monitor: the remembered one when still present,
    /// otherwise the sole candidate, otherwise none (FR-010).
    /// </summary>
    public static string? ResolveSelection(IReadOnlyCollection<string> candidates, string? remembered)
    {
        if (remembered is not null && candidates.Contains(remembered)) return remembered;
        if (candidates.Count == 1) return candidates.First();
        return null;
    }

    private static string IdentifierPrefix(string identifier) =>
        identifier.Length <= 8 ? identifier : identifier[..8];
}
