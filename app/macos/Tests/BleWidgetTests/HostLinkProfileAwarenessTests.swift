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

    // MARK: - T028 [US2]: LinkSlotCache re-read / re-learn

    func testCache_initialLearn_setsSlotAndLearnedAt_noReadBack() {
        var cache = LinkSlotCache()
        XCTAssertNil(cache.slot)
        XCTAssertNil(cache.learnedAt)

        let t0 = Date(timeIntervalSince1970: 1_000)
        let readBack = cache.learn(LinkSlot(slot: 1), at: t0)

        // First learn is not a "read-back change" → no diagnostic.
        XCTAssertFalse(readBack)
        XCTAssertEqual(cache.slot?.slot, 1)
        XCTAssertEqual(cache.learnedAt, t0)
    }

    func testCache_reReadDifferentSlot_N_to_M_refreshesAndSignalsReadBack() {
        var cache = LinkSlotCache()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 2_000)

        _ = cache.learn(LinkSlot(slot: 2), at: t0) // N = 2 (initial)
        let readBack = cache.learn(LinkSlot(slot: 5), at: t1) // M = 5 (re-pair)

        XCTAssertTrue(readBack, "slot N→M must report a read-back change (T034)")
        XCTAssertEqual(cache.slot?.slot, 5)
        XCTAssertEqual(cache.learnedAt, t1, "learnedAt must advance on re-read")
    }

    func testCache_reReadSameSlot_refreshesLearnedAt_noReadBack() {
        var cache = LinkSlotCache()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 2_000)

        _ = cache.learn(LinkSlot(slot: 3), at: t0)
        let readBack = cache.learn(LinkSlot(slot: 3), at: t1)

        // Same slot → no read-back diagnostic, but the fallback re-read still
        // refreshes the freshness stamp.
        XCTAssertFalse(readBack)
        XCTAssertEqual(cache.slot?.slot, 3)
        XCTAssertEqual(cache.learnedAt, t1)
    }

    func testCache_unresolvedThenResolved_zeroToSlot_signalsReadBack() {
        // The real-world bug: slot=0 at connect time (peer not yet matched to a
        // bond), later resolves to a concrete slot on a fallback re-read.
        var cache = LinkSlotCache()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_060)

        _ = cache.learn(LinkSlot(slot: 0), at: t0)
        let readBack = cache.learn(LinkSlot(slot: 1), at: t1)

        XCTAssertTrue(readBack)
        XCTAssertEqual(cache.slot?.slot, 1)
    }

    func testCache_nilRead_retainsPreviousSlot_noReadBack() {
        var cache = LinkSlotCache()
        let t0 = Date(timeIntervalSince1970: 1_000)
        _ = cache.learn(LinkSlot(slot: 4), at: t0)

        // An empty/failed read (parse → nil) MUST NOT clobber the known slot.
        let readBack = cache.learn(nil, at: Date(timeIntervalSince1970: 2_000))

        XCTAssertFalse(readBack)
        XCTAssertEqual(cache.slot?.slot, 4)
        XCTAssertEqual(cache.learnedAt, t0, "learnedAt unchanged when read yields nil")
    }

    func testCache_reset_clearsSlotAndLearnedAt() {
        var cache = LinkSlotCache()
        _ = cache.learn(LinkSlot(slot: 2), at: Date())
        cache.reset()

        XCTAssertNil(cache.slot)
        XCTAssertNil(cache.learnedAt)

        // After reset, the next learn is an initial learn again (no read-back).
        let readBack = cache.learn(LinkSlot(slot: 2), at: Date())
        XCTAssertFalse(readBack)
    }

    // MARK: - T035 [US3]: old firmware (no AA4) never fabricates in-use/elsewhere

    func testDerive_noAA4_neverFabricates_exhaustive() {
        // US3: a new app against old firmware (AA4 absent) MUST degrade to
        // cannotDetermine for every active/local/output combination — it must
        // never claim inUseHere or activeElsewhere without AA4 (FR-008, C-L2).
        // The only states allowed without AA4 are disconnected and onUsb.
        for active in UInt8(0)...4 {
            for local in UInt8(0)...4 {
                let status = deriveLocalHostStatus(
                    hasAA4: false,
                    connected: true,
                    capability: cap(hasOutputEndpoint: false),
                    activeProfile: profile(index: active),
                    localSlot: LinkSlot(slot: local),
                    output: .ble
                )
                XCTAssertEqual(
                    status, .cannotDetermine,
                    "no AA4 must never fabricate (active=\(active) local=\(local))"
                )
            }
        }
    }

    func testDerive_noAA4_stillHonoursDisconnectedAndUsb() {
        // Disconnected and onUsb do not depend on AA4 and still win.
        XCTAssertEqual(
            deriveLocalHostStatus(
                hasAA4: false, connected: false, capability: cap(),
                activeProfile: profile(index: 1), localSlot: nil, output: .ble
            ), .disconnected
        )
        XCTAssertEqual(
            deriveLocalHostStatus(
                hasAA4: false, connected: true, capability: cap(hasOutputEndpoint: true),
                activeProfile: profile(index: 1), localSlot: nil, output: .usb
            ), .onUsb
        )
    }

    // MARK: - T044 [Phase 7]: hostStatusVisual five-state encoding (V-1/V-4)

    func testVisual_exhaustive_fiveStates() {
        // Colour + symbol single source of truth (host-status-visual.md V-1).
        // Both full and compact modes consume this exact mapping (FR-016).
        XCTAssertEqual(hostStatusVisual(for: .inUseHere),
                       HostStatusVisual(color: .green, symbol: "●"))
        XCTAssertEqual(hostStatusVisual(for: .activeElsewhere(slot: 3)),
                       HostStatusVisual(color: .orange, symbol: "◐"))
        XCTAssertEqual(hostStatusVisual(for: .onUsb),
                       HostStatusVisual(color: .blue, symbol: "◆"))
        XCTAssertEqual(hostStatusVisual(for: .cannotDetermine),
                       HostStatusVisual(color: .gray, symbol: "○"))
        XCTAssertEqual(hostStatusVisual(for: .disconnected),
                       HostStatusVisual(color: .red, symbol: "✕"))
    }

    func testVisual_disconnectedIsRed_notGray_distinctFromCannotDetermine() {
        // V-2.3: "not connected" reads as an alarm (red), never confused with
        // the grey "unknown" state.
        XCTAssertEqual(hostStatusVisual(for: .disconnected).color, .red)
        XCTAssertNotEqual(hostStatusVisual(for: .disconnected).color,
                          hostStatusVisual(for: .cannotDetermine).color)
        XCTAssertNotEqual(hostStatusVisual(for: .disconnected).symbol,
                          hostStatusVisual(for: .cannotDetermine).symbol)
    }

    func testVisual_coloursAreUniquePerState() {
        // Each state maps to a distinct colour; blue is reserved for USB so it
        // never collides with active-elsewhere (V-1 rationale).
        let all: [LocalHostStatus] = [
            .inUseHere, .activeElsewhere(slot: 2), .onUsb, .cannotDetermine, .disconnected,
        ]
        let colors = all.map { hostStatusVisual(for: $0).color }
        XCTAssertEqual(Set(colors.map { "\($0)" }).count, all.count)
        XCTAssertEqual(hostStatusVisual(for: .onUsb).color, .blue)
        XCTAssertEqual(hostStatusVisual(for: .activeElsewhere(slot: 1)).color, .orange)
    }
}
