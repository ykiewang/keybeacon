// Copyright (c) 2026 The TOTEM ZMK Contributors
// SPDX-License-Identifier: MIT

import XCTest
import CoreBluetooth
@testable import BleWidgetCore

final class CompatibilityTests: XCTestCase {

    // KBP 1.x service (the one this app supports) + common keyboard services.
    private let supported = CBUUID(string: "AA440AA0-F5ED-4C48-84A1-8062D20D3D55")
    private let hid = CBUUID(string: "1812")
    private let battery = CBUUID(string: "180F")

    // A hypothetical future MAJOR revision: same KeyBeacon UUID base, different
    // leading segment (per protocol §9, a MAJOR bump means a new service UUID).
    private let futureMajor = CBUUID(string: "AA440AB0-F5ED-4C48-84A1-8062D20D3D55")

    // MARK: - classify (US4 / FR-013, FR-014, SC-007)

    func testKnownServiceIsSupported() {
        XCTAssertEqual(
            KBPCompatibility.classify(discoveredServices: [hid, supported]),
            .supported
        )
    }

    func testUnknownKeyBeaconFamilyIsUnsupportedVersion() {
        XCTAssertEqual(
            KBPCompatibility.classify(discoveredServices: [hid, futureMajor]),
            .unsupportedVersion
        )
    }

    func testNonKeyBeaconDeviceIsNotAKeyboard() {
        XCTAssertEqual(
            KBPCompatibility.classify(discoveredServices: [hid, battery]),
            .notAKeyboard
        )
    }

    func testNoServicesIsNotAKeyboard() {
        XCTAssertEqual(
            KBPCompatibility.classify(discoveredServices: []),
            .notAKeyboard
        )
    }

    func testSupportedWinsWhenBothSupportedAndFamilyPresent() {
        XCTAssertEqual(
            KBPCompatibility.classify(discoveredServices: [futureMajor, supported]),
            .supported
        )
    }

    func testSupportedSetContainsKBP1() {
        XCTAssertTrue(KBPCompatibility.supportedServiceUUIDs.contains(supported))
    }

    func testFamilyDetection() {
        XCTAssertTrue(KBPCompatibility.isKeyBeaconFamily(supported))
        XCTAssertTrue(KBPCompatibility.isKeyBeaconFamily(futureMajor))
        XCTAssertFalse(KBPCompatibility.isKeyBeaconFamily(hid))
    }
}
