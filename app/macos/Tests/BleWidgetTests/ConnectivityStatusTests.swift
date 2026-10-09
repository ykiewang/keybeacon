// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import XCTest
@testable import BleWidgetCore

final class ConnectivityStatusTests: XCTestCase {

    // MARK: - IV-CS1: payload shorter than 7 bytes → nil

    func testShortPayload_SixBytes_ReturnsNil() {
        let short = Data([0x7F, 0x01, 0x82, 0x05, 0x03, 0x02])
        XCTAssertNil(ConnectivityStatus.parse(from: short))
    }

    func testShortPayload_EmptyData_ReturnsNil() {
        XCTAssertNil(ConnectivityStatus.parse(from: Data()))
    }

    // MARK: - IV-CS2: payload longer than 7 bytes → parse first 7, ignore tail

    func testLongPayload_TwelveBytes_IgnoresTail() {
        let data = Data([
            0x7F, 0x01, 0x82, 0x05, 0x03, 0x02, 0x03,       // first 7 bytes
            0xAA, 0xBB, 0xCC, 0xDD, 0xEE,                   // extra 5 bytes
        ])
        guard let s = ConnectivityStatus.parse(from: data) else {
            return XCTFail("12-byte payload must parse successfully")
        }
        XCTAssertEqual(s.trailingBytesIgnored, 5)
        // First 7 bytes decoded correctly:
        XCTAssertTrue(s.capability.isSplit)
        XCTAssertTrue(s.capability.hasHostConnection)
        XCTAssertTrue(s.capability.hasProfile)
        XCTAssertTrue(s.capability.hasSplitLink)
        XCTAssertTrue(s.capability.hasOutputEndpoint)
        XCTAssertTrue(s.capability.hasLeftCharging)
        XCTAssertTrue(s.capability.hasRightCharging)
        XCTAssertFalse(s.capability.reserved7)
    }

    // MARK: - IV-K1: host_state bit combinations

    func testHostStateBitCombinations_ConnectedOnly() {
        // byte 1 = 0b00000001 → connected=1, reason=unknown (0)
        let data = Data([0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00])
        let s = ConnectivityStatus.parse(from: data)!
        XCTAssertTrue(s.link.connected)
        XCTAssertEqual(s.link.lastDisconnectReason, .unknown)
    }

    func testHostStateBitCombinations_DisconnectedExplicit() {
        // byte 1 = 0b00000010 → connected=0, reason=explicit (1)
        let data = Data([0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00])
        let s = ConnectivityStatus.parse(from: data)!
        XCTAssertFalse(s.link.connected)
        XCTAssertEqual(s.link.lastDisconnectReason, .explicit)
    }

    func testHostStateBitCombinations_DisconnectedTimeout() {
        // byte 1 = 0b00000100 → connected=0, reason=timeout (2)
        let data = Data([0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00])
        let s = ConnectivityStatus.parse(from: data)!
        XCTAssertFalse(s.link.connected)
        XCTAssertEqual(s.link.lastDisconnectReason, .timeout)
    }

    func testHostStateBitCombinations_ReservedReasonValue() {
        // byte 1 = 0b00000110 → connected=0, reason bits = 0b11 (reserved)
        let data = Data([0x00, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00])
        let s = ConnectivityStatus.parse(from: data)!
        XCTAssertFalse(s.link.connected)
        XCTAssertEqual(s.link.lastDisconnectReason, .reserved)
    }

    func testHostStateBitCombinations_ReservedBitsPreserved() {
        // byte 1 bits 3..7 all set → bits3To7 should be 0x1F (ignored by UI, kept for diagnostics)
        let data = Data([0x00, 0b11111000, 0x00, 0x00, 0x00, 0x00, 0x00])
        let s = ConnectivityStatus.parse(from: data)!
        XCTAssertEqual(s.link.reservedBits3To7, 0x1F)
    }

    // MARK: - IV-P1: profile_index > profile_max_slots (parser preserves raw)

