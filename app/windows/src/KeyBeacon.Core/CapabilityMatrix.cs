using System;

namespace KeyBeacon.Core;

/// <summary>
/// KBP 1.1 <c>capability_bits</c> (Connectivity payload byte 0).
/// Wire contract: protocol/README.md §14.3.2.
/// </summary>
public sealed record CapabilityMatrix(
    bool IsSplit,
    bool HasHostConnection,
    bool HasProfile,
    bool HasSplitLink,
    bool HasOutputEndpoint,
    bool HasLeftCharging,
    bool HasRightCharging,
    bool Reserved7)
{
    public static CapabilityMatrix FromByte(byte b) => new(
        IsSplit: (b & 0x01) != 0,
        HasHostConnection: (b & 0x02) != 0,
        HasProfile: (b & 0x04) != 0,
        HasSplitLink: (b & 0x08) != 0,
        HasOutputEndpoint: (b & 0x10) != 0,
        HasLeftCharging: (b & 0x20) != 0,
        HasRightCharging: (b & 0x40) != 0,
        Reserved7: (b & 0x80) != 0);

    /// <summary>Lossless byte round-trip; bit 7 is preserved.</summary>
    public byte ToByte()
    {
        byte b = 0;
        if (IsSplit) b |= 0x01;
        if (HasHostConnection) b |= 0x02;
        if (HasProfile) b |= 0x04;
        if (HasSplitLink) b |= 0x08;
        if (HasOutputEndpoint) b |= 0x10;
        if (HasLeftCharging) b |= 0x20;
        if (HasRightCharging) b |= 0x40;
        if (Reserved7) b |= 0x80;
        return b;
    }

    /// <summary>
    /// IV-C1: HasSplitLink requires IsSplit.
    /// IV-C3: HasRightCharging requires IsSplit and HasLeftCharging.
    /// </summary>
    public bool IsConsistent
    {
        get
        {
            if (HasSplitLink && !IsSplit) return false;
            if (HasRightCharging && !IsSplit) return false;
            if (HasRightCharging && !HasLeftCharging) return false;
            return true;
        }
    }

    /// <summary>
    /// Returns the first violated invariant as a stable reason token, or null.
    /// Callers SHOULD drop the offending bit (treat as false) and emit a
    /// <c>capability.inconsistent</c> diagnostic.
    /// </summary>
    public string? InconsistencyReason()
    {
        if (HasSplitLink && !IsSplit) return "IV-C1:has_split_link_without_is_split";
        if (HasRightCharging && !IsSplit) return "IV-C3:right_charging_without_split";
        if (HasRightCharging && !HasLeftCharging) return "IV-C3:right_charging_without_left";
        return null;
    }

    /// <summary>Drops violating bits so the result is self-consistent.</summary>
    public CapabilityMatrix Normalized()
    {
        var split = IsSplit;
        var splitLink = HasSplitLink && split;
        var leftCharging = HasLeftCharging;
        var rightCharging = HasRightCharging && split && leftCharging;
        return this with
        {
            HasSplitLink = splitLink,
            HasRightCharging = rightCharging
        };
    }
}
