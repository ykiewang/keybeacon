// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import XCTest
@testable import BleWidgetCore

/// US1 (spec 005) pure-function tests: `LinkSlot.parse` (T010) and
/// `deriveLocalHostStatus` five-state derivation (T011). No BLE I/O — exhaustive
/// wire→state mapping per FR-014.
final class HostLinkProfileAwarenessTests: XCTestCase {

    // MARK: - T010: LinkSlot.parse

    func testLinkSlot_notDetermined_zero() {
        let s = LinkSlot.parse(from: Data([0x00]))
        XCTAssertEqual(s, LinkSlot(slot: 0, reservedBit7: false, trailingBytesIgnored: 0))
        XCTAssertFalse(s!.isDetermined)
    }

    func testLinkSlot_oneBasedSlot() {
        let s = LinkSlot.parse(from: Data([0x01]))!
        XCTAssertEqual(s.slot, 1)
        XCTAssertTrue(s.isDetermined)
        XCTAssertFalse(s.reservedBit7)
    }

    func testLinkSlot_exhaustive_0_to_127() {
        for raw in UInt8(0)...UInt8(127) {
            let s = LinkSlot.parse(from: Data([raw]))!
            XCTAssertEqual(s.slot, raw, "slot for 0x\(String(raw, radix: 16))")
            XCTAssertFalse(s.reservedBit7)
            XCTAssertEqual(s.isDetermined, raw >= 1)
        }
    }

    func testLinkSlot_bit7_ignoredForSlotValue() {
        for slot in UInt8(0)...UInt8(127) {
            let raw = slot | 0x80
            let s = LinkSlot.parse(from: Data([raw]))!
            XCTAssertEqual(s.slot, slot, "bit7 must not bleed into slot (raw 0x\(String(raw, radix: 16)))")
            XCTAssertTrue(s.reservedBit7)
        }
    }

    func testLinkSlot_emptyPayload_returnsNil() {
        XCTAssertNil(LinkSlot.parse(from: Data()))
    }

    func testLinkSlot_trailingBytesIgnored() {
        let s = LinkSlot.parse(from: Data([0x02, 0xAA, 0xBB, 0xCC]))!
        XCTAssertEqual(s.slot, 2)
        XCTAssertEqual(s.trailingBytesIgnored, 3)
    }

    func testLinkSlot_isWithinRange() {
        XCTAssertTrue(LinkSlot(slot: 3).isWithinRange(maxSlots: 5))
        XCTAssertTrue(LinkSlot(slot: 5).isWithinRange(maxSlots: 5))
        XCTAssertFalse(LinkSlot(slot: 6).isWithinRange(maxSlots: 5))
        XCTAssertFalse(LinkSlot(slot: 0).isWithinRange(maxSlots: 5))
        // maxSlots unknown (0) only requires slot >= 1.
        XCTAssertTrue(LinkSlot(slot: 9).isWithinRange(maxSlots: 0))
        XCTAssertFalse(LinkSlot(slot: 0).isWithinRange(maxSlots: 0))
    }

    // MARK: - T011: deriveLocalHostStatus helpers

    private func cap(hasProfile: Bool = true, hasOutputEndpoint: Bool = false) -> CapabilityMatrix {
        CapabilityMatrix(
            isSplit: false,
            hasHostConnection: true,
            hasProfile: hasProfile,
            hasSplitLink: false,
            hasOutputEndpoint: hasOutputEndpoint,
            hasLeftCharging: false,
            hasRightCharging: false
        )
    }

    private func profile(index: UInt8, isOpen: Bool = false, maxSlots: UInt8 = 5) -> ConnectivityStatus.Profile {
        ConnectivityStatus.Profile(index: index, isOpen: isOpen, maxSlots: maxSlots)
    }

    // MARK: - T011: disconnected (highest priority)

    func testDerive_disconnected_whenNotConnected_regardlessOfOtherInputs() {
        // Even with a fully-resolvable in-use setup, connected=false wins.
        let status = deriveLocalHostStatus(
            hasAA4: true,
            connected: false,
            capability: cap(hasOutputEndpoint: true),
            activeProfile: profile(index: 2),
            localSlot: LinkSlot(slot: 2),
            output: .usb
        )
        XCTAssertEqual(status, .disconnected)
    }

    // MARK: - T011: onUsb (before in-use over BLE)

    func testDerive_onUsb_whenOutputUsbAndCapable() {
        let status = deriveLocalHostStatus(
            hasAA4: true,
            connected: true,
            capability: cap(hasOutputEndpoint: true),
            activeProfile: profile(index: 2),
            localSlot: LinkSlot(slot: 2),
            output: .usb
        )
        XCTAssertEqual(status, .onUsb)
    }

