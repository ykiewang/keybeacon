# Contract: Connectivity characteristic (`AA440AA2-F5ED-4C48-84A1-8062D20D3D55`)

**Feature**: 002-zmk-keybeacon-kbp11

**Normative source**: `protocol/README.md §14.3` (keybeacon main repo). This contract **mirrors** that normative text; where any conflict arises, protocol §14.3 wins.

**Role**: this document is the **producer-side** contract for the `zmk-keybeacon` module. The **consumer-side** mirror lives in `specs/001-connectivity-power/contracts/` and shares the same wire bytes (that is the whole point of KBP being a protocol).

## 1. GATT shape

| Item | Value |
|------|-------|
| Service UUID | `AA440AA0-F5ED-4C48-84A1-8062D20D3D55` (shared with KBP 1.0 — unchanged) |
| Characteristic UUID | `AA440AA2-F5ED-4C48-84A1-8062D20D3D55` |
| Properties | `BT_GATT_CHRC_READ \| BT_GATT_CHRC_NOTIFY` |
| Permission | `BT_GATT_PERM_READ` |
| Descriptor | `BT_GATT_CCC(cb, BT_GATT_PERM_READ \| BT_GATT_PERM_WRITE)` |
| Presence | **optional**; registered iff `CONFIG_ZMK_KEYBEACON_CONNECTIVITY=y` AND `CONFIG_ZMK_KEYBEACON=y` AND `CONFIG_ZMK_SPLIT_ROLE_CENTRAL=y` (or non-split) AND `CONFIG_ZMK_BLE=y` |

## 2. Payload layout (little-endian, fixed 7 bytes)

| Offset | Field | Encoding | Producer rule |
|--------|-------|----------|---------------|
| `[0]` | `capability_bits` | uint8 bitmask | compile-time constant; see `data-model.md E4`; byte 7 reserved MUST be `0` |
| `[1]` | `host_state` | uint8: bit 0 `connected`; bits 1–2 `last_disconnect_reason` (0 unknown / 1 explicit / 2 timeout / 3 reserved); bits 3–7 reserved | bit 0 = `zmk_ble_active_profile_is_connected()`; bits 1–2 = `0` on this ZMK pin; bits 3–7 = `0` |
| `[2]` | `profile_index` | uint8: bits 0–6 `profile_index` (1-based; 0 = N/A); bit 7 `profile_open` | bits 0–6 = `zmk_ble_active_profile_index() + 1`; bit 7 = `zmk_ble_active_profile_is_open() ? 0x80 : 0` |
| `[3]` | `profile_max_slots` | uint8 (0 = N/A) | `ZMK_BLE_PROFILE_COUNT` |
| `[4]` | `split_link_flags` | uint8: bit 0 `left_online`; bit 1 `right_online`; bits 2–7 reserved | left = `IS_ENABLED(CONFIG_ZMK_SPLIT_BLE) ? 1 : 0`; right = `(peripheral_slots[0].last_seen_ms > 0 && (k_uptime_get() - peripheral_slots[0].last_seen_ms) <= 10000) ? 2 : 0`; bits 2–7 = `0` |
| `[5]` | `output_endpoint` | uint8: 0 unknown / 1 USB / 2 BLE / 3–255 reserved | map `zmk_endpoints_selected().transport`: `ZMK_TRANSPORT_USB → 1`, `ZMK_TRANSPORT_BLE → 2`, else `0` |
| `[6]` | `charging_flags` | uint8: bit 0 left/overall; bit 1 right; bits 2–7 reserved | `0` in v1.1.0 (no charger GPIO support) |

**BUILD_ASSERT**:

```c
BUILD_ASSERT(sizeof(struct conn_payload) == 7, "KBP 1.1 §14.3.1: Connectivity payload must be 7 bytes");
```

## 3. Invariants (producer-side; firmware MUST)

