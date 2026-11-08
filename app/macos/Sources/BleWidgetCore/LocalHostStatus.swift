// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import Foundation

/// The host-local "is this keyboard being used *on this computer*?" status,
/// derived per BLE connection from the KBP 1.2 Link-slot characteristic (`AA4`)
/// combined with the KBP 1.1 Connectivity snapshot (`AA2`).
///
/// This is the five-state enum from `data-model.md` §6. It is deliberately
/// distinct from the transport-level connection state: it answers a
/// higher-level question — "in use *here* vs *elsewhere*" — that only a
/// per-connection READ can honestly answer.
public enum LocalHostStatus: Equatable {
    /// The keyboard's active profile maps to *this* connection's slot.
    case inUseHere
    /// The keyboard is active on another host. `slot` is the keyboard's active
    /// profile slot (1-based), displayed as "P{slot}".
    case activeElsewhere(slot: UInt8)
    /// The keyboard is outputting over USB (not this BLE link).
    case onUsb
    /// Not enough positive confirmation to classify: old firmware without
    /// `AA4`, an open/unassigned active profile, or the firmware could not
    /// resolve this connection to a slot.
    case cannotDetermine
    /// The BLE link is down.
    case disconnected
}

/// Pure, host-local status derivation. Structurally identical to the Windows
/// `HostContextStatus.DeriveLocalHostStatus` (cross-platform parity,
/// constitution §III).
///
/// Inputs are already-parsed fields + whether `AA4` was discovered. No I/O, no
/// global state — exhaustively unit-testable (FR-014).
///
/// Priority (`data-model.md` §6.1): `disconnected` > `onUsb` >
/// `inUseHere`/`activeElsewhere` > `cannotDetermine`. The function NEVER
/// returns `inUseHere`/`activeElsewhere` without positive confirmation
/// (constitution §IV, FR-008).
///
/// - Parameters:
///   - hasAA4: whether the Link-slot characteristic was discovered on this
///     keyboard (capability probing is by characteristic existence, HW-5).
///   - connected: the live BLE transport connection state. `false` short-
///     circuits to `.disconnected` (FR-009), overriding any cached value.
///   - capability: parsed `capability_bits` (`AA2` byte 0), or `nil` if `AA2`
///     is absent / not yet read.
///   - activeProfile: parsed active profile (`AA2` bytes 2–3), or `nil`.
///   - localSlot: parsed Link-slot (`AA4`), or `nil` if not yet read.
///   - output: parsed output endpoint (`AA2` byte 5), or `nil`.
public func deriveLocalHostStatus(
    hasAA4: Bool,
    connected: Bool,
    capability: CapabilityMatrix?,
    activeProfile: ConnectivityStatus.Profile?,
    localSlot: LinkSlot?,
    output: ConnectivityStatus.OutputEndpoint?
) -> LocalHostStatus {
    // 1. disconnected — highest priority (FR-009).
    guard connected else { return .disconnected }

    // 2. on-usb — the keyboard is typing over USB, not this BLE link.
    if let capability, capability.hasOutputEndpoint, let output, output == .usb {
        return .onUsb
    }

    // 3. no AA4 (old firmware) → never fabricate in-use/elsewhere (C-L2, FR-008).
    guard hasAA4 else { return .cannotDetermine }

    // 4. active profile unknown / open / no profile capability.
    guard let capability, capability.hasProfile,
          let activeProfile, activeProfile.index != 0, !activeProfile.isOpen
    else { return .cannotDetermine }

    // 5. firmware could not resolve this connection to a slot.
    guard let localSlot, localSlot.slot != 0 else { return .cannotDetermine }

    // 6. compare the keyboard's active profile to this connection's slot.
    if activeProfile.index == localSlot.slot {
        return .inUseHere
    }
    return .activeElsewhere(slot: activeProfile.index)
}
