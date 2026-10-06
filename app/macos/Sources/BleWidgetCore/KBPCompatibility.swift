// Copyright (c) 2026 The TOTEM ZMK Contributors
// SPDX-License-Identifier: MIT

import Foundation
import CoreBluetooth

/// Declares the KeyBeacon Protocol (KBP) MAJOR versions this host supports and
/// classifies a discovered device against them — purely, so it is unit-testable
/// with no BLE hardware (protocol §9/§3; FR-013/FR-014, SC-007).
///
/// The **service UUID is the MAJOR-version signal**: a MAJOR bump uses a new
/// service UUID that keeps the KeyBeacon UUID base. A host therefore supports a
/// *set* of service UUIDs; anything in the KeyBeacon family but outside that set
/// is a protocol version this app does not understand, and must be reported as
/// such rather than mis-parsed.
public enum KBPCompatibility {

    public enum Classification: Equatable {
        /// A recognized KBP service UUID — a MAJOR version this app supports.
        case supported
        /// A KeyBeacon-family service, but not one this app supports (newer/unknown MAJOR).
        case unsupportedVersion
        /// No KeyBeacon service at all — not a KeyBeacon keyboard.
        case notAKeyboard
    }

    /// The set of KBP service UUIDs (MAJORs) this app understands. KBP 1.x only, today.
    public static let supportedServiceUUIDs: Set<CBUUID> = [
        CBUUID(string: "AA440AA0-F5ED-4C48-84A1-8062D20D3D55")
    ]

    /// Shared KeyBeacon UUID namespace suffix. A future MAJOR keeps this suffix with
    /// a different leading segment, so an unknown family member stays detectable.
    static let familySuffix = "-F5ED-4C48-84A1-8062D20D3D55"

    /// True when `uuid` belongs to the KeyBeacon UUID family (any MAJOR).
    public static func isKeyBeaconFamily(_ uuid: CBUUID) -> Bool {
        uuid.uuidString.uppercased().hasSuffix(familySuffix)
    }

    /// Classify a device from the set of GATT service UUIDs it exposes.
    public static func classify(discoveredServices: [CBUUID]) -> Classification {
        if !supportedServiceUUIDs.isDisjoint(with: Set(discoveredServices)) {
            return .supported
        }
        if discoveredServices.contains(where: isKeyBeaconFamily) {
            return .unsupportedVersion
        }
        return .notAKeyboard
    }
}
