namespace KeyBeacon.Core;

/// <summary>
/// Abstract colour for the per-link host-status visual encoding. The palette is
/// platform-agnostic here (no WPF types) so it is pure-function unit-testable;
/// the UI layer maps each case to a WPF <c>SolidColorBrush</c>.
///
/// Single source of truth: <b>both</b> the full card and the compact strip reuse
/// this exact mapping (FR-016). Never define a mode-specific scheme.
/// Structurally identical to the macOS <c>HostStatusColor</c>
/// (cross-platform parity, constitution §III).
/// </summary>
public enum HostStatusColor
{
    Green,   // in use on this computer
    Orange,  // keyboard active on another computer
    Blue,    // keyboard on USB (not this BLE link)
    Gray,    // cannot determine
    Red      // disconnected
}

/// <summary>
/// The colour + shape symbol that encode a <see cref="LocalHostStatus"/>.
/// Redundant by design: <see cref="Symbol"/> (a shape) lets the state be told
/// apart without relying on colour alone (WCAG 1.4.1 / FR-016).
///
/// Contract: <c>specs/005-host-link-profile-awareness/contracts/host-status-visual.md</c>
/// (V-1 table, V-2 rules). Structurally identical to the macOS
/// <c>HostStatusVisual</c>.
/// </summary>
public readonly record struct HostStatusVisual(HostStatusColor Color, string Symbol)
{
    /// <summary>Map a derived <see cref="LocalHostStatus"/> to its colour + symbol.
    /// Pure, exhaustive, no I/O (FR-014). Parity with macOS <c>hostStatusVisual</c>.</summary>
    public static HostStatusVisual For(LocalHostStatus status) => status.Kind switch
    {
        LocalHostStatusKind.InUseHere => new(HostStatusColor.Green, "●"),
        LocalHostStatusKind.ActiveElsewhere => new(HostStatusColor.Orange, "◐"),
        LocalHostStatusKind.OnUsb => new(HostStatusColor.Blue, "◆"),
        LocalHostStatusKind.CannotDetermine => new(HostStatusColor.Gray, "○"),
        LocalHostStatusKind.Disconnected => new(HostStatusColor.Red, "✕"),
    };
}
