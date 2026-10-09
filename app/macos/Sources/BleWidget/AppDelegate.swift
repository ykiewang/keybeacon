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

        panel = FloatingPanel()
        panel.orderFrontRegardless()

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
            headerTitle = "⚠︎ 不受支持的键盘协议版本"
        } else {
            headerTitle = "未连接键盘"
        }
        let header = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if activeKeyboard == nil, !unsupportedKeyboards.isEmpty {
            let names = unsupportedKeyboards.map { $0.displayName }.joined(separator: ", ")
            let info = NSMenuItem(
                title: "检测到较新的 KeyBeacon 协议(\(names));请升级本应用后使用。",
                action: nil, keyEquivalent: ""
            )
            info.isEnabled = false
            menu.addItem(info)
        }
        menu.addItem(.separator())

        let chooser = NSMenuItem(title: "键盘", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        if candidates.isEmpty {
            let none = NSMenuItem(title: "无可用键盘", action: nil, keyEquivalent: "")
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
            NSMenuItem(title: "重连", action: #selector(reconnect), keyEquivalent: "r")
        )
        menu.addItem(
            NSMenuItem(
                title: "锁定 / 穿透",
                action: #selector(toggleLock), keyEquivalent: "l"
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
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
        statusItem.button?.toolTip = "检测到不受支持的 KeyBeacon 协议版本;请升级本应用。"
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
        // Row contents are rendered by US-phase task T030. Foundational only wires.
        _ = status
    }
}
