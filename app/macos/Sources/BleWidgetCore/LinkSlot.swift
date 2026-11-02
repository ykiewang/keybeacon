// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import Foundation

/// Parsed form of a single KBP 1.2 Link-slot characteristic payload (`AA4`).
///
/// Wire contract: `protocol/README.md` §15 and
/// `specs/005-host-link-profile-awareness/contracts/host-link-context.md`.
///
/// `parse(from:)` returns `nil` when the payload is empty (invariant C-L3,
/// length < 1 byte). Byte `[0]` carries the 1-based profile slot that *this*
/// BLE connection maps to in bits 0–6 (`0` = not determined / not applicable).
/// Bit 7 is reserved and ignored for the slot value; trailing bytes `[1..]`
/// are ignored (invariant C-L5, MINOR forward-compatibility).
///
/// Because `AA4` is READ-only (no NOTIFY), the value a host reads is always the
/// response for *its own* connection — there is no broadcast-frame ambiguity to
/// disentangle. See `data-model.md` §1.2.
public struct LinkSlot: Equatable {

    /// 1-based profile slot for *this* BLE connection. `0` = not-determined /
    /// not-applicable (the firmware could not resolve the connection peer to a
    /// slot — empty/unpaired/open/private-address mismatch).
    public let slot: UInt8

    /// Bit 7 of byte 0; 1.2 firmware MUST emit 0 (invariant P-L4). Preserved
    /// here only for diagnostics / forward-compatibility.
    public let reservedBit7: Bool

    /// Bytes beyond offset 0 present in the raw payload and discarded
    /// (invariant C-L5). Useful for diagnostics.
    public let trailingBytesIgnored: Int

    public init(slot: UInt8, reservedBit7: Bool = false, trailingBytesIgnored: Int = 0) {
        self.slot = slot
        self.reservedBit7 = reservedBit7
        self.trailingBytesIgnored = trailingBytesIgnored
    }

    /// `true` when the firmware resolved this connection to a concrete slot
    /// (`slot >= 1`). `slot == 0` means "not determined" — the host MUST NOT
    /// fabricate an in-use claim (FR-003 / C-L2).
    public var isDetermined: Bool { slot >= 1 }

    /// `true` when `slot` is a usable 1-based value within `maxSlots`
    /// (`maxSlots` is the Connectivity payload byte 3). A `maxSlots` of 0
    /// (unknown) only requires `slot >= 1`. Used for the out-of-range
    /// diagnostic (C-L4).
    public func isWithinRange(maxSlots: UInt8) -> Bool {
        guard slot >= 1 else { return false }
        if maxSlots == 0 { return true }
        return slot <= maxSlots
    }

    /// Decode a Link-slot payload. Returns `nil` when `data` is empty (C-L3).
    public static func parse(from data: Data) -> LinkSlot? {
        guard let first = data.first else { return nil }
        return LinkSlot(
            slot: first & 0x7F,
            reservedBit7: (first & 0x80) != 0,
            trailingBytesIgnored: data.count - 1
        )
    }
}
