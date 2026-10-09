// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import Foundation

/// Per-field staleness bookkeeping for KBP 1.1 live values (FR-015).
///
/// A field is "live" when its last notify timestamp is within the staleness
/// window (default **3 seconds**, per Clarify Q1); older than that → "stale",
/// and the UI MUST render the last-known value + "updated hh:mm:ss" instead of
/// a live number.
///
/// This type is deliberately a plain `final class` rather than an `actor` so
/// it is trivially unit-testable with injected monotonic timestamps and does
/// not spawn any timer of its own. The 1-Hz tick that decides when to re-check
/// is driven by `BLEClient` (see tasks.md T019).
///
/// Thread safety: callers MUST serialise access on the BLE delegate queue
/// (`BLEClient` already does this; the UI reads via a snapshot copy on the
/// main actor).
public final class StalenessTracker {

    /// How long since the last notify counts as "stale".
    public let stalenessWindow: TimeInterval

    private var lastNotify: [String: TimeInterval] = [:]
    /// Fields explicitly forced stale (e.g., BLE disconnect event). Reset by
    /// a subsequent `recordNotify`.
    private var forcedStale: Set<String> = []

    public init(stalenessWindow: TimeInterval = 3.0) {
        self.stalenessWindow = stalenessWindow
    }

    /// Record a fresh notify for `fieldKey` at monotonic time `at`.
    ///
    /// Clears any forced-stale state and overrides older timestamps. If `at`
    /// is older than a previously-recorded timestamp for the same field (clock
    /// moving backward), the newer value is retained — the tracker never
    /// regresses, so a time-source glitch cannot cause a spurious "stale".
    public func recordNotify(fieldKey: String, at: TimeInterval) {
        if let existing = lastNotify[fieldKey], existing > at {
            // Keep the newer timestamp; still clear forced-stale.
        } else {
            lastNotify[fieldKey] = at
        }
        forcedStale.remove(fieldKey)
    }

    /// Return `true` when `fieldKey` has been forced stale, or when
    /// `now - lastNotify[fieldKey] >= stalenessWindow`. A field that has never
    /// been recorded is treated as **stale** (there is no live reading yet).
    public func isStale(fieldKey: String, now: TimeInterval) -> Bool {
        if forcedStale.contains(fieldKey) { return true }
        guard let last = lastNotify[fieldKey] else { return true }
        return (now - last) >= stalenessWindow
    }

    /// Immediately mark **every** field stale. Called on BLE disconnect so the
    /// UI does not keep showing live values after the link is gone.
    public func forceStaleAll() {
        forcedStale.formUnion(lastNotify.keys)
    }

    /// Immediately mark one field stale (rare — most paths use `forceStaleAll`
    /// on disconnect and `recordNotify` to recover a single field).
    public func forceStale(fieldKey: String) {
        forcedStale.insert(fieldKey)
    }

    /// Return the recorded last-notify timestamp for a field (for diagnostics
    /// / UI "updated hh:mm:ss" labels), or `nil` if never recorded.
    public func lastNotifyAt(fieldKey: String) -> TimeInterval? {
        lastNotify[fieldKey]
    }

    /// All field keys currently tracked. For diagnostics only.
    public var trackedFieldKeys: [String] {
        Array(lastNotify.keys).sorted()
    }

    /// Forget all state. Used only by tests.
    public func reset() {
        lastNotify.removeAll()
        forcedStale.removeAll()
    }
}
