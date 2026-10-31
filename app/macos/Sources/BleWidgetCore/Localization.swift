// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - Language model

/// User-visible three-state language preference (FR-001).
/// Persisted in `AppSettings`; resolved to a concrete ``ResolvedLanguage``
/// at launch via ``ResolvedLanguage/resolve(preference:systemCode:)``.
public enum LanguagePreference: String, CaseIterable {
    case system = "system"
    case chinese = "chinese"
    case english = "english"

    /// Display name. The two concrete languages self-name (a Chinese user can
    /// spot "English", an English user can spot "中文"); the "follow system"
    /// entry localises to the currently active UI language (FR-012).
    public var displayName: String {
        switch self {
        case .system:  return L10n.text("Menu_LanguageSystem", language: L10n.currentLanguage)
        case .chinese: return L10n.text("Menu_LanguageChinese", language: .chinese)
        case .english: return L10n.text("Menu_LanguageEnglish", language: .english)
        }
    }
}

/// The concrete language resolved at launch (FR-002): exactly one of the two
/// supported resource sets. `en` doubles as the fallback for any non-Chinese
/// system locale (US3 AS3 / SC-004).
public enum ResolvedLanguage {
    case chinese
    case english

    /// Resource-set tag, aligned with Windows `Resources.zh-CN.resx` / `Resources.resx`.
    public var tag: String {
        switch self {
        case .chinese: return "zh-CN"
        case .english: return "en"
        }
    }

    public var locale: Locale {
        switch self {
        case .chinese: return Locale(identifier: "zh_CN")
        case .english: return Locale(identifier: "en")
        }
    }

    /// Resolve a preference against the system language code.
    ///
    /// - `system` → Chinese when the code starts with `zh`, otherwise English
    ///   (the explicit fallback — the static tables have no neutral locale).
    /// - `chinese` / `english` → forced.
    public static func resolve(
        preference: LanguagePreference,
        systemCode: String?
    ) -> ResolvedLanguage {
        switch preference {
        case .chinese: return .chinese
        case .english: return .english
        case .system:
            let code = (systemCode ?? "").lowercased()
            return code.hasPrefix("zh") ? .chinese : .english
        }
    }
}

// MARK: - String table

/// Pure, unit-testable UI string lookup (FR-006 / FR-010 / Principle IV).
///
/// The table is keyed identically to the Windows `Resources.resx` entries so
/// the two platforms stay aligned. Lookup order on a miss is
/// `selected → English → key itself`, never empty and never a crash.
public enum L10n {
    /// The language currently in effect for the whole app. Set once at launch
    /// from the persisted preference and again on every language switch, then
    /// read by every default-argument-less call site (FR-003 / FR-011).
    public static var currentLanguage: ResolvedLanguage = .english

    /// Look up `key` in `language`, falling back to English then the key.
    public static func text(_ key: String, language: ResolvedLanguage) -> String {
        if let hit = table(for: language)[key] { return hit }
        if let en = english[key] { return en }
        return key
    }

    /// Look up `key` in the currently active language.
    public static func text(_ key: String) -> String {
        text(key, language: currentLanguage)
    }

    /// Format a placeholder template (`{0}` style) in `language`. Missing keys
    /// fall back the same way as ``text(_:language:)``.
    public static func format(_ key: String, _ language: ResolvedLanguage, _ args: CVarArg...) -> String {
        let template = text(key, language: language)
        return String(format: template, locale: language.locale, arguments: args)
    }

    /// Format a placeholder template in the currently active language.
    public static func format(_ key: String, _ args: CVarArg...) -> String {
        let template = text(key, language: currentLanguage)
        return String(format: template, locale: currentLanguage.locale, arguments: args)
    }

    static func table(for language: ResolvedLanguage) -> [String: String] {
        switch language {
        case .chinese: return chinese
        case .english: return english
        }
    }

    // MARK: English

