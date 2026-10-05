// Copyright (c) 2026 The TOTEM ZMK Contributors
// SPDX-License-Identifier: MIT

import Foundation
import CoreBluetooth

public struct CompatibleKeyboard: Equatable {
    public static let serviceUUID = CBUUID(
        string: "AA440AA0-F5ED-4C48-84A1-8062D20D3D55"
    )

    public let identifier: UUID
    public let name: String?
    public let state: BLEConnectionState
    public let isCompatible: Bool

    public init(
        identifier: UUID,
        name: String?,
        state: BLEConnectionState,
        isCompatible: Bool
    ) {
        self.identifier = identifier
        self.name = name
        self.state = state
        self.isCompatible = isCompatible
    }

    public static func isCompatible(discoveredServiceUUIDs: [CBUUID]) -> Bool {
        discoveredServiceUUIDs.contains(serviceUUID)
    }

    public var displayName: String {
        if let name = name,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return "Keyboard \(identifier.uuidString.prefix(8))"
    }

    public static func resolveSelection(
        candidates: [UUID],
        remembered: UUID?
    ) -> UUID? {
        if let remembered = remembered, candidates.contains(remembered) {
            return remembered
        }
        if candidates.count == 1 {
            return candidates[0]
        }
        return nil
    }
}
