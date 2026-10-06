// Copyright (c) 2026 The TOTEM ZMK Contributors
// SPDX-License-Identifier: MIT

import XCTest
@testable import BleWidgetCore

final class KeyboardStatusTests: XCTestCase {

    // MARK: - Parsing

    func testParsesNormalPacket() {
        // [idx=1][mods=0x02][ "NAVI" ]
        let data = Data([1, 0x02]) + Data("NAVI".utf8)
        let status = KeyboardStatus.parse(data)
        XCTAssertEqual(status?.layerIndex, 1)
        XCTAssertEqual(status?.layerName, "NAVI")
        XCTAssertEqual(status?.mods, 0x02)
        XCTAssertEqual(status?.connected, true)
    }

    func testEmptyLayerNameFallsBackToIndex() {
        let data = Data([3, 0x00])
        let status = KeyboardStatus.parse(data)
        XCTAssertEqual(status?.layerName, "L3")
    }

    func testUndersizedPacketRejected() {
        XCTAssertNil(KeyboardStatus.parse(Data([1])))
        XCTAssertNil(KeyboardStatus.parse(Data()))
    }

    func testInvalidUTF8FallsBackToIndex() {
        let data = Data([2, 0x00, 0xFF, 0xFE])
        let status = KeyboardStatus.parse(data)
        XCTAssertEqual(status?.layerName, "L2")
    }

    // MARK: - Modifier merge

    func testEachModifierBit() {
        XCTAssertTrue(KeyboardStatus.parse(Data([0, 0x02]))!.shiftActive)
        XCTAssertTrue(KeyboardStatus.parse(Data([0, 0x01]))!.controlActive)
        XCTAssertTrue(KeyboardStatus.parse(Data([0, 0x04]))!.optionActive)
        XCTAssertTrue(KeyboardStatus.parse(Data([0, 0x08]))!.commandActive)
    }

    func testMergedHalves() {
        XCTAssertTrue(KeyboardStatus.parse(Data([0, 0x20]))!.shiftActive)
        XCTAssertTrue(KeyboardStatus.parse(Data([0, 0x10]))!.controlActive)
        XCTAssertTrue(KeyboardStatus.parse(Data([0, 0x40]))!.optionActive)
        XCTAssertTrue(KeyboardStatus.parse(Data([0, 0x80]))!.commandActive)
    }

    func testNoModifiers() {
        let status = KeyboardStatus.parse(Data([0, 0x00]))!
        XCTAssertFalse(status.shiftActive)
        XCTAssertFalse(status.controlActive)
        XCTAssertFalse(status.optionActive)
        XCTAssertFalse(status.commandActive)
    }
}
