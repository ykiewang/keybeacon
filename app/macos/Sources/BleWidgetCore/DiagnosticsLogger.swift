// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import Foundation
import os

/// Structured diagnostic logger for KBP 1.1 observability (FR-018).
///
/// Backing: `os.Logger` with subsystem `com.keybeacon.app` and categories
/// `capability` / `profile` / `battery` / `staleness` / `connection`.
///
/// Every log call uses `%{public}` so key diagnostic fields are visible via
/// `log stream --predicate 'subsystem == "com.keybeacon.app"'` and the
/// Console.app filter UI; this matches `contracts/macos-ui.md` §5.
///
/// This is a static facade; call sites (`BLEClient` + future UI code) use
/// `DiagnosticsLogger.capability.discovered(byte: 0x7F, …)` etc. The real
/// `os.Logger` instances are process-wide and thread-safe.
public enum DiagnosticsLogger {

    public static let subsystem = "com.keybeacon.app"

    // MARK: - Category instances

    public static let capability = Capability()
    public static let profile = Profile()
    public static let battery = Battery()
    public static let staleness = Staleness()
    public static let connection = Connection()

    // MARK: - capability

    public struct Capability {
        fileprivate init() {}

        private let log = Logger(subsystem: DiagnosticsLogger.subsystem, category: "capability")

        /// First successful parse of a connected keyboard's CapabilityMatrix.
        public func discovered(byte: UInt8, isSplit: Bool,
                               hasHostConnection: Bool, hasProfile: Bool,
                               hasSplitLink: Bool, hasOutputEndpoint: Bool,
                               hasLeftCharging: Bool, hasRightCharging: Bool) {
            log.info("""
                capability.discovered raw=0x\(byte, format: .hex, privacy: .public) \
                is_split=\(isSplit, privacy: .public) \
                has_host_connection=\(hasHostConnection, privacy: .public) \
                has_profile=\(hasProfile, privacy: .public) \
                has_split_link=\(hasSplitLink, privacy: .public) \
                has_output_endpoint=\(hasOutputEndpoint, privacy: .public) \
                has_left_charging=\(hasLeftCharging, privacy: .public) \
                has_right_charging=\(hasRightCharging, privacy: .public)
                """)
        }

        /// Invariant violation (IV-C1 / IV-C3) → the offending bit is dropped
        /// by the caller; this entry records the violation.
        public func inconsistent(byte: UInt8, reason: String) {
            log.warning("""
                capability.inconsistent raw=0x\(byte, format: .hex, privacy: .public) \
                reason=\(reason, privacy: .public)
                """)
        }

        /// The capability byte changed between notifies (hot-reload scenario).
        public func mutated(fromByte: UInt8, toByte: UInt8) {
            log.notice("""
                capability.mutated from=0x\(fromByte, format: .hex, privacy: .public) \
                to=0x\(toByte, format: .hex, privacy: .public)
                """)
        }
    }

    // MARK: - profile

    public struct Profile {
        fileprivate init() {}
        private let log = Logger(subsystem: DiagnosticsLogger.subsystem, category: "profile")

        /// `profile_index` > `profile_max_slots` → UI clamps; this records the raw.
        public func outOfRange(rawIndex: UInt8, maxSlots: UInt8) {
            log.warning("""
                profile.out_of_range raw_index=\(rawIndex, privacy: .public) \
                max_slots=\(maxSlots, privacy: .public)
                """)
        }
    }

    // MARK: - battery

    public struct Battery {
        fileprivate init() {}
        private let log = Logger(subsystem: DiagnosticsLogger.subsystem, category: "battery")

        public func lengthMismatch(expected: Int, got: Int, isSplit: Bool) {
            log.warning("""
                battery.length_mismatch expected=\(expected, privacy: .public) \
                got=\(got, privacy: .public) \
                is_split=\(isSplit, privacy: .public)
                """)
        }

        /// Byte value in `101..254` (reserved); treat as unavailable (C-B3).
        public func outOfRange(rawByte: UInt8, side: String) {
            log.warning("""
                battery.out_of_range raw=0x\(rawByte, format: .hex, privacy: .public) \
                side=\(side, privacy: .public)
                """)
        }
    }

    // MARK: - staleness

    public struct Staleness {
        fileprivate init() {}
        private let log = Logger(subsystem: DiagnosticsLogger.subsystem, category: "staleness")

        /// Crossed from live → stale (3 s elapsed or BLE disconnect).
        public func fieldStale(fieldKey: String, reason: String) {
            log.notice("""
                staleness.field_stale field=\(fieldKey, privacy: .public) \
                reason=\(reason, privacy: .public)
                """)
        }

        /// Crossed from stale → live (fresh notify arrived).
        public func fieldLive(fieldKey: String) {
            log.notice("staleness.field_live field=\(fieldKey, privacy: .public)")
        }
    }

    // MARK: - connection

    public struct Connection {
        fileprivate init() {}
        private let log = Logger(subsystem: DiagnosticsLogger.subsystem, category: "connection")

        /// `host_state.connected` bit toggled.
        public func stateChanged(connected: Bool, reasonRaw: UInt8) {
            log.notice("""
                connection.state_changed connected=\(connected, privacy: .public) \
                reason_raw=0x\(reasonRaw, format: .hex, privacy: .public)
                """)
        }

        /// Payload length under 7 bytes (invariant C-C1).
        public func connectivityShortPayload(length: Int) {
            log.warning("connectivity.short_payload length=\(length, privacy: .public)")
        }

        /// GATT discovery saw `AA2` without `AA1` (anomalous wire).
        public func discoveryAnomaly(reason: String) {
            log.warning("discovery.anomaly reason=\(reason, privacy: .public)")
        }
    }
}
