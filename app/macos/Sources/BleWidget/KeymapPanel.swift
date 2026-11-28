// Copyright (c) 2026 The TOTEM ZMK Contributors
// SPDX-License-Identifier: MIT

import AppKit
import BleWidgetCore

final class KeymapPanel: NSPanel {
    private let segmentedControl = NSSegmentedControl()
    private let scrollView = NSScrollView()
    private let keymapView = KeymapView(frame: .zero)
    private let placeholder = NSTextField(labelWithString: "")
    private var snapshot: KeymapSnapshot?
    private var currentLayer = 0

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 360),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        title = L10n.text("Keymap_PanelTitle")
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces]

        let content = NSView(frame: contentRect(forFrameRect: frame))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor

        segmentedControl.segmentStyle = .texturedRounded
        segmentedControl.target = self
        segmentedControl.action = #selector(layerChanged(_:))
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = keymapView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        placeholder.textColor = NSColor.white.withAlphaComponent(0.6)
        placeholder.alignment = .center
        placeholder.font = .systemFont(ofSize: 14)
        placeholder.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(segmentedControl)
        content.addSubview(scrollView)
        content.addSubview(placeholder)

        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            segmentedControl.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            segmentedControl.heightAnchor.constraint(equalToConstant: 24),

            scrollView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),

            placeholder.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])

        contentView = content
        showPlaceholder(L10n.text("Keymap_NoData"))
    }

    required init?(coder: NSCoder) { fatalError() }

    private func showPlaceholder(_ text: String) {
        placeholder.stringValue = text
        placeholder.isHidden = false
        scrollView.isHidden = true
    }

    private func hidePlaceholder() {
        placeholder.isHidden = true
        scrollView.isHidden = false
    }

    func update(snapshot: KeymapSnapshot) {
        self.snapshot = snapshot
        currentLayer = min(currentLayer, max(0, snapshot.bindings.count - 1))

        let names = snapshot.meta.layerNames
        let count = Int(snapshot.meta.layerCount)
        segmentedControl.segmentCount = count
        for i in 0..<count {
            let title = i < names.count && !names[i].isEmpty ? names[i] : "L\(i)"
            segmentedControl.setLabel(title, forSegment: i)
        }
        segmentedControl.selectSegment(withTag: currentLayer)
        segmentedControl.setEnabled(true, forSegment: currentLayer)
        segmentedControl.selectedSegment = currentLayer

        renderCurrentLayer()
    }

    func highlightLayer(_ index: Int) {
        guard let snapshot, snapshot.bindings.indices.contains(index) else { return }
        for i in 0..<segmentedControl.segmentCount {
            let label = segmentedControl.label(forSegment: i) ?? ""
            segmentedControl.setLabel(
                index == i ? "● " + label : label.trimmingCharacters(in: ["●", " "]),
                forSegment: i
            )
        }
    }

    func showPlaceholderLoading() {
        showPlaceholder(L10n.text("Keymap_Loading"))
    }

    func markDisconnected() {
        showPlaceholder(L10n.text("Keymap_Disconnected"))
    }

    func showUnsupported() {
        showPlaceholder(L10n.text("Keymap_Unsupported"))
    }

    private func renderCurrentLayer() {
        guard let snapshot, snapshot.bindings.indices.contains(currentLayer) else {
            showPlaceholder(L10n.text("Keymap_NoData"))
            return
        }
        hidePlaceholder()
        keymapView.update(snapshot: snapshot, layer: currentLayer)
        keymapView.frame = NSRect(origin: .zero, size: keymapView.intrinsicContentSize)
        keymapView.needsDisplay = true
    }

    @objc private func layerChanged(_ sender: NSSegmentedControl) {
        currentLayer = sender.selectedSegment
        renderCurrentLayer()
    }
}
