// Copyright (c) 2026 The TOTEM ZMK Contributors
// SPDX-License-Identifier: MIT

import Foundation

public struct KeyboardStatus {
    public let layerIndex: UInt8
    public let layerName: String
    public let mods: UInt8
    public let connected: Bool

    public static let disconnected = KeyboardStatus(
        layerIndex: 0, layerName: "", mods: 0, connected: false
    )

    public static func parse(_ data: Data) -> KeyboardStatus? {
        guard data.count >= 2 else { return nil }
        let idx  = data[0]
        let mods = data[1]
        var name = ""
        if data.count > 2 {
            name = String(bytes: data[2...], encoding: .utf8) ?? ""
        }
        return KeyboardStatus(
            layerIndex: idx,
            layerName: name.isEmpty ? "L\(idx)" : name,
            mods: mods,
            connected: true
        )
    }

    public var shiftActive:   Bool { mods & 0x22 != 0 }
    public var controlActive: Bool { mods & 0x11 != 0 }
    public var optionActive:  Bool { mods & 0x44 != 0 }
    public var commandActive: Bool { mods & 0x88 != 0 }
}
