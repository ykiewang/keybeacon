// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import XCTest
@testable import BleWidgetCore

final class StalenessTrackerTests: XCTestCase {

    // MARK: - Default window is 3 seconds (Clarify Q1 / FR-015)

    func testDefaultStalenessWindow_IsThreeSeconds() {
        let t = StalenessTracker()
        XCTAssertEqual(t.stalenessWindow, 3.0)
    }

    // MARK: - Fresh notify → not stale

    func testFreshNotify_IsLive() {
        let t = StalenessTracker()
        t.recordNotify(fieldKey: "host.connected", at: 1000.0)
        XCTAssertFalse(t.isStale(fieldKey: "host.connected", now: 1000.0))
        XCTAssertFalse(t.isStale(fieldKey: "host.connected", now: 1000.5))
    }

    // MARK: - 3-second threshold

    func testAtExactly299s_StillLive() {
        let t = StalenessTracker()
        t.recordNotify(fieldKey: "f", at: 100.0)
        XCTAssertFalse(t.isStale(fieldKey: "f", now: 102.99))
    }

    func testAtExactly3s_IsStale() {
        let t = StalenessTracker()
        t.recordNotify(fieldKey: "f", at: 100.0)
        XCTAssertTrue(t.isStale(fieldKey: "f", now: 103.0))
    }

    func testAt3sPlusEpsilon_StillStale() {
        let t = StalenessTracker()
        t.recordNotify(fieldKey: "f", at: 100.0)
        XCTAssertTrue(t.isStale(fieldKey: "f", now: 103.001))
        XCTAssertTrue(t.isStale(fieldKey: "f", now: 1_000_000.0))
    }

    // MARK: - Never recorded → treated as stale

    func testNeverRecorded_IsStale() {
        let t = StalenessTracker()
        XCTAssertTrue(t.isStale(fieldKey: "unknown", now: 1000.0))
    }

    // MARK: - forceStaleAll (BLE disconnect)

    func testForceStaleAll_MarksAllTrackedFieldsStale() {
        let t = StalenessTracker()
        t.recordNotify(fieldKey: "f1", at: 1000.0)
        t.recordNotify(fieldKey: "f2", at: 1000.0)
        t.recordNotify(fieldKey: "f3", at: 1000.0)
        XCTAssertFalse(t.isStale(fieldKey: "f1", now: 1000.0))
        XCTAssertFalse(t.isStale(fieldKey: "f2", now: 1000.0))
        XCTAssertFalse(t.isStale(fieldKey: "f3", now: 1000.0))
        t.forceStaleAll()
        XCTAssertTrue(t.isStale(fieldKey: "f1", now: 1000.0))
        XCTAssertTrue(t.isStale(fieldKey: "f2", now: 1000.0))
        XCTAssertTrue(t.isStale(fieldKey: "f3", now: 1000.0))
    }

    func testForceStaleAll_DoesNotMarkUnknownFields() {
        let t = StalenessTracker()
        t.recordNotify(fieldKey: "f1", at: 1000.0)
        t.forceStaleAll()
        // "unknown" was never tracked → still stale by default
        XCTAssertTrue(t.isStale(fieldKey: "unknown", now: 1000.0))
    }

    // MARK: - New recordNotify after forceStaleAll → recovers live

    func testRecoveryAfterForceStaleAll() {
        let t = StalenessTracker()
        t.recordNotify(fieldKey: "f", at: 1000.0)
        t.forceStaleAll()
        XCTAssertTrue(t.isStale(fieldKey: "f", now: 1000.0))
        t.recordNotify(fieldKey: "f", at: 1000.5)
        XCTAssertFalse(t.isStale(fieldKey: "f", now: 1001.0))
    }

    // MARK: - Per-field recovery (not whole-tracker)

    func testPerFieldRecovery_OnlyAffectsThatField() {
        let t = StalenessTracker()
        t.recordNotify(fieldKey: "a", at: 1000.0)
        t.recordNotify(fieldKey: "b", at: 1000.0)
        t.forceStaleAll()
        t.recordNotify(fieldKey: "a", at: 1000.5)
        // "a" recovered, "b" still forced stale.
        XCTAssertFalse(t.isStale(fieldKey: "a", now: 1001.0))
        XCTAssertTrue(t.isStale(fieldKey: "b", now: 1001.0))
    }

    // MARK: - Monotonic-clock backward motion never increases staleness

    func testBackwardsTimestamp_NeverRegressesStaleness() {
        let t = StalenessTracker()
        t.recordNotify(fieldKey: "f", at: 1000.0)
        // Inject an older timestamp (should be ignored, newer is kept).
        t.recordNotify(fieldKey: "f", at: 500.0)
        XCTAssertFalse(t.isStale(fieldKey: "f", now: 1001.0),
            "injecting an older timestamp must not make the field stale")
    }

    // MARK: - forceStale single field

    func testForceStale_SingleField() {
        let t = StalenessTracker()
        t.recordNotify(fieldKey: "f1", at: 1000.0)
        t.recordNotify(fieldKey: "f2", at: 1000.0)
        t.forceStale(fieldKey: "f1")
        XCTAssertTrue(t.isStale(fieldKey: "f1", now: 1000.0))
        XCTAssertFalse(t.isStale(fieldKey: "f2", now: 1000.0))
    }

    // MARK: - Custom window (future-proofing)

    func testCustomWindow_FiveSeconds() {
        let t = StalenessTracker(stalenessWindow: 5.0)
        t.recordNotify(fieldKey: "f", at: 100.0)
        XCTAssertFalse(t.isStale(fieldKey: "f", now: 104.99))
        XCTAssertTrue(t.isStale(fieldKey: "f", now: 105.0))
    }

    // MARK: - lastNotifyAt helper

    func testLastNotifyAt_ReturnsRecordedTimestamp() {
        let t = StalenessTracker()
        XCTAssertNil(t.lastNotifyAt(fieldKey: "f"))
        t.recordNotify(fieldKey: "f", at: 1234.5)
        XCTAssertEqual(t.lastNotifyAt(fieldKey: "f"), 1234.5)
    }

    // MARK: - reset()

    func testReset_ClearsAllTracking() {
        let t = StalenessTracker()
        t.recordNotify(fieldKey: "a", at: 100.0)
        t.recordNotify(fieldKey: "b", at: 100.0)
        t.forceStale(fieldKey: "a")
        t.reset()
        XCTAssertTrue(t.isStale(fieldKey: "a", now: 100.0))
        XCTAssertTrue(t.isStale(fieldKey: "b", now: 100.0))
        XCTAssertEqual(t.trackedFieldKeys, [])
    }
}
