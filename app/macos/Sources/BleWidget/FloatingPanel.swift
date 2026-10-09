// Copyright (c) 2026 The TOTEM ZMK Contributors
// SPDX-License-Identifier: MIT

import AppKit
import BleWidgetCore

// UI toggle: when `false`, the "last-updated HH:mm:ss" captions in both
// the FloatingPanel stale labels and the BatteryBarView frozen percent
// readout are suppressed. All staleness logic (alpha dim, frozen battery
// fill, isStale checks, DiagnosticsLogger entries) still runs.
// Flip to `true` to restore the on-screen timestamps for debugging.
fileprivate let showStaleTimestamps = false

final class FloatingPanel: NSPanel {
    private let settings = AppSettings()

    private let topRow = NSView()
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

    private let splitLeftDot = FloatingPanel.makeDot(diameter: 9)
    private let splitLeftLabel = NSTextField(labelWithString: "左 —")
    private let splitRightDot = FloatingPanel.makeDot(diameter: 9)
    private let splitRightLabel = NSTextField(labelWithString: "右 —")
    private let splitStaleLabel = NSTextField(labelWithString: "")
    private let splitRow = NSStackView()

    private let batteryCaption = NSTextField(labelWithString: "电量")
    private let batteryBarsStack = NSStackView()
    private let batteryStaleLabel = NSTextField(labelWithString: "")
    private let batteryRow = NSStackView()
    private var batteryOverallBar: BatteryBarView?
    private var batteryLeftBar: BatteryBarView?
    private var batteryRightBar: BatteryBarView?
    private var cachedBatteryStatus: BatteryStatus?
    private var cachedLeftReading: BatteryStatus.BatteryReading?
    private var cachedLeftReadingAt: TimeInterval?
    private var cachedRightReading: BatteryStatus.BatteryReading?
    private var cachedRightReadingAt: TimeInterval?
    private var cachedOverallReading: BatteryStatus.BatteryReading?
    private var cachedOverallReadingAt: TimeInterval?

    private let endpointLabel = NSTextField(labelWithString: "输出:—")
    private let endpointStaleLabel = NSTextField(labelWithString: "")
    private let endpointRow = NSStackView()

    // MARK: - Compact (single-row) mode subviews
    //
    // When `displayMode == .compact`, `compactRow` replaces both `topRow`
    // and `connectivityCard`, packing everything into one horizontal strip:
    //   "L1 ⇧⌃⌥⌘ │ ● P1 │ ●L85 ●R72 │ USB"
    // Each sub-segment hides itself when its capability bit is 0 or when the
    // keyboard is KBP 1.0 (no AA2). The segments share state with the full
    // mode via the same cached* vars + staleness tracker; both layouts are
    // kept up to date on every render so switching modes is instant.

    private let compactRow = NSStackView()
    private let compactLayerLabel = NSTextField(labelWithString: "")
    private let compactModLabels: [NSTextField] = ["⇧", "⌃", "⌥", "⌘"].map {
        NSTextField(labelWithString: $0)
    }
    private let compactSep1 = NSTextField(labelWithString: "│")
    private let compactHostDot = FloatingPanel.makeDot(diameter: 8)
    private let compactProfileLabel = NSTextField(labelWithString: "P—")
    private let compactSep2 = NSTextField(labelWithString: "│")
    private let compactSplitLeftDot = FloatingPanel.makeDot(diameter: 7)
    private let compactLeftBattLabel = NSTextField(labelWithString: "L—")
    private let compactSplitRightDot = FloatingPanel.makeDot(diameter: 7)
    private let compactRightBattLabel = NSTextField(labelWithString: "R—")
    private let compactSep3 = NSTextField(labelWithString: "│")
    private let compactEndpointLabel = NSTextField(labelWithString: "—")
    private let compactChargingLeftIcon = NSTextField(labelWithString: "⚡︎")
    private let compactChargingRightIcon = NSTextField(labelWithString: "⚡︎")

    // Sub-stacks that group related items so we can hide a whole segment
    // (host+profile, split, battery, endpoint) atomically.
    private let compactHostSegment = NSStackView()
    private let compactProfileSegment = NSStackView()
    private let compactSplitSegment = NSStackView()
    private let compactEndpointSegment = NSStackView()

    private let staleness = StalenessTracker()
    private var stalenessTimer: Timer?
    private var cachedConnectivity: ConnectivityStatus?

    /// Outer vertical stack that holds `topRow`, `connectivityCard` and
    /// `compactRow` (whichever are currently visible per `displayMode`).
    /// Held as a property so `applyDisplayMode()` can retune its edgeInsets
    /// per layout (full: top=0 to anchor the already-tall topRow; compact:
    /// symmetric top+bottom so the single line is vertically centred).
    private let vstack = NSStackView()

    /// Last known staleness state per field_key — used only to emit a log
    /// line on each live↔stale transition (not for rendering).
    private var lastStaleStates: [String: Bool] = [:]

    private let baseContentHeight: CGFloat = 44

