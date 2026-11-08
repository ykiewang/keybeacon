// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import Foundation

/// Abstract colour for the per-link host-status visual encoding. The palette is
/// platform-agnostic here (no AppKit) so it is pure-function unit-testable; the
/// UI layer maps each case to `NSColor` (macOS) / `SolidColorBrush` (Windows).
///
/// Single source of truth: **both** the full card and the compact strip reuse
/// this exact mapping (FR-016). Never define a mode-specific scheme.
public enum HostStatusColor: Equatable {
    case green   // in use on this computer
    case orange  // keyboard active on another computer
    case blue    // keyboard on USB (not this BLE link)
    case gray    // cannot determine
    case red     // disconnected
}

/// The colour + shape symbol that encode a `LocalHostStatus`. Redundant by
/// design: `symbol` (a shape) lets the state be told apart without relying on
/// colour alone (WCAG 1.4.1 / FR-016).
///
/// Contract: `specs/005-host-link-profile-awareness/contracts/host-status-visual.md`
/// (V-1 table, V-2 rules). Structurally identical to the Windows
/// `HostStatusVisual` (cross-platform parity, constitution §III).
public struct HostStatusVisual: Equatable {

    /// Abstract palette entry (mapped to a real colour by the UI layer).
    public let color: HostStatusColor

    /// A single-glyph shape symbol, drawn alongside the colour for redundancy:
    /// filled ● (in-use), half ◐ (elsewhere), diamond ◆ (USB), hollow ○
    /// (cannot-determine), cross ✕ (disconnected).
    public let symbol: String

    public init(color: HostStatusColor, symbol: String) {
        self.color = color
        self.symbol = symbol
    }
}

/// Map a derived `LocalHostStatus` to its colour + symbol. Pure, exhaustive,
/// no I/O (FR-014).
///
/// Colours: green = in-use-here, orange = active-elsewhere (blue is reserved
/// for USB so the two never collide), blue = on-USB, gray = cannot-determine,
/// red = disconnected (an alarm, visually distinct from the gray "unknown").
public func hostStatusVisual(for status: LocalHostStatus) -> HostStatusVisual {
    switch status {
    case .inUseHere:
        return HostStatusVisual(color: .green, symbol: "●")
    case .activeElsewhere:
        return HostStatusVisual(color: .orange, symbol: "◐")
    case .onUsb:
        return HostStatusVisual(color: .blue, symbol: "◆")
    case .cannotDetermine:
        return HostStatusVisual(color: .gray, symbol: "○")
    case .disconnected:
        return HostStatusVisual(color: .red, symbol: "✕")
    }
}
