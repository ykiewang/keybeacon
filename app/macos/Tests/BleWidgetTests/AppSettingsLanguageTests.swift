// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import XCTest
@testable import BleWidgetCore

/// Persistence-layer coverage for the UI-language preference (FR-001 / FR-004).
/// `ResolvedLanguage.resolve` and the `L10n` table are exercised by
/// `LocalizationTests`; these tests pin the `AppSettings` read/write path,
/// including the corrupt-value fallback that must never crash or blank.
final class AppSettingsLanguageTests: XCTestCase {

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (defaults, suite)
    }

    func testLanguage_DefaultsToSystem() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(AppSettings(defaults: defaults).languagePreference, .system)
    }

    func testLanguage_PersistsChineseRoundTrip() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        AppSettings(defaults: defaults).languagePreference = .chinese

        // A fresh instance over the same store proves it reached UserDefaults.
        XCTAssertEqual(AppSettings(defaults: defaults).languagePreference, .chinese)
        XCTAssertEqual(defaults.string(forKey: "uiLanguage"), "chinese")
    }

    func testLanguage_PersistsEnglishRoundTrip() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        AppSettings(defaults: defaults).languagePreference = .english

        XCTAssertEqual(AppSettings(defaults: defaults).languagePreference, .english)
        XCTAssertEqual(defaults.string(forKey: "uiLanguage"), "english")
    }

    func testLanguage_PersistsSystemRoundTrip() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        settings.languagePreference = .english
        settings.languagePreference = .system

        XCTAssertEqual(AppSettings(defaults: defaults).languagePreference, .system)
        XCTAssertEqual(defaults.string(forKey: "uiLanguage"), "system")
    }

    func testLanguage_CorruptValueFallsBackToSystem() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("klingon", forKey: "uiLanguage")

        XCTAssertEqual(AppSettings(defaults: defaults).languagePreference, .system)
    }

    func testLanguage_EmptyStringFallsBackToSystem() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("", forKey: "uiLanguage")

        XCTAssertEqual(AppSettings(defaults: defaults).languagePreference, .system)
    }

    func testResolvedLanguage_ForcedChineseIgnoresSystem() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        settings.languagePreference = .chinese

        // Forced preferences resolve regardless of the host OS locale.
        XCTAssertEqual(settings.resolvedLanguage, .chinese)
    }

    func testResolvedLanguage_ForcedEnglishIgnoresSystem() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        settings.languagePreference = .english

        XCTAssertEqual(settings.resolvedLanguage, .english)
    }
}
