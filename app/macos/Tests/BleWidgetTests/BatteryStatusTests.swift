// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import XCTest
@testable import BleWidgetCore

final class BatteryStatusTests: XCTestCase {

    // MARK: - overall (integer board) — happy path

    func testOverall_NormalPercent() {
        let s = BatteryStatus.parse(from: Data([72]), isSplit: false)
        XCTAssertEqual(s, BatteryStatus(kind: .overall(.percent(72))))
    }

    func testOverall_ZeroPercent() {
        let s = BatteryStatus.parse(from: Data([0]), isSplit: false)
        XCTAssertEqual(s, BatteryStatus(kind: .overall(.percent(0))))
    }

    func testOverall_HundredPercent() {
        let s = BatteryStatus.parse(from: Data([100]), isSplit: false)
        XCTAssertEqual(s, BatteryStatus(kind: .overall(.percent(100))))
    }

    // MARK: - overall — sentinel + reserved

    func testOverall_Sentinel255_Unavailable() {
        let s = BatteryStatus.parse(from: Data([255]), isSplit: false)
        guard case .overall(let reading) = s?.kind else {
            return XCTFail("expected .overall")
        }
        if case .unavailable(let raw, let outOfRange) = reading {
            XCTAssertEqual(raw, 255)
            XCTAssertFalse(outOfRange, "255 is a legitimate sentinel — not out-of-range")
        } else {
            XCTFail("255 should decode to .unavailable")
        }
    }

    func testOverall_ReservedValues_UnavailableAndOutOfRange() {
        for byte in UInt8(101)...UInt8(254) {
            let s = BatteryStatus.parse(from: Data([byte]), isSplit: false)
            guard case .overall(let reading) = s?.kind,
                  case .unavailable(let raw, let outOfRange) = reading else {
                return XCTFail("reserved byte \(byte) must decode to .unavailable")
            }
            XCTAssertEqual(raw, byte)
            XCTAssertTrue(outOfRange,
                "reserved byte \(byte) should carry outOfRange=true")
        }
    }

    // MARK: - IV-BS1: overall length mismatch → nil

    func testOverall_LengthMismatch_ZeroBytes() {
        XCTAssertNil(BatteryStatus.parse(from: Data(), isSplit: false))
    }

    func testOverall_LengthMismatch_TwoBytes() {
        XCTAssertNil(BatteryStatus.parse(from: Data([50, 50]), isSplit: false))
    }

    func testOverall_LengthMismatch_ThreeBytes() {
        XCTAssertNil(BatteryStatus.parse(from: Data([1, 2, 3]), isSplit: false))
    }

    // MARK: - split (two bytes) — happy path

    func testSplit_BothPresent() {
        let s = BatteryStatus.parse(from: Data([80, 65]), isSplit: true)
        XCTAssertEqual(s, BatteryStatus(kind: .split(
            left: .percent(80),
            right: .percent(65)
        )))
    }

    func testSplit_OneSentinelPlusNormal() {
        let s = BatteryStatus.parse(from: Data([255, 72]), isSplit: true)
        guard case .split(let left, let right) = s?.kind else {
            return XCTFail("expected .split")
        }
        if case .unavailable(let raw, let outOfRange) = left {
            XCTAssertEqual(raw, 255)
            XCTAssertFalse(outOfRange)
        } else {
            XCTFail("left should be .unavailable (sentinel)")
        }
        XCTAssertEqual(right, .percent(72))
    }

    func testSplit_BothSentinel() {
        let s = BatteryStatus.parse(from: Data([255, 255]), isSplit: true)
        guard case .split(let left, let right) = s?.kind else {
            return XCTFail("expected .split")
        }
        if case .unavailable(_, let outOfRange) = left {
            XCTAssertFalse(outOfRange)
        } else { XCTFail("left should be .unavailable (sentinel)") }
        if case .unavailable(_, let outOfRange) = right {
            XCTAssertFalse(outOfRange)
        } else { XCTFail("right should be .unavailable (sentinel)") }
    }

    func testSplit_ReservedPlusSentinel() {
        // left=150 (reserved, out_of_range), right=255 (sentinel)
        let s = BatteryStatus.parse(from: Data([150, 255]), isSplit: true)
        guard case .split(let left, let right) = s?.kind else {
            return XCTFail("expected .split")
        }
        if case .unavailable(let raw, let outOfRange) = left {
            XCTAssertEqual(raw, 150)
            XCTAssertTrue(outOfRange)
        } else { XCTFail("left (150) should be .unavailable + outOfRange") }
        if case .unavailable(let raw, let outOfRange) = right {
            XCTAssertEqual(raw, 255)
            XCTAssertFalse(outOfRange)
        } else { XCTFail("right (255) should be .unavailable (sentinel)") }
    }

    // MARK: - IV-BS2: split length mismatch → nil

    func testSplit_LengthMismatch_ZeroBytes() {
        XCTAssertNil(BatteryStatus.parse(from: Data(), isSplit: true))
    }

    func testSplit_LengthMismatch_OneByte() {
        XCTAssertNil(BatteryStatus.parse(from: Data([50]), isSplit: true))
    }

    func testSplit_LengthMismatch_ThreeBytes() {
        XCTAssertNil(BatteryStatus.parse(from: Data([1, 2, 3]), isSplit: true))
    }

    // MARK: - BatteryReading percentValue helper

    func testBatteryReading_PercentValue_Available() {
        XCTAssertEqual(BatteryStatus.BatteryReading.percent(72).percentValue, 72)
        XCTAssertEqual(BatteryStatus.BatteryReading.percent(0).percentValue, 0)
        XCTAssertEqual(BatteryStatus.BatteryReading.percent(100).percentValue, 100)
    }

    func testBatteryReading_PercentValue_Unavailable() {
        XCTAssertNil(
            BatteryStatus.BatteryReading.unavailable(rawByte: 255, outOfRange: false).percentValue
        )
        XCTAssertNil(
            BatteryStatus.BatteryReading.unavailable(rawByte: 150, outOfRange: true).percentValue
        )
    }

    // MARK: - BatteryReading rawByte round-trip

    func testBatteryReading_RawByteRoundTrip() {
        for byte in UInt8(0)...UInt8(255) {
            let reading = BatteryStatus.BatteryReading(fromByte: byte)
            XCTAssertEqual(reading.rawByte, byte,
                "rawByte round-trip failed for byte \(byte)")
        }
    }
}
