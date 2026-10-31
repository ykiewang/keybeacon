// Copyright (c) 2026 The TOTEM ZMK Contributors
// SPDX-License-Identifier: MIT

import AppKit
import BleWidgetCore

final class AppDelegate: NSObject, NSApplicationDelegate, BLEClientDelegate {
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private let client = BLEClient()
    private var state: BLEConnectionState = .connecting
    private var activeKeyboard: CompatibleKeyboard?
    private var candidates: [CompatibleKeyboard] = []
    private var unsupportedKeyboards: [CompatibleKeyboard] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        AppSettings().migrateIfNeeded()

        // Resolve the persisted language preference once, before any UI string
        // is built (FR-002 / FR-004).
        L10n.currentLanguage = AppSettings().resolvedLanguage

        panel = FloatingPanel()
        if AppSettings().panelVisible {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }

        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        updateMenuBarIcon()
        buildMenu()

        client.delegate = self
        client.start()
    }

    private func buildMenu() {
        let menu = NSMenu()
        let headerTitle: String
        if let active = activeKeyboard {
            headerTitle = active.displayName
        } else if !unsupportedKeyboards.isEmpty {
            headerTitle = L10n.text("Header_Unsupported")
        } else {
            headerTitle = L10n.text("Header_NoKeyboard")
        }
        let header = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if activeKeyboard == nil, !unsupportedKeyboards.isEmpty {
            let names = unsupportedKeyboards.map { $0.displayName }.joined(separator: ", ")
            let info = NSMenuItem(
                title: L10n.format("Info_UnsupportedNames", names),
                action: nil, keyEquivalent: ""
            )
            info.isEnabled = false
            menu.addItem(info)
        }
        menu.addItem(.separator())

        let chooser = NSMenuItem(title: L10n.text("Menu_Keyboard"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        if candidates.isEmpty {
            let none = NSMenuItem(title: L10n.text("Menu_NoKeyboards"), action: nil, keyEquivalent: "")
            none.isEnabled = false
            submenu.addItem(none)
        } else {
            for keyboard in candidates {
                let item = NSMenuItem(
                    title: keyboard.displayName,
                    action: #selector(selectKeyboard(_:)), keyEquivalent: ""
                )
                item.target = self
                item.representedObject = keyboard.identifier
                item.state = keyboard.identifier == activeKeyboard?.identifier ? .on : .off
                submenu.addItem(item)
            }
        }
        chooser.submenu = submenu
        menu.addItem(chooser)
        menu.addItem(.separator())

        menu.addItem(
            NSMenuItem(title: L10n.text("Menu_Reconnect"), action: #selector(reconnect), keyEquivalent: "r")
        )

        // Panel visibility toggle (persisted). Checkmark reflects current state.
        let showPanelItem = NSMenuItem(
            title: L10n.text("Menu_ShowPanel"),
            action: #selector(togglePanelVisible), keyEquivalent: ""
        )
        showPanelItem.target = self
        showPanelItem.state = AppSettings().panelVisible ? .on : .off
        menu.addItem(showPanelItem)

        menu.addItem(
            NSMenuItem(
                title: L10n.text("Menu_Lock"),
                action: #selector(toggleLock), keyEquivalent: "l"
            )
        )

        // "Pin to corner" submenu — anchors the panel to a visible-frame
        // corner of its current screen so it never drifts when the user
        // switches active window to another display.
        let pinChooser = NSMenuItem(title: L10n.text("Menu_PinCorner"), action: nil, keyEquivalent: "")
        let pinSubmenu = NSMenu()
        let currentPin = panel.pinnedCorner

        let offItem = NSMenuItem(
            title: L10n.text("Menu_PinOff"),
            action: #selector(setPinOff), keyEquivalent: ""
        )
        offItem.target = self
        offItem.state = (currentPin == nil) ? .on : .off
        pinSubmenu.addItem(offItem)
        pinSubmenu.addItem(.separator())

        for corner in PinnedCorner.allCases {
            let item = NSMenuItem(
                title: corner.displayName,
                action: #selector(setPinCorner(_:)), keyEquivalent: ""
            )
            item.target = self
            item.representedObject = corner.rawValue
            item.state = (currentPin == corner) ? .on : .off
            pinSubmenu.addItem(item)
        }
        pinChooser.submenu = pinSubmenu
        menu.addItem(pinChooser)

        // "Display mode" submenu — 完整 (multi-row card) / 精简 (single-row).
        let modeChooser = NSMenuItem(title: L10n.text("Menu_DisplayMode"), action: nil, keyEquivalent: "")
        let modeSubmenu = NSMenu()
        let currentMode = panel.displayMode
        for mode in DisplayMode.allCases {
            let item = NSMenuItem(
                title: mode.displayName,
                action: #selector(setDisplayMode(_:)), keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            item.state = (currentMode == mode) ? .on : .off
            modeSubmenu.addItem(item)
        }
        modeChooser.submenu = modeSubmenu
        menu.addItem(modeChooser)

        // "Language" submenu — 跟随系统 / 中文 / English (FR-005 / FR-012).
        let languageChooser = NSMenuItem(title: L10n.text("Menu_Language"), action: nil, keyEquivalent: "")
        let languageSubmenu = NSMenu()
        let currentPreference = AppSettings().languagePreference
        for preference in LanguagePreference.allCases {
            let item = NSMenuItem(
                title: preference.displayName,
                action: #selector(setLanguage(_:)), keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preference.rawValue
            item.state = (currentPreference == preference) ? .on : .off
            languageSubmenu.addItem(item)
        }
        languageChooser.submenu = languageSubmenu
        menu.addItem(languageChooser)

        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: L10n.text("Menu_Quit"), action: #selector(quit), keyEquivalent: "q")
        )
        for item in menu.items where item.action != nil { item.target = self }
        statusItem.menu = menu
    }

    private func updateMenuBarIcon() {
        let symbol: String
        let fallback: String
        switch state {
        case .connected: symbol = "keyboard"; fallback = "⌨︎"
        case .connecting: symbol = "keyboard.badge.ellipsis"; fallback = "⌨…"
        case .notConnected: symbol = "keyboard.slash"; fallback = "⌨✕"
        case .unavailable: symbol = "bolt.slash"; fallback = "⚡︎✕"
        }
        guard let button = statusItem.button else { return }
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = fallback
        }
    }

    @objc private func reconnect() {
        client.start()
    }

    @objc private func toggleLock() {
        panel.isLocked.toggle()
    }

    @objc private func togglePanelVisible() {
        let settings = AppSettings()
        let next = !settings.panelVisible
        settings.panelVisible = next
        if next {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
        buildMenu()
    }

    @objc private func setPinOff() {
        panel.pinnedCorner = nil
        buildMenu()
    }

    @objc private func setPinCorner(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let corner = PinnedCorner(rawValue: raw)
        else { return }
        panel.pinnedCorner = corner
        buildMenu()
    }

    @objc private func setDisplayMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = DisplayMode(rawValue: raw)
        else { return }
        panel.displayMode = mode
        buildMenu()
    }

    /// Persist the language preference and rebuild every visible surface
    /// immediately — no restart (FR-003 / FR-011).
    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let pref = LanguagePreference(rawValue: raw)
        else { return }
        let settings = AppSettings()
        settings.languagePreference = pref
        L10n.currentLanguage = settings.resolvedLanguage
        panel.applyLanguage()
        buildMenu()
    }

    @objc private func selectKeyboard(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        client.select(id)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func bleClient(_ client: BLEClient, didUpdate status: KeyboardStatus) {
        panel.update(status)
    }

    func bleClient(_ client: BLEClient, didChangeState newState: BLEConnectionState) {
        state = newState
        updateMenuBarIcon()
        if newState != .connected {
            panel.update(.disconnected)
            panel.markConnectivityStaleOnDisconnect()
        }
    }

    func bleClient(_ client: BLEClient, didChangeActiveKeyboard keyboard: CompatibleKeyboard?) {
        activeKeyboard = keyboard
        if keyboard != nil { unsupportedKeyboards = [] }
        statusItem.button?.toolTip = keyboard?.displayName
        buildMenu()
    }

    func bleClient(_ client: BLEClient, didUpdateCandidates keyboards: [CompatibleKeyboard]) {
        candidates = keyboards
        if !keyboards.isEmpty { unsupportedKeyboards = [] }
        buildMenu()
    }

    func bleClient(_ client: BLEClient, didDetectUnsupported keyboards: [CompatibleKeyboard]) {
        unsupportedKeyboards = keyboards
        statusItem.button?.toolTip = L10n.text("Tip_Unsupported")
        buildMenu()
    }

    func bleClient(_ client: BLEClient, didDetermineKBPMinor minor: KBPMinor) {
        // IV-X1 / U-5: hide the entire 1.1 card when the keyboard is KBP 1.0.
        switch minor {
        case .onePointZero, .unknown:
            panel.setConnectivityCardVisible(false)
        case .onePointOne:
            panel.setConnectivityCardVisible(true)
        }
    }

    func bleClient(_ client: BLEClient, didUpdateConnectivity status: ConnectivityStatus) {
        panel.update(connectivity: status)
    }

    func bleClient(_ client: BLEClient, didUpdateBattery status: BatteryStatus) {
        panel.update(battery: status)
    }
}