    static let english: [String: String] = [
        "AppName": "KeyBeacon",

        "Menu_Keyboard": "Keyboard",
        "Menu_NoKeyboards": "No compatible keyboards",
        "Menu_Reconnect": "Reconnect",
        "Menu_ShowPanel": "Show Floating Panel",
        "Menu_Lock": "Lock / Click-through",
        "Menu_PinCorner": "Pin to Corner",
        "Menu_PinOff": "Off (remember position)",
        "Menu_DisplayMode": "Display Mode",
        "Menu_DisplayFull": "Full",
        "Menu_DisplayCompact": "Compact",
        "Menu_Language": "Language",
        "Menu_LanguageSystem": "Follow System",
        "Menu_LanguageEnglish": "English",
        "Menu_LanguageChinese": "中文",
        "Menu_ExportDiagnostics": "Export Diagnostics…",
        "Menu_Quit": "Quit",

        "Corner_TopLeft": "Top-left",
        "Corner_TopRight": "Top-right",
        "Corner_BottomLeft": "Bottom-left",
        "Corner_BottomRight": "Bottom-right",

        "Header_NoKeyboard": "No keyboard connected",
        "Header_Unsupported": "⚠︎ Unsupported keyboard protocol version",
        "Info_UnsupportedNames": "Detected a newer KeyBeacon protocol (%@); please upgrade this app.",
        "Tip_Unsupported": "Detected an unsupported KeyBeacon protocol version; please upgrade this app.",

        "Card_Connectivity": "Connectivity & Power",
        "Card_Profile": "Profile",
        "Split_LeftDash": "Left —",
        "Split_RightDash": "Right —",
        "Split_LeftOnline": "Left online",
        "Split_LeftOffline": "Left offline",
        "Split_RightOnline": "Right online",
        "Split_RightOffline": "Right offline",
        "Battery_Caption": "Battery",
        "Battery_Percent": "%d%%",
        "Battery_ReadFailed": "Read failed",
        "Conn_Charging": "Charging",
        "Conn_Pending": "Pairing",
        "Conn_Connected": "Connected",
        "Conn_Disconnected": "Disconnected",
        "Conn_TimeoutSuffix": " (timeout)",
        "Conn_ExplicitSuffix": " (disconnected)",

        "State_Disconnected": "Disconnected",
        "Last_Updated": "updated %@",

        "Endpoint_Usb": "Output: USB",
        "Endpoint_Ble": "Output: BLE",
        "Endpoint_Unknown": "Output: unknown",
        "Endpoint_Reserved": "Output: unknown (0x%02X)",
    ]

    // MARK: Simplified Chinese

    static let chinese: [String: String] = [
        "AppName": "KeyBeacon",

        "Menu_Keyboard": "键盘",
        "Menu_NoKeyboards": "无可用键盘",
        "Menu_Reconnect": "重连",
        "Menu_ShowPanel": "显示浮窗",
        "Menu_Lock": "锁定 / 穿透",
        "Menu_PinCorner": "钉到角落",
        "Menu_PinOff": "关闭（记忆位置）",
        "Menu_DisplayMode": "显示模式",
        "Menu_DisplayFull": "完整",
        "Menu_DisplayCompact": "精简",
        "Menu_Language": "语言",
        "Menu_LanguageSystem": "跟随系统",
        "Menu_LanguageEnglish": "English",
        "Menu_LanguageChinese": "中文",
        "Menu_ExportDiagnostics": "导出诊断信息…",
        "Menu_Quit": "退出",

        "Corner_TopLeft": "左上",
        "Corner_TopRight": "右上",
        "Corner_BottomLeft": "左下",
        "Corner_BottomRight": "右下",

        "Header_NoKeyboard": "未连接键盘",
        "Header_Unsupported": "⚠︎ 不受支持的键盘协议版本",
        "Info_UnsupportedNames": "检测到较新的 KeyBeacon 协议(%@);请升级本应用后使用。",
        "Tip_Unsupported": "检测到不受支持的 KeyBeacon 协议版本;请升级本应用。",

        "Card_Connectivity": "连接与电量",
        "Card_Profile": "配置",
        "Split_LeftDash": "左 —",
        "Split_RightDash": "右 —",
        "Split_LeftOnline": "左 在线",
        "Split_LeftOffline": "左 离线",
        "Split_RightOnline": "右 在线",
        "Split_RightOffline": "右 离线",
        "Battery_Caption": "电量",
        "Battery_Percent": "%d%%",
        "Battery_ReadFailed": "读取失败",
        "Conn_Charging": "充电中",
        "Conn_Pending": "待配对",
        "Conn_Connected": "已连接",
        "Conn_Disconnected": "未连接",
        "Conn_TimeoutSuffix": "(超时)",
        "Conn_ExplicitSuffix": "(主动断开)",

        "State_Disconnected": "未连接",
        "Last_Updated": "最后更新 %@",

        "Endpoint_Usb": "输出:USB",
        "Endpoint_Ble": "输出:BLE",
        "Endpoint_Unknown": "输出:未知",
        "Endpoint_Reserved": "输出:未知(0x%02X)",
    ]
}
