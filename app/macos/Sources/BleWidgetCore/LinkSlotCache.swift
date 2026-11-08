// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import Foundation

/// Session-scoped cache of the last-learned KBP 1.2 Link-slot (`AA4`) for the
/// active BLE connection (spec 005 / US2, T033).
///
/// `AA4` is READ-only (no NOTIFY), so the host must re-read it to notice a slot
/// change (e.g. the keyboard was re-paired to a different profile slot, or the
/// peer address was not yet resolved to a bond at connect time and resolved
/// later). This value lives only for the current connection — `reset()` on
/// disconnect guarantees a stale in-use claim never survives a re-pair (FR-006,
/// FR-009).
///
/// `learnedAt` records when the current slot was last (re-)read, for diagnostics
/// and the fallback re-read timer. Structurally identical to the Windows
/// `LinkSlotCache` (cross-platform parity, constitution §III).
public struct LinkSlotCache: Equatable {

    /// The most recently read Link-slot, or `nil` if never read this session.
    public private(set) var slot: LinkSlot?

    /// Wall-clock instant the current `slot` was last (re-)read, or `nil`.
    public private(set) var learnedAt: Date?

    public init() {}

    /// Record a freshly-read Link-slot. A `nil` argument (empty/failed read) is
    /// ignored — the previously-learned slot is retained, never clobbered.
    ///
    /// Returns `true` only for a *read-back change*: a non-nil new value whose
    /// slot differs from a previously-known slot. The initial learn (no prior
    /// value) returns `false` so the `hostlink.read_back_slot` diagnostic (T034)
    /// fires on genuine changes, not the first read. Always refreshes
    /// `learnedAt` on a successful parse.
    @discardableResult
    public mutating func learn(_ newSlot: LinkSlot?, at now: Date) -> Bool {
        guard let newSlot else { return false }
        let hadPrevious = slot != nil
        let previousSlot = slot?.slot
        slot = newSlot
        learnedAt = now
        return hadPrevious && previousSlot != newSlot.slot
    }

    /// Forget the learned slot (connection dropped / keyboard switched).
    public mutating func reset() {
        slot = nil
        learnedAt = nil
    }
}