    func testProfileIndexExceedingMaxSlots_ParserPreservesRaw() {
        // index=10, maxSlots=5 — the parser MUST decode faithfully; clamping to
        // maxSlots is BLEClient / UI responsibility (per data-model.md IV-P1).
        let data = Data([0x00, 0x00, 0x0A, 0x05, 0x00, 0x00, 0x00])
        let s = ConnectivityStatus.parse(from: data)!
        XCTAssertEqual(s.profile.index, 10)
        XCTAssertEqual(s.profile.maxSlots, 5)
        XCTAssertFalse(s.profile.isOpen)
    }

    func testProfileOpenBit() {
        // index=3 + bit 7 set → index=3, isOpen=true
        let data = Data([0x00, 0x00, 0x83, 0x05, 0x00, 0x00, 0x00])
        let s = ConnectivityStatus.parse(from: data)!
        XCTAssertEqual(s.profile.index, 3)
        XCTAssertTrue(s.profile.isOpen)
    }

    // MARK: - IV-O2: output_endpoint reserved values become `.reserved(n)`

    func testOutputEndpoint_KnownValues() {
        for (code, expected): (UInt8, ConnectivityStatus.OutputEndpoint) in [
            (0, .unknown),
            (1, .usb),
            (2, .ble),
        ] {
            let data = Data([0x00, 0x00, 0x00, 0x00, 0x00, code, 0x00])
            let s = ConnectivityStatus.parse(from: data)!
            XCTAssertEqual(s.output, expected,
                "endpoint code \(code) should map to \(expected)")
        }
    }

    func testOutputEndpoint_ReservedValuesPreserveRaw() {
        for code in UInt8(3)...UInt8(255) {
            let data = Data([0x00, 0x00, 0x00, 0x00, 0x00, code, 0x00])
            let s = ConnectivityStatus.parse(from: data)!
            if case let .reserved(byte) = s.output {
                XCTAssertEqual(byte, code,
                    "reserved endpoint code \(code) should round-trip through .reserved")
            } else {
                XCTFail("output byte \(code) must map to .reserved(\(code)), got \(s.output)")
            }
        }
    }

    // MARK: - splitFlags bit 0 / bit 1

    func testSplitFlags_IndependentBits() {
        for leftOnline in [false, true] {
            for rightOnline in [false, true] {
                var byte: UInt8 = 0
                if leftOnline  { byte |= 0x01 }
                if rightOnline { byte |= 0x02 }
                let data = Data([0x00, 0x00, 0x00, 0x00, byte, 0x00, 0x00])
                let s = ConnectivityStatus.parse(from: data)!
                XCTAssertEqual(s.splitFlags.leftOnline, leftOnline)
                XCTAssertEqual(s.splitFlags.rightOnline, rightOnline)
            }
        }
    }

    // MARK: - chargingFlags bit 0 / bit 1

    func testChargingFlags_IndependentBits() {
        for leftCharging in [false, true] {
            for rightCharging in [false, true] {
                var byte: UInt8 = 0
                if leftCharging  { byte |= 0x01 }
                if rightCharging { byte |= 0x02 }
                let data = Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, byte])
                let s = ConnectivityStatus.parse(from: data)!
                XCTAssertEqual(s.chargingFlags.leftCharging, leftCharging)
                XCTAssertEqual(s.chargingFlags.rightCharging, rightCharging)
            }
        }
    }

    // MARK: - Reserved bits in flag bytes are preserved for diagnostics

    func testSplitFlagsReservedBits_RecordedForDiagnostics() {
        // byte 4 = 0xFF → reservedBits2To7 should be 0x3F
        let data = Data([0x00, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00])
        let s = ConnectivityStatus.parse(from: data)!
        XCTAssertEqual(s.splitFlags.reservedBits2To7, 0x3F)
    }

    func testChargingFlagsReservedBits_RecordedForDiagnostics() {
        let data = Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF])
        let s = ConnectivityStatus.parse(from: data)!
        XCTAssertEqual(s.chargingFlags.reservedBits2To7, 0x3F)
    }
}
