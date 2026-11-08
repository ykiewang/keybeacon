using System;

namespace KeyBeacon.Core;

/// <summary>
/// Session-scoped cache of the last-learned KBP 1.2 Link-slot (AA4) for the
/// active BLE connection (spec 005 / US2, T033).
///
/// AA4 is READ-only (no NOTIFY), so the host must re-read it to notice a slot
/// change (e.g. the keyboard was re-paired to a different profile slot, or the
/// peer address was not yet resolved to a bond at connect time and resolved
/// later). This value lives only for the current connection — <see cref="Reset"/>
/// on disconnect guarantees a stale in-use claim never survives a re-pair
/// (FR-006, FR-009).
///
/// <see cref="LearnedAt"/> records when the current slot was last (re-)read, for
/// diagnostics and the fallback re-read timer. Structurally identical to the
/// macOS <c>LinkSlotCache</c> (cross-platform parity, constitution §III).
/// </summary>
public sealed class LinkSlotCache
{
    /// <summary>The most recently read Link-slot, or null if never read this session.</summary>
    public LinkSlot? Slot { get; private set; }

    /// <summary>Wall-clock instant the current <see cref="Slot"/> was last (re-)read, or null.</summary>
    public DateTimeOffset? LearnedAt { get; private set; }

    /// <summary>
    /// Record a freshly-read Link-slot. A null argument (empty/failed read) is
    /// ignored — the previously-learned slot is retained, never clobbered.
    ///
    /// Returns true only for a <em>read-back change</em>: a non-null new value
    /// whose slot differs from a previously-known slot. The initial learn (no
    /// prior value) returns false so the <c>hostlink.read_back_slot</c>
    /// diagnostic (T034) fires on genuine changes, not the first read. Always
    /// refreshes <see cref="LearnedAt"/> on a successful parse.
    /// </summary>
    public bool Learn(LinkSlot? newSlot, DateTimeOffset now)
    {
        if (newSlot is null) return false;
        bool hadPrevious = Slot is not null;
        var previousSlot = Slot?.Slot;
        Slot = newSlot;
        LearnedAt = now;
        return hadPrevious && previousSlot != newSlot.Slot;
    }

    /// <summary>Forget the learned slot (connection dropped / keyboard switched).</summary>
    public void Reset()
    {
        Slot = null;
        LearnedAt = null;
    }
}
