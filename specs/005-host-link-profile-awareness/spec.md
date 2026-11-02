# Feature Specification: Per-Link Host Context — "Is the keyboard typing on this computer?"

**Feature Branch**: `005-host-link-profile-awareness` (spec-only; the firmware half lands in the sibling **`zmk-keybeacon`** repo)

**Created**: 2026-10-31

**Status**: Draft

**Input**: User description: "去啃固件侧的方案 2" — make each connected host able to answer, unambiguously and with **zero user configuration**, whether the keyboard is *currently sending keystrokes to this computer* (as opposed to merely having a live BLE link while typing on a different machine). This is the "per-connection host context" (方案 2) approach, chosen over the manual "which slot am I?" setting (方案 1).

**Background / why this exists**:

- A ZMK keyboard bonded to several machines (e.g. Mac on P1, Windows on P2) keeps a **live BLE link to every bonded host simultaneously** — this is intended ZMK behaviour, not a bug. Only the *active profile* receives keystrokes.
- Because the current KBP 1.1 Connectivity characteristic is delivered by a **broadcast** notification, every host receives **byte-identical** payloads. The active `profile_index` therefore reports the *globally active* profile, so Mac and Windows both see the same value and both conclude "connected" — the ambiguity the user reported.
- The decisive enabler: a characteristic **read** is inherently **per-connection** — the firmware knows which link is asking and can answer differently per host. Each host therefore learns **its own** slot with zero configuration, then compares it against the broadcast active index to decide "in use by me / in use elsewhere / idle".

**Related work (read-only here)**:

- Protocol §9 / §14.6 (MINOR additive evolution, reserved trailing bytes): `protocol/README.md`.
- Protocol §14.3.1 (the reserved trailing-byte region is the sanctioned MINOR extension point).
- Existing firmware producer and host consumers (macOS `app/macos/**`, Windows `app/windows/**`) remain the implementers of this spec.

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Unambiguous "this computer" status while bonded to multiple machines (Priority: P1)

A user has one keyboard bonded to a Mac (slot P1) and a Windows PC (slot P2), both with the KeyBeacon app running. The keyboard is currently typing on the Windows PC. On **both** machines the app shows a single, honest status for "this computer":

- On the Mac: **"Keyboard is active on another computer (P2)"** — clearly *not* "in use here".
- On Windows: **"In use on this computer"** — clearly the active target.

When the user flips the keyboard's active profile back to the Mac (P1), the Mac app switches to **"In use on this computer"** and the Windows app switches to **"Keyboard is active on another computer (P1)"** — within about one second, with no reconnect.

**Why this priority**: this is the entire reason the feature exists — it directly resolves the ambiguity that started this work (both machines showing "connected" at once). Without it the feature delivers no user value.

**Independent Test**: with one keyboard bonded to two hosts, cycle the active profile on-keyboard between the two slots. Each host's "this computer" status MUST track the active slot within ≤ 1 s and MUST never show "in use here" on the host that is not receiving keystrokes. Fully testable on the reference keyboard + two computers; no firmware-internal inspection required.

**Acceptance Scenarios**:

1. **Given** a KBP per-link-aware keyboard bonded to Host A (P1) and Host B (P2), active on P1, **When** both apps are connected, **Then** Host A shows "in use on this computer" and Host B shows "keyboard active on another computer (P1)".
2. **Given** the same setup, **When** the user switches the active profile from P1 to P2 on the keyboard, **Then** within ≤ 1 s Host A flips to "active on another computer (P2)" and Host B flips to "in use on this computer", with no BLE disconnect on either side.
3. **Given** the keyboard is physically powered off / out of range of Host A, **When** Host A's BLE link drops, **Then** Host A shows "disconnected" (not any retained "in use" state) — the link-loss signal wins over any cached active-slot value.

---

### User Story 2 — Zero-configuration: the host learns its own slot automatically (Priority: P2)

The user does **nothing** to configure the app. Each host app, on connecting (or reconnecting), learns "this BLE link is profile N" directly from the keyboard over the per-connection read, and remembers it for the session. There is no "which slot am I?" dropdown, no manual mapping, no per-machine setup file. When a keyboard is re-paired into a different slot, the host re-learns the new slot on the next connection without user action.

**Why this priority**: this is what distinguishes the chosen approach (方案 2) from the rejected manual approach (方案 1). If the user had to type in "I am P1", the feature would be half as valuable. Zero-config is the differentiator, so it is a first-class requirement — but it depends on US1's status surface already existing, hence P2.

