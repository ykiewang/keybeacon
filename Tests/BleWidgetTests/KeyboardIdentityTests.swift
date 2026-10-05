// Copyright (c) 2026 The TOTEM ZMK Contributors
// SPDX-License-Identifier: MIT

import XCTest
import CoreBluetooth
@testable import BleWidgetCore

final class KeyboardIdentityTests: XCTestCase {

    // MARK: - Identity by service (US1 / FR-001, FR-003)

    func testCompatibleWhenCustomServicePresent() {
        let uuids = [CBUUID(string: "1812"), CompatibleKeyboard.serviceUUID]
        XCTAssertTrue(CompatibleKeyboard.isCompatible(discoveredServiceUUIDs: uuids))
    }

    func testIncompatibleWhenOnlyHIDServicePresent() {
        let uuids = [CBUUID(string: "1812")]
        XCTAssertFalse(CompatibleKeyboard.isCompatible(discoveredServiceUUIDs: uuids))
    }

    func testIncompatibleWhenNoServices() {
        XCTAssertFalse(CompatibleKeyboard.isCompatible(discoveredServiceUUIDs: []))
    }

    // MARK: - Self-reported name & fallback (US2 / FR-006)

    func testDisplayNameUsesNameWhenPresent() {
        let kb = CompatibleKeyboard(
            identifier: UUID(), name: "Corne", state: .connected, isCompatible: true
        )
        XCTAssertEqual(kb.displayName, "Corne")
    }

    func testDisplayNameFallsBackWhenNil() {
        let id = UUID(uuidString: "AABBCCDD-0000-0000-0000-000000000000")!
        let kb = CompatibleKeyboard(
            identifier: id, name: nil, state: .connected, isCompatible: true
        )
        XCTAssertEqual(kb.displayName, "Keyboard AABBCCDD")
    }

    func testDisplayNameFallsBackWhenBlank() {
        let id = UUID(uuidString: "AABBCCDD-0000-0000-0000-000000000000")!
        let kb = CompatibleKeyboard(
            identifier: id, name: "   ", state: .connected, isCompatible: true
        )
        XCTAssertEqual(kb.displayName, "Keyboard AABBCCDD")
    }

    func testDisplayNameNeverBlank() {
        let kb = CompatibleKeyboard(
            identifier: UUID(), name: "", state: .connected, isCompatible: true
        )
        XCTAssertFalse(
            kb.displayName.trimmingCharacters(in: .whitespaces).isEmpty
        )
    }

    // MARK: - Selection resolver (US4 / FR-013, FR-014, FR-015)

    func testSelectsSoleCandidate() {
        let a = UUID()
        XCTAssertEqual(
            CompatibleKeyboard.resolveSelection(candidates: [a], remembered: nil), a
        )
    }

    func testSelectsRememberedAmongCandidates() {
        let a = UUID()
        let b = UUID()
        XCTAssertEqual(
            CompatibleKeyboard.resolveSelection(candidates: [a, b], remembered: b), b
        )
    }

    func testNoAutoSelectWhenMultipleAndNoneRemembered() {
        let a = UUID()
        let b = UUID()
        XCTAssertNil(
            CompatibleKeyboard.resolveSelection(candidates: [a, b], remembered: nil)
        )
    }

    func testNoAutoSelectWhenRememberedAbsentAndMultiple() {
        let a = UUID()
        let b = UUID()
        XCTAssertNil(
            CompatibleKeyboard.resolveSelection(candidates: [a, b], remembered: UUID())
        )
    }

    func testNoCandidatesReturnsNil() {
        XCTAssertNil(
            CompatibleKeyboard.resolveSelection(candidates: [], remembered: UUID())
        )
    }
}
