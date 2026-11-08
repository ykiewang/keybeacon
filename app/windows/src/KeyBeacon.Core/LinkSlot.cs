using System;

namespace KeyBeacon.Core;

/// <summary>
/// Parsed KBP 1.2 Link-slot characteristic payload (AA4).
/// Wire contract: protocol/README.md §15 and
/// specs/005-host-link-profile-awareness/contracts/host-link-context.md.
///
/// Because AA4 is READ-only (no NOTIFY), the value a host reads is always the
/// response for its own connection — there is no broadcast-frame ambiguity to
/// disentangle (data-model.md §1.2). Structurally identical to the macOS
/// <c>LinkSlot</c>.
/// </summary>
public sealed record LinkSlot(byte Slot, bool ReservedBit7, int TrailingBytesIgnored)
{
    /// <summary>
    /// True when the firmware resolved this connection to a concrete slot
    /// (<c>Slot &gt;= 1</c>). <c>Slot == 0</c> means "not determined" — the host
    /// MUST NOT fabricate an in-use claim (FR-003 / C-L2).
    /// </summary>
    public bool IsDetermined => Slot >= 1;

    /// <summary>
    /// True when <c>Slot</c> is a usable 1-based value within <paramref name="maxSlots"/>
    /// (the Connectivity payload byte 3). A <paramref name="maxSlots"/> of 0
    /// (unknown) only requires <c>Slot &gt;= 1</c>. Used for the out-of-range
    /// diagnostic (C-L4).
    /// </summary>
    public bool IsWithinRange(byte maxSlots)
    {
        if (Slot < 1) return false;
        if (maxSlots == 0) return true;
        return Slot <= maxSlots;
    }

    /// <summary>
    /// Decodes a Link-slot payload. Returns null when <paramref name="data"/> is
    /// empty (C-L3). Bits 0–6 of <c>[0]</c> = the 1-based slot; bit 7 is reserved
    /// and ignored for the slot value; trailing bytes <c>[1..]</c> are ignored
    /// (C-L5, MINOR forward-compatibility).
    /// </summary>
    public static LinkSlot? Parse(ReadOnlySpan<byte> data)
    {
        if (data.Length < 1) return null;
        byte b0 = data[0];
        return new LinkSlot(
            Slot: (byte)(b0 & 0x7F),
            ReservedBit7: (b0 & 0x80) != 0,
            TrailingBytesIgnored: data.Length - 1);
    }
}