**Independent Test**: with a fresh app install (no prior settings) and a keyboard already bonded, connect the app and confirm the "this computer" status is correct **without entering any slot number**. Then re-pair the keyboard into a different slot and reconnect; confirm the app reports the new slot without user action.

**Acceptance Scenarios**:

1. **Given** a freshly installed app with no saved configuration, **When** it connects to a per-link-aware keyboard, **Then** it displays the correct "this computer" status on first render, with no user input required.
2. **Given** a connected host that has learned its slot, **When** the keyboard is re-bonded into a different slot and the host reconnects, **Then** the host reports the corrected slot and status with no manual reconfiguration.

---

### User Story 3 — Old firmware / old host keep working unchanged (Priority: P3)

A user on the currently released firmware (no per-link field) with the new app, or the new firmware with an old app, sees **exactly** the previous behaviour — no errors, no blank card, no crash. The new "in use / active elsewhere" distinction is simply unavailable, and the app degrades honestly (shows only the link-level status it can support, never fabricates an active-elsewhere claim).

**Why this priority**: backward compatibility is constitutionally non-negotiable (§II) but adds no new user capability for already-upgraded pairs; it protects the mixed-version population, so P3.

**Independent Test**: (a) new app + old firmware → app shows prior connectivity behaviour and no "active on another computer" claim; (b) old app + new firmware → old app's parsing of existing bytes is byte-identical to before (new trailing byte ignored). Both confirmed by running each app build against each firmware build.

**Acceptance Scenarios**:

1. **Given** an app that does not understand the per-link field, **When** it connects to a per-link-aware keyboard, **Then** all previously published fields parse byte-identically and no new UI appears.
2. **Given** a per-link-aware app, **When** it connects to firmware that lacks the per-link field, **Then** the app shows link-level status only and MUST NOT display "in use / active elsewhere" (no guessing).

---

### Edge Cases

