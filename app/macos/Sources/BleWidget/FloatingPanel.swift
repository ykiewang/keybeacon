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
    private let connectivityCard: NSView = {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
        v.layer?.cornerRadius = 8
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    private let connectivityCardTitle = NSTextField(labelWithString: "连接与电量")

    private let hostDot: NSView = {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = 5
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    private let hostLabel = NSTextField(labelWithString: "")
    private let hostStaleLabel = NSTextField(labelWithString: "")
    private let hostRow = NSStackView()

    private let profileCaption = NSTextField(labelWithString: "Profile")
    private let profileSlotStack = NSStackView()
    private let profileStaleLabel = NSTextField(labelWithString: "")
    private let profileRow = NSStackView()
    private var profileBadges: [ProfileBadgeView] = []

    private let staleness = StalenessTracker()
    private var stalenessTimer: Timer?
    private var cachedConnectivity: ConnectivityStatus?

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
        buildConnectivityCard()

        // Compose rows into a vertical stack.
        let vstack = NSStackView(views: [topRow, connectivityCard])
        vstack.orientation = .vertical
        vstack.spacing = 6
        vstack.alignment = .leading
        vstack.translatesAutoresizingMaskIntoConstraints = false
        vstack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 10, right: 10)
        content.addSubview(vstack)

        NSLayoutConstraint.activate([
            vstack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            vstack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            vstack.topAnchor.constraint(equalTo: content.topAnchor),
            vstack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            connectivityCard.leadingAnchor.constraint(equalTo: vstack.leadingAnchor, constant: 10),
            connectivityCard.trailingAnchor.constraint(equalTo: vstack.trailingAnchor, constant: -10),
        ])

        contentView = content
        restorePosition()
        if !settings.hasPosition(screenID: screenID()) {
            setDefaultPosition()
        }
        reflowFrameToContent()
    }

    deinit {
        stalenessTimer?.invalidate()
    }

    private func buildConnectivityCard() {
        connectivityCardTitle.font = .systemFont(ofSize: 11, weight: .medium)
        connectivityCardTitle.textColor = NSColor.white.withAlphaComponent(0.72)
        connectivityCardTitle.translatesAutoresizingMaskIntoConstraints = false

        hostLabel.font = .systemFont(ofSize: 12, weight: .medium)
        hostLabel.textColor = .white
        hostLabel.translatesAutoresizingMaskIntoConstraints = false
        hostStaleLabel.font = .systemFont(ofSize: 10)
        hostStaleLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        hostStaleLabel.translatesAutoresizingMaskIntoConstraints = false
        hostStaleLabel.setContentHuggingPriority(.required, for: .horizontal)

        let hostSpacer = NSView()
        hostSpacer.translatesAutoresizingMaskIntoConstraints = false
        hostRow.orientation = .horizontal
        hostRow.spacing = 8
        hostRow.alignment = .centerY
        hostRow.translatesAutoresizingMaskIntoConstraints = false
        hostRow.addArrangedSubview(hostDot)
        hostRow.addArrangedSubview(hostLabel)
        hostRow.addArrangedSubview(hostSpacer)
        hostRow.addArrangedSubview(hostStaleLabel)
        hostRow.setHuggingPriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            hostDot.widthAnchor.constraint(equalToConstant: 10),
            hostDot.heightAnchor.constraint(equalToConstant: 10),
        ])

        profileCaption.font = .systemFont(ofSize: 11, weight: .regular)
        profileCaption.textColor = NSColor.white.withAlphaComponent(0.72)
        profileCaption.translatesAutoresizingMaskIntoConstraints = false
        profileSlotStack.orientation = .horizontal
        profileSlotStack.spacing = 4
        profileSlotStack.alignment = .centerY
        profileSlotStack.translatesAutoresizingMaskIntoConstraints = false
        profileStaleLabel.font = .systemFont(ofSize: 10)
        profileStaleLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        profileStaleLabel.translatesAutoresizingMaskIntoConstraints = false

        let profileSpacer = NSView()
        profileSpacer.translatesAutoresizingMaskIntoConstraints = false
        profileRow.orientation = .horizontal
        profileRow.spacing = 8
        profileRow.alignment = .centerY
        profileRow.translatesAutoresizingMaskIntoConstraints = false
        profileRow.addArrangedSubview(profileCaption)
        profileRow.addArrangedSubview(profileSlotStack)
        profileRow.addArrangedSubview(profileSpacer)
        profileRow.addArrangedSubview(profileStaleLabel)

        hostRow.isHidden = true
        profileRow.isHidden = true

        let cardStack = NSStackView(views: [connectivityCardTitle, hostRow, profileRow])
        cardStack.orientation = .vertical
        cardStack.alignment = .leading
        cardStack.spacing = 4
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        connectivityCard.addSubview(cardStack)

        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: connectivityCard.topAnchor, constant: 6),
            cardStack.leadingAnchor.constraint(equalTo: connectivityCard.leadingAnchor, constant: 10),
            cardStack.trailingAnchor.constraint(equalTo: connectivityCard.trailingAnchor, constant: -10),
            cardStack.bottomAnchor.constraint(equalTo: connectivityCard.bottomAnchor, constant: -6),
            hostRow.widthAnchor.constraint(equalTo: cardStack.widthAnchor),
            profileRow.widthAnchor.constraint(equalTo: cardStack.widthAnchor),
        ])

        connectivityCard.isHidden = true
    }

    // MARK: - KBP 1.1 card visibility (invariant IV-X1 / U-5)

    /// Show/hide the entire "Connectivity & Power" card based on whether the
    /// active keyboard declares KBP 1.1 (presence of `AA440AA2-…`).
    func setConnectivityCardVisible(_ visible: Bool) {
        connectivityCard.isHidden = !visible
        if visible {
            startStalenessTimer()
        } else {
            stopStalenessTimer()
            cachedConnectivity = nil
            staleness.reset()
            hostRow.isHidden = true
            profileRow.isHidden = true
        }
        reflowFrameToContent()
    }

    // MARK: - KBP 1.1 connectivity row updates (T023, T024)

    func update(connectivity status: ConnectivityStatus) {
        cachedConnectivity = status
        let now = CFAbsoluteTimeGetCurrent()
        if status.capability.hasHostConnection {
            staleness.recordNotify(fieldKey: "host_connection", at: now)
        }
        if status.capability.hasProfile {
            staleness.recordNotify(fieldKey: "profile", at: now)
        }
        renderConnectivity()
    }

    func markConnectivityStaleOnDisconnect() {
        staleness.forceStaleAll()
        renderConnectivity()
    }

    private func renderConnectivity() {
        let now = CFAbsoluteTimeGetCurrent()
        guard let s = cachedConnectivity else {
            hostRow.isHidden = true
            profileRow.isHidden = true
            reflowFrameToContent()
            return
        }
        renderHostRow(status: s, now: now)
        renderProfileRow(status: s, now: now)
        reflowFrameToContent()
    }

    private func renderHostRow(status s: ConnectivityStatus, now: TimeInterval) {
        guard s.capability.hasHostConnection else {
            hostRow.isHidden = true
            return
        }
        hostRow.isHidden = false
        let connected = s.link.connected
        let dotColor: NSColor = connected ? .systemGreen : .systemGray
        hostDot.layer?.backgroundColor = dotColor.cgColor
        var text = connected ? "已连接" : "未连接"
        if !connected {
            switch s.link.lastDisconnectReason {
            case .timeout:  text += "(超时)"
            case .explicit: text += "(主动断开)"
            case .unknown, .reserved: break
            }
        }
        hostLabel.stringValue = text
        let isStale = staleness.isStale(fieldKey: "host_connection", now: now)
        hostDot.alphaValue = isStale ? 0.5 : 1.0
        hostLabel.alphaValue = isStale ? 0.5 : 1.0
        if isStale, let last = staleness.lastNotifyAt(fieldKey: "host_connection") {
            hostStaleLabel.isHidden = false
            hostStaleLabel.stringValue = "最后更新 \(Self.formatTimestamp(monotonic: last, now: now))"
        } else {
            hostStaleLabel.isHidden = true
            hostStaleLabel.stringValue = ""
        }
    }

    private func renderProfileRow(status s: ConnectivityStatus, now: TimeInterval) {
        guard s.capability.hasProfile else {
            profileRow.isHidden = true
            return
        }
        profileRow.isHidden = false
        let slotCount = max(1, Int(s.profile.maxSlots))
        rebuildProfileBadgesIfNeeded(count: slotCount)
        let maxSlot = max(1, s.profile.maxSlots)
        let clampedIndex: UInt8 = {
            let raw = s.profile.index
            if raw == 0 { return 0 }
            return min(raw, maxSlot)
        }()
        for (i, badge) in profileBadges.enumerated() {
            let slotIndex = UInt8(i + 1)
            let isCurrent = slotIndex == clampedIndex
            let isOpen = s.profile.isOpen && isCurrent
            badge.apply(slotIndex: slotIndex, isCurrent: isCurrent, isOpen: isOpen)
        }
        let isStale = staleness.isStale(fieldKey: "profile", now: now)
        profileCaption.alphaValue = isStale ? 0.5 : 1.0
        for badge in profileBadges { badge.alphaValue = isStale ? 0.5 : 1.0 }
        if isStale, let last = staleness.lastNotifyAt(fieldKey: "profile") {
            profileStaleLabel.isHidden = false
            profileStaleLabel.stringValue = "最后更新 \(Self.formatTimestamp(monotonic: last, now: now))"
        } else {
            profileStaleLabel.isHidden = true
            profileStaleLabel.stringValue = ""
        }
    }

    private func rebuildProfileBadgesIfNeeded(count: Int) {
        guard profileBadges.count != count else { return }
        for badge in profileBadges {
            profileSlotStack.removeArrangedSubview(badge)
            badge.removeFromSuperview()
        }
        profileBadges = (0..<count).map { _ in ProfileBadgeView() }
        for badge in profileBadges {
            profileSlotStack.addArrangedSubview(badge)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func formatTimestamp(monotonic: TimeInterval, now: TimeInterval) -> String {
        let delta = max(0, now - monotonic)
        let wallDate = Date().addingTimeInterval(-delta)
        return timeFormatter.string(from: wallDate)
    }

    private func startStalenessTimer() {
        stopStalenessTimer()
        stalenessTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0, repeats: true
        ) { [weak self] _ in
            self?.renderConnectivity()
        }
    }

    private func stopStalenessTimer() {
        stalenessTimer?.invalidate()
        stalenessTimer = nil
    }

    private func reflowFrameToContent() {
        contentView?.layoutSubtreeIfNeeded()
        let desiredHeight: CGFloat
        if connectivityCard.isHidden {
            desiredHeight = baseContentHeight + 10
        } else {
            let cardHeight = max(24, connectivityCard.fittingSize.height)
            desiredHeight = baseContentHeight + cardHeight + 6 + 10
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

fileprivate final class ProfileBadgeView: NSView {
    private let indexLabel = NSTextField(labelWithString: "")
    private let pendingHint = NSTextField(labelWithString: "⋯")
    private var dashedLayer: CAShapeLayer?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9
        translatesAutoresizingMaskIntoConstraints = false

        indexLabel.alignment = .center
        indexLabel.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        indexLabel.textColor = .white
        indexLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(indexLabel)

        pendingHint.font = .systemFont(ofSize: 8, weight: .bold)
        pendingHint.textColor = .systemYellow
        pendingHint.toolTip = "待配对"
        pendingHint.setAccessibilityLabel("待配对")
        pendingHint.isHidden = true
        pendingHint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pendingHint)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 18),
            heightAnchor.constraint(equalToConstant: 18),
            indexLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            indexLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            pendingHint.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 3),
            pendingHint.topAnchor.constraint(equalTo: topAnchor, constant: -5),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(slotIndex: UInt8, isCurrent: Bool, isOpen: Bool) {
        indexLabel.stringValue = "\(slotIndex)"
        pendingHint.isHidden = !isOpen
        if isCurrent {
            layer?.borderWidth = 2
            layer?.borderColor = NSColor.white.cgColor
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
            indexLabel.textColor = .white
        } else {
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.white.withAlphaComponent(0.45).cgColor
            layer?.backgroundColor = NSColor.clear.cgColor
            indexLabel.textColor = NSColor.white.withAlphaComponent(0.65)
        }
        if isOpen {
            installDashedBorder()
        } else {
            removeDashedBorder()
        }
    }

    override func layout() {
        super.layout()
        guard let dashed = dashedLayer else { return }
        dashed.frame = bounds
        dashed.path = CGPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            cornerWidth: 9, cornerHeight: 9, transform: nil
        )
    }

    private func installDashedBorder() {
        if dashedLayer == nil {
            let shape = CAShapeLayer()
            shape.fillColor = NSColor.clear.cgColor
            shape.strokeColor = NSColor.systemYellow.cgColor
            shape.lineWidth = 1.5
            shape.lineDashPattern = [3, 2]
            layer?.addSublayer(shape)
            dashedLayer = shape
        }
        layer?.borderColor = NSColor.clear.cgColor
        needsLayout = true
    }

    private func removeDashedBorder() {
        dashedLayer?.removeFromSuperlayer()
        dashedLayer = nil
    }
}
