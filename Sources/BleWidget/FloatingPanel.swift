// Copyright (c) 2026 The TOTEM ZMK Contributors
// SPDX-License-Identifier: MIT

import AppKit
import BleWidgetCore

final class FloatingPanel: NSPanel {
    private static let posKeyPrefix = "totemPanelFrame"
    private static let lockKey = "totemPanelLocked"

    private let layerLabel = NSTextField(labelWithString: "")
    private let modLabels: [NSTextField] = ["⇧", "⌃", "⌥", "⌘"].map {
        NSTextField(labelWithString: $0)
    }

    var isLocked: Bool {
        get { UserDefaults.standard.bool(forKey: Self.lockKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.lockKey)
            ignoresMouseEvents = newValue
        }
    }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        ignoresMouseEvents = isLocked

        let content = NSView(frame: contentRect(forFrameRect: frame))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        content.layer?.cornerRadius = 12

        layerLabel.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
        layerLabel.textColor = .white
        layerLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(layerLabel)

        let stack = NSStackView(views: modLabels)
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        for label in modLabels {
            label.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
            label.textColor = .gray
        }

        NSLayoutConstraint.activate([
            layerLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            layerLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])

        contentView = content
        restorePosition()
        if UserDefaults.standard.object(forKey: positionKey()) == nil {
            setDefaultPosition()
        }
    }

    private func positionKey() -> String {
        let screenID = NSScreen.main?.localizedName ?? "default"
        return "\(Self.posKeyPrefix).\(screenID)"
    }

    private func restorePosition() {
        if let saved = UserDefaults.standard.string(forKey: positionKey()) {
            let parts = saved.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 {
                setFrameOrigin(NSPoint(x: parts[0], y: parts[1]))
                clampToVisibleBounds()
                return
            }
        }
    }

    private func setDefaultPosition() {
        guard let screen = NSScreen.main else { return }
        let margin: CGFloat = 20
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.maxX - frame.width - margin,
            y: visible.maxY - frame.height - margin
        )
        setFrameOrigin(origin)
        savePosition()
    }

    private func clampToVisibleBounds() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        var origin = frame.origin
        origin.x = min(max(origin.x, visible.minX), visible.maxX - frame.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - frame.height)
        setFrameOrigin(origin)
    }

    override var canBecomeKey: Bool { false }

    func savePosition() {
        let p = frame.origin
        UserDefaults.standard.set("\(p.x),\(p.y)", forKey: positionKey())
    }

    override func mouseUp(with event: NSEvent) {
        savePosition()
    }

    func update(_ status: KeyboardStatus) {
        layerLabel.stringValue = status.connected ? status.layerName : "未连接"
        let active = [
            status.shiftActive, status.controlActive,
            status.optionActive, status.commandActive,
        ]
        for (label, on) in zip(modLabels, active) {
            label.textColor = on ? .white : .gray
        }
    }
}