- **Host cannot be resolved to a slot** (e.g. the connection's peer address does not match any bonded profile — a plausible outcome with resolvable-private-address privacy): the app MUST show an explicit "unknown / cannot determine" status for the "this computer" line, MUST NOT claim "in use" or "active elsewhere", and MUST emit exactly one structured diagnostic. It MUST still show the basic link-connected state.
- **Profile slot is "open" (waiting-to-pair)**: there is no active peer identity yet; the "this computer" line MUST show "pairing / not applicable" rather than a fabricated slot.
- **Single-host keyboard** (only one bond ever): active slot always equals the local slot while connected; status shows "in use on this computer"; no "elsewhere" state should ever appear.
- **Keyboard active on USB output** (not BLE) while bonded: the existing `output_endpoint` says USB. The "this computer" line SHOULD distinguish "keyboard is on USB — not sending over this BLE link" from "in use here over BLE". It MUST NOT say "in use on this computer over BLE" when output is USB.
- **Rapid profile switching**: two flips within one second MUST settle on the final active slot; no flicker that leaves a host stuck on a stale "in use" claim.
- **Link drops mid-update**: if the BLE link drops between receiving an active-slot change and re-reading, the disconnect MUST immediately override any pending "in use" state.
- **Firmware that cannot compute the per-link slot** (address mismatch at the firmware layer): firmware MUST emit the "not determined" sentinel for the per-link field rather than a wrong slot number.

---

## Requirements *(mandatory)*

### Functional Requirements

**Per-link host context (the core new signal)**

- **FR-001**: The keyboard MUST expose, **per BLE connection**, the profile (host slot) that this specific connection corresponds to, obtainable by that host on connect via a per-connection read. A host MUST NOT need any prior configuration to obtain its own slot.
- **FR-002**: The per-link slot value MUST be `1`-based (matching the existing `profile_index` wire convention) with a single reserved value meaning "not determined / not applicable".
- **FR-003**: When the firmware cannot resolve the connection's peer to a bonded profile, it MUST emit the "not determined" reserved value — it MUST NOT emit a guessed slot.
- **FR-004**: The per-link signal MUST reach each host **independently of the broadcast active-slot notification**; a host MUST be able to obtain its own slot even when notifications are shared/identical across hosts.

**Host app status (this computer)**

- **FR-005**: The host app MUST present a single, explicit "this computer" status, distinct from the keyboard's global host-state, with exactly these observable states: *in use on this computer*; *keyboard active on another computer (slot N)*; *keyboard on USB (not this BLE link)*; *cannot determine*; *disconnected*.
- **FR-006**: The status MUST update within ≤ 1 second of the keyboard's active profile changing, without requiring a reconnect.
- **FR-007**: The app MUST re-evaluate status on every way the inputs can change: active-profile change, per-link slot learned/changed, output-endpoint change, and link connect/disconnect.
- **FR-008**: Under the governance principle *Observable Degradation Over Guessing* (§IV), the app MUST never render "in use on this computer" unless it can positively confirm the keyboard's active slot equals this link's slot. Any missing/unknown/stale input degrades to *cannot determine* or *disconnected* — never to a confident wrong claim.
- **FR-009**: On BLE link loss the app MUST immediately show *disconnected*, overriding any previously shown "in use" state.
- **FR-010**: The "this computer" line MUST be available in **both** English and 中文 UI, consistent with the existing bilingual surfaces (§VI for docs; the app strings for both languages).

**Backward compatibility & protocol evolution**

- **FR-011**: The change MUST be a **KBP MINOR** evolution: the service UUID stays unchanged, all previously published bytes keep identical offsets and meaning, and the new information is carried only in the sanctioned additive extension point (reserved trailing bytes and/or the existing optional characteristics). (Constitution §II.)
- **FR-012**: A host that does not understand the new signal MUST continue to parse all prior fields byte-identically and observe no new UI. A per-link-aware host against firmware lacking the signal MUST fall back to link-level status without fabricating the "active elsewhere" claim.
- **FR-013**: Every degradation path (FR-003, FR-008, edge cases) MUST emit exactly one structured diagnostic log entry, per the existing degradation-logging convention.

**Verification & docs**

- **FR-014**: Payload parsing and the status-classification logic MUST be covered by pure-function unit tests runnable without BLE hardware, and the mapping from wire bytes → the five status states MUST be exhaustively tested.
- **FR-015**: The normative protocol documents (`protocol/README.md`, `protocol/CHANGELOG.md`, conformance checklist) MUST be updated as bilingual English/中文 mirrors (§VI) describing the new additive field/semantics.

### Key Entities *(include if feature involves data)*

- **Local Link Slot**: the profile index that *this* BLE connection maps to (per host, per connection). Attributes: `slot` (1-based or "not determined"), source = per-connection read.
- **Active Slot**: the keyboard's globally active profile index, already broadcast in the Connectivity payload. Shared, identical across hosts.
- **Local Host Status** (derived): one of {in-use-here, active-elsewhere(slot N), on-usb, cannot-determine, disconnected}. Derived from Local Link Slot + Active Slot + output endpoint + link state.
- **Output Endpoint**: existing field (USB/BLE/unknown), reused to distinguish "on USB" from "over this BLE link".

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a two-host setup (keyboard bonded to two computers), when the user switches the active profile on the keyboard, **each** host displays the correct "this computer" status within ≤ 1 second, and **zero** hosts display "in use here" while not receiving keystrokes — verified across ≥ 20 consecutive profile switches with no stuck state.
- **SC-002**: A freshly installed host app reaches the correct "this computer" status on first connection **with zero user configuration steps** (no slot entry, no mapping file) — 100% of trials.
- **SC-003**: Every degradation scenario (unresolvable slot, open slot, USB output, link loss, unknown input) results in a *cannot-determine* / *disconnected* / *on-usb* status and **never** a false "in use on this computer" claim — verified by a targeted negative-test matrix, 100% pass.
- **SC-004**: A host that does not understand the new signal observes **byte-identical** parsing of all previously published fields and renders no new UI (regression), confirmed against the prior release build.
- **SC-005**: The wire addition passes the project's conformance tool with no new failures and the protocol's declared MINOR version reflects the addition.

## Assumptions

- The ZMK public API `zmk_ble_profile_index(const bt_addr_le_t *addr)` reliably maps a live connection's peer address to a bonded slot on the supported known-good pins. If a host's connection uses a resolvable-private-address whose peer does not compare equal to the bonded address, firmware emits the "not determined" sentinel (FR-003) and the host shows *cannot determine* — this is an accepted, honest degradation, not a failure.
- "Keyboard active on another computer (slot N)" is acceptable UX; the exact wording may change but the three-way distinction (here / elsewhere / cannot-determine) is the requirement.
- The keyboard supports the existing KBP 1.1 Connectivity characteristic; the per-link signal rides on it rather than introducing a new top-level surface.
- Both host platforms (macOS, Windows) share the same wire contract and the same five-state status semantics; only the UI chrome differs.
- A reference keyboard and a second computer are available for end-to-end verification (per the Platform Scope & Delivery section of the constitution).
- Firmware changes ship from the sibling `zmk-keybeacon` repo as a new MINOR release and are flashed by the user; the app must therefore work correctly against both the old and new firmware during the transition.
