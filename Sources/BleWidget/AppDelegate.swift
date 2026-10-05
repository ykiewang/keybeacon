// Copyright (c) 2026 The TOTEM ZMK Contributors
// SPDX-License-Identifier: MIT

import AppKit
import BleWidgetCore

final class AppDelegate: NSObject, NSApplicationDelegate, BLEClientDelegate {
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private let client = BLEClient()
    private var state: BLEConnectionState = .connecting

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    private func updateMenuBarIcon() {
        let symbol: String
        switch state {
        case .connected: symbol = "keyboard"
        case .connecting: symbol = "keyboard.badge.ellipsis"
        case .notConnected: symbol = "keyboard.slash"
        case .unavailable: symbol = "bolt.slash"
        }
        statusItem.button?.image = NSImage(
            systemSymbolName: symbol, accessibilityDescription: nil
        )
    }

    @objc private func reconnect() {
        client.start()
    }

    @objc private func toggleLock() {
        panel.isLocked.toggle()
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
}
