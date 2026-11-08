using System;

namespace KeyBeacon.Core;

/// <summary>
/// The five host-local states from data-model.md §6. Structurally identical to
/// the macOS <c>LocalHostStatus</c> enum (cross-platform parity, §III).
/// </summary>
public enum LocalHostStatusKind
{
    InUseHere,
    ActiveElsewhere,
    OnUsb,
    CannotDetermine,
    Disconnected
}

/// <summary>
/// Host-local "is this keyboard being used on this computer?" status. Wraps the
/// <see cref="LocalHostStatusKind"/> plus the active slot (1-based) used to
/// render "P{Slot}" for <see cref="LocalHostStatusKind.ActiveElsewhere"/>.
/// </summary>
public readonly record struct LocalHostStatus(LocalHostStatusKind Kind, byte Slot)
{
    public static readonly LocalHostStatus InUseHere = new(LocalHostStatusKind.InUseHere, 0);
    public static LocalHostStatus ActiveElsewhere(byte slot) => new(LocalHostStatusKind.ActiveElsewhere, slot);
    public static readonly LocalHostStatus OnUsb = new(LocalHostStatusKind.OnUsb, 0);
    public static readonly LocalHostStatus CannotDetermine = new(LocalHostStatusKind.CannotDetermine, 0);
    public static readonly LocalHostStatus Disconnected = new(LocalHostStatusKind.Disconnected, 0);
}

/// <summary>
/// Pure, host-local status derivation for the KBP 1.2 per-link feature.
/// </summary>
public static class HostContextStatus
{
    /// <summary>
    /// Line-for-line parity with the macOS <c>deriveLocalHostStatus</c>
    /// (data-model.md §6.1). Inputs are already-parsed fields + whether AA4 was
    /// discovered. No I/O, no global state — exhaustively unit-testable (FR-014).
    ///
    /// Priority: Disconnected &gt; OnUsb &gt; InUseHere/ActiveElsewhere &gt;
    /// CannotDetermine. NEVER returns InUseHere/ActiveElsewhere without positive
    /// confirmation (constitution §IV, FR-008).
    /// </summary>
    /// <param name="hasAA4">Whether the Link-slot characteristic was discovered
    /// on this keyboard (capability probing by characteristic existence, HW-5).</param>
    /// <param name="connected">Live BLE transport connection state. <c>false</c>
    /// short-circuits to <see cref="LocalHostStatus.Disconnected"/> (FR-009).</param>
    /// <param name="capability">Parsed capability_bits (AA2 byte 0), or null.</param>
    /// <param name="activeProfile">Parsed active profile (AA2 bytes 2–3), or null.</param>
    /// <param name="localSlot">Parsed Link-slot (AA4), or null if not yet read.</param>
    /// <param name="output">Parsed output endpoint (AA2 byte 5), or null.</param>
    public static LocalHostStatus DeriveLocalHostStatus(
        bool hasAA4,
        bool connected,
        CapabilityMatrix? capability,
        ConnectivityStatus.ProfileData? activeProfile,
        LinkSlot? localSlot,
        ConnectivityStatus.OutputEndpoint? output)
    {
        // 1. disconnected — highest priority (FR-009).
        if (!connected) return LocalHostStatus.Disconnected;

        // 2. on-usb — the keyboard is typing over USB, not this BLE link.
        if (capability is { HasOutputEndpoint: true }
            && output is { Kind: ConnectivityStatus.OutputKind.Usb })
        {
            return LocalHostStatus.OnUsb;
        }

        // 3. no AA4 (old firmware) → never fabricate in-use/elsewhere (C-L2, FR-008).
        if (!hasAA4) return LocalHostStatus.CannotDetermine;

        // 4. active profile unknown / open / no profile capability.
        if (capability is not { HasProfile: true }
            || activeProfile is null
            || activeProfile.Index == 0
            || activeProfile.IsOpen)
        {
            return LocalHostStatus.CannotDetermine;
        }

        // 5. firmware could not resolve this connection to a slot.
        if (localSlot is null || localSlot.Slot == 0)
        {
            return LocalHostStatus.CannotDetermine;
        }

        // 6. compare the keyboard's active profile to this connection's slot.
        return activeProfile.Index == localSlot.Slot
            ? LocalHostStatus.InUseHere
            : LocalHostStatus.ActiveElsewhere(activeProfile.Index);
    }
}
