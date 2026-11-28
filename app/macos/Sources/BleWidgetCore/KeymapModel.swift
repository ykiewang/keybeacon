// Copyright (c) 2026 The TOTEM ZMK Contributors
// SPDX-License-Identifier: MIT

import Foundation

public enum BehaviorID: UInt8, Equatable, Codable {
    case kp          = 0x01
    case mt          = 0x02
    case lt          = 0x03
    case mo          = 0x04
    case to          = 0x05
    case tog         = 0x06
    case sl          = 0x07
    case sk          = 0x08
    case trans       = 0x09
    case none        = 0x0A
    case keyRepeat   = 0x0B
    case gresc       = 0x0C
    case capsWord    = 0x0D
    case kt          = 0x0E
    case td          = 0x10
    case macro       = 0x11
    case modMorph    = 0x12
    case bt          = 0x20
    case out         = 0x21
    case reset       = 0x22
    case bootloader  = 0x23
    case mkp         = 0x30
    case rgb         = 0x40
    case bl          = 0x41
    case extPower    = 0x42
    case softOff     = 0x43
    case studioUnlock = 0x44
    case unknown     = 0xFF
}

public struct KeyEntry: Equatable, Codable {
    public let x: Int16
    public let y: Int16
    public let w: UInt8
    public let h: UInt8
    public let r: Int16
    public let rx: Int16
    public let ry: Int16

    public init(x: Int16, y: Int16, w: UInt8, h: UInt8, r: Int16, rx: Int16, ry: Int16) {
        self.x = x; self.y = y; self.w = w; self.h = h
        self.r = r; self.rx = rx; self.ry = ry
    }
}

public struct BindingEntry: Equatable, Codable {
    public let behaviorID: BehaviorID
    public let param1: UInt16
    public let param2: UInt16

    public init(behaviorID: BehaviorID, param1: UInt16, param2: UInt16) {
        self.behaviorID = behaviorID
        self.param1 = param1
        self.param2 = param2
    }

    public func displayLabel(layerNames: [String]) -> String {
        switch behaviorID {
        case .kp:
            return hid(param1)
        case .mt:
            return "\(modLabel(param1))/\(hid(param2))"
        case .lt:
            let name = layerNames.indices.contains(Int(param1)) ? layerNames[Int(param1)] : "L\(param1)"
            return "\(name)/\(hid(param2))"
        case .mo:
            return "MO(\(param1))"
        case .to:
            return "TO(\(param1))"
        case .tog:
            return "TOG(\(param1))"
        case .sl:
            return "SL(\(param1))"
        case .sk:
            return "SK(\(hid(param1)))"
        case .trans:
            return "▽"
        case .none:
            return "∅"
        case .keyRepeat:
            return "⟳"
        case .gresc:
            return "⎋/`"
        case .capsWord:
            return "CAPS"
        case .kt:
            return "KT(\(hid(param1)))"
        case .td:
            return "TD"
        case .macro:
            return "▶M"
        case .modMorph:
            return "MM"
        case .bt:
            return btLabel(param1)
        case .out:
            return param1 == 1 ? "USB" : param1 == 2 ? "BLE" : "OUT"
        case .reset:
            return "RST"
        case .bootloader:
            return "BOOT"
        case .mkp:
            return "MKP"
        case .rgb:
            return "RGB"
        case .bl:
            return "BL"
        case .extPower:
            return "PWR"
        case .softOff:
            return "OFF"
        case .studioUnlock:
            return "STU"
        case .unknown:
            return "?"
        }
    }

    private func hid(_ code: UInt16) -> String {
        HIDKeyLabel.label(for: code)
    }

    private func modLabel(_ mods: UInt16) -> String {
        var parts: [String] = []
        if mods & 0x01 != 0 { parts.append("⌃") }
        if mods & 0x02 != 0 { parts.append("⇧") }
        if mods & 0x04 != 0 { parts.append("⌥") }
        if mods & 0x08 != 0 { parts.append("⌘") }
        if mods & 0x10 != 0 { parts.append("⌃") }
        if mods & 0x20 != 0 { parts.append("⇧") }
        if mods & 0x40 != 0 { parts.append("⌥") }
        if mods & 0x80 != 0 { parts.append("⌘") }
        return parts.isEmpty ? "MOD" : parts.joined()
    }

    private func btLabel(_ cmd: UInt16) -> String {
        switch cmd {
        case 0: return "BT CLR"
        case 1: return "BT NXT"
        case 2: return "BT PRV"
        default: return "BT\(cmd)"
        }
    }
}

public struct KeymapMeta: Equatable, Codable {
    public let crc32: UInt32
    public let layerCount: UInt8
    public let keyCount: UInt16
    public let layerNames: [String]

    public init(crc32: UInt32, layerCount: UInt8, keyCount: UInt16, layerNames: [String]) {
        self.crc32 = crc32
        self.layerCount = layerCount
        self.keyCount = keyCount
        self.layerNames = layerNames
    }

    public static func parse(_ data: Data) -> KeymapMeta? {
        guard data.count >= 7 else { return nil }
        let crc = data.withUnsafeBytes { ptr in
            ptr.loadUnaligned(fromByteOffset: 0, as: UInt32.self).littleEndian
        }
        let layerCount = data[4]
        let keyCount = UInt16(data[5]) | (UInt16(data[6]) << 8)
        var names: [String] = []
        if data.count > 7 {
            let nameData = data.subdata(in: 7..<data.count)
            let parts = nameData.split(separator: 0, omittingEmptySubsequences: false)
            names = parts.compactMap { String(bytes: $0, encoding: .utf8) }
        }
        return KeymapMeta(crc32: crc, layerCount: layerCount, keyCount: keyCount, layerNames: names)
    }
}

