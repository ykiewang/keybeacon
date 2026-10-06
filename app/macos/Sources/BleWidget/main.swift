// Copyright (c) 2026 The TOTEM ZMK Contributors
// SPDX-License-Identifier: MIT

import AppKit

// Minimum-macOS guard: LSMinimumSystemVersion keeps the Finder from launching us
// on < 12, but a direct exec (or future loosened plist) could still start here.
// Fail with a clear, user-visible message instead of crashing on a missing API.
private func requireMinimumMacOS() {
    let required = OperatingSystemVersion(majorVersion: 12, minorVersion: 0, patchVersion: 0)
    if ProcessInfo.processInfo.isOperatingSystemAtLeast(required) { return }

    let current = ProcessInfo.processInfo.operatingSystemVersionString
    let message = "KeyBeacon (BleWidget) requires macOS 12 (Monterey) or later.\n"
        + "This Mac is running \(current). Please update macOS to use this app."
    FileHandle.standardError.write(Data((message + "\n").utf8))

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = "Unsupported macOS version"
    alert.informativeText = message
    alert.addButton(withTitle: "Quit")
    alert.runModal()
    exit(1)
}

requireMinimumMacOS()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
