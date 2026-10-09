// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import Foundation

/// Parsed form of a single KBP 1.1 Connectivity characteristic payload.
///
/// Wire contract: `protocol/README.md` §14.3 and
/// `specs/001-connectivity-power/contracts/protocol-kbp11.md` §3.
///
/// `parse(from:)` returns `nil` when the payload is shorter than 7 bytes
/// (invariant C-C1); payloads longer than 7 bytes are consumed up to byte 6
/// and the tail is ignored (invariant C-C2 for MINOR forward-compatibility).
public struct ConnectivityStatus: Equatable {

    /// `host_state` (byte 1): connected flag + last-disconnect reason.
    public struct Link: Equatable {
        public enum DisconnectReason: UInt8, Equatable {
            case unknown  = 0
            case explicit = 1
            case timeout  = 2
            case reserved = 3
        }

        public let connected: Bool
        public let lastDisconnectReason: DisconnectReason
        /// Bits 3–7 of `host_state` byte; 1.1 firmware MUST emit 0. Preserved
        /// here only for diagnostics / forward-compat.
        public let reservedBits3To7: UInt8

        public init(connected: Bool, lastDisconnectReason: DisconnectReason, reservedBits3To7: UInt8 = 0) {
            self.connected = connected
            self.lastDisconnectReason = lastDisconnectReason
            self.reservedBits3To7 = reservedBits3To7
        }

        public init(fromByte byte: UInt8) {
            self.connected = (byte & 0x01) != 0
            let reasonBits = (byte >> 1) & 0x03
            self.lastDisconnectReason = DisconnectReason(rawValue: reasonBits) ?? .unknown
            self.reservedBits3To7 = (byte >> 3) & 0x1F
        }
    }

    /// `profile_index` + `profile_max_slots` (bytes 2–3).
    public struct Profile: Equatable {
        /// 1-based index extracted from bits 0–6 of byte 2. `0` means "field
        /// not applicable" (expected when `hasProfile = false`).
        public let index: UInt8
        /// Bit 7 of byte 2.
        public let isOpen: Bool
        public let maxSlots: UInt8

        public init(index: UInt8, isOpen: Bool, maxSlots: UInt8) {
            self.index = index
            self.isOpen = isOpen
            self.maxSlots = maxSlots
        }

        public init(fromBytes b2: UInt8, _ b3: UInt8) {
            self.index    = b2 & 0x7F
            self.isOpen   = (b2 & 0x80) != 0
            self.maxSlots = b3
        }
    }

    /// `split_link_flags` byte (byte 4).
    public struct SplitLinkFlags: Equatable {
        public let leftOnline: Bool
        public let rightOnline: Bool
        public let reservedBits2To7: UInt8

        public init(leftOnline: Bool, rightOnline: Bool, reservedBits2To7: UInt8 = 0) {
            self.leftOnline = leftOnline
            self.rightOnline = rightOnline
            self.reservedBits2To7 = reservedBits2To7
        }

        public init(fromByte byte: UInt8) {
            self.leftOnline        = (byte & 0x01) != 0
            self.rightOnline       = (byte & 0x02) != 0
            self.reservedBits2To7  = (byte >> 2) & 0x3F
        }
    }

    /// `output_endpoint` byte (byte 5).
    public enum OutputEndpoint: Equatable {
        case unknown
        case usb
        case ble
        case reserved(UInt8)

        public init(fromByte byte: UInt8) {
            switch byte {
            case 0: self = .unknown
            case 1: self = .usb
            case 2: self = .ble
            default: self = .reserved(byte)
            }
        }

        public var rawByte: UInt8 {
            switch self {
            case .unknown: return 0
            case .usb: return 1
            case .ble: return 2
            case .reserved(let b): return b
            }
        }
    }

    /// `charging_flags` byte (byte 6).
    public struct ChargingFlags: Equatable {
        public let leftCharging: Bool
        public let rightCharging: Bool
        public let reservedBits2To7: UInt8

        public init(leftCharging: Bool, rightCharging: Bool, reservedBits2To7: UInt8 = 0) {
            self.leftCharging = leftCharging
            self.rightCharging = rightCharging
            self.reservedBits2To7 = reservedBits2To7
        }

        public init(fromByte byte: UInt8) {
            self.leftCharging        = (byte & 0x01) != 0
            self.rightCharging       = (byte & 0x02) != 0
            self.reservedBits2To7    = (byte >> 2) & 0x3F
        }
    }

    public let capability: CapabilityMatrix
    public let link: Link
    public let profile: Profile
    public let splitFlags: SplitLinkFlags
    public let output: OutputEndpoint
    public let chargingFlags: ChargingFlags
    /// How many bytes beyond offset 6 were present in the raw payload and
    /// discarded (invariant C-C2). Useful for diagnostics.
    public let trailingBytesIgnored: Int

    public init(
        capability: CapabilityMatrix,
        link: Link,
        profile: Profile,
        splitFlags: SplitLinkFlags,
        output: OutputEndpoint,
        chargingFlags: ChargingFlags,
        trailingBytesIgnored: Int = 0
    ) {
        self.capability = capability
        self.link = link
        self.profile = profile
        self.splitFlags = splitFlags
        self.output = output
        self.chargingFlags = chargingFlags
        self.trailingBytesIgnored = trailingBytesIgnored
    }

    /// Decode a Connectivity payload. Returns `nil` when `data.count < 7`.
    public static func parse(from data: Data) -> ConnectivityStatus? {
        guard data.count >= 7 else { return nil }
        let bytes = [UInt8](data.prefix(7))
        return ConnectivityStatus(
            capability: CapabilityMatrix(fromByte: bytes[0]),
            link: Link(fromByte: bytes[1]),
            profile: Profile(fromBytes: bytes[2], bytes[3]),
            splitFlags: SplitLinkFlags(fromByte: bytes[4]),
            output: OutputEndpoint(fromByte: bytes[5]),
            chargingFlags: ChargingFlags(fromByte: bytes[6]),
            trailingBytesIgnored: data.count - 7
        )
    }
}
