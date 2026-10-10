# Feature Specification: zmk-keybeacon module — KBP 1.1 Connectivity & Power

**Feature Branch**: `feat/kbp-1.1-connectivity-power` (branch is created in the sibling **`zmk-keybeacon`** repo, not in this `keybeacon` repo)

**Target repository**: `../zmk-keybeacon/` (sibling Zephyr module; separate git repo pinned by consumer firmware via `west.yml revision`)

**Created**: 2026-10-09

**Status**: Draft

**Input**: User description: "先做 module 的改动" — implement the firmware-producer (ZMK) side of KBP 1.1 Connectivity & Power in the standalone `zmk-keybeacon` Zephyr module so a KBP 1.1 host (e.g. the macOS KeyBeacon app on branch `001-connectivity-power`) can render the "Connectivity & Battery" card on real hardware.

**Related work (upstream, read-only here)**:

- Protocol §14 (normative wire contract for KBP 1.1): `protocol/README.md` lines 204–370 (English) / 702–716 (中文).
- Protocol §14.8 (non-normative ZMK API hints): `protocol/README.md` lines 357–370.
- Conformance checklist C7–C12: `conformance/checklist.md` lines 28–37.
- Keyboard-author guide §8: `conformance/CONFORMANCE.md` lines 125–216.
- Host-side feature spec: `specs/001-connectivity-power/spec.md` (36/48 tasks landed; 12 remaining need real hardware).
- Current module contract: `../zmk-keybeacon/CHANGELOG.md` v1.0.0 only; **this feature produces v1.1.0**.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Connectivity characteristic end-to-end on a split central (Priority: P1)