public struct KeymapSnapshot: Equatable, Codable {
    public let meta: KeymapMeta
    public let keys: [KeyEntry]
    public let bindings: [[BindingEntry]]

    public init(meta: KeymapMeta, keys: [KeyEntry], bindings: [[BindingEntry]]) {
        self.meta = meta
        self.keys = keys
        self.bindings = bindings
    }

    public static func parse(meta: KeymapMeta, data: Data) -> KeymapSnapshot? {
        let keyCount = Int(meta.keyCount)
        let layerCount = Int(meta.layerCount)
        let keyBlockSize = keyCount * 10
        let bindingBlockSize = layerCount * keyCount * 5
        guard data.count >= keyBlockSize + bindingBlockSize else { return nil }

        var keys: [KeyEntry] = []
        for i in 0..<keyCount {
            let off = i * 10
            let x  = Int16(bitPattern: UInt16(data[off])     | UInt16(data[off+1]) << 8)
            let y  = Int16(bitPattern: UInt16(data[off+2])   | UInt16(data[off+3]) << 8)
            let w  = data[off+4]
            let h  = data[off+5]
            let r  = Int16(bitPattern: UInt16(data[off+6])   | UInt16(data[off+7]) << 8)
            let rx = Int16(bitPattern: UInt16(data[off+8])   | UInt16(data[off+9]) << 8)
            let ry: Int16
            if off + 11 < data.count {
                ry = Int16(bitPattern: UInt16(data[off+10])  | UInt16(data[off+11]) << 8)
            } else {
                ry = 0
            }
            keys.append(KeyEntry(x: x, y: y, w: w, h: h, r: r, rx: rx, ry: ry))
        }

        var bindings: [[BindingEntry]] = []
        for l in 0..<layerCount {
            var row: [BindingEntry] = []
            for k in 0..<keyCount {
                let off = keyBlockSize + (l * keyCount + k) * 5
                let bid = BehaviorID(rawValue: data[off]) ?? .unknown
                let p1 = UInt16(data[off+1]) | UInt16(data[off+2]) << 8
                let p2 = UInt16(data[off+3]) | UInt16(data[off+4]) << 8
                row.append(BindingEntry(behaviorID: bid, param1: p1, param2: p2))
            }
            bindings.append(row)
        }

        return KeymapSnapshot(meta: meta, keys: keys, bindings: bindings)
    }
}

public enum HIDKeyLabel {
    public static func label(for code: UInt16) -> String {
        switch code {
        case 0x04: return "A"; case 0x05: return "B"; case 0x06: return "C"
        case 0x07: return "D"; case 0x08: return "E"; case 0x09: return "F"
        case 0x0A: return "G"; case 0x0B: return "H"; case 0x0C: return "I"
        case 0x0D: return "J"; case 0x0E: return "K"; case 0x0F: return "L"
        case 0x10: return "M"; case 0x11: return "N"; case 0x12: return "O"
        case 0x13: return "P"; case 0x14: return "Q"; case 0x15: return "R"
        case 0x16: return "S"; case 0x17: return "T"; case 0x18: return "U"
        case 0x19: return "V"; case 0x1A: return "W"; case 0x1B: return "X"
        case 0x1C: return "Y"; case 0x1D: return "Z"
        case 0x1E: return "1"; case 0x1F: return "2"; case 0x20: return "3"
        case 0x21: return "4"; case 0x22: return "5"; case 0x23: return "6"
        case 0x24: return "7"; case 0x25: return "8"; case 0x26: return "9"
        case 0x27: return "0"
        case 0x28: return "↵"; case 0x29: return "⎋"; case 0x2A: return "⌫"
        case 0x2B: return "⇥"; case 0x2C: return "␣"
        case 0x2D: return "-"; case 0x2E: return "="
        case 0x2F: return "["; case 0x30: return "]"; case 0x31: return "\\"
        case 0x33: return ";"; case 0x34: return "'"
        case 0x35: return "`"; case 0x36: return ","; case 0x37: return "."
        case 0x38: return "/"
        case 0x39: return "⇪"
        case 0x3A: return "F1"; case 0x3B: return "F2"; case 0x3C: return "F3"
        case 0x3D: return "F4"; case 0x3E: return "F5"; case 0x3F: return "F6"
        case 0x40: return "F7"; case 0x41: return "F8"; case 0x42: return "F9"
        case 0x43: return "F10"; case 0x44: return "F11"; case 0x45: return "F12"
        case 0x4A: return "Home"; case 0x4B: return "PgUp"
        case 0x4C: return "Del"; case 0x4D: return "End"; case 0x4E: return "PgDn"
        case 0x4F: return "→"; case 0x50: return "←"; case 0x51: return "↓"; case 0x52: return "↑"
        case 0xE0: return "⌃"; case 0xE1: return "⇧"; case 0xE2: return "⌥"; case 0xE3: return "⌘"
        case 0xE4: return "⌃"; case 0xE5: return "⇧"; case 0xE6: return "⌥"; case 0xE7: return "⌘"
        default: return String(format: "0x%02X", code)
        }
    }
}
