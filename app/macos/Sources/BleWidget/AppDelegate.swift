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
        let header = NSMenuItem(
            title: activeKeyboard?.displayName ?? "未连接键盘",
            action: nil, keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)
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
        }
    }

    func bleClient(_ client: BLEClient, didChangeActiveKeyboard keyboard: CompatibleKeyboard?) {
        activeKeyboard = keyboard
        statusItem.button?.toolTip = keyboard?.displayName
        buildMenu()
    }

    func bleClient(_ client: BLEClient, didUpdateCandidates keyboards: [CompatibleKeyboard]) {
        candidates = keyboards
        buildMenu()
    }
}