    private static func makeDot(diameter: CGFloat) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = diameter / 2
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: diameter),
            v.heightAnchor.constraint(equalToConstant: diameter),
        ])
        return v
    }

    var isLocked: Bool {
        get { settings.locked }
        set {
            settings.locked = newValue
            ignoresMouseEvents = newValue
        }
    }

    /// Pinned corner. When non-nil, the panel is anchored to the given corner
    /// of its *current* screen (determined by physical position), ignoring any
    /// saved absolute coordinates. When nil, the panel remembers absolute
    /// coordinates per screen.
    var pinnedCorner: PinnedCorner? {
        get { settings.pinnedCorner }
        set {
            settings.pinnedCorner = newValue
            if newValue != nil {
                applyPinnedCorner()
            }
        }
    }

    /// Current layout mode. Setter re-flows the frame + repaints both layouts
    /// so the switch is instant.
    var displayMode: DisplayMode {
        get { settings.displayMode }
        set {
            settings.displayMode = newValue
            applyDisplayMode()
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

        // Alternative single-row (compact) layout. Added separately below
        // (not as a vstack arrangedSubview) so it can be vertically centred
        // inside `content` independently of the full-mode vstack. (NSStackView
        // with distribution .gravityAreas pins a lone arranged subview to
        // the top edge even with symmetric edgeInsets.)
        buildCompactRow()

        // Compose full-mode rows into a vertical stack. compactRow is NOT
        // part of this stack; see note above.
        for v in [topRow, connectivityCard] {
            vstack.addArrangedSubview(v)
        }
        vstack.orientation = .vertical
        vstack.spacing = 6
        vstack.alignment = .leading
        vstack.translatesAutoresizingMaskIntoConstraints = false
        vstack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 10, right: 10)
        content.addSubview(vstack)
        content.addSubview(compactRow)

        NSLayoutConstraint.activate([
            vstack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            vstack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            vstack.topAnchor.constraint(equalTo: content.topAnchor),
            vstack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            connectivityCard.leadingAnchor.constraint(equalTo: vstack.leadingAnchor, constant: 10),
            connectivityCard.trailingAnchor.constraint(equalTo: vstack.trailingAnchor, constant: -10),
            // compactRow: horizontally centred inside content, with min 10 pt
            // breathing room on each side. The strict leading-equality we had
            // before pinned the row flush-left so any extra width that
            // reflowFrameToContent reserved (rowWidth + 24 vs rowWidth + 20)
            // leaked onto the right side, which read as "data偏左".
            compactRow.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 10),
            compactRow.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -10),
            compactRow.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            compactRow.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])

        contentView = content
        applyDisplayMode()
        if settings.pinnedCorner != nil {
            applyPinnedCorner()
        } else {
            restorePosition()
            if !settings.hasPosition(screenID: screenID()) {
                setDefaultPosition()
            }
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

        buildSplitRow()
        buildBatteryRow()
        buildEndpointRow()
        splitRow.isHidden = true
        batteryRow.isHidden = true
        endpointRow.isHidden = true

        let cardStack = NSStackView(views: [
            connectivityCardTitle, hostRow, profileRow, splitRow, batteryRow, endpointRow,
        ])
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
            splitRow.widthAnchor.constraint(equalTo: cardStack.widthAnchor),
            batteryRow.widthAnchor.constraint(equalTo: cardStack.widthAnchor),
            endpointRow.widthAnchor.constraint(equalTo: cardStack.widthAnchor),
        ])

        connectivityCard.isHidden = true
    }

    private func buildSplitRow() {
        splitLeftLabel.font = .systemFont(ofSize: 11, weight: .medium)
        splitLeftLabel.textColor = .white
        splitLeftLabel.translatesAutoresizingMaskIntoConstraints = false
        splitRightLabel.font = .systemFont(ofSize: 11, weight: .medium)
        splitRightLabel.textColor = .white
        splitRightLabel.translatesAutoresizingMaskIntoConstraints = false
        splitStaleLabel.font = .systemFont(ofSize: 10)
        splitStaleLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        splitStaleLabel.translatesAutoresizingMaskIntoConstraints = false

        let leftSide = NSStackView(views: [splitLeftDot, splitLeftLabel])
        leftSide.orientation = .horizontal
        leftSide.spacing = 4
        leftSide.alignment = .centerY
        leftSide.translatesAutoresizingMaskIntoConstraints = false

        let rightSide = NSStackView(views: [splitRightDot, splitRightLabel])
        rightSide.orientation = .horizontal
        rightSide.spacing = 4
        rightSide.alignment = .centerY
        rightSide.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        splitRow.orientation = .horizontal
        splitRow.spacing = 12
        splitRow.alignment = .centerY
        splitRow.translatesAutoresizingMaskIntoConstraints = false
        splitRow.addArrangedSubview(leftSide)
        splitRow.addArrangedSubview(rightSide)
        splitRow.addArrangedSubview(spacer)
        splitRow.addArrangedSubview(splitStaleLabel)
    }

    private func buildBatteryRow() {
        batteryCaption.font = .systemFont(ofSize: 11, weight: .regular)
        batteryCaption.textColor = NSColor.white.withAlphaComponent(0.72)
        batteryCaption.translatesAutoresizingMaskIntoConstraints = false
        batteryBarsStack.orientation = .horizontal
        batteryBarsStack.spacing = 8
        batteryBarsStack.alignment = .centerY
        batteryBarsStack.translatesAutoresizingMaskIntoConstraints = false
        batteryStaleLabel.font = .systemFont(ofSize: 10)
        batteryStaleLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        batteryStaleLabel.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        batteryRow.orientation = .horizontal
        batteryRow.spacing = 8
        batteryRow.alignment = .centerY
        batteryRow.translatesAutoresizingMaskIntoConstraints = false
        batteryRow.addArrangedSubview(batteryCaption)
        batteryRow.addArrangedSubview(batteryBarsStack)
        batteryRow.addArrangedSubview(spacer)
        batteryRow.addArrangedSubview(batteryStaleLabel)
    }

    private func buildEndpointRow() {
        endpointLabel.font = .systemFont(ofSize: 12, weight: .medium)
        endpointLabel.textColor = .white
        endpointLabel.translatesAutoresizingMaskIntoConstraints = false
        endpointStaleLabel.font = .systemFont(ofSize: 10)
        endpointStaleLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        endpointStaleLabel.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        endpointRow.orientation = .horizontal
        endpointRow.spacing = 8
        endpointRow.alignment = .centerY
        endpointRow.translatesAutoresizingMaskIntoConstraints = false
        endpointRow.addArrangedSubview(endpointLabel)
        endpointRow.addArrangedSubview(spacer)
        endpointRow.addArrangedSubview(endpointStaleLabel)
    }

    // MARK: - Compact single-row layout (displayMode == .compact)

    private func buildCompactRow() {
        // Layer label (compact) — monospaced bold.
        compactLayerLabel.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        compactLayerLabel.textColor = .white
        compactLayerLabel.translatesAutoresizingMaskIntoConstraints = false

        // Modifier labels (⇧⌃⌥⌘).
        let modStack = NSStackView(views: compactModLabels)
        modStack.orientation = .horizontal
        modStack.spacing = 3
        modStack.translatesAutoresizingMaskIntoConstraints = false
        for label in compactModLabels {
            label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            label.textColor = .gray
        }

        // Separators '│' — faint grey.
        for sep in [compactSep1, compactSep2, compactSep3] {
            sep.font = .systemFont(ofSize: 12, weight: .regular)
            sep.textColor = NSColor.white.withAlphaComponent(0.35)
            sep.translatesAutoresizingMaskIntoConstraints = false
        }

        // Host segment: dot + "P1".
        compactProfileLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        compactProfileLabel.textColor = .white
        compactProfileLabel.translatesAutoresizingMaskIntoConstraints = false
        compactHostSegment.orientation = .horizontal
        compactHostSegment.spacing = 4
        compactHostSegment.alignment = .centerY
        compactHostSegment.translatesAutoresizingMaskIntoConstraints = false
        compactHostSegment.addArrangedSubview(compactHostDot)
        compactHostSegment.addArrangedSubview(compactProfileLabel)

        // Split segment: ●L85 ●R72 (with charging ⚡ overlays).
        compactLeftBattLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        compactLeftBattLabel.textColor = .white
        compactLeftBattLabel.translatesAutoresizingMaskIntoConstraints = false
        compactRightBattLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        compactRightBattLabel.textColor = .white
        compactRightBattLabel.translatesAutoresizingMaskIntoConstraints = false
        for icon in [compactChargingLeftIcon, compactChargingRightIcon] {
            icon.font = .systemFont(ofSize: 10, weight: .bold)
            icon.textColor = .systemYellow
            icon.toolTip = "充电中"
            icon.setAccessibilityLabel("充电中")
            icon.isHidden = true
            icon.translatesAutoresizingMaskIntoConstraints = false
        }
        let leftGroup = NSStackView(views: [compactSplitLeftDot, compactLeftBattLabel, compactChargingLeftIcon])
        leftGroup.orientation = .horizontal
        leftGroup.spacing = 3
        leftGroup.alignment = .centerY
        leftGroup.translatesAutoresizingMaskIntoConstraints = false
        let rightGroup = NSStackView(views: [compactSplitRightDot, compactRightBattLabel, compactChargingRightIcon])
        rightGroup.orientation = .horizontal
        rightGroup.spacing = 3
        rightGroup.alignment = .centerY
        rightGroup.translatesAutoresizingMaskIntoConstraints = false
        compactSplitSegment.orientation = .horizontal
        compactSplitSegment.spacing = 8
        compactSplitSegment.alignment = .centerY
        compactSplitSegment.translatesAutoresizingMaskIntoConstraints = false
        compactSplitSegment.addArrangedSubview(leftGroup)
        compactSplitSegment.addArrangedSubview(rightGroup)

        // Endpoint segment.
        compactEndpointLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        compactEndpointLabel.textColor = .white
        compactEndpointLabel.translatesAutoresizingMaskIntoConstraints = false
        compactEndpointSegment.orientation = .horizontal
        compactEndpointSegment.spacing = 4
        compactEndpointSegment.alignment = .centerY
        compactEndpointSegment.translatesAutoresizingMaskIntoConstraints = false
        compactEndpointSegment.addArrangedSubview(compactEndpointLabel)

        // Final row assembly.
        compactRow.orientation = .horizontal
        compactRow.spacing = 8
        compactRow.alignment = .centerY
        compactRow.translatesAutoresizingMaskIntoConstraints = false
        compactRow.addArrangedSubview(compactLayerLabel)
        compactRow.addArrangedSubview(modStack)
        compactRow.addArrangedSubview(compactSep1)
        compactRow.addArrangedSubview(compactHostSegment)
        compactRow.addArrangedSubview(compactSep2)
        compactRow.addArrangedSubview(compactSplitSegment)
        compactRow.addArrangedSubview(compactSep3)
        compactRow.addArrangedSubview(compactEndpointSegment)

        // All 1.1 segments start hidden; render* enables them per capability.
        compactSep1.isHidden = true
        compactHostSegment.isHidden = true
        compactSep2.isHidden = true
        compactSplitSegment.isHidden = true
        compactSep3.isHidden = true
        compactEndpointSegment.isHidden = true
        compactRow.isHidden = true
    }

    // MARK: - Display mode switching

    private func applyDisplayMode() {
        let mode = settings.displayMode
        switch mode {
        case .full:
            topRow.isHidden = false
            // connectivityCard visibility is driven by setConnectivityCardVisible();
            // don't override it here.
            compactRow.isHidden = true
        case .compact:
            topRow.isHidden = true
            connectivityCard.isHidden = true
            compactRow.isHidden = false
        }
        // Re-render so the newly-visible layout picks up current data.
        renderConnectivity()
        reflowFrameToContent()
    }

    // MARK: - KBP 1.1 card visibility (invariant IV-X1 / U-5)

    /// Show/hide the entire "Connectivity & Power" card based on whether the
    /// active keyboard declares KBP 1.1 (presence of `AA440AA2-…`).
    /// In compact mode the card is always hidden; the compact row's 1.1
    /// segments are driven by `renderConnectivity` instead.
    func setConnectivityCardVisible(_ visible: Bool) {
        if settings.displayMode == .full {
            connectivityCard.isHidden = !visible
        } else {
            connectivityCard.isHidden = true
        }
        if visible {
            startStalenessTimer()
        } else {
            stopStalenessTimer()
            cachedConnectivity = nil
            staleness.reset()
            hostRow.isHidden = true
            profileRow.isHidden = true
            splitRow.isHidden = true
            batteryRow.isHidden = true
            endpointRow.isHidden = true
            // Compact segments too.
            compactSep1.isHidden = true
            compactHostSegment.isHidden = true
            compactSep2.isHidden = true
            compactSplitSegment.isHidden = true
            compactSep3.isHidden = true
            compactEndpointSegment.isHidden = true
            cachedBatteryStatus = nil
            cachedOverallReading = nil
            cachedOverallReadingAt = nil
            cachedLeftReading = nil
            cachedLeftReadingAt = nil
            cachedRightReading = nil
            cachedRightReadingAt = nil
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
        if status.capability.isSplit, status.capability.hasSplitLink {
            staleness.recordNotify(fieldKey: "split_link", at: now)
        }
        if status.capability.hasOutputEndpoint {
            staleness.recordNotify(fieldKey: "output_endpoint", at: now)
        }
        renderConnectivity()
    }

    func update(battery status: BatteryStatus) {
        cachedBatteryStatus = status
        let now = CFAbsoluteTimeGetCurrent()
        switch status.kind {
        case .overall(let reading):
            cachedOverallReading = reading
            cachedOverallReadingAt = now
            staleness.recordNotify(fieldKey: "overall_battery", at: now)
        case .split(let left, let right):
            cachedLeftReading = left
            cachedLeftReadingAt = now
            cachedRightReading = right
            cachedRightReadingAt = now
            staleness.recordNotify(fieldKey: "left_battery", at: now)
            staleness.recordNotify(fieldKey: "right_battery", at: now)
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
            splitRow.isHidden = true
            batteryRow.isHidden = true
            endpointRow.isHidden = true
            compactSep1.isHidden = true
            compactHostSegment.isHidden = true
            compactSep2.isHidden = true
            compactSplitSegment.isHidden = true
            compactSep3.isHidden = true
            compactEndpointSegment.isHidden = true
            reflowFrameToContent()
            return
        }
        renderHostRow(status: s, now: now)
        renderProfileRow(status: s, now: now)
        renderSplitRow(status: s, now: now)
        renderBatteryRow(status: s, now: now)
        renderEndpointRow(status: s, now: now)
        renderCompactSegments(status: s, now: now)
        reflowFrameToContent()
    }

    /// Mirror the full-mode render output into the compact single-row layout.
    /// Called at the tail of `renderConnectivity` so compact state stays
    /// current even while hidden (switching displayMode is instant).
    private func renderCompactSegments(status s: ConnectivityStatus, now: TimeInterval) {
        // Host dot + profile index — one visual segment.
        let hostVisible = s.capability.hasHostConnection || s.capability.hasProfile
        compactHostSegment.isHidden = !hostVisible
        compactSep1.isHidden = !hostVisible
        if s.capability.hasHostConnection {
            compactHostDot.isHidden = false
            let connected = s.link.connected
            compactHostDot.layer?.backgroundColor =
                (connected ? NSColor.systemGreen : NSColor.systemGray).cgColor
            let hostStale = isStaleTracked(fieldKey: "host_connection", now: now)
            compactHostDot.alphaValue = hostStale ? 0.5 : 1.0
        } else {
            compactHostDot.isHidden = true
        }
        if s.capability.hasProfile {
            compactProfileLabel.isHidden = false
            let maxSlot = max(1, s.profile.maxSlots)
            let idx: UInt8 = {
                let raw = s.profile.index
                if raw == 0 { return 0 }
                return min(raw, maxSlot)
            }()
            let suffix = s.profile.isOpen ? "⋯" : ""
            compactProfileLabel.stringValue = (idx == 0 ? "P—" : "P\(idx)") + suffix
            let profStale = isStaleTracked(fieldKey: "profile", now: now)
            compactProfileLabel.alphaValue = profStale ? 0.5 : 1.0
        } else {
            compactProfileLabel.isHidden = true
        }

        // Split + per-side battery segment.
        let splitVisible = s.capability.isSplit
        compactSplitSegment.isHidden = !splitVisible
        compactSep2.isHidden = !splitVisible
        if splitVisible {
            let leftOnline = s.capability.hasSplitLink ? s.splitFlags.leftOnline : true
            let rightOnline = s.capability.hasSplitLink ? s.splitFlags.rightOnline : true
            compactSplitLeftDot.layer?.backgroundColor =
                (leftOnline ? NSColor.systemGreen : NSColor.systemRed).cgColor
            compactSplitRightDot.layer?.backgroundColor =
                (rightOnline ? NSColor.systemGreen : NSColor.systemRed).cgColor
            compactLeftBattLabel.stringValue = Self.compactBatteryText(
                prefix: "L", reading: cachedLeftReading
            )
            compactRightBattLabel.stringValue = Self.compactBatteryText(
                prefix: "R", reading: cachedRightReading
            )
            let leftStale = isStaleTracked(fieldKey: "left_battery", now: now)
            let rightStale = isStaleTracked(fieldKey: "right_battery", now: now)
            compactLeftBattLabel.alphaValue = leftStale ? 0.5 : 1.0
            compactRightBattLabel.alphaValue = rightStale ? 0.5 : 1.0
            let splitStale = isStaleTracked(fieldKey: "split_link", now: now)
            let splitAlpha: CGFloat = splitStale ? 0.5 : 1.0
            compactSplitLeftDot.alphaValue = splitAlpha
            compactSplitRightDot.alphaValue = splitAlpha
            compactChargingLeftIcon.isHidden =
                !(s.capability.hasLeftCharging && s.chargingFlags.leftCharging)
            compactChargingRightIcon.isHidden =
                !(s.capability.hasRightCharging && s.chargingFlags.rightCharging)
        } else {
            // Non-split keyboard: show overall battery once in the "left" slot.
            let hasOverall = cachedOverallReading != nil
            compactSplitSegment.isHidden = !hasOverall
            compactSep2.isHidden = !hasOverall
            if hasOverall {
                compactSplitLeftDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
                compactLeftBattLabel.stringValue = Self.compactBatteryText(
                    prefix: "", reading: cachedOverallReading
                )
                compactSplitRightDot.isHidden = true
                compactRightBattLabel.isHidden = true
                let battStale = isStaleTracked(fieldKey: "overall_battery", now: now)
                compactLeftBattLabel.alphaValue = battStale ? 0.5 : 1.0
                compactChargingLeftIcon.isHidden =
                    !(s.capability.hasLeftCharging && s.chargingFlags.leftCharging)
                compactChargingRightIcon.isHidden = true
            }
        }

        // Endpoint segment.
        compactEndpointSegment.isHidden = !s.capability.hasOutputEndpoint
        compactSep3.isHidden = !s.capability.hasOutputEndpoint
        if s.capability.hasOutputEndpoint {
            let txt: String
            switch s.output {
            case .unknown: txt = "—"
            case .usb:     txt = "USB"
            case .ble:     txt = "BLE"
            case .reserved(let code): txt = String(format: "0x%02X", code)
            }
            compactEndpointLabel.stringValue = txt
            let epStale = isStaleTracked(fieldKey: "output_endpoint", now: now)
            compactEndpointLabel.alphaValue = epStale ? 0.5 : 1.0
        }
    }

    private static func compactBatteryText(
        prefix: String, reading: BatteryStatus.BatteryReading?
    ) -> String {
        guard let r = reading else { return "\(prefix)—" }
        switch r {
        case .percent(let n):
            let clamped = max(0, min(100, Int(n)))
            return "\(prefix)\(clamped)"
        case .unavailable:
            return "\(prefix)—"
        }
    }

    /// Thin wrapper around `StalenessTracker.isStale` that also emits a
    /// diagnostic log entry on each live↔stale transition. Rendering uses
    /// this instead of calling `staleness.isStale` directly so that we can
    /// hide the on-screen "last-updated HH:mm:ss" labels while still keeping
    /// a durable trail in `log stream --predicate 'subsystem ==
    /// "com.keybeacon.app"'`.
    private func isStaleTracked(fieldKey: String, now: TimeInterval) -> Bool {
        let stale = staleness.isStale(fieldKey: fieldKey, now: now)
        if lastStaleStates[fieldKey] != stale {
            lastStaleStates[fieldKey] = stale
            if stale {
                let reason: String
                if let last = staleness.lastNotifyAt(fieldKey: fieldKey) {
                    let elapsed = max(0, now - last)
                    reason = "window_elapsed last=\(Self.formatTimestamp(monotonic: last, now: now)) elapsed_s=\(String(format: "%.1f", elapsed))"
                } else {
                    reason = "no_notify_yet"
                }
                DiagnosticsLogger.staleness.fieldStale(fieldKey: fieldKey, reason: reason)
            } else {
                DiagnosticsLogger.staleness.fieldLive(fieldKey: fieldKey)
            }
        }
        return stale
    }

    /// Apply the "last-updated HH:mm:ss" caption to a stale label. Currently a
    /// no-op (the label is kept hidden) because
    /// `showStaleTimestamps == false`; flip that flag to re-enable the
    /// on-screen timestamps without touching the render sites.
    private func applyStaleLabel(_ label: NSTextField,
                                 fieldKey: String,
                                 isStale: Bool,
                                 now: TimeInterval,
                                 lastOverride: TimeInterval? = nil) {
        guard showStaleTimestamps else {
            label.isHidden = true
            label.stringValue = ""
            return
        }
        if isStale,
           let last = lastOverride ?? staleness.lastNotifyAt(fieldKey: fieldKey) {
            label.isHidden = false
            label.stringValue = "最后更新 \(Self.formatTimestamp(monotonic: last, now: now))"
        } else {
            label.isHidden = true
            label.stringValue = ""
        }
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
        let isStale = isStaleTracked(fieldKey: "host_connection", now: now)
        hostDot.alphaValue = isStale ? 0.5 : 1.0
        hostLabel.alphaValue = isStale ? 0.5 : 1.0
        applyStaleLabel(hostStaleLabel, fieldKey: "host_connection", isStale: isStale, now: now)
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
        let isStale = isStaleTracked(fieldKey: "profile", now: now)
        profileCaption.alphaValue = isStale ? 0.5 : 1.0
        for badge in profileBadges { badge.alphaValue = isStale ? 0.5 : 1.0 }
        applyStaleLabel(profileStaleLabel, fieldKey: "profile", isStale: isStale, now: now)
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

    private func renderSplitRow(status s: ConnectivityStatus, now: TimeInterval) {
        guard s.capability.isSplit, s.capability.hasSplitLink else {
            splitRow.isHidden = true
            return
        }
        splitRow.isHidden = false
        let leftOnline = s.splitFlags.leftOnline
        let rightOnline = s.splitFlags.rightOnline
        splitLeftDot.layer?.backgroundColor =
            (leftOnline ? NSColor.systemGreen : NSColor.systemRed).cgColor
        splitRightDot.layer?.backgroundColor =
            (rightOnline ? NSColor.systemGreen : NSColor.systemRed).cgColor
        splitLeftLabel.stringValue = leftOnline ? "左 在线" : "左 离线"
        splitRightLabel.stringValue = rightOnline ? "右 在线" : "右 离线"

        let isStale = isStaleTracked(fieldKey: "split_link", now: now)
        let alpha: CGFloat = isStale ? 0.5 : 1.0
        splitLeftDot.alphaValue = alpha
        splitRightDot.alphaValue = alpha
        splitLeftLabel.alphaValue = alpha
        splitRightLabel.alphaValue = alpha
        applyStaleLabel(splitStaleLabel, fieldKey: "split_link", isStale: isStale, now: now)
    }

    private func renderBatteryRow(status s: ConnectivityStatus, now: TimeInterval) {
        let isSplit = s.capability.isSplit
        guard cachedBatteryStatus != nil
                || cachedOverallReading != nil
                || cachedLeftReading != nil
                || cachedRightReading != nil
        else {
            batteryRow.isHidden = true
            return
        }
        batteryRow.isHidden = false
        if isSplit {
            installSplitBars()
            let leftOnline = s.capability.hasSplitLink ? s.splitFlags.leftOnline : true
            let rightOnline = s.capability.hasSplitLink ? s.splitFlags.rightOnline : true
            let leftCharging = s.capability.hasLeftCharging && s.chargingFlags.leftCharging
            let rightCharging = s.capability.hasRightCharging && s.chargingFlags.rightCharging
            if let left = batteryLeftBar {
                left.sideLabel.stringValue = "L"
                left.sideLabel.isHidden = false
                let frozen = !leftOnline
                left.apply(
                    reading: cachedLeftReading ?? .unavailable(rawByte: 255, outOfRange: false),
                    frozenAt: frozen ? cachedLeftReadingAt : nil,
                    isCharging: leftCharging,
                    now: now
                )
            }
            if let right = batteryRightBar {
                right.sideLabel.stringValue = "R"
                right.sideLabel.isHidden = false
                let frozen = !rightOnline
                right.apply(
                    reading: cachedRightReading ?? .unavailable(rawByte: 255, outOfRange: false),
                    frozenAt: frozen ? cachedRightReadingAt : nil,
                    isCharging: rightCharging,
                    now: now
                )
            }
            let leftStale = isStaleTracked(fieldKey: "left_battery", now: now)
            let rightStale = isStaleTracked(fieldKey: "right_battery", now: now)
            let anyStale = leftStale || rightStale
            batteryCaption.alphaValue = anyStale ? 0.5 : 1.0
            let lastLeft = staleness.lastNotifyAt(fieldKey: "left_battery")
            let lastRight = staleness.lastNotifyAt(fieldKey: "right_battery")
            let latest = [lastLeft, lastRight].compactMap { $0 }.max()
            applyStaleLabel(batteryStaleLabel,
                            fieldKey: "left_battery",
                            isStale: anyStale,
                            now: now,
                            lastOverride: latest)
        } else {
            installOverallBar()
            let overallCharging = s.capability.hasLeftCharging && s.chargingFlags.leftCharging
            if let overall = batteryOverallBar {
                overall.sideLabel.isHidden = true
                overall.apply(
                    reading: cachedOverallReading ?? .unavailable(rawByte: 255, outOfRange: false),
                    frozenAt: nil,
                    isCharging: overallCharging,
                    now: now
                )
            }
            let isStale = isStaleTracked(fieldKey: "overall_battery", now: now)
            batteryCaption.alphaValue = isStale ? 0.5 : 1.0
            applyStaleLabel(batteryStaleLabel, fieldKey: "overall_battery", isStale: isStale, now: now)
        }
    }

    private func installOverallBar() {
        batteryLeftBar?.removeFromSuperview()
        batteryLeftBar = nil
        batteryRightBar?.removeFromSuperview()
        batteryRightBar = nil
        if batteryOverallBar == nil {
            let bar = BatteryBarView(trackWidth: 140)
            batteryBarsStack.addArrangedSubview(bar)
            batteryOverallBar = bar
        }
    }

    private func installSplitBars() {
        batteryOverallBar?.removeFromSuperview()
        batteryOverallBar = nil
        if batteryLeftBar == nil {
            let bar = BatteryBarView(trackWidth: 60)
            batteryBarsStack.addArrangedSubview(bar)
            batteryLeftBar = bar
        }
        if batteryRightBar == nil {
            let bar = BatteryBarView(trackWidth: 60)
            batteryBarsStack.addArrangedSubview(bar)
            batteryRightBar = bar
        }
    }

    private func renderEndpointRow(status s: ConnectivityStatus, now: TimeInterval) {
        guard s.capability.hasOutputEndpoint else {
            endpointRow.isHidden = true
            return
        }
        endpointRow.isHidden = false
        let text: String
        switch s.output {
        case .unknown: text = "输出:未知"
        case .usb:     text = "输出:USB"
        case .ble:     text = "输出:BLE"
        case .reserved(let code): text = String(format: "输出:未知(0x%02X)", code)
        }
        endpointLabel.stringValue = text
        let isStale = isStaleTracked(fieldKey: "output_endpoint", now: now)
        endpointLabel.alphaValue = isStale ? 0.5 : 1.0
        applyStaleLabel(endpointStaleLabel, fieldKey: "output_endpoint", isStale: isStale, now: now)
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
        let desiredWidth: CGFloat
        if settings.displayMode == .compact {
            let rowHeight = max(22, compactRow.fittingSize.height)
            desiredHeight = rowHeight + 16
            let rowWidth = compactRow.fittingSize.width
            // Keep a reasonable minimum so a disconnected keyboard doesn't
            // produce a tiny unreadable chip.
            desiredWidth = max(160, rowWidth + 24)
        } else if connectivityCard.isHidden {
            desiredHeight = baseContentHeight + 10
            desiredWidth = 240
        } else {
            let cardHeight = max(24, connectivityCard.fittingSize.height)
            desiredHeight = baseContentHeight + cardHeight + 6 + 10
            desiredWidth = 240
        }
        let currentOrigin = frame.origin
        let topLeft = NSPoint(x: currentOrigin.x,
                              y: currentOrigin.y + frame.height - desiredHeight)
        let newFrame = NSRect(x: topLeft.x, y: topLeft.y,
                              width: desiredWidth, height: desiredHeight)
        setFrame(newFrame, display: true, animate: false)
        if pinnedCorner != nil {
            applyPinnedCorner()
        } else {
            clampToVisibleBounds()
        }
    }

    /// Returns the screen that currently contains the panel's center point.
    /// Falls back to `self.screen`, then `NSScreen.main`. This is intentionally
    /// NOT `NSScreen.main` (which tracks the key window / active screen and
    /// would cause the panel to jump between displays whenever the user
    /// switches focus).
    private func currentScreen() -> NSScreen? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        if let hit = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            return hit
        }
        return self.screen ?? NSScreen.main
    }

    private func screenID() -> String {
        currentScreen()?.localizedName ?? "default"
    }

    private func restorePosition() {
        if pinnedCorner != nil {
            // Pinned corners are computed, not restored.
            return
        }
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
        guard let screen = currentScreen() else { return }
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
        guard let screen = currentScreen() else { return }
        let visible = screen.visibleFrame
        var origin = frame.origin
        origin.x = min(max(origin.x, visible.minX), visible.maxX - frame.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - frame.height)
        setFrameOrigin(origin)
    }

    /// Anchor the panel to the configured corner of `currentScreen()`. Called
    /// whenever pinnedCorner is non-nil (reflow, screen change, menu toggle).
    func applyPinnedCorner() {
        guard let corner = pinnedCorner, let screen = currentScreen() else { return }
        let margin: CGFloat = 20
        let visible = screen.visibleFrame
        let x: CGFloat
        let y: CGFloat
        switch corner {
        case .topLeft:
            x = visible.minX + margin
            y = visible.maxY - frame.height - margin
        case .topRight:
            x = visible.maxX - frame.width - margin
            y = visible.maxY - frame.height - margin
        case .bottomLeft:
            x = visible.minX + margin
            y = visible.minY + margin
        case .bottomRight:
            x = visible.maxX - frame.width - margin
            y = visible.minY + margin
        }
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    override var canBecomeKey: Bool { false }

    func savePosition() {
        // When pinned to a corner, position is derived — don't persist drag
        // coordinates (dragging will visually move but snap back on next
        // reflow / pin apply).
        if pinnedCorner != nil { return }
        let p = frame.origin
        settings.setPosition("\(p.x),\(p.y)", screenID: screenID())
    }

    override func mouseUp(with event: NSEvent) {
        if pinnedCorner != nil {
            // Snap back to the configured corner if user dragged while pinned.
            applyPinnedCorner()
        } else {
            savePosition()
        }
    }

    func update(_ status: KeyboardStatus) {
        let txt = status.connected ? status.layerName : "未连接"
        layerLabel.stringValue = txt
        compactLayerLabel.stringValue = txt
        let active = [
            status.shiftActive, status.controlActive,
            status.optionActive, status.commandActive,
        ]
        for (label, on) in zip(modLabels, active) {
            label.textColor = on ? .white : .gray
        }
        for (label, on) in zip(compactModLabels, active) {
            label.textColor = on ? .white : .gray
        }
        if settings.displayMode == .compact {
            reflowFrameToContent()
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

fileprivate final class BatteryBarView: NSView {
    let sideLabel = NSTextField(labelWithString: "")
    private let percentLabel = NSTextField(labelWithString: "—")
    private let track = NSView()
    private let fill = NSView()
    private let chargingIcon = NSTextField(labelWithString: "⚡︎")
    private var fillWidthConstraint: NSLayoutConstraint!
    private let trackWidth: CGFloat
    private let trackHeight: CGFloat = 6

    init(trackWidth: CGFloat) {
        self.trackWidth = trackWidth
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        sideLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        sideLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        sideLabel.translatesAutoresizingMaskIntoConstraints = false
        sideLabel.isHidden = true
        addSubview(sideLabel)

        track.wantsLayer = true
        track.layer?.cornerRadius = trackHeight / 2
        track.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        track.translatesAutoresizingMaskIntoConstraints = false
        addSubview(track)

        fill.wantsLayer = true
        fill.layer?.cornerRadius = trackHeight / 2
        fill.layer?.backgroundColor = NSColor.systemGreen.cgColor
        fill.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(fill)

        percentLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        percentLabel.textColor = .white
        percentLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(percentLabel)

        chargingIcon.font = .systemFont(ofSize: 11, weight: .bold)
        chargingIcon.textColor = .systemYellow
        chargingIcon.toolTip = "充电中"
        chargingIcon.setAccessibilityLabel("充电中")
        chargingIcon.isHidden = true
        chargingIcon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chargingIcon)

        fillWidthConstraint = fill.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            sideLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            sideLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            track.leadingAnchor.constraint(equalTo: sideLabel.trailingAnchor, constant: 4),
            track.centerYAnchor.constraint(equalTo: centerYAnchor),
            track.widthAnchor.constraint(equalToConstant: trackWidth),
            track.heightAnchor.constraint(equalToConstant: trackHeight),
            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            fillWidthConstraint,
            percentLabel.leadingAnchor.constraint(equalTo: track.trailingAnchor, constant: 6),
            percentLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            percentLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            chargingIcon.trailingAnchor.constraint(equalTo: track.trailingAnchor, constant: 2),
            chargingIcon.topAnchor.constraint(equalTo: track.topAnchor, constant: -11),
            heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(
        reading: BatteryStatus.BatteryReading,
        frozenAt: TimeInterval?,
        isCharging: Bool,
        now: TimeInterval
    ) {
        switch reading {
        case .percent(let n):
            let clamped = max(0, min(100, Int(n)))
            fillWidthConstraint.constant = trackWidth * CGFloat(clamped) / 100.0
            fill.layer?.backgroundColor = Self.colorForPercent(clamped).cgColor
            fill.isHidden = false
            if let frozen = frozenAt {
                // Keep the alpha=0.65 "frozen" visual, but suppress the
                // trailing "· HH:mm:ss" caption unless the file-scope
                // debug flag is enabled.
                if showStaleTimestamps {
                    let stamp = BatteryBarView.timeFormatter.string(
                        from: Date().addingTimeInterval(-(max(0, now - frozen)))
                    )
                    percentLabel.stringValue = "\(clamped)% · \(stamp)"
                } else {
                    _ = frozen  // retained for future debug / breakpoint use
                    percentLabel.stringValue = "\(clamped)%"
                }
                percentLabel.alphaValue = 0.65
            } else {
                percentLabel.stringValue = "\(clamped)%"
                percentLabel.alphaValue = 1.0
            }
        case .unavailable:
            fillWidthConstraint.constant = 0
            fill.isHidden = true
            percentLabel.stringValue = "读取失败"
            percentLabel.alphaValue = 1.0
        }
        chargingIcon.isHidden = !isCharging
    }

    private static func colorForPercent(_ n: Int) -> NSColor {
        switch n {
        case ..<20: return .systemRed
        case ..<40: return .systemOrange
        default:    return .systemGreen
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
