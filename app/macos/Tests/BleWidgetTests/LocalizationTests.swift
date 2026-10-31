// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import XCTest
@testable import BleWidgetCore

final class LocalizationTests: XCTestCase {

    // MARK: - FR-002: three-state resolution incl. non-CJK fallback

    func testResolve_ForcedChinese_IgnoresSystem() {
        XCTAssertEqual(
            ResolvedLanguage.resolve(preference: .chinese, systemCode: "en-US"),
            .chinese
        )
        XCTAssertEqual(
            ResolvedLanguage.resolve(preference: .chinese, systemCode: nil),
            .chinese
        )
    }

    func testResolve_ForcedEnglish_IgnoresSystem() {
        XCTAssertEqual(
            ResolvedLanguage.resolve(preference: .english, systemCode: "zh-Hans-CN"),
            .english
        )
    }

    func testResolve_System_ChineseRegions() {
        for code in ["zh", "zh-Hans", "zh-Hans-CN", "zh-Hant-TW", "ZH-cn"] {
            XCTAssertEqual(
                ResolvedLanguage.resolve(preference: .system, systemCode: code),
                .chinese,
                "system locale \(code) must resolve to Chinese"
            )
        }
    }

    func testResolve_System_EverythingElseFallsBackToEnglish() {
        for code in ["en-US", "ja-JP", "de-DE", "fr", "ko-KR"] {
            XCTAssertEqual(
                ResolvedLanguage.resolve(preference: .system, systemCode: code),
                .english,
                "system locale \(code) must fall back to English"
            )
        }
        XCTAssertEqual(
            ResolvedLanguage.resolve(preference: .system, systemCode: nil),
            .english
        )
    }

    // MARK: - FR-010: missing-key fallback (selected → English → key)

    func testText_KnownKeyReturnsSelectedLanguage() {
        XCTAssertEqual(L10n.text("Menu_Quit", language: .chinese), "退出")
        XCTAssertEqual(L10n.text("Menu_Quit", language: .english), "Quit")
    }

    func testText_UnknownKeyReturnsKeyItself() {
        XCTAssertEqual(L10n.text("No_Such_Key", language: .chinese), "No_Such_Key")
        XCTAssertEqual(L10n.text("No_Such_Key", language: .english), "No_Such_Key")
    }

    func testText_SelfNamedLanguageLabelsExistInBothTables() {
        // Concrete-language labels are self-named, so both lookups agree.
        XCTAssertEqual(L10n.text("Menu_LanguageEnglish", language: .chinese), "English")
        XCTAssertEqual(L10n.text("Menu_LanguageEnglish", language: .english), "English")
        XCTAssertEqual(L10n.text("Menu_LanguageChinese", language: .chinese), "中文")
        XCTAssertEqual(L10n.text("Menu_LanguageChinese", language: .english), "中文")
    }

    // MARK: - FR-009 / FR-014: placeholder templates render as a whole

    func testFormat_BatteryPercentUsesWholeTemplate() {
        XCTAssertEqual(L10n.format("Battery_Percent", .chinese, 85), "85%")
        XCTAssertEqual(L10n.format("Battery_Percent", .english, 85), "85%")
    }

    func testFormat_LastUpdatedWholeTemplate() {
        XCTAssertEqual(L10n.format("Last_Updated", .chinese, "12:34:56"), "最后更新 12:34:56")
        XCTAssertEqual(L10n.format("Last_Updated", .english, "12:34:56"), "updated 12:34:56")
    }

    func testFormat_ReservedEndpointHexNeverMixLanguages() {
        let zh = L10n.format("Endpoint_Reserved", .chinese, 0xAB)
        let en = L10n.format("Endpoint_Reserved", .english, 0xAB)
        XCTAssertEqual(zh, "输出:未知(0xAB)")
        XCTAssertEqual(en, "Output: unknown (0xAB)")
    }

    // MARK: - FR-012: language chooser shows concrete languages self-named

    func testPreferenceDisplayName_SelfNamedForConcreteLanguages() {
        XCTAssertEqual(LanguagePreference.english.displayName, "English")
        XCTAssertEqual(LanguagePreference.chinese.displayName, "中文")
    }
}
