// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import XCTest
@testable import BleWidgetCore

final class CapabilityMatrixTests: XCTestCase {

    // MARK: - All-zero and all-one bytes

    func testAllZeroByte_AllFlagsFalse() {
        let m = CapabilityMatrix(fromByte: 0x00)
        XCTAssertFalse(m.isSplit)
        XCTAssertFalse(m.hasHostConnection)
        XCTAssertFalse(m.hasProfile)
        XCTAssertFalse(m.hasSplitLink)
        XCTAssertFalse(m.hasOutputEndpoint)
        XCTAssertFalse(m.hasLeftCharging)
        XCTAssertFalse(m.hasRightCharging)
        XCTAssertFalse(m.reserved7)
        XCTAssertEqual(m.rawByte, 0x00)
    }

    func testAllOneByte_AllFlagsTrueIncludingReserved() {
        let m = CapabilityMatrix(fromByte: 0xFF)
        XCTAssertTrue(m.isSplit)
        XCTAssertTrue(m.hasHostConnection)
        XCTAssertTrue(m.hasProfile)
        XCTAssertTrue(m.hasSplitLink)
        XCTAssertTrue(m.hasOutputEndpoint)
        XCTAssertTrue(m.hasLeftCharging)
        XCTAssertTrue(m.hasRightCharging)
        XCTAssertTrue(m.reserved7)
        XCTAssertEqual(m.rawByte, 0xFF)
    }

    // MARK: - 2^7 = 128 round-trip for bits 0..6

    /// Enumerate every combination of bits 0–6 and check the raw-byte round trip.
    /// (bit 7 — `reserved7` — is covered separately by `testReserved7Tolerated`.)
    func testBits0To6_AllCombinationsRoundTrip() {
        for raw in UInt8(0)...UInt8(0x7F) {
            let m = CapabilityMatrix(fromByte: raw)
            XCTAssertEqual(m.rawByte, raw,
                "round-trip mismatch for raw byte \(String(raw, radix: 2))")
        }
    }

    // MARK: - IV-C1: hasSplitLink requires isSplit

    func testIVC1_HasSplitLinkRequiresIsSplit_Violation() {
        let m = CapabilityMatrix(fromByte: 0x08) // hasSplitLink only
        XCTAssertFalse(m.isSplit)
        XCTAssertTrue(m.hasSplitLink)
        XCTAssertFalse(m.isConsistent, "IV-C1 violation must flip isConsistent to false")
    }

    func testIVC1_HasSplitLinkWithIsSplit_Consistent() {
        let m = CapabilityMatrix(fromByte: 0x09) // isSplit + hasSplitLink
        XCTAssertTrue(m.isConsistent)
    }

    // MARK: - IV-C2: reserved bit 7 is tolerated

    func testReserved7Tolerated_DoesNotFlipConsistency() {
        // reserved7 alone — isConsistent should still be true
        let only7 = CapabilityMatrix(fromByte: 0x80)
        XCTAssertTrue(only7.reserved7)
        XCTAssertTrue(only7.isConsistent)

        // reserved7 combined with every other bit set — still consistent
        // (0xFF: isSplit=1 ∧ hasLeftCharging=1 ∧ hasRightCharging=1 ∧ ... satisfies IV-C3)
        let all = CapabilityMatrix(fromByte: 0xFF)
        XCTAssertTrue(all.reserved7)
        XCTAssertTrue(all.isConsistent)
    }

    // MARK: - IV-C3: hasRightCharging ⇒ (isSplit ∧ hasLeftCharging)

    func testIVC3_HasRightChargingWithoutIsSplit_Violation() {
        // bit 6 only
        let m = CapabilityMatrix(fromByte: 0x40)
        XCTAssertFalse(m.isSplit)
        XCTAssertFalse(m.hasLeftCharging)
        XCTAssertTrue(m.hasRightCharging)
        XCTAssertFalse(m.isConsistent)
    }

    func testIVC3_HasRightChargingWithoutHasLeftCharging_Violation() {
        // bit 0 (isSplit) + bit 6 (hasRightCharging) but NO bit 5 (hasLeftCharging)
        let m = CapabilityMatrix(fromByte: 0x41)
        XCTAssertTrue(m.isSplit)
        XCTAssertFalse(m.hasLeftCharging)
        XCTAssertTrue(m.hasRightCharging)
        XCTAssertFalse(m.isConsistent)
    }

    func testIVC3_SplitWithLeftAndRightCharging_Consistent() {
        // bits 0, 5, 6
        let m = CapabilityMatrix(fromByte: 0x61)
        XCTAssertTrue(m.isSplit)
        XCTAssertTrue(m.hasLeftCharging)
        XCTAssertTrue(m.hasRightCharging)
        XCTAssertTrue(m.isConsistent)
    }

    func testIVC3_SplitWithLeftOnly_Consistent() {
        // bits 0, 5 — asymmetric charging hardware (left half only)
        let m = CapabilityMatrix(fromByte: 0x21)
        XCTAssertTrue(m.isSplit)
        XCTAssertTrue(m.hasLeftCharging)
        XCTAssertFalse(m.hasRightCharging)
        XCTAssertTrue(m.isConsistent)
    }

    func testIVC3_IntegerBoardWithLeftCharging_Consistent() {
        // bit 5 only — integer board with overall charging (hasLeftCharging = overall)
        let m = CapabilityMatrix(fromByte: 0x20)
        XCTAssertFalse(m.isSplit)
        XCTAssertTrue(m.hasLeftCharging)
        XCTAssertFalse(m.hasRightCharging)
        XCTAssertTrue(m.isConsistent)
    }

    // MARK: - memberwise init equivalence

    func testMemberwiseInit_EquivalentToByteInit() {
        let m1 = CapabilityMatrix(fromByte: 0x61)
        let m2 = CapabilityMatrix(
            isSplit: true,
            hasHostConnection: false,
            hasProfile: false,
            hasSplitLink: false,
            hasOutputEndpoint: false,
            hasLeftCharging: true,
            hasRightCharging: true,
            reserved7: false
        )
        XCTAssertEqual(m1, m2)
    }
}