    func testDerive_onUsb_takesPrecedenceOverInUseHere() {
        // active == local would be inUseHere, but USB output wins.
        let status = deriveLocalHostStatus(
            hasAA4: true,
            connected: true,
            capability: cap(hasOutputEndpoint: true),
            activeProfile: profile(index: 3),
            localSlot: LinkSlot(slot: 3),
            output: .usb
        )
        XCTAssertEqual(status, .onUsb)
    }

    func testDerive_notOnUsb_whenOutputUsbButCapabilityOff() {
        // hasOutputEndpoint = false → USB byte is not trusted → fall through.
        let status = deriveLocalHostStatus(
            hasAA4: true,
            connected: true,
            capability: cap(hasOutputEndpoint: false),
            activeProfile: profile(index: 2),
            localSlot: LinkSlot(slot: 2),
            output: .usb
        )
        XCTAssertEqual(status, .inUseHere)
    }

    // MARK: - T011: cannotDetermine

    func testDerive_cannotDetermine_whenNoAA4() {
        let status = deriveLocalHostStatus(
            hasAA4: false,
            connected: true,
            capability: cap(),
            activeProfile: profile(index: 2),
            localSlot: LinkSlot(slot: 2),
            output: .ble
        )
        XCTAssertEqual(status, .cannotDetermine)
    }

    func testDerive_cannotDetermine_whenNoProfileCapability() {
        let status = deriveLocalHostStatus(
            hasAA4: true,
            connected: true,
            capability: cap(hasProfile: false),
            activeProfile: profile(index: 2),
            localSlot: LinkSlot(slot: 2),
            output: .ble
        )
        XCTAssertEqual(status, .cannotDetermine)
    }

    func testDerive_cannotDetermine_whenActiveIndexZero() {
        let status = deriveLocalHostStatus(
            hasAA4: true,
            connected: true,
            capability: cap(),
            activeProfile: profile(index: 0),
            localSlot: LinkSlot(slot: 2),
            output: .ble
        )
        XCTAssertEqual(status, .cannotDetermine)
    }

    func testDerive_cannotDetermine_whenProfileOpen() {
        let status = deriveLocalHostStatus(
            hasAA4: true,
            connected: true,
            capability: cap(),
            activeProfile: profile(index: 2, isOpen: true),
            localSlot: LinkSlot(slot: 2),
            output: .ble
        )
        XCTAssertEqual(status, .cannotDetermine)
    }

    func testDerive_cannotDetermine_whenLocalSlotNil() {
        let status = deriveLocalHostStatus(
            hasAA4: true,
            connected: true,
            capability: cap(),
            activeProfile: profile(index: 2),
            localSlot: nil,
            output: .ble
        )
        XCTAssertEqual(status, .cannotDetermine)
    }

    func testDerive_cannotDetermine_whenLocalSlotZero() {
        let status = deriveLocalHostStatus(
            hasAA4: true,
            connected: true,
            capability: cap(),
            activeProfile: profile(index: 2),
            localSlot: LinkSlot(slot: 0),
            output: .ble
        )
        XCTAssertEqual(status, .cannotDetermine)
    }

    func testDerive_cannotDetermine_whenCapabilityNil() {
        let status = deriveLocalHostStatus(
            hasAA4: true,
            connected: true,
            capability: nil,
            activeProfile: profile(index: 2),
            localSlot: LinkSlot(slot: 2),
            output: .ble
        )
        XCTAssertEqual(status, .cannotDetermine)
    }

    // MARK: - T011: inUseHere / activeElsewhere

    func testDerive_inUseHere_whenActiveEqualsLocal() {
        let status = deriveLocalHostStatus(
            hasAA4: true,
            connected: true,
            capability: cap(),
            activeProfile: profile(index: 3),
            localSlot: LinkSlot(slot: 3),
            output: .ble
        )
        XCTAssertEqual(status, .inUseHere)
    }

    func testDerive_activeElsewhere_whenActiveDiffersFromLocal() {
        let status = deriveLocalHostStatus(
            hasAA4: true,
            connected: true,
            capability: cap(),
            activeProfile: profile(index: 1),
            localSlot: LinkSlot(slot: 2),
            output: .ble
        )
        XCTAssertEqual(status, .activeElsewhere(slot: 1))
    }

    // MARK: - T011: exhaustive active × local matrix (the in-use/elsewhere core)

    func testDerive_exhaustive_activeVsLocal_matrix() {
        let maxSlots: UInt8 = 4
        for active in UInt8(1)...maxSlots {
            for local in UInt8(1)...maxSlots {
                let status = deriveLocalHostStatus(
                    hasAA4: true,
                    connected: true,
                    capability: cap(),
                    activeProfile: profile(index: active, maxSlots: maxSlots),
                    localSlot: LinkSlot(slot: local),
                    output: .ble
                )
                if active == local {
                    XCTAssertEqual(status, .inUseHere, "active=\(active) local=\(local)")
                } else {
                    XCTAssertEqual(status, .activeElsewhere(slot: active), "active=\(active) local=\(local)")
                }
            }
        }
    }
}
