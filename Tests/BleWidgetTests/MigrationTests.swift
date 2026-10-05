// Copyright (c) 2026 The TOTEM ZMK Contributors
// SPDX-License-Identifier: MIT

import XCTest
@testable import BleWidgetCore

final class MigrationTests: XCTestCase {

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (defaults, suite)
    }

    func testMigratesLegacyKeysForward() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("100.0,200.0", forKey: "totemPanelFrame.Display1")
        defaults.set(true, forKey: "totemPanelLocked")

        AppSettings(defaults: defaults).migrateIfNeeded()

        XCTAssertEqual(defaults.string(forKey: "panelFrame.Display1"), "100.0,200.0")
        XCTAssertTrue(defaults.bool(forKey: "panelLocked"))
        XCTAssertTrue(defaults.bool(forKey: "settingsMigratedV2"))
    }

    func testMigrationNeverOverwritesExistingNewValue() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("1.0,1.0", forKey: "totemPanelFrame.Display1")
        defaults.set("9.0,9.0", forKey: "panelFrame.Display1")

        AppSettings(defaults: defaults).migrateIfNeeded()

        XCTAssertEqual(defaults.string(forKey: "panelFrame.Display1"), "9.0,9.0")
    }

    func testMigrationRunsOnlyOnce() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(true, forKey: "settingsMigratedV2")
        defaults.set("1.0,1.0", forKey: "totemPanelFrame.Display1")

        AppSettings(defaults: defaults).migrateIfNeeded()

        XCTAssertNil(defaults.string(forKey: "panelFrame.Display1"))
    }
}
