// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import Foundation

/// KBP 1.1 `capability_bits` (Connectivity characteristic byte 0): a per-field
/// support declaration that lets the host decide which 1.1 fields are
/// meaningful on a given keyboard.
///
/// Wire contract: `protocol/README.md` §14.3.2 and
/// `specs/001-connectivity-power/contracts/protocol-kbp11.md` §3.2.
///
/// The two "consistency" cross-field invariants IV-C1 and IV-C3 (see
/// `data-model.md` §1) are checked by `isConsistent`; the firmware-bug
/// recovery (`capability.inconsistent` log) is the caller's responsibility —
/// typically `BLEClient` when it parses the first notify.
public struct CapabilityMatrix: Equatable {

    public let isSplit: Bool              // bit 0 — CONFIG_ZMK_SPLIT
    public let hasHostConnection: Bool    // bit 1
    public let hasProfile: Bool           // bit 2
    public let hasSplitLink: Bool         // bit 3 — requires isSplit (IV-C1)
    public let hasOutputEndpoint: Bool    // bit 4
    public let hasLeftCharging: Bool      // bit 5 — overall when !isSplit
    public let hasRightCharging: Bool     // bit 6 — requires isSplit + hasLeftCharging (IV-C3)
    public let reserved7: Bool            // bit 7 — 1.1 firmware MUST emit 0

    public init(
        isSplit: Bool,
        hasHostConnection: Bool,
        hasProfile: Bool,
        hasSplitLink: Bool,
        hasOutputEndpoint: Bool,
        hasLeftCharging: Bool,
        hasRightCharging: Bool,
        reserved7: Bool = false
    ) {
        self.isSplit = isSplit
        self.hasHostConnection = hasHostConnection
        self.hasProfile = hasProfile
        self.hasSplitLink = hasSplitLink
        self.hasOutputEndpoint = hasOutputEndpoint
        self.hasLeftCharging = hasLeftCharging
        self.hasRightCharging = hasRightCharging
        self.reserved7 = reserved7
    }

    /// Decode `capability_bits` (byte 0 of the Connectivity payload).
    public init(fromByte byte: UInt8) {
        self.isSplit            = (byte & 0x01) != 0
        self.hasHostConnection  = (byte & 0x02) != 0
        self.hasProfile         = (byte & 0x04) != 0
        self.hasSplitLink       = (byte & 0x08) != 0
        self.hasOutputEndpoint  = (byte & 0x10) != 0
        self.hasLeftCharging    = (byte & 0x20) != 0
        self.hasRightCharging   = (byte & 0x40) != 0
        self.reserved7          = (byte & 0x80) != 0
    }

    /// Raw byte round-trip (lossless; `reserved7` is preserved).
    public var rawByte: UInt8 {
        var byte: UInt8 = 0
        if isSplit             { byte |= 0x01 }
        if hasHostConnection   { byte |= 0x02 }
        if hasProfile          { byte |= 0x04 }
        if hasSplitLink        { byte |= 0x08 }
        if hasOutputEndpoint   { byte |= 0x10 }
        if hasLeftCharging     { byte |= 0x20 }
        if hasRightCharging    { byte |= 0x40 }
        if reserved7           { byte |= 0x80 }
        return byte
    }

    /// IV-C1: `hasSplitLink` requires `isSplit`.
    /// IV-C3: `hasRightCharging` requires `isSplit && hasLeftCharging`.
    ///
    /// Returns `false` when either invariant is violated. The caller SHOULD
    /// drop the offending bit (treat as 0) and emit a `capability.inconsistent`
    /// diagnostic log entry, per consumer rules C-C3 and C-C6.
    public var isConsistent: Bool {
        if hasSplitLink && !isSplit { return false }
        if hasRightCharging && !isSplit { return false }
        if hasRightCharging && !hasLeftCharging { return false }
        return true
    }
}
