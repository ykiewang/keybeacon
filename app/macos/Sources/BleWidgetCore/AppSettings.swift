// Copyright (c) 2026 The TOTEM ZMK Contributors
// SPDX-License-Identifier: MIT

import Foundation

public enum PinnedCorner: String, CaseIterable {
    case topLeft = "top-left"
    case topRight = "top-right"
    case bottomLeft = "bottom-left"
    case bottomRight = "bottom-right"

    public var displayName: String {
        switch self {
        case .topLeft: return L10n.text("Corner_TopLeft")
        case .topRight: return L10n.text("Corner_TopRight")
        case .bottomLeft: return L10n.text("Corner_BottomLeft")
        case .bottomRight: return L10n.text("Corner_BottomRight")
        }
    }
}

public enum DisplayMode: String, CaseIterable {
    case full = "full"
    case compact = "compact"

    public var displayName: String {
        switch self {
        case .full: return L10n.text("Menu_DisplayFull")
        case .compact: return L10n.text("Menu_DisplayCompact")
        }
    }
}

public final class AppSettings {
    private static let positionPrefix = "panelFrame"
    private static let lockedKey = "panelLocked"
    private static let migratedKey = "settingsMigratedV2"
    private static let selectedKeyboardKey = "selectedKeyboardIdentifier"
    private static let pinnedCornerKey = "panelPinnedCorner"
    private static let panelVisibleKey = "panelVisible"
    private static let displayModeKey = "panelDisplayMode"
    private static let languagePrefKey = "uiLanguage"

    private static let legacyPositionPrefix = "totemPanelFrame"
    private static let legacyLockedKey = "totemPanelLocked"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Panel visibility (nil-default = visible)

    /// Whether the floating panel is shown. Defaults to true for first-run
    /// users so the panel behaves the same as before. User toggles via the
    /// menu-bar "显示浮窗" item.
    public var panelVisible: Bool {
        get {
            if defaults.object(forKey: Self.panelVisibleKey) == nil {
                return true
            }
            return defaults.bool(forKey: Self.panelVisibleKey)
        }
        set { defaults.set(newValue, forKey: Self.panelVisibleKey) }
    }

    // MARK: - Display mode (full = multi-row card, compact = single-row)

    /// Floating panel layout. `.full` matches the KBP 1.1 multi-row card
    /// (default). `.compact` packs everything into a single-row high-density
    /// strip; the user picks via the menu-bar "显示模式" submenu.
    public var displayMode: DisplayMode {
        get {
            guard let raw = defaults.string(forKey: Self.displayModeKey) else {
                return .full
            }
            return DisplayMode(rawValue: raw) ?? .full
        }
        set { defaults.set(newValue.rawValue, forKey: Self.displayModeKey) }
    }

    // MARK: - Language preference (跟随系统 / 中文 / English)

    /// User-visible three-state language preference (FR-001 / FR-004).
    /// `system` is the default for first-run users (US3). Corrupt or unknown
    /// stored values fall back to `system` rather than crashing or blanking.
    public var languagePreference: LanguagePreference {
        get {
            guard let raw = defaults.string(forKey: Self.languagePrefKey),
                  let pref = LanguagePreference(rawValue: raw) else {
                return .system
            }
            return pref
        }
        set { defaults.set(newValue.rawValue, forKey: Self.languagePrefKey) }
    }

    /// The concrete language resolved from the persisted preference against the
    /// current OS locale (FR-002). Resolved once per launch (spec Assumptions).
    public var resolvedLanguage: ResolvedLanguage {
        ResolvedLanguage.resolve(
            preference: languagePreference,
            systemCode: Locale.preferredLanguages.first
        )
    }

    // MARK: - Panel lock

    public var locked: Bool {
        get { defaults.bool(forKey: Self.lockedKey) }
        set { defaults.set(newValue, forKey: Self.lockedKey) }
    }

    // MARK: - Pinned corner (nil = remember absolute position, default)

    public var pinnedCorner: PinnedCorner? {
        get {
            guard let raw = defaults.string(forKey: Self.pinnedCornerKey) else {
                return nil
            }
            return PinnedCorner(rawValue: raw)
        }
        set {
            if let v = newValue {
                defaults.set(v.rawValue, forKey: Self.pinnedCornerKey)
            } else {
                defaults.removeObject(forKey: Self.pinnedCornerKey)
            }
        }
    }

    // MARK: - Selected keyboard (persisted, MR4 / FR-015)

    public var selectedKeyboardIdentifier: UUID? {
        get {
            guard let s = defaults.string(forKey: Self.selectedKeyboardKey) else {
                return nil
            }
            return UUID(uuidString: s)
        }
        set {
            if let id = newValue {
                defaults.set(id.uuidString, forKey: Self.selectedKeyboardKey)
            } else {
                defaults.removeObject(forKey: Self.selectedKeyboardKey)
            }
        }
    }

    // MARK: - Panel position (per-screen)

    public func positionKey(screenID: String) -> String {
        "\(Self.positionPrefix).\(screenID)"
    }

    public func position(screenID: String) -> String? {
        defaults.string(forKey: positionKey(screenID: screenID))
    }

    public func setPosition(_ value: String, screenID: String) {
        defaults.set(value, forKey: positionKey(screenID: screenID))
    }

    public func hasPosition(screenID: String) -> Bool {
        defaults.object(forKey: positionKey(screenID: screenID)) != nil
    }

    // MARK: - One-time de-branding migration (MR5 / FR-004)

    public func migrateIfNeeded() {
        guard !defaults.bool(forKey: Self.migratedKey) else { return }

        if defaults.object(forKey: Self.lockedKey) == nil,
           let legacyLocked = defaults.object(forKey: Self.legacyLockedKey) {
            defaults.set(legacyLocked, forKey: Self.lockedKey)
        }

        let legacyDot = Self.legacyPositionPrefix + "."
        for (key, value) in defaults.dictionaryRepresentation()
        where key.hasPrefix(legacyDot) {
            let newKey = Self.positionPrefix + String(key.dropFirst(Self.legacyPositionPrefix.count))
            if defaults.object(forKey: newKey) == nil {
                defaults.set(value, forKey: newKey)
            }
        }

        defaults.set(true, forKey: Self.migratedKey)
    }
}
