// Copyright (c) 2026 The TOTEM ZMK Contributors
// SPDX-License-Identifier: MIT

import AppKit
import BleWidgetCore

final class KeymapView: NSView {
    private var snapshot: KeymapSnapshot?
    private var layerIndex: Int = 0

    private static let unitSize: CGFloat = 54
    private static let gap: CGFloat = 3

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(snapshot: KeymapSnapshot, layer: Int) {
        self.snapshot = snapshot
        self.layerIndex = min(layer, max(0, snapshot.bindings.count - 1))
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        guard let snapshot else { return NSSize(width: 400, height: 200) }
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        for k in snapshot.keys {
            let x = CGFloat(k.x) / 100.0
            let y = CGFloat(k.y) / 100.0
            let w = CGFloat(k.w) / 10.0
            let h = CGFloat(k.h) / 10.0
            maxX = max(maxX, (x + w) * Self.unitSize)
            maxY = max(maxY, (y + h) * Self.unitSize)
        }
        return NSSize(width: maxX + 16, height: maxY + 16)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let snapshot, snapshot.bindings.indices.contains(layerIndex) else { return }
        let layerNames = snapshot.meta.layerNames
        let bindings = snapshot.bindings[layerIndex]

        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        let transform = NSAffineTransform()
        transform.translateX(by: 8, yBy: 8)
        transform.concat()

        for (i, k) in snapshot.keys.enumerated() {
            let x = CGFloat(k.x) / 100.0
            let y = CGFloat(k.y) / 100.0
            let w = CGFloat(k.w) / 10.0
            let h = CGFloat(k.h) / 10.0

            let rect = NSRect(
                x: x * Self.unitSize,
                y: bounds.height - 16 - (y + h) * Self.unitSize,
                width: w * Self.unitSize - Self.gap,
                height: h * Self.unitSize - Self.gap
            )
            if !dirtyRect.intersects(rect.insetBy(dx: -20, dy: -20)) && !rect.isNull { continue }

            NSGraphicsContext.current?.saveGraphicsState()
            if k.r != 0 {
                let origin = NSPoint(
                    x: CGFloat(k.rx) / 100.0 * Self.unitSize,
                    y: bounds.height - 16 - CGFloat(k.ry) / 100.0 * Self.unitSize
                )
                let rot = NSAffineTransform()
                rot.translateX(by: origin.x, yBy: origin.y)
                rot.rotate(byDegrees: CGFloat(k.r) / 100.0)
                rot.translateX(by: -origin.x, yBy: -origin.y)
                rot.concat()
            }

            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            let isUnknown = i < bindings.count && bindings[i].behaviorID == .unknown
            (isUnknown ? NSColor.controlBackgroundColor : NSColor.white.withAlphaComponent(0.12)).setFill()
            path.fill()
            NSColor.white.withAlphaComponent(0.25).setStroke()
            path.lineWidth = 1
            path.stroke()

            let label = i < bindings.count
                ? bindings[i].displayLabel(layerNames: layerNames)
                : "?"

            let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(isUnknown ? 0.45 : 0.92),
            ]
            let size = label.size(withAttributes: attrs)
            let textRect = NSRect(
                x: rect.midX - size.width / 2,
                y: rect.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
            label.draw(in: textRect, withAttributes: attrs)

            NSGraphicsContext.current?.restoreGraphicsState()
        }
    }
}
