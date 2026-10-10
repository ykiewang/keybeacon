// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import Foundation

/// Parsed form of a single KBP 1.1 Battery characteristic payload.
///
/// Wire contract: `protocol/README.md` §14.4 and
/// `specs/001-connectivity-power/contracts/protocol-kbp11.md` §4.
///
/// Length rules (invariants C-B1 / C-B2):
///   - `isSplit == false` ⇒ payload MUST be 1 byte (overall).
///   - `isSplit == true`  ⇒ payload MUST be 2 bytes `[left, right]`.
public struct BatteryStatus: Equatable {

    /// A single battery byte decoded per the uint8-encoding table (§14.4.2):
    ///   - `0...100` → `.percent(n)`
    ///   - `255`     → `.unavailable` (sentinel: read failed / temporarily unavailable)
    ///   - `101...254` → `.unavailable` with `outOfRange == true` (reserved, treat as unavailable)
    public enum BatteryReading: Equatable {
        case percent(UInt8)
        case unavailable(rawByte: UInt8, outOfRange: Bool)

        /// Decode a single byte of battery percent per §14.4.2.
        public init(fromByte byte: UInt8) {
            if byte <= 100 {
                self = .percent(byte)
            } else if byte == 255 {
                self = .unavailable(rawByte: byte, outOfRange: false)
            } else {
                // 101..254: reserved values. Treat as unavailable + flag so the
                // caller can emit a `battery.out_of_range` diagnostic (C-B3).
                self = .unavailable(rawByte: byte, outOfRange: true)
            }
        }

        public var rawByte: UInt8 {
            switch self {
            case .percent(let n): return n
            case .unavailable(let raw, _): return raw
            }
        }

        /// Convenience: Int percentage when available, nil otherwise.
        public var percentValue: Int? {
            switch self {
            case .percent(let n): return Int(n)
            case .unavailable: return nil
            }
        }
    }

    /// Shape of the parsed Battery payload — overall for integer boards, or
    /// left + right for splits (determined by `CapabilityMatrix.isSplit`).
    public enum Kind: Equatable {
        case overall(BatteryReading)
        case split(left: BatteryReading, right: BatteryReading)
    }

    public let kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }

    /// Decode a Battery payload. The caller MUST pass the Connectivity-advertised
    /// `isSplit` so this parser can validate the length (C-B1 / C-B2).
    ///
    /// Returns `nil` on length mismatch; the caller SHOULD emit a
    /// `battery.length_mismatch` diagnostic.
    public static func parse(from data: Data, isSplit: Bool) -> BatteryStatus? {
        if isSplit {
            guard data.count == 2 else { return nil }
            let bytes = [UInt8](data)
            return BatteryStatus(kind: .split(
                left:  BatteryReading(fromByte: bytes[0]),
                right: BatteryReading(fromByte: bytes[1])
            ))
        } else {
            guard data.count == 1 else { return nil }
            return BatteryStatus(kind: .overall(BatteryReading(fromByte: data[data.startIndex])))
        }
    }
}
