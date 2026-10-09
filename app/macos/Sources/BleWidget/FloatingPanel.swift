// Copyright (c) 2026 The TOTEM ZMK Contributors
// SPDX-License-Identifier: MIT

import AppKit
import BleWidgetCore

final class FloatingPanel: NSPanel {
    private let settings = AppSettings()

    private let layerLabel = NSTextField(labelWithString: "")
    private let modLabels: [NSTextField] = ["⇧", "⌃", "⌥", "⌘"].map {
        NSTextField(labelWithString: $0)
    }

    // KBP 1.1 "Connectivity & Power" card. Hidden by default; shown when the
    // active keyboard exposes `AA440AA2-…` (per contracts/macos-ui.md §1.1).
    // Inner rows are populated by the US phases (US1-US4); this task only
    // wires up the shell + visibility hook.
    private let connectivityCard: NSView = {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
        v.layer?.cornerRadius = 8
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    private let connectivityCardTitle = NSTextField(labelWithString: "连接与电量")
    private var connectivityCardHeightConstraint: NSLayoutConstraint!
    private let connectivityCardCollapsedHeight: CGFloat = 0
    private let connectivityCardExpandedHeight: CGFloat = 72  // reserved for US-phase rows

    private let baseContentHeight: CGFloat = 44

    var isLocked: Bool {
        get { settings.locked }
        set {
            settings.locked = newValue
            ignoresMouseEvents = newValue
        }
    }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 44),
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
        content.translatesAutoresizingMaskIntoConstraints = false

        // Row 1 — layer + modifiers (unchanged KBP 1.0 behaviour).
        let topRow = NSView()
        topRow.translatesAutoresizingMaskIntoConstraints = false

        layerLabel.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
        layerLabel.textColor = .white
        layerLabel.translatesAutoresizingMaskIntoConstraints = false
        topRow.addSubview(layerLabel)

        let stack = NSStackView(views: modLabels)
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        topRow.addSubview(stack)
        for label in modLabels {
            label.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
            label.textColor = .gray
        }

        NSLayoutConstraint.activate([
            layerLabel.leadingAnchor.constraint(equalTo: topRow.leadingAnchor, constant: 14),
            layerLabel.centerYAnchor.constraint(equalTo: topRow.centerYAnchor),
            stack.trailingAnchor.constraint(equalTo: topRow.trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: topRow.centerYAnchor),
            topRow.heightAnchor.constraint(equalToConstant: baseContentHeight),
        ])

        // Row 2 — Connectivity & Power card (hidden by default).
        connectivityCardTitle.font = .systemFont(ofSize: 11, weight: .medium)
        connectivityCardTitle.textColor = NSColor.white.withAlphaComponent(0.72)
        connectivityCardTitle.translatesAutoresizingMaskIntoConstraints = false
        connectivityCard.addSubview(connectivityCardTitle)

        connectivityCardHeightConstraint = connectivityCard.heightAnchor
            .constraint(equalToConstant: connectivityCardCollapsedHeight)
        connectivityCard.isHidden = true

        NSLayoutConstraint.activate([
            connectivityCardTitle.leadingAnchor.constraint(
                equalTo: connectivityCard.leadingAnchor, constant: 10
            ),
            connectivityCardTitle.topAnchor.constraint(
                equalTo: connectivityCard.topAnchor, constant: 8
            ),
            connectivityCardHeightConstraint,
        ])

        // Compose rows into a vertical stack.
        let vstack = NSStackView(views: [topRow, connectivityCard])
        vstack.orientation = .vertical
        vstack.spacing = 6
        vstack.translatesAutoresizingMaskIntoConstraints = false
        vstack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 10, right: 10)
        content.addSubview(vstack)

        NSLayoutConstraint.activate([
            vstack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            vstack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            vstack.topAnchor.constraint(equalTo: content.topAnchor),
            vstack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        contentView = content
        restorePosition()
        if !settings.hasPosition(screenID: screenID()) {
            setDefaultPosition()
        }
        reflowFrameToContent()
    }

    // MARK: - KBP 1.1 card visibility (invariant IV-X1 / U-5)

    /// Show/hide the entire "Connectivity & Power" card based on whether the
    /// active keyboard declares KBP 1.1 (presence of `AA440AA2-…`).
    ///
    /// Called by `AppDelegate` on `didDetermineKBPMinor(_:)`. Row contents are
    /// filled in by the US-phase tasks (T023/T024/T029/T030/T034/T038); this
    /// method only toggles the shell visibility and resizes the panel.
    func setConnectivityCardVisible(_ visible: Bool) {
        connectivityCard.isHidden = !visible
        connectivityCardHeightConstraint.constant = visible
            ? connectivityCardExpandedHeight
            : connectivityCardCollapsedHeight
        reflowFrameToContent()
    }

    /// Reconstrain the window frame to the current content height so the
    /// visual chrome matches the row count. Preserves the top-left origin so
    /// user-placed panels do not jump.
    private func reflowFrameToContent() {
        contentView?.layoutSubtreeIfNeeded()
        let desiredHeight: CGFloat
        if connectivityCard.isHidden {
            desiredHeight = baseContentHeight + 10
        } else {
            desiredHeight = baseContentHeight + connectivityCardExpandedHeight + 6 + 10
        }
        let currentOrigin = frame.origin
        let topLeft = NSPoint(x: currentOrigin.x,
                              y: currentOrigin.y + frame.height - desiredHeight)
        let newFrame = NSRect(x: topLeft.x, y: topLeft.y,
                              width: frame.width, height: desiredHeight)
        setFrame(newFrame, display: true, animate: false)
        clampToVisibleBounds()
    }

    private func screenID() -> String {
        NSScreen.main?.localizedName ?? "default"
    }

    private func restorePosition() {
        if let saved = settings.position(screenID: screenID()) {
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
        settings.setPosition("\(p.x),\(p.y)", screenID: screenID())
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