A keyboard author (reference: user's Corne split on branch `feat/keybeacon` in `zmk-config-corne`) updates `west.yml revision` from `zmk-keybeacon@v1.0.0` to `v1.1.0`, keeps `CONFIG_ZMK_KEYBEACON=y`, and reflashes the central half. On the first connect, the macOS KeyBeacon app renders four live rows in the "Connectivity & Battery" card: host-connection state, profile slot/open-flag, split-halves on/off (both halves lit when the peripheral is paired), and the output endpoint (USB vs BLE). Flipping the output endpoint on the keyboard (Mo+Fn+O or equivalent) updates the row within one second without the app disconnecting; disconnecting a peripheral half flips its split-link indicator; opening a profile slot flips the profile row's "open/paired" badge.

**Why this priority**: this is the MVP for the firmware side. All four fields derive from existing ZMK events (`zmk_ble_active_profile_changed`, `zmk_split_bt_peripheral_status_changed`, `zmk_endpoint_changed`) that are already firing on the user's current build — no new hardware required. Without this, the host-side 1.1 card stays empty on real keyboards and the whole feature cannot be field-tested.

**Independent Test**: on a Corne central running KBP 1.1 firmware, `python3 conformance/conformance_tool.py --json` on the main keybeacon repo returns `declared_minor = "1.1"`, `characteristics.AA440AA2.present = true`, and `check_us1 / check_us2_split_link / check_us3_output_endpoint` are PASS. Running `conformance_tool.py` while cycling output endpoint + unpairing the peripheral half shows NOTIFYs arriving on the Connectivity characteristic within ≤ 1 second of each hardware event.

**Acceptance Scenarios**:

1. **Given** a Corne central freshly flashed with KBP 1.1 firmware and connected to a Mac over BLE, **When** `python3 conformance/conformance_tool.py --timeout 15` runs from `/Users/wangyuting19/kbd/keybeacon/keybeacon`, **Then** the exit code is `0`, C7/C8 are PASS, and C12 is MANUAL (not a failure).
2. **Given** the keyboard is connected, **When** the user cycles the output endpoint from BLE to USB (and back) on-keyboard, **Then** the app's "output endpoint" row updates within ≤ 1 second each way, and the conformance tool records corresponding NOTIFYs on `AA440AA2-…` in observation mode (`--observe 4`).
3. **Given** the keyboard is a connected split, **When** the user unpairs the peripheral half (holds reset), **Then** `split_link_flags.right_online` flips `1 → 0` on the next NOTIFY within ≤ 1 second, and the app's split-halves row shows the right half as offline.
4. **Given** a KBP 1.0 host (macOS KeyBeacon app pre-`001-connectivity-power`) connects to the same KBP 1.1 firmware, **When** it subscribes to `AA440AA1-…` only, **Then** zero NOTIFYs arrive on `AA440AA2-…` / `AA440AA3-…` (CCC never enabled by the 1.0 host), the keyboard's layer+modifier display works bit-for-bit identical to v1.0.0, and no behaviour change is observable on the 1.0 host.

---

### User Story 2 — Battery characteristic with throttling (Priority: P2)

The same Corne build enables the Battery sub-Kconfig; firmware aggregates central-side battery via `zmk_battery_state_changed` and peripheral-side via `zmk_peripheral_battery_state_changed`, emits a 2-byte split payload (`[left_percent, right_percent]`) on `AA440AA3-…`, and throttles NOTIFYs to ≥ 1 percentage-point OR ≥ 1 second since last emit (OR relation). The host app renders a live `BatteryBarView` for both halves; the right-half bar updates when the peripheral reports a new reading; a transient I²C/sync-bus read failure surfaces as the `255` sentinel (rendered "read failed" per host §C-B3), not as a mysterious "0%".

**Why this priority**: battery depends on sync-bus reliability between central and peripheral, so it is slightly more hardware-fragile than US1 and often ships one release later than connectivity. It is still a required part of 1.1 (C9/C11) and is the second-most-requested field in the KeyBeacon roadmap.

**Independent Test**: with the Battery sub-Kconfig enabled, `conformance_tool.py --json` returns `characteristics.AA440AA3.present = true`, `check_us2_battery` is PASS, and `--observe 4` reports no NOTIFY on the battery characteristic faster than ≥ 1 pp OR ≥ 1 s. Removing the sync-bus (e.g. power the peripheral off) causes the right-half reading to go to `255` within ≤ 2 s and the host to render "read failed".

**Acceptance Scenarios**:

1. **Given** `CONFIG_ZMK_KEYBEACON_BATTERY=y` on the central and the peripheral paired, **When** both halves report fresh battery readings, **Then** the Battery characteristic is 2 bytes `[left_percent, right_percent]`, both values ∈ [0, 100], and the app shows both bars.
2. **Given** a connected board, **When** the user types continuously for 60 seconds (no real battery change), **Then** the firmware emits at most **60** NOTIFYs on `AA440AA3-…` (one per second maximum), demonstrating ≥ 1 s throttling.
3. **Given** a split with peripheral powered off, **When** the central's periodic read of the peripheral battery times out, **Then** the right-half byte transitions to `255` within ≤ 2 s and the host renders "read failed" (no "0%", no stale-looking small number).

---

### User Story 3 — Backward compatibility, Kconfig gating, and corne upgrade path (Priority: P3)

A keyboard author who does **not** want the 1.1 characteristics (for binary-size reasons, or because they expose only the layer/mods field today) can either (a) stay on `revision: v1.0.0` (unchanged behaviour), or (b) upgrade to `v1.1.0` and set `CONFIG_ZMK_KEYBEACON_CONNECTIVITY=n` and `CONFIG_ZMK_KEYBEACON_BATTERY=n` in `.conf` to opt out at compile time; in either case GATT discovery exposes **only** `AA440AA1-…`, and KBP 1.0 and KBP 1.1 hosts both see identical 1.0 behaviour. Default is **opt-in** (both sub-Kconfigs `default y` under `CONFIG_ZMK_KEYBEACON=y`) so the typical upgrade is literally one line in `west.yml`.

**Why this priority**: this is a protection + documentation story, not a new capability. Everything is still testable by rebuilding and probing GATT; it has no runtime dependency on hardware. Priority P3 because US1/US2 cover the live firmware behaviour and this story only guards against regressions and misconfiguration.

**Independent Test**: three builds — (A) module v1.0.0 as pinned today, (B) module v1.1.0 with both sub-Kconfigs `y`, (C) module v1.1.0 with both sub-Kconfigs `n` — produce three keyboards where (A) and (C) are byte-indistinguishable to KBP 1.0 and KBP 1.1 hosts (only `AA440AA1-…` on GATT, zero NOTIFYs elsewhere), and (B) exposes `AA440AA2-…` + `AA440AA3-…` with correct payloads. `conformance_tool.py --json` on each build exits with the expected `declared_minor` and `exit_code = 0`.

**Acceptance Scenarios**:

1. **Given** `revision: v1.0.0` (unchanged west.yml), **When** the firmware is rebuilt, **Then** the GATT service exposes only `AA440AA1-…`, byte-identical to the current corne build.
2. **Given** `revision: v1.1.0` with no `.conf` changes, **When** the firmware is rebuilt, **Then** both `AA440AA2-…` and `AA440AA3-…` are present and functional (default-y both sub-Kconfigs).
3. **Given** `revision: v1.1.0` + explicit `CONFIG_ZMK_KEYBEACON_CONNECTIVITY=n` and `CONFIG_ZMK_KEYBEACON_BATTERY=n`, **When** the firmware is rebuilt, **Then** the GATT service exposes only `AA440AA1-…` and both KBP 1.0 and KBP 1.1 hosts see identical 1.0 behaviour.

---

### Edge Cases

- **Non-central images (peripheral half, settings_reset)**: `keybeacon.cmake` currently gates on `CONFIG_ZMK_SPLIT_ROLE_CENTRAL`; the 1.1 additions MUST inherit the same guard so no 1.1 GATT bytes appear on peripheral or recovery images (C12 MANUAL).
- **Firmware with no charger GPIO (e.g. the user's Corne)**: `has_left_charging` and `has_right_charging` MUST be `0` in `capability_bits`; bytes `charging_flags.bit 0/1` MUST be emitted as `0` (per P-C5 and the host's `Observable Degradation Over Guessing` governance rule). The app will not render a charging icon on either half — correct behaviour.
- **Integer board with Battery sub-Kconfig enabled**: `is_split` capability bit is `0`, Battery payload is 1 byte `[overall_percent]` (per §14.4.1). The module MUST detect this at compile time from `CONFIG_ZMK_SPLIT` and emit the correct-length payload.
- **Reserved bits/bytes**: all reserved positions in Connectivity (byte 1 bits 3–7, byte 4 bits 2–7, byte 6 bits 2–7, byte 0 bit 7, byte 7+) MUST be `0` (P-C4). Battery reserved values 101–254 are forbidden; firmware MUST only emit `0..100` or `255`.
- **Transient battery read failure**: if `zmk_battery_state_changed` has never fired for a half (fresh boot before first ADC sample), the firmware MUST emit `255` (sentinel) rather than `0`. Same rule when the sync-bus loses the peripheral battery value transiently.
- **Payload-length mismatch at compile time**: `BUILD_ASSERT`s MUST verify that the Connectivity payload is exactly 7 bytes and the Battery payload length matches `IS_ENABLED(CONFIG_ZMK_SPLIT)` so a build-time regression is caught before flashing.
- **Snapshot-unchanged suppression**: both characteristics inherit the KBP 1.0 §5 rule — if the recomputed payload byte-for-byte equals the last-sent payload, firmware MUST suppress the NOTIFY (keeps idle traffic at zero per C3's spirit extended to 1.1).

## Requirements *(mandatory)*

### Functional Requirements

#### FR-G: GATT shape

- **FR-G1**: The module MUST add two new characteristics on the existing primary service `AA440AA0-F5ED-4C48-84A1-8062D20D3D55` with UUIDs `AA440AA2-F5ED-4C48-84A1-8062D20D3D55` (Connectivity) and `AA440AA3-F5ED-4C48-84A1-8062D20D3D55` (Battery), each with properties `READ | NOTIFY` and a CCC (`0x2902`) descriptor. The service UUID and the KBP 1.0 characteristic `AA440AA1-…` MUST remain byte-for-byte identical to v1.0.0 (verified by diffing `keybeacon.c` v1.0.0 vs v1.1.0 for the `BT_GATT_SERVICE_DEFINE` prefix).
- **FR-G2**: The `keybeacon.cmake` central-only guard (`CONFIG_ZMK_KEYBEACON AND CONFIG_ZMK_BLE AND CONFIG_ZMK_SPLIT_ROLE_CENTRAL`) MUST continue to compile the module source only into the central image; the 1.1 additions MUST live inside the same guarded `zephyr_library()` and MUST NOT introduce any new condition that could leak the service into a peripheral or `settings_reset` image.

#### FR-C: Connectivity characteristic (`AA440AA2-…`)

- **FR-C1**: Connectivity payload length MUST be exactly 7 bytes (little-endian), matching protocol §14.3.1; a `BUILD_ASSERT` MUST catch any struct-layout regression at compile time.
- **FR-C2**: `capability_bits` (byte 0) MUST be computed at compile time from Kconfig/`IS_ENABLED(...)` symbols so the host can enumerate exactly which 1.1 fields this firmware supports: `is_split`, `has_host_connection`, `has_profile`, `has_split_link` (requires `is_split`), `has_output_endpoint`, `has_left_charging`, `has_right_charging` (requires `is_split`). Bit 7 MUST be `0`.
- **FR-C3**: `host_state` (byte 1) MUST reflect `zmk_ble_active_profile_is_connected()` in bit 0; bits 1–2 MUST encode `last_disconnect_reason` (0 unknown / 1 explicit / 2 timeout / 3 reserved); bits 3–7 MUST be `0`. The firmware MUST subscribe to `zmk_ble_active_profile_changed` and recompute the payload on each event.
- **FR-C4**: `profile_index` (byte 2) bits 0–6 MUST reflect `zmk_ble_active_profile_index()` as **1-based** (0 = field not applicable); bit 7 MUST reflect `zmk_ble_active_profile_is_open()`. `profile_max_slots` (byte 3) MUST reflect `ZMK_BLE_PROFILE_COUNT` (or the ZMK equivalent at build time). Firmware MUST satisfy P-C3 (`profile_index` ≤ `profile_max_slots`).
- **FR-C5**: `split_link_flags` (byte 4) bit 0 MUST be `left_online` and bit 1 MUST be `right_online`, derived from `zmk_split_bt_peripherals_connected()` and the central-vs-left-vs-right role assignment; bits 2–7 MUST be `0`. The field is only meaningful when `is_split = 1` (invariant P-C1). Firmware MUST subscribe to `zmk_split_bt_peripheral_status_changed`.
- **FR-C6**: `output_endpoint` (byte 5) MUST map `ZMK_ENDPOINT_USB → 1`, `ZMK_ENDPOINT_BLE → 2`, and any other / unknown state → `0`. Firmware MUST subscribe to `zmk_endpoint_changed` (if present in the ZMK target) and recompute on each event.
- **FR-C7**: `charging_flags` (byte 6) default implementation MUST emit `0` on both bits, and the corresponding capability bits (`has_left_charging`, `has_right_charging`) MUST be `0` by default — i.e. a board that does not implement charger-GPIO reporting MUST NOT falsely advertise charging support. Boards with charger GPIOs MAY override this via board-specific overlays; this feature does not require that override and does not touch any shield overlay in this release.
- **FR-C8**: On any state-ish field change (any bit in bytes 1–6 that is covered by a capability bit), firmware MUST emit a NOTIFY immediately with no minimum interval; firmware MUST suppress the NOTIFY when the recomputed 7-byte payload is byte-for-byte identical to the last sent one (snapshot-unchanged suppression inherited from KBP 1.0 §5).
- **FR-C9**: All of invariants P-C1 through P-C5 (protocol §14.3.3) MUST hold on every emitted payload. In particular: `has_split_link ⇒ is_split`; `has_right_charging ⇒ is_split ∧ has_left_charging`; integer board (`is_split = 0`) MUST emit `charging_flags.bit 1 = 0` and `has_right_charging = 0`.

#### FR-B: Battery characteristic (`AA440AA3-…`)

- **FR-B1**: Battery payload length MUST match `is_split`: exactly 1 byte `[overall_percent]` when `IS_ENABLED(CONFIG_ZMK_SPLIT)` is false, exactly 2 bytes `[left_percent, right_percent]` when true. A `BUILD_ASSERT` MUST catch regressions.
- **FR-B2**: Each percent byte MUST be either `0..100` (normal percent) or `255` (sentinel for "read failed / temporarily unavailable"); values `101..254` MUST NOT be emitted (P-B4 reserved).
- **FR-B3**: Battery NOTIFY throttling MUST follow protocol §14.4.5 OR relation: emit when (a) a byte value differs from last-sent by ≥ 1, **OR** (b) ≥ 1 second has elapsed since last emit of this characteristic; always suppress when the full payload is byte-identical to last sent.
- **FR-B4**: Firmware MUST subscribe to `zmk_battery_state_changed` for the central half and `zmk_peripheral_battery_state_changed` for the peripheral half; MUST pass raw ADC readings through without any firmware-side smoothing / moving average (P-B2) so the host preserves authority over any display smoothing.
- **FR-B5**: On fresh boot before any battery-state event has fired for a half, firmware MUST emit `255` for that byte (not `0`). On loss of the sync-bus with the peripheral while split, firmware MUST emit `255` for the right byte within ≤ 2 seconds (bounded by the ZMK split sync timeout).
- **FR-B6**: If a build has `CONFIG_ZMK_KEYBEACON_BATTERY=n`, firmware MUST NOT register the Battery characteristic at all (consumer sees it missing on GATT discovery, per protocol §14.4.3 P-B3).

#### FR-K: Kconfig & build integration

- **FR-K1**: Add two new Kconfig symbols under `Kconfig.keybeacon`: `ZMK_KEYBEACON_CONNECTIVITY` (bool, depends on `ZMK_KEYBEACON`, `default y`) and `ZMK_KEYBEACON_BATTERY` (bool, depends on `ZMK_KEYBEACON`, `default y`). Both inherit the parent's `depends on ZMK_BLE`. Enabling either MUST have zero effect when `ZMK_KEYBEACON=n`.
- **FR-K2**: The module MUST compile cleanly on the current corne west manifest (zmk pinned to commit `6b44d33db2f4bad7d98e475e6f7968493b05af73`, as declared in `/Users/wangyuting19/kbd/zmk-config-corne/config/west.yml`) with both sub-Kconfigs on; `BUILD_ASSERT`s MUST catch any struct-layout drift against upstream ZMK API renames.
- **FR-K3**: If an upstream ZMK API hint from §14.8 is missing in the pinned ZMK (e.g. `zmk_endpoint_changed` on an older tree), the module MUST `#if defined`-guard it, degrade gracefully (emit `0` for that field, keep the capability bit `0`), and log a build-time `#warning` so the author can see what degraded.

#### FR-D: Docs & versioning

- **FR-D1**: `CHANGELOG.md` in `zmk-keybeacon` MUST get a `## [1.1.0]` entry (date-stamped) listing: the two new characteristics with UUIDs, the two new Kconfig symbols with defaults, the ZMK events subscribed, the backward-compatibility guarantee ("v1.0 wire unchanged; existing consumers unaffected"), and the versioning rationale (MINOR, additive).
- **FR-D2**: `README.md` in `zmk-keybeacon` MUST update the "This module implements **KBP 1.0.0**" line to `KBP 1.1.0`, add a "What's new in 1.1" subsection (short English + 中文 mirror per project `Bilingual Normative Docs` constitution principle), and update the `revision: v1.0.0` placeholder in both Quick-integration snippets to `v1.1.0`.
- **FR-D3**: A new git tag `v1.1.0` MUST be created on the `feat/kbp-1.1-connectivity-power` branch after local verification against the user's corne hardware (see Success Criteria SC-002/SC-003); the tag MUST be the final deliverable of this feature.

### Key Entities

- **Connectivity payload (`AA440AA2-…`)**: 7-byte little-endian snapshot carrying `capability_bits`, `host_state`, `profile_index`, `profile_max_slots`, `split_link_flags`, `output_endpoint`, `charging_flags`. Lifecycle: recomputed on each subscribed ZMK event; cached; emitted on change; suppressed on byte-identical no-op.
- **Battery payload (`AA440AA3-…`)**: 1-or-2 byte snapshot of raw battery readings. Lifecycle: driven by `zmk_battery_state_changed` + `zmk_peripheral_battery_state_changed`; throttled per §14.4.5; passed through raw; `255` on unavailable.
- **CapabilityMatrix (compile-time)**: the fixed set of `has_*` bits that this firmware build advertises, derived from `IS_ENABLED(...)` on Kconfig symbols + ZMK config (e.g. `CONFIG_ZMK_SPLIT`). Not a runtime entity — it is a const byte baked into every emitted Connectivity payload.
- **GATT service `AA440AA0-…`**: unchanged primary service, now hosting three characteristics (`AA1` unchanged + new `AA2` + new `AA3`); same CCC rules.
- **Guarded zephyr_library (`keybeacon.cmake`)**: the central-only link gate. All three characteristics live inside the same gate; peripheral and `settings_reset` images do not link `keybeacon.c`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On a Corne central running the 1.1.0 firmware with both sub-Kconfigs on, `python3 conformance/conformance_tool.py --timeout 15` on the main keybeacon repo exits with code `0` and prints `C7..C11 PASS, C12 MANUAL`; `--json` output shows `declared_minor = "1.1"`, `characteristics.AA440AA2.present = true`, `characteristics.AA440AA3.present = true`.
- **SC-002**: Toggling the output endpoint on the keyboard (BLE ↔ USB) updates the host app's "output endpoint" row within **≤ 1 second** on **≥ 10 consecutive trials** (measured by wall-clock from on-keyboard keypress to app render).
- **SC-003**: During **60 seconds of continuous typing** with no real battery change, firmware emits **≤ 60 NOTIFYs** on `AA440AA3-…` (one per second cap, demonstrating ≥ 1 s throttling).
- **SC-004**: A KBP 1.0 host (the main-branch KeyBeacon app, pre-`001-connectivity-power`) connecting to the 1.1.0 firmware shows **zero** behavioural change compared to a v1.0.0 firmware build: identical layer+modifier display, zero NOTIFYs on `AA440AA2-…` / `AA440AA3-…`, same connection stability over 10 min of mixed typing (regression gate for FR-G1).
- **SC-005**: Rebuilding the user's Corne with `CONFIG_ZMK_KEYBEACON_CONNECTIVITY=n` + `CONFIG_ZMK_KEYBEACON_BATTERY=n` produces a firmware byte-indistinguishable (at the GATT layer) from the v1.0.0 build; `conformance_tool.py` reports `declared_minor = "1.0"` and exits `0`.
- **SC-006**: Binary-size impact: `west build` output `zephyr.elf` text-section delta between v1.0.0 and v1.1.0 (both sub-Kconfigs on) is **≤ 4 KB** on `nice_nano_v2` + `puchi_ble_v1` (keeps the module usable on tight NRF52840 flash budgets common to split keyboards).
- **SC-007**: Zero regressions on existing `swift test` (90 tests, host side) and existing `pytest conformance/tests/` (81 tests, cross-platform CLI) when run against the 1.1.0 firmware (both suites still 100% pass, since neither depends on firmware internals).

## Assumptions

- **ZMK API availability**: the pinned ZMK commit `6b44d33` (used by `zmk-config-corne`) exposes `zmk_ble_active_profile_changed`, `zmk_ble_active_profile_is_connected()`, `zmk_ble_active_profile_index()`, `zmk_ble_active_profile_is_open()`, `ZMK_BLE_PROFILE_COUNT`, `zmk_split_bt_peripheral_status_changed`, `zmk_split_bt_peripherals_connected()`, `zmk_endpoint_changed`, `zmk_endpoints_selected()`, `zmk_battery_state_changed`, `zmk_peripheral_battery_state_changed`. API renames in newer ZMK trees are handled by the FR-K3 `#if defined`-guard strategy.
- **Charger GPIO scope**: this release does **not** implement charger-GPIO reading for any board; `has_left_charging` / `has_right_charging` default to `0`. Boards wishing to advertise charging will add that in a follow-up (v1.2.0 or board-overlay-driven), consistent with the user's answer in the pre-plan discussion.
- **Target repo isolation**: all code changes land in the sibling `zmk-keybeacon` repo on branch `feat/kbp-1.1-connectivity-power`. This `keybeacon` repo and `zmk-config-corne` repo are **not** modified by this feature (corne is upgraded in a follow-up once v1.1.0 is tagged, per the user's "延后" answer).
- **Reference hardware**: the user's **Corne** on `feat/keybeacon` (nice_nano_v2 central + puchi_ble_v1 peripheral per `build.yaml`, with nice_epaper displays) is the primary verification target. One central image is enough — US2's peripheral-battery path is observable from the central.
- **Backward-compat scope**: FR-G1 guarantees the v1.0 wire is byte-identical. If the user later ships a KBP 1.1 host **and** a v1.0.0-pinned firmware simultaneously, the 1.1 UI is correctly hidden on the host side (verified by host-side spec `001-connectivity-power` FR-002 / `research.md §11` compatibility matrix).
- **Tag discipline**: no `v1.1.0` tag is pushed until SC-001 through SC-005 all pass on real Corne hardware. Interim verification uses a relative-path `west.yml` override on the user's corne config (temporary; never committed).