- **P-C1**: `(capability_bits & 0x08) == 0x08` ⇒ `(capability_bits & 0x01) == 0x01` (split_link requires is_split). Satisfied by construction: `KEYBEACON_CAP_HAS_SPLIT_LINK` is only set when `CONFIG_ZMK_SPLIT=y`.
- **P-C2**: fields with cap bit `0` MAY have `0` byte; consumer MUST ignore. v1.1.0 emits `0` for `charging_flags` consistently.
- **P-C3**: `profile_index` bits 0–6 ≤ `profile_max_slots`. Enforced at build-payload time by `MIN(zmk_ble_active_profile_index() + 1, ZMK_BLE_PROFILE_COUNT)`.
- **P-C4**: all reserved positions `0`. Satisfied: `host_state` bits 3–7, `split_link_flags` bits 2–7, `charging_flags` bits 2–7, `capability_bits` bit 7 all `0`.
- **P-C5**: `has_right_charging` ⇒ `is_split ∧ has_left_charging`. Trivially satisfied: `has_right_charging = 0` in v1.1.0.

## 4. NOTIFY policy

- **On change**: any ZMK event (`zmk_ble_active_profile_changed`, `zmk_endpoint_changed`, `zmk_peripheral_battery_state_changed`) MAY cause a payload change. Firmware MUST rebuild the snapshot and compare byte-for-byte to the cached last-sent payload. If different: NOTIFY.
- **Suppression (inherited KBP 1.0 §5)**: if the rebuilt snapshot is byte-for-byte identical to the last-sent cache, firmware MUST NOT NOTIFY.
- **No minimum interval**: state-ish fields have no throttling floor (unlike Battery). Rapid toggles between two equivalent snapshots naturally throttle themselves via the suppression rule.

## 5. READ policy

A GATT READ returns the current cached payload (same 7 bytes), served via `bt_gatt_attr_read` with `payload_cache` and `payload_len_cache = 7`.

## 6. Degradation hooks

| Scenario | Producer behaviour |
|----------|-------------------|
| `CONFIG_ZMK_KEYBEACON_CONNECTIVITY=n` | characteristic NOT registered; GATT discovery doesn't find `AA440AA2-…`; consumer hides entire 1.1 Connectivity UI (host §C-C-1 / `001-connectivity-power` FR-002) |
| Older ZMK without `zmk_endpoints_selected()` | `output_endpoint` byte stays `0`; `has_output_endpoint` cap bit = `0` (consumer hides field) |
| Older ZMK without `zmk_peripheral_battery_state_changed` + `CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING=n` | `right_online` always `0`; `has_split_link` cap bit MAY still be `1` (semantically the field is "known"; the value "offline" is honest), but a stricter degradation sets cap bit `0` under the same guard |

## 7. Mapping back to feature spec

| FR / SC | Covered by this contract |
|---------|--------------------------|
| FR-G1 | characteristic UUID + service UUID exact match |
| FR-G2 | section 1 "registered iff" clause |
| FR-C1 | section 2 BUILD_ASSERT |
| FR-C2 | section 2 byte `[0]` + data-model E4 |
| FR-C3 | section 2 byte `[1]` + section 3 P-C4 |
| FR-C4 | section 2 byte `[2]` + section 3 P-C3 |
| FR-C5 | section 2 byte `[4]` + research.md §R1.3 (10 s TTL) |
| FR-C6 | section 2 byte `[5]` |
| FR-C7 | section 2 byte `[6]` + section 3 P-C5 |
| FR-C8 | section 4 (change-on-emit + suppression) |
| FR-C9 | section 3 P-C1..P-C5 |
| FR-K3 | section 6 degradation hooks |
| SC-001 (conformance tool PASS C7..C11) | sections 1–4 satisfy C7, C8, C10 directly; C9/C11 are Battery (separate contract) |
| SC-004 (KBP 1.0 host regression) | section 1 "GATT shape": service UUID unchanged, AA1 unchanged, AA2 added as **new attribute** inside the same `BT_GATT_SERVICE_DEFINE` |

## 8. Non-goals in v1.1.0

- No charger-GPIO reading (both `has_left_charging` and `has_right_charging` cap bits are `0`).
- No `last_disconnect_reason` codes beyond `0` (unknown) at this ZMK pin.
- No per-slot `split_link_flags` beyond 2 slots (bit 0 + bit 1). N-peripheral splits (N > 1) are not addressed by this release; firmware emits `right_online` from `peripheral_slots[0]` only.
